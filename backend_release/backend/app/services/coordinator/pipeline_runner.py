"""
管线运行器 — 封装多步骤管线编排逻辑。

职责：
  1. M1 全线管线（标准化 → 拆分 → 依赖）
  2. 一致性优先主线（M1 → 子需求列表 → 一致性循环 → 可实现性 + 集成）
  3. 用户节点重拆入口（refine_node_and_run_m2_tail）

依赖关系：PipelineRunner → AgentInvoker + SubARRefiner
"""
from __future__ import annotations

import logging
from typing import TYPE_CHECKING, Any, Callable, Awaitable, Dict, Optional

from app.core.enums import PipelineStage
from app.schemas.agent import BaseAgentOutput
from app.services.coordinator.tree_utils import (
    collect_direct_child_ids_from_rows,
    filter_dependencies_for_node_ids,
    norm_function_id,
    sub_requirement_list_stats,
)
from app.services.agents.M1.focus_from_normalizer import build_focus_node_from_normalizer
from app.services.coordinator.m1_debug_recorder import record_m1_decomposer_invocation
from app.services.coordinator.agent_timeline import (
    apply_sub_requirement_list_artifacts,
    with_llm_agent_span,
)

if TYPE_CHECKING:
    from app.services.coordinator.agent_invoker import AgentInvoker
    from app.services.coordinator.sub_ar_refiner import SubARRefiner
    from app.services.coordinator.context import CoordinatorContext

logger = logging.getLogger(__name__)


class PipelineRunner:
    """管线运行器"""

    def __init__(
        self,
        agent_invoker: "AgentInvoker",
        sub_ar_refiner: "SubARRefiner",
    ):
        self.invoker = agent_invoker
        self.sub_ar_refiner = sub_ar_refiner

    # ───────────── M1 管线 ─────────────

    async def invoke_module1_pipeline_without_gate(
        self,
        context: "CoordinatorContext",
        on_agent_complete: Optional[
            Callable[[str, "CoordinatorContext"], Awaitable[None]]
        ] = None,
    ) -> Dict[str, BaseAgentOutput]:
        """Normalizer → Decomposer → DependencyClassifier（默认编排主路径）。"""
        results: Dict[str, BaseAgentOutput] = {}
        task_id = context.conversation_id
        emit = getattr(context, "agent_span_emit", None)

        logger.info(f"[{task_id}] M1-Normalizer 开始")
        norm_input = self.invoker._build_input(context)
        norm_output = await with_llm_agent_span(
            context,
            "normalizer",
            "M1-Normalizer",
            emit,
            self.invoker._m1_normalizer.execute(norm_input),
        )
        results["normalizer"] = norm_output

        norm_result = self.invoker._to_serializable(norm_output.get_payload())
        normalized_requirement_text = (
            norm_result.get("normalized_requirement") or ""
        ) if isinstance(norm_result, dict) else ""

        context.artifacts["normalizer_meta"] = self.invoker._to_serializable(
            norm_output.meta or {}
        )
        context.add_artifact("normalized_requirement", norm_result, agent="normalizer")
        decomp_focus = build_focus_node_from_normalizer(
            norm_result if isinstance(norm_result, dict) else {}
        )
        context.add_artifact("decomposition_root", decomp_focus, agent="normalizer")
        self.invoker._record_quality_flags(context, "normalizer", norm_output)
        logger.info(f"[{task_id}] M1-Normalizer 完成")
        if on_agent_complete:
            await on_agent_complete("normalizer", context)

        if context.stop_requested:
            logger.info(f"[{task_id}] 停止请求：Normalizer 后退出 M1 管线")
            return results

        logger.info(f"[{task_id}] M1-Decomposer 开始")
        decomp_input = self.invoker._build_input(
            context,
            normalized_requirement=normalized_requirement_text,
            artifacts={
                "focus_node": decomp_focus,
                "normalizer_result": self.invoker._slim_norm_for_decomposer(norm_result),
            },
        )
        decomp_output = await with_llm_agent_span(
            context,
            "decomposer",
            "M1-Decomposer",
            emit,
            self.invoker._m1_decomposer.execute(decomp_input),
        )
        results["decomposer"] = decomp_output
        record_m1_decomposer_invocation(
            self.invoker,
            context,
            source="module1_pipeline",
            decomp_input=decomp_input,
            decomp_output=decomp_output,
        )
        self.invoker._apply_decomposer_normalizer_patch(context, decomp_output)

        decomp_result = self.invoker._to_serializable(decomp_output.get_payload())
        _sync = self.invoker._artifacts_from_decomposer_result(decomp_result)
        fl = _sync.get("function_list")
        core_flow = _sync.get("core_flow") or []
        context.add_artifact("function_list", fl, agent="decomposer")
        context.add_artifact("core_flow", core_flow, agent="decomposer")
        context.add_artifact("decomposer_full", decomp_result, agent="decomposer")
        self.invoker._record_quality_flags(context, "decomposer", decomp_output)
        logger.info(f"[{task_id}] M1-Decomposer 完成")
        if on_agent_complete:
            await on_agent_complete("decomposer", context)

        if context.stop_requested:
            logger.info(f"[{task_id}] 停止请求：Decomposer 后退出 M1 管线")
            return results

        norm_result = context.artifacts.get("normalized_requirement")
        if not isinstance(norm_result, dict):
            norm_result = {}

        logger.info(f"[{task_id}] M1-DependencyClassifier 开始")
        dep_input = self.invoker._build_input(
            context,
            artifacts={
                "function_list": fl,
                "normalizer_result": self.invoker._slim_norm_for_dependency(norm_result),
                "core_flow": core_flow,
            },
        )
        dep_output = await with_llm_agent_span(
            context,
            "dependency_classifier",
            "M1-DependencyClassifier",
            emit,
            self.invoker._m1_dependency.execute(dep_input),
        )
        results["dependency_classifier"] = dep_output

        dep_result = self.invoker._to_serializable(dep_output.get_payload())
        dependencies = self.invoker._to_serializable(dep_result.get("dependencies"))
        if not isinstance(dependencies, list):
            dependencies = []

        context.add_artifact("dependencies", dependencies, agent="dependency_classifier")
        context.add_artifact("dependency_full", dep_result, agent="dependency_classifier")
        self.invoker._record_quality_flags(context, "dependency_classifier", dep_output)
        logger.info(f"[{task_id}] M1-DependencyClassifier 完成")
        if on_agent_complete:
            await on_agent_complete("dependency_classifier", context)

        return results

    async def invoke_m1_decomposer_and_dependency_no_gate(
        self,
        context: "CoordinatorContext",
        on_agent_complete: Optional[
            Callable[[str, "CoordinatorContext"], Awaitable[None]]
        ] = None,
    ) -> Dict[str, BaseAgentOutput]:
        """仅从 Decomposer 起执行至 DependencyClassifier（用于一致性内层重试）。"""
        results: Dict[str, BaseAgentOutput] = {}
        task_id = context.conversation_id
        emit = getattr(context, "agent_span_emit", None)

        norm_data = context.artifacts.get("normalized_requirement") or {}
        normalized_requirement_text = (
            norm_data.get("normalized_requirement", "")
            if isinstance(norm_data, dict)
            else ""
        )
        if not normalized_requirement_text:
            logger.warning(
                f"[{task_id}] decomposer+dependency 缺少 normalized_requirement，使用 requirement_text"
            )
            normalized_requirement_text = context.requirement_text or ""

        norm_dict = norm_data if isinstance(norm_data, dict) else {}
        decomp_focus = build_focus_node_from_normalizer(norm_dict)

        logger.info(f"[{task_id}] M1 Decomposer→Dependency（无 Gate）开始")
        decomp_input = self.invoker._build_input(
            context,
            normalized_requirement=normalized_requirement_text,
            artifacts={
                "focus_node": decomp_focus,
                "normalizer_result": self.invoker._slim_norm_for_decomposer(norm_dict),
            },
        )
        decomp_output = await with_llm_agent_span(
            context,
            "decomposer",
            "M1-Decomposer(retry)",
            emit,
            self.invoker._m1_decomposer.execute(decomp_input),
        )
        results["decomposer"] = decomp_output
        record_m1_decomposer_invocation(
            self.invoker,
            context,
            source="decomposer_dependency_no_gate",
            decomp_input=decomp_input,
            decomp_output=decomp_output,
        )
        self.invoker._apply_decomposer_normalizer_patch(context, decomp_output)

        decomp_result = self.invoker._to_serializable(decomp_output.get_payload())
        _sync = self.invoker._artifacts_from_decomposer_result(decomp_result)
        fl = _sync.get("function_list")
        core_flow = _sync.get("core_flow") or []
        context.add_artifact("function_list", fl, agent="decomposer")
        context.add_artifact("core_flow", core_flow, agent="decomposer")
        context.add_artifact("decomposer_full", decomp_result, agent="decomposer")
        self.invoker._record_quality_flags(context, "decomposer", decomp_output)
        if on_agent_complete:
            await on_agent_complete("decomposer", context)

        if context.stop_requested:
            logger.info(f"[{task_id}] 停止请求：Decomposer 后退出内层重拆")
            return results

        norm_data = context.artifacts.get("normalized_requirement")
        if not isinstance(norm_data, dict):
            norm_data = {}

        dep_input = self.invoker._build_input(
            context,
            artifacts={
                "function_list": fl,
                "normalizer_result": self.invoker._slim_norm_for_dependency(
                    norm_data if isinstance(norm_data, dict) else {}
                ),
                "core_flow": core_flow,
            },
        )
        dep_output = await with_llm_agent_span(
            context,
            "dependency_classifier",
            "M1-DependencyClassifier(retry)",
            emit,
            self.invoker._m1_dependency.execute(dep_input),
        )
        results["dependency_classifier"] = dep_output

        dep_result = self.invoker._to_serializable(dep_output.get_payload())
        dependencies = self.invoker._to_serializable(dep_result.get("dependencies"))
        if not isinstance(dependencies, list):
            dependencies = []
        context.add_artifact("dependencies", dependencies, agent="dependency_classifier")
        context.add_artifact("dependency_full", dep_result, agent="dependency_classifier")
        self.invoker._record_quality_flags(context, "dependency_classifier", dep_output)
        if on_agent_complete:
            await on_agent_complete("dependency_classifier", context)

        logger.info(f"[{task_id}] M1 Decomposer→Dependency（无 Gate）完成")
        return results

    # ───────────── M2 尾部 + 一致性循环 ─────────────

    async def _cf_list_consistency_m2_tail(
        self,
        context: "CoordinatorContext",
        merged: Dict[str, BaseAgentOutput],
        on_agent_complete: Optional[
            Callable[[str, "CoordinatorContext"], Awaitable[None]]
        ] = None,
        on_list_ready: Optional[
            Callable[["CoordinatorContext"], Awaitable[None]]
        ] = None,
        on_m2_agent_complete: Optional[
            Callable[[str, "CoordinatorContext", Optional[Dict[str, Any]]], Awaitable[None]]
        ] = None,
        *,
        refinement_root_id: str = "",
    ) -> Dict[str, BaseAgentOutput]:
        """
        子需求列表 → 一致性内层重拆 → 可实现性 + 集成 → 可选可实现性驱动子 AR 递归细化。

        refinement_root_id: 深度预算根节点 id，传空时由 SubARRefiner 自动确定（正常拆分用 F-1）。
        """
        cfg = context.config or {}
        threshold = float(cfg.get("consistency_pass_threshold", 0.7))
        inner_max = int(cfg.get("consistency_inner_max_retries", 1))

        # 按当前 function_list 动态计算分解根的直接子节点列表；
        # M1 重拆后需重新调用以反映更新后的树。
        def _child_fl_deps():
            from app.services.coordinator.sub_ar_refiner import SubARRefiner as _SAR
            _root = refinement_root_id or _SAR._resolve_refinement_root(context)
            _fl = context.artifacts.get("function_list") or []
            _ids = collect_direct_child_ids_from_rows(_fl, _root) if _root else set()
            _deps = context.artifacts.get("dependencies") or []
            c_fl = (
                [r for r in _fl if isinstance(r, dict)
                 and norm_function_id(r.get("id")) in _ids]
                if _ids else None
            )
            c_deps = filter_dependencies_for_node_ids(_deps, _ids) if _ids else None
            return c_fl, c_deps

        sub_list = await apply_sub_requirement_list_artifacts(
            context, self.invoker
        )
        if on_list_ready:
            await on_list_ready(context)

        if context.stop_requested:
            logger.info(f"[{context.conversation_id}] 停止请求：子需求列表生成后退出")
            return merged

        inner_attempt = 0
        while True:
            if context.stop_requested:
                logger.info(f"[{context.conversation_id}] 停止请求：一致性循环入口退出")
                return merged
            context.update_stage(PipelineStage.CONSISTENCY)
            child_fl, child_deps = _child_fl_deps()
            c_out = await self.invoker.invoke_m2_consistency_only(
                context,
                function_list_override=child_fl,
                dependencies_override=child_deps,
                on_m2_agent_complete=on_m2_agent_complete,
            )
            merged["consistency_evaluator"] = c_out
            ev = self.invoker._unwrap_consistency_eval_dict(c_out)

            if self.invoker.consistency_evaluation_passes(ev, threshold):
                context.retry_context["consistency_passed"] = True
                context.retry_context["consistency_inner_attempts"] = inner_attempt
                break

            inner_attempt += 1
            remediation = (ev.get("remediation_instruction") or "").strip()
            context.retry_context = {
                "consistency_passed": False,
                "consistency_inner_attempt": inner_attempt,
                "last_consistency_score": ev.get("score"),
                "remediation_instruction": remediation,
            }
            ncfg = dict(context.config or {})
            if remediation:
                ncfg["split_retry_hints"] = remediation
            context.config = ncfg

            if inner_attempt > inner_max:
                context.add_quality_flag(
                    "consistency_evaluator",
                    "consistency_not_passed_after_inner_retries",
                )
                break

            logger.info(
                f"[{context.conversation_id}] 一致性未通过，内层重拆第 {inner_attempt}/{inner_max}"
            )
            context.tree_version += 1
            context.add_artifact("tree_version", context.tree_version, agent="coordinator")
            dd = await self.invoke_m1_decomposer_and_dependency_no_gate(
                context, on_agent_complete=on_agent_complete
            )
            merged.update(dd)

            if context.stop_requested:
                logger.info(f"[{context.conversation_id}] 停止请求：一致性内层重拆后退出")
                return merged

            sub_list = await apply_sub_requirement_list_artifacts(
                context, self.invoker
            )
            # 快照记录 M1 重拆后、下一轮 M2 前的状态（此时 child_fl 已因 M1 更新而改变，
            # 在循环头部下次计算；快照传 None 表示全树基准，下一次 M2 调用的 override 将记录 actual_m2_input）
            self.invoker.refresh_m2_inputs_snapshot(context)

        consistency_unresolved = (
            "consistency_not_passed_after_inner_retries"
            in (context.quality_flags.get("consistency_evaluator") or [])
        )
        if consistency_unresolved and not bool(
            cfg.get("continue_pipeline_after_consistency_exhausted", False)
        ):
            logger.info(
                f"[{context.conversation_id}] 一致性内层耗尽且未开启 "
                "continue_pipeline_after_consistency_exhausted，跳过可实现性评估"
            )
            # invoke_m2_integrator_skip_feasibility 内部 stage="integrator" 不传 function_list，无需 override
            m2_partial = await self.invoker.invoke_m2_integrator_skip_feasibility(
                context, on_m2_agent_complete=on_m2_agent_complete
            )
            merged.update(m2_partial)
            child_fl, child_deps = _child_fl_deps()
            self.invoker.refresh_m2_inputs_snapshot(
                context,
                function_list_override=child_fl,
                dependencies_override=child_deps,
            )
            return merged

        if context.stop_requested:
            logger.info(f"[{context.conversation_id}] 停止请求：可实现性评估前退出")
            return merged

        context.update_stage(PipelineStage.FEASIBILITY)
        child_fl, child_deps = _child_fl_deps()
        m2tail = await self.invoker.invoke_m2_feasibility_integrator_only(
            context,
            function_list_override=child_fl,
            on_m2_agent_complete=on_m2_agent_complete,
        )
        merged.update(m2tail)
        self.invoker.refresh_m2_inputs_snapshot(
            context,
            function_list_override=child_fl,
        )
        await self.sub_ar_refiner._run_feasibility_refinement_after_root(
            context,
            merged,
            on_agent_complete,
            on_m2_agent_complete=on_m2_agent_complete,
            refinement_root_id=refinement_root_id,
        )
        return merged

    # ───────────── 主入口 ─────────────

    async def invoke_consistency_first_pipeline(
        self,
        context: "CoordinatorContext",
        on_agent_complete: Optional[
            Callable[[str, "CoordinatorContext"], Awaitable[None]]
        ] = None,
        on_list_ready: Optional[
            Callable[["CoordinatorContext"], Awaitable[None]]
        ] = None,
        on_m2_agent_complete: Optional[
            Callable[[str, "CoordinatorContext", Optional[Dict[str, Any]]], Awaitable[None]]
        ] = None,
    ) -> Dict[str, BaseAgentOutput]:
        """
        M1 全线 → 子需求列表 → 一致性门禁 → 可实现性 + 集成 →
        可选可实现性驱动子 AR 递归细化。

        配置（context.config）：
          - consistency_pass_threshold: float，默认 0.7
          - consistency_inner_max_retries: int，默认 1
          - continue_pipeline_after_consistency_exhausted: bool
          - enable_feasibility_refinement: bool
          - max_feasibility_refinement_depth: int
        """
        merged: Dict[str, BaseAgentOutput] = {}
        context.update_stage(PipelineStage.SPLIT)

        m1wg = await self.invoke_module1_pipeline_without_gate(
            context, on_agent_complete=on_agent_complete
        )
        merged.update(m1wg)

        if context.stop_requested:
            logger.info(f"[{context.conversation_id}] 停止请求：M1 完成后退出主管线")
            return merged

        return await self._cf_list_consistency_m2_tail(
            context,
            merged,
            on_agent_complete=on_agent_complete,
            on_list_ready=on_list_ready,
            on_m2_agent_complete=on_m2_agent_complete,
        )

    async def refine_node_and_run_m2_tail(
        self,
        context: "CoordinatorContext",
        node_id: str,
        *,
        user_instruction: str = "",
        on_agent_complete: Optional[
            Callable[[str, "CoordinatorContext"], Awaitable[None]]
        ] = None,
        on_list_ready: Optional[
            Callable[["CoordinatorContext"], Awaitable[None]]
        ] = None,
        on_m2_agent_complete: Optional[
            Callable[[str, "CoordinatorContext", Optional[Dict[str, Any]]], Awaitable[None]]
        ] = None,
    ) -> Dict[str, BaseAgentOutput]:
        """用户选定节点为根重拆 M1，再跑子需求列表 → 一致性 → 可实现性。

        选定节点作为本次深度预算的根（相对深度 0）；
        max_feasibility_refinement_depth=0 时拒绝执行重拆。
        """
        cfg = context.config or {}
        max_relative_depth = int(cfg.get("max_feasibility_refinement_depth", 1))
        if max_relative_depth <= 0:
            raise ValueError(
                "max_feasibility_refinement_depth=0，当前配置不允许执行节点重拆。"
                "如需重拆请在 request.config 中传入正整数值。"
            )

        merged: Dict[str, BaseAgentOutput] = {}
        nid = norm_function_id(node_id)
        if not nid:
            raise ValueError("node_id 无效")
        hint = {
            "need_further_split": True,
            "split_reason": "user_requested",
            "split_instruction": (user_instruction or "").strip(),
        }
        ok = await self.sub_ar_refiner._refine_one_sub_ar_node(
            context, merged, nid, hint, on_agent_complete
        )
        if not ok:
            raise ValueError(f"无法在功能树中细化节点: {node_id}")
        return await self._cf_list_consistency_m2_tail(
            context,
            merged,
            on_agent_complete=on_agent_complete,
            on_list_ready=on_list_ready,
            on_m2_agent_complete=on_m2_agent_complete,
            refinement_root_id=nid,
        )
