"""
子 AR 递归细化器 — 封装可实现性驱动的子需求递归细化逻辑。

职责：
  1. 对单个节点运行 M1 Decomposer（_refine_one_sub_ar_node）
  2. 可实现性失败后对子树做递归细化（_feasibility_failed_walk）
  3. 管理 sub_ar_refinement_stack 与 m2_scope 元数据

关键设计（修复 backup/restore artifact 污染）：
  - 在子树评估时不修改 context.artifacts["function_list"] / ["dependencies"]；
    改为将 scoped 数据以参数形式传入 AgentInvoker，避免并发读取时获取截断数据。
  - m2_scope 元数据写入 context.artifacts["m2_scope"]（轻量元数据，非大数据）。
"""
from __future__ import annotations

import copy
import json
import logging
import time
from datetime import datetime
from typing import TYPE_CHECKING, Any, Callable, Awaitable, Dict, List, Optional

from app.core.enums import PipelineStage
from app.schemas.agent import BaseAgentOutput
from app.services.coordinator.tree_utils import (
    append_node_evaluation_history,
    calc_node_depth_from_root,
    collect_direct_child_ids_from_rows,
    collect_subtree_ids_from_rows,
    ensure_subtree_splice_anchor_rows,
    filter_dependencies_for_node_ids,
    find_function_list_row_by_id,
    norm_function_id,
    splice_subtree_into_function_list,
    sub_requirement_list_stats,
)
from app.services.agents.M1.schemas.m1_decomposer import rebuild_function_list_paths
from app.services.agents.M1.focus_from_normalizer import DECOMPOSITION_ROOT_ID
from app.services.coordinator.m1_debug_recorder import record_m1_decomposer_invocation
from app.services.coordinator.agent_timeline import (
    apply_sub_requirement_list_artifacts,
    with_llm_agent_span,
)

if TYPE_CHECKING:
    from app.services.coordinator.agent_invoker import AgentInvoker
    from app.services.coordinator.context import CoordinatorContext

logger = logging.getLogger(__name__)

# #region agent log
_DEBUG_LOG_PATH = "/Users/xuxiao/Desktop/complex-functional-requirements-automated-decomposition-system/.cursor/debug-e5c18e.log"


def _dbg_sub_ar(message: str, data: Dict[str, Any], hypothesis_id: str) -> None:
    try:
        with open(_DEBUG_LOG_PATH, "a", encoding="utf-8") as f:
            f.write(
                json.dumps(
                    {
                        "sessionId": "e5c18e",
                        "timestamp": int(time.time() * 1000),
                        "location": "sub_ar_refiner.py",
                        "message": message,
                        "hypothesisId": hypothesis_id,
                        "data": data,
                    },
                    ensure_ascii=False,
                )
                + "\n"
            )
    except Exception:
        pass


# #endregion


class SubARRefiner:
    """子 AR 递归细化器"""

    def __init__(self, agent_invoker: "AgentInvoker"):
        self.invoker = agent_invoker
        # 直接持有 M1 agent 实例，避免通过 invoker 的私有属性访问
        self._m1_decomposer = agent_invoker._m1_decomposer
        self._m1_dependency = agent_invoker._m1_dependency

    # ───────────── 单节点细化 ─────────────

    async def _refine_one_sub_ar_node(
        self,
        context: "CoordinatorContext",
        merged: Dict[str, BaseAgentOutput],
        node_id: str,
        hint: Dict[str, Any],
        on_agent_complete: Optional[
            Callable[[str, "CoordinatorContext"], Awaitable[None]]
        ] = None,
    ) -> bool:
        """
        对单个子 AR 节点重跑 M1 Decomposer，将子树写回整树并全量重跑依赖。
        返回 True 表示细化成功；False 表示节点未找到或拼接失败。
        """
        fl = context.artifacts.get("function_list")
        if not isinstance(fl, list) or len(fl) == 0:
            return False
        focus_row = find_function_list_row_by_id(fl, node_id)
        if not focus_row:
            # #region agent log
            sample_ids = [
                norm_function_id(r.get("id"))
                for r in (fl or [])[:25]
                if isinstance(r, dict)
            ]
            _dbg_sub_ar(
                "focus_row_missing",
                {
                    "conversation_id": str(context.conversation_id),
                    "node_id": node_id,
                    "fl_len": len(fl) if isinstance(fl, list) else 0,
                    "id_sample": sample_ids,
                },
                "H4",
            )
            # #endregion
            logger.warning(
                f"[{context.conversation_id}] sub_ar: 未找到节点 {node_id}"
            )
            return False

        title = (focus_row.get("title") or "").strip()
        desc = (focus_row.get("desc") or "").strip()
        synthetic = (
            "【子范围细化】将下列子需求拆分为可开发粒度的功能点列表。\n"
            f"标题：{title}\n说明：{desc}\n"
        )
        instr = (hint.get("split_instruction") or "").strip()
        if instr:
            synthetic += f"评估提示：{instr}\n"

        norm_data = context.artifacts.get("normalized_requirement") or {}
        cfg_saved = dict(context.config or {})
        focus_snapshot = copy.deepcopy(focus_row)

        context.update_stage(PipelineStage.REFINE_SUB_AR)
        task_id = context.conversation_id
        logger.info(f"[{task_id}] M1-Decomposer（子 AR focus_node={node_id}）开始")

        decomp_input = self.invoker._build_input(
            context,
            normalized_requirement=synthetic,
            artifacts={
                "focus_node": focus_snapshot,
                "normalizer_result": self.invoker._slim_norm_for_decomposer(
                    norm_data if isinstance(norm_data, dict) else {}
                ),
            },
        )
        emit = getattr(context, "agent_span_emit", None)
        decomp_output = await with_llm_agent_span(
            context,
            "decomposer",
            f"M1-Decomposer(sub_ar:{node_id})",
            emit,
            self._m1_decomposer.execute(decomp_input),
        )
        merged["decomposer"] = decomp_output
        record_m1_decomposer_invocation(
            self.invoker,
            context,
            source="sub_ar_refinement",
            decomp_input=decomp_input,
            decomp_output=decomp_output,
        )
        self.invoker._apply_decomposer_normalizer_patch(context, decomp_output)

        decomp_result = self.invoker._to_serializable(decomp_output.get_payload())
        _sync = self.invoker._artifacts_from_decomposer_result(decomp_result)
        new_list = _sync.get("function_list") or []
        if not isinstance(new_list, list):
            new_list = []
        new_list = ensure_subtree_splice_anchor_rows(new_list, node_id, focus_snapshot)
        merged_list = splice_subtree_into_function_list(fl, node_id, new_list)
        if merged_list is None:
            logger.warning(
                f"[{task_id}] sub_ar: 列表拼接写回失败 node={node_id}"
            )
            context.config = cfg_saved
            return False

        rebuild_function_list_paths(merged_list)
        context.add_artifact("function_list", merged_list, agent="decomposer")
        core_flow = _sync.get("core_flow") or []
        context.add_artifact("core_flow", core_flow, agent="decomposer")
        context.add_artifact("decomposer_full", decomp_result, agent="decomposer")
        context.config = cfg_saved

        norm_data = context.artifacts.get("normalized_requirement")
        if not isinstance(norm_data, dict):
            norm_data = {}

        merged_list = context.artifacts.get("function_list")
        dep_input = self.invoker._build_input(
            context,
            artifacts={
                "function_list": merged_list,
                "normalizer_result": self.invoker._slim_norm_for_dependency(
                    norm_data if isinstance(norm_data, dict) else {}
                ),
                "core_flow": core_flow,
            },
        )
        dep_output = await with_llm_agent_span(
            context,
            "dependency_classifier",
            f"M1-DependencyClassifier(sub_ar:{node_id})",
            emit,
            self._m1_dependency.execute(dep_input),
        )
        merged["dependency_classifier"] = dep_output
        dep_result = self.invoker._to_serializable(dep_output.get_payload())
        dependencies = self.invoker._to_serializable(dep_result.get("dependencies"))
        if not isinstance(dependencies, list):
            dependencies = []
        context.add_artifact("dependencies", dependencies, agent="dependency_classifier")
        context.add_artifact("dependency_full", dep_result, agent="dependency_classifier")

        context.tree_version += 1
        context.add_artifact("tree_version", context.tree_version, agent="coordinator")

        ne = context.artifacts.get("node_evaluations") or {}
        if not isinstance(ne, dict):
            ne = {}
        append_node_evaluation_history(
            ne,
            node_id,
            {
                "stage": "refine_split",
                "tree_version": context.tree_version,
                "ts": datetime.now().isoformat(),
                "hint": {k: v for k, v in hint.items() if k in (
                    "need_further_split", "split_reason", "split_instruction",
                )},
            },
        )
        context.add_artifact("node_evaluations", ne, agent="coordinator")

        self.invoker._record_quality_flags(context, "dependency_classifier", dep_output)
        if on_agent_complete:
            await on_agent_complete("decomposer", context)
            await on_agent_complete("dependency_classifier", context)

        logger.info(
            f"[{task_id}] M1 子 AR 细化完成 node={node_id} "
            f"tree_version={context.tree_version}"
        )
        return True

    # ───────────── 可实现性驱动递归 ─────────────

    async def _feasibility_failed_walk(
        self,
        context: "CoordinatorContext",
        merged: Dict[str, BaseAgentOutput],
        on_agent_complete: Optional[
            Callable[[str, "CoordinatorContext"], Awaitable[None]]
        ],
        failed_ids: List[str],
        refinement_root_id: str,
        log: List[Dict[str, Any]],
        on_m2_agent_complete: Optional[
            Callable[[str, "CoordinatorContext", Optional[Dict[str, Any]]], Awaitable[None]]
        ] = None,
    ) -> None:
        """
        对可实现性未通过的节点：
          1. 计算节点相对 refinement_root_id 的真实树深；超过配置上限则跳过。
          2. 子范围重拆（_refine_one_sub_ar_node）
          3. 收窄作用域做一致性评估（scoped_fl/deps 以参数传入，不污染 artifacts）
          4. 一致性通过后运行可实现性 + 集成
          5. 仍有失败则递归（传入同一 refinement_root_id）
        """
        cfg = context.config or {}
        max_relative_depth = int(cfg.get("max_feasibility_refinement_depth", 1))
        threshold = float(cfg.get("consistency_pass_threshold", 0.7))
        inner_max = int(cfg.get("consistency_inner_max_retries", 1))

        if not failed_ids:
            return

        for nid_raw in failed_ids:
            nid = norm_function_id(nid_raw)
            if not nid:
                continue

            # 计算该节点相对当前拆分根的真实树深
            fl_current = context.artifacts.get("function_list") or []
            relative_depth = calc_node_depth_from_root(fl_current, refinement_root_id, nid)

            # 深度不可计算（节点不在树中、断链等）视为超限，保守跳过
            if relative_depth is None or relative_depth >= max_relative_depth:
                context.add_quality_flag(
                    "coordinator", "feasibility_refinement_depth_exceeded"
                )
                logger.info(
                    f"[{context.conversation_id}] 节点 {nid} 相对深度 {relative_depth!r} "
                    f">= 上限 {max_relative_depth}，跳过细化"
                )
                continue

            hint = {
                "need_further_split": True,
                "split_reason": "feasibility_failed",
                "split_instruction": "",
            }
            context.sub_ar_refinement_stack.append({
                "node_id": nid,
                "node_depth": relative_depth,
                "refinement_root_id": refinement_root_id,
                "at": datetime.now().isoformat(),
            })
            context.update_stage(PipelineStage.REFINE_SUB_AR)
            ok = await self._refine_one_sub_ar_node(
                context, merged, nid, hint, on_agent_complete
            )
            if not ok:
                context.sub_ar_refinement_stack.pop()
                continue

            fl = context.artifacts.get("function_list")
            deps = context.artifacts.get("dependencies")
            if not isinstance(fl, list):
                context.sub_ar_refinement_stack.pop()
                continue

            child_ids = collect_direct_child_ids_from_rows(fl, nid)
            if not child_ids:
                context.sub_ar_refinement_stack.pop()
                continue

            # 构建收窄作用域的局部副本（仅直接子节点，不含 nid 自身，不写入 context.artifacts）
            scoped_fl = [
                r for r in fl
                if isinstance(r, dict) and norm_function_id(r.get("id")) in child_ids
            ]
            scoped_deps = filter_dependencies_for_node_ids(
                deps if isinstance(deps, list) else [], child_ids
            )

            # 写入 m2_scope 元数据到 artifacts（轻量，无污染风险）
            m2_scope: Dict[str, Any] = {
                "scope_root_node_id": nid,
                "node_depth": relative_depth,
                "refinement_root_id": refinement_root_id,
            }
            context.add_artifact("m2_scope", m2_scope, agent="coordinator")

            scoped_consistency_ok = False
            inner_attempt = 0
            subtree_collapsed_early = False

            while True:
                context.update_stage(PipelineStage.CONSISTENCY)
                # 关键修复：传入 scoped 数据 + write_to_artifacts=False，不污染根层 artifacts
                c_out = await self.invoker.invoke_m2_consistency_only(
                    context,
                    function_list_override=scoped_fl,
                    dependencies_override=scoped_deps,
                    on_m2_agent_complete=on_m2_agent_complete,
                    write_to_artifacts=False,
                )
                merged["consistency_evaluator"] = c_out
                ev_scoped = self.invoker._unwrap_consistency_eval_dict(c_out)
                self.invoker.refresh_m2_inputs_snapshot(
                    context,
                    function_list_override=scoped_fl,
                    dependencies_override=scoped_deps,
                )

                if self.invoker.consistency_evaluation_passes(ev_scoped, threshold):
                    scoped_consistency_ok = True
                    break

                inner_attempt += 1
                remediation = (ev_scoped.get("remediation_instruction") or "").strip()

                if inner_attempt > inner_max:
                    context.add_quality_flag(
                        "consistency_evaluator",
                        "feasibility_refinement_scoped_consistency_failed",
                    )
                    break

                hint_retry = {
                    "need_further_split": True,
                    "split_reason": "scoped_consistency_failed",
                    "split_instruction": remediation or (
                        "Consistency failed on narrowed scope; further split the subtree."
                    ),
                }
                ok = await self._refine_one_sub_ar_node(
                    context, merged, nid, hint_retry, on_agent_complete
                )
                if not ok:
                    break

                fl = context.artifacts.get("function_list")
                deps = context.artifacts.get("dependencies")
                if not isinstance(fl, list):
                    break

                child_ids = collect_direct_child_ids_from_rows(fl, nid)
                if not child_ids:
                    subtree_collapsed_early = True
                    break

                scoped_fl = [
                    r for r in fl
                    if isinstance(r, dict) and norm_function_id(r.get("id")) in child_ids
                ]
                scoped_deps = filter_dependencies_for_node_ids(
                    deps if isinstance(deps, list) else [], child_ids
                )

            # 仅弹出细化栈；保留 m2_scope 直到可实现性+Integrator 完成，
            # 以便 invoke_m2_feasibility_integrator_only 内追加 evaluation_episode 时能正确标为子树。
            context.sub_ar_refinement_stack.pop()

            # 更新子需求列表（基于完整树）
            await apply_sub_requirement_list_artifacts(context, self.invoker)

            if subtree_collapsed_early:
                context.artifacts.pop("m2_scope", None)
                log.append({
                    "scope_root_node_id": nid,
                    "node_depth": relative_depth,
                    "nested_failed": [],
                    "scoped_subtree_single_node": True,
                })
                continue

            if not scoped_consistency_ok:
                context.artifacts.pop("m2_scope", None)
                log.append({
                    "scope_root_node_id": nid,
                    "node_depth": relative_depth,
                    "nested_failed": [],
                    "scoped_consistency_skipped_feasibility": True,
                })
                continue

            context.update_stage(PipelineStage.FEASIBILITY)
            # 关键修复：传入 scoped 数据 + write_to_artifacts=False，不污染根层 artifacts
            # consistency_result_override 传入上方一致性循环最终通过时的 ev_scoped，
            # 避免 invoke_m2_feasibility_integrator_only 从 artifacts 读取根层一致性结果
            try:
                m2p = await self.invoker.invoke_m2_feasibility_integrator_only(
                    context,
                    function_list_override=scoped_fl,
                    on_m2_agent_complete=on_m2_agent_complete,
                    write_to_artifacts=False,
                    consistency_result_override=ev_scoped,
                )
            finally:
                context.artifacts.pop("m2_scope", None)
            merged.update(m2p)
            self.invoker.refresh_m2_inputs_snapshot(
                context,
                function_list_override=scoped_fl,
            )

            # 从返回值中提取可实现性评估结果，避免读取被根层结果污染的 artifacts
            _feas_output = m2p.get("feasibility_evaluator")
            nested_feas: Dict[str, Any] = (
                self.invoker._to_serializable(_feas_output.get_payload())
                if _feas_output is not None
                else {}
            )
            if not isinstance(nested_feas, dict):
                nested_feas = {}
            nested_failed = self.invoker._extract_feasibility_failed_node_ids(nested_feas)

            log.append({
                "scope_root_node_id": nid,
                "node_depth": relative_depth,
                "nested_failed": nested_failed,
            })

            if nested_failed:
                await self._feasibility_failed_walk(
                    context,
                    merged,
                    on_agent_complete,
                    nested_failed,
                    refinement_root_id,
                    log,
                    on_m2_agent_complete,
                )

    async def _run_feasibility_refinement_after_root(
        self,
        context: "CoordinatorContext",
        merged: Dict[str, BaseAgentOutput],
        on_agent_complete: Optional[
            Callable[[str, "CoordinatorContext"], Awaitable[None]]
        ] = None,
        on_m2_agent_complete: Optional[
            Callable[[str, "CoordinatorContext", Optional[Dict[str, Any]]], Awaitable[None]]
        ] = None,
        *,
        refinement_root_id: str = "",
    ) -> None:
        """根层可实现性+集成完成后，按未通过节点做子 AR 递归细化。

        refinement_root_id: 深度预算的根节点 id。
          - 正常拆分传空字符串，此时自动用 F-1 或 function_list 中首个无父节点；
          - refine-node 传用户选择的节点 id。
        """
        cfg = context.config or {}
        if cfg.get("enable_feasibility_refinement") is False:
            return
        max_relative_depth = int(cfg.get("max_feasibility_refinement_depth", 1))
        if max_relative_depth <= 0:
            return

        # 确定深度预算根
        if not refinement_root_id:
            refinement_root_id = self._resolve_refinement_root(context)

        root_eval = copy.deepcopy(context.artifacts.get("evaluation"))
        root_cons = copy.deepcopy(context.artifacts.get("consistency_evaluation"))
        root_feas = copy.deepcopy(context.artifacts.get("feasibility_evaluation") or {})
        failed = self.invoker._extract_feasibility_failed_node_ids(
            root_feas if isinstance(root_feas, dict) else {}
        )
        if not failed:
            return

        log: List[Dict[str, Any]] = []
        await self._feasibility_failed_walk(
            context,
            merged,
            on_agent_complete,
            failed,
            refinement_root_id,
            log,
            on_m2_agent_complete,
        )

        # 根层快照写入 artifacts（替代旧的 workspace 存储）
        context.add_artifact(
            "feasibility_refinement_log", log, agent="coordinator"
        )
        if root_eval is not None:
            context.add_artifact(
                "m2_root_evaluation_snapshot", root_eval, agent="coordinator"
            )
        if root_cons is not None:
            context.add_artifact(
                "m2_root_consistency_evaluation_snapshot", root_cons, agent="coordinator"
            )
        if isinstance(root_feas, dict) and root_feas:
            context.add_artifact(
                "m2_root_feasibility_evaluation_snapshot",
                copy.deepcopy(root_feas),
                agent="coordinator",
            )

    @staticmethod
    def _resolve_refinement_root(context: "CoordinatorContext") -> str:
        """确定正常拆分的深度预算根节点 id。

        优先使用预处理产物根 DECOMPOSITION_ROOT_ID（F-1）；
        若不在当前 function_list 中，退回到 function_list 里首个无父节点；
        均不可用时返回空字符串（_feasibility_failed_walk 会保守跳过所有节点）。
        """
        fl = context.artifacts.get("function_list")
        if not isinstance(fl, list):
            return ""
        ids_in_list = {
            norm_function_id(r.get("id"))
            for r in fl
            if isinstance(r, dict) and norm_function_id(r.get("id"))
        }
        if DECOMPOSITION_ROOT_ID in ids_in_list:
            return DECOMPOSITION_ROOT_ID
        # 回退：第一个无父节点
        for r in fl:
            if not isinstance(r, dict):
                continue
            nid = norm_function_id(r.get("id"))
            pid = norm_function_id(r.get("parent_id"))
            if nid and not pid:
                return nid
        return ""
