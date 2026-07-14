"""
编排器（Orchestrator）— 统一流程编排。

职责：
  1. 按 PipelineStage 管线阶段驱动单次编排，终态为 done / error
  2. 协调 AgentInvoker（模块一/二）与 DecisionEngine 的调用
  3. 在关键节点发出"进度回调"以支撑 SSE 实时推送
  4. 迭代结束时拍快照并调用持久化（单次运行 iteration_count=1）
"""
from typing import Dict, Any, Optional, Callable, Awaitable, List, MutableMapping
import copy
import itertools
import logging

from app.core.enums import PipelineStage
from app.services.coordinator.context import CoordinatorContext
from app.services.coordinator.agent_invoker import AgentInvoker
from app.services.coordinator.sub_ar_refiner import SubARRefiner
from app.services.coordinator.pipeline_runner import PipelineRunner
from app.services.coordinator.decision_engine import DecisionEngine
from app.services.coordinator.final_result_assembler import FinalResultAssembler
from app.services.coordinator.sse_payload_factory import SsePayloadFactory
from app.services.coordinator.global_report_builder import build_global_report
from app.services.agents.function_list_bridge import function_tree_from_artifacts

logger = logging.getLogger(__name__)

# 进度回调签名: async def callback(task_id, event_type, payload)
ProgressCallback = Callable[[str, str, Dict[str, Any]], Awaitable[None]]


def _apply_sse_family_metadata(
    context: CoordinatorContext,
    payload: MutableMapping[str, Any],
    family_key: str,
) -> None:
    prev = context.sse_last_by_family.get(family_key)
    payload["supersedes_sse_sequence"] = prev if prev is not None else None
    payload["artifact_family"] = family_key


def _record_sse_family(
    context: CoordinatorContext,
    payload: MutableMapping[str, Any],
    family_key: str,
) -> None:
    seq = payload.get("sse_sequence")
    if seq is not None:
        context.sse_last_by_family[family_key] = int(seq)


class Orchestrator:
    """编排器 — 驱动协调流程（单次主运行 + 用户节点重拆见 API refine-node）"""

    def __init__(
        self,
        pipeline_runner: Optional[PipelineRunner] = None,
        decision_engine: Optional[DecisionEngine] = None,
        final_assembler: Optional[FinalResultAssembler] = None,
        sse_factory: Optional[SsePayloadFactory] = None,
    ):
        if pipeline_runner is None:
            _invoker = AgentInvoker()
            _sub_ar = SubARRefiner(_invoker)
            pipeline_runner = PipelineRunner(_invoker, _sub_ar)
        self.pipeline_runner = pipeline_runner
        self.decision_engine = decision_engine or DecisionEngine()
        self.final_assembler = final_assembler or FinalResultAssembler()
        self.sse_factory = sse_factory or SsePayloadFactory()

        # 进度推送回调列表（由 TaskManager / API 层注入）
        self._progress_callbacks: Dict[str, List[ProgressCallback]] = {}

    # ─────────────── 回调管理 ───────────────

    def register_progress_callback(
        self, task_id: str, callback: ProgressCallback
    ):
        """注册进度回调（用于 SSE 推送）"""
        if task_id not in self._progress_callbacks:
            self._progress_callbacks[task_id] = []
        self._progress_callbacks[task_id].append(callback)

    def unregister_progress_callbacks(self, task_id: str):
        """移除指定任务的所有回调"""
        self._progress_callbacks.pop(task_id, None)

    async def _emit(
        self, task_id: str, event_type: str, payload: Dict[str, Any]
    ):
        """触发进度回调"""
        callbacks = self._progress_callbacks.get(task_id, [])
        for cb in callbacks:
            try:
                await cb(task_id, event_type, payload)
            except Exception as e:
                logger.warning(f"进度回调执行失败: {e}")

    # ─────────────── 主流程（单次） ───────────────

    async def run(
        self,
        context: CoordinatorContext,
        on_iteration_complete: Optional[Callable] = None,
        on_state_change: Optional[Callable] = None,
    ) -> Dict[str, Any]:
        """
        执行编排：单次一致性优先管线，无外层自动重试；用户重拆见 refine-node API。
        """
        task_id = context.conversation_id
        self._on_state_change = on_state_change
        logger.info(f"[{task_id}] 编排开始")

        _sse_intermediate_seq = itertools.count(1)

        def _stamp_intermediate_sse(p: Dict[str, Any]) -> None:
            p["sse_sequence"] = next(_sse_intermediate_seq)

        async def _emit_agent_span(
            phase: str, ctx: CoordinatorContext, span_id: str
        ) -> None:
            span_row = ctx.get_agent_span(span_id)
            payload: Dict[str, Any] = {
                "type": "AGENT_TIMELINE",
                "phase": phase,
                "span": copy.deepcopy(span_row) if span_row else None,
                "pipeline_stage": ctx.pipeline_stage.value,
                "progress": ctx.progress,
                "running_spans": ctx.list_running_agent_spans(),
            }
            _stamp_intermediate_sse(payload)
            await self._emit(task_id, "agent_timeline", payload)

        context.agent_span_emit = _emit_agent_span

        try:
            context.update_stage(PipelineStage.SPLIT)
            self._notify_state_change(context)
            context.progress = 10.0
            context.iteration_count = 1
            await self._emit_intermediate(
                task_id,
                context,
                "开始需求拆分并执行拆分与依赖分析（标准化 → 功能树 → 依赖 → 子需求列表 → 一致性 → 评估）",
                _stamp_intermediate_sse,
            )

            if context.stop_requested:
                return await self._finish_stopped(task_id, context)

            async def _on_m1_agent_complete(agent_name: str, ctx: CoordinatorContext):
                if agent_name == "normalizer":
                    norm = ctx.artifacts.get("normalized_requirement")
                    payload = self.sse_factory.assemble_normalizer_preview(
                        norm, stage="需求标准化"
                    )
                    payload["pipeline_stage"] = ctx.pipeline_stage.value
                    _apply_sse_family_metadata(
                        ctx, payload, "normalizer_preview"
                    )
                    _stamp_intermediate_sse(payload)
                    _record_sse_family(ctx, payload, "normalizer_preview")
                    await self._emit(task_id, "intermediate_result", payload)
                elif agent_name == "decomposer":
                    ft = function_tree_from_artifacts(
                        {"function_list": ctx.artifacts.get("function_list")}
                    )
                    stage = "功能拆分"
                    if ctx.pipeline_stage == PipelineStage.REFINE_SUB_AR:
                        stage = "子AR递归细化"
                    payload = self.sse_factory.assemble_function_tree_preview(
                        ft, stage=stage
                    )
                    payload["pipeline_stage"] = ctx.pipeline_stage.value
                    payload["tree_version"] = getattr(ctx, "tree_version", 0)
                    _apply_sse_family_metadata(
                        ctx, payload, "function_tree_preview"
                    )
                    _stamp_intermediate_sse(payload)
                    _record_sse_family(ctx, payload, "function_tree_preview")
                    await self._emit(task_id, "intermediate_result", payload)
                elif agent_name == "dependency_classifier":
                    deps = ctx.artifacts.get("dependencies")
                    payload = self.sse_factory.assemble_dependencies_preview(
                        deps, stage="依赖分析"
                    )
                    _apply_sse_family_metadata(
                        ctx, payload, "dependencies_preview"
                    )
                    _stamp_intermediate_sse(payload)
                    _record_sse_family(ctx, payload, "dependencies_preview")
                    await self._emit(task_id, "intermediate_result", payload)
                    ft = function_tree_from_artifacts(
                        {"function_list": ctx.artifacts.get("function_list")}
                    )
                    stage = "功能拆分"
                    if ctx.pipeline_stage == PipelineStage.REFINE_SUB_AR:
                        stage = "子AR递归细化"
                    bundle = self.sse_factory.assemble_function_tree_dependencies_bundle(
                        ft,
                        deps,
                        tree_stage=stage,
                    )
                    bundle["pipeline_stage"] = ctx.pipeline_stage.value
                    bundle["tree_version"] = getattr(ctx, "tree_version", 0)
                    _apply_sse_family_metadata(
                        ctx, bundle, "function_tree_dependencies_bundle"
                    )
                    _stamp_intermediate_sse(bundle)
                    _record_sse_family(ctx, bundle, "function_tree_dependencies_bundle")
                    await self._emit(task_id, "intermediate_result", bundle)

            async def _on_m2_agent_complete(
                agent_name: str,
                ctx: CoordinatorContext,
                result_payload: Optional[Dict[str, Any]] = None,
            ):
                payload = self.sse_factory.assemble_m2_agent_complete(
                    agent_name, ctx, result_payload=result_payload
                )
                fam = f"m2:{agent_name}"
                _apply_sse_family_metadata(ctx, payload, fam)
                _stamp_intermediate_sse(payload)
                _record_sse_family(ctx, payload, fam)
                await self._emit(task_id, "intermediate_result", payload)

            async def _on_list_ready(ctx: CoordinatorContext):
                sub = ctx.artifacts.get("sub_requirement_list")
                payload = self.sse_factory.assemble_sub_requirement_list_preview(
                    sub, stage="子需求列表"
                )
                _apply_sse_family_metadata(
                    ctx, payload, "sub_requirement_list_preview"
                )
                _stamp_intermediate_sse(payload)
                _record_sse_family(ctx, payload, "sub_requirement_list_preview")
                await self._emit(task_id, "intermediate_result", payload)

            m1_results = await self.pipeline_runner.invoke_consistency_first_pipeline(
                context,
                on_agent_complete=_on_m1_agent_complete,
                on_list_ready=_on_list_ready,
                on_m2_agent_complete=_on_m2_agent_complete,
            )
            all_results = dict(m1_results)

            if context.stop_requested:
                return await self._finish_stopped(task_id, context)

            context.progress = 85.0
            await self._emit_intermediate(
                task_id,
                context,
                "已完成本阶段（子需求列表 → 一致性 → 可实现性与综合评估）",
                _stamp_intermediate_sse,
            )
            context.progress = min(context.progress + 15, 90)
            context.progress = min(context.progress + 10, 95)

            await self._emit_intermediate(
                task_id,
                context,
                "汇总质量标记与评估说明（无外层自动重试；可按节点使用 refine-node）",
                _stamp_intermediate_sse,
            )

            context.take_iteration_snapshot()
            if on_iteration_complete:
                await on_iteration_complete(context, context.iteration_count)

            decision = await self.decision_engine.make_iteration_decision(
                context, all_results
            )
            context.artifacts["coordinator_decision"] = decision.model_dump()
            logger.info(
                f"[{task_id}] 决策摘要: reason={decision.reason}"
            )

            context.update_stage(PipelineStage.DONE)
            self._notify_state_change(context)
            context.progress = 100.0

            global_report = await self._generate_global_report(context)
            context.artifacts["global_report"] = global_report

            final_result = self.final_assembler.assemble_final_result(context)
            final_result["coordinator_decision"] = decision.model_dump()

            await self._emit(task_id, "completed", final_result)
            logger.info(f"[{task_id}] 编排完成")

            return final_result

        except Exception as e:
            logger.error(f"[{task_id}] 编排失败: {e}", exc_info=True)
            context.update_stage(PipelineStage.ERROR)
            self._notify_state_change(context)
            await self._emit(task_id, "error", {
                "error": str(e),
                "pipeline_stage": context.pipeline_stage.value,
                "coord_kind": "main",
            })
            raise

        finally:
            context.agent_span_emit = None
            self.unregister_progress_callbacks(task_id)

    async def run_refine_node(
        self,
        context: CoordinatorContext,
        node_id: str,
        user_instruction: str = "",
        on_iteration_complete: Optional[Callable] = None,
        on_state_change: Optional[Callable] = None,
    ) -> Dict[str, Any]:
        """
        在已有最终产物上，对指定节点重拆并重新跑列表→一致性→可实现性尾部。
        """
        task_id = context.conversation_id
        self._on_state_change = on_state_change
        logger.info(f"[{task_id}] refine-node 开始 node={node_id}")

        _sse_intermediate_seq = itertools.count(1)

        def _stamp_intermediate_sse(p: Dict[str, Any]) -> None:
            p["sse_sequence"] = next(_sse_intermediate_seq)

        async def _emit_agent_span(
            phase: str, ctx: CoordinatorContext, span_id: str
        ) -> None:
            span_row = ctx.get_agent_span(span_id)
            payload: Dict[str, Any] = {
                "type": "AGENT_TIMELINE",
                "phase": phase,
                "span": copy.deepcopy(span_row) if span_row else None,
                "pipeline_stage": ctx.pipeline_stage.value,
                "progress": ctx.progress,
                "running_spans": ctx.list_running_agent_spans(),
            }
            _stamp_intermediate_sse(payload)
            await self._emit(task_id, "agent_timeline", payload)

        context.agent_span_emit = _emit_agent_span

        try:
            context.iteration_count += 1
            context.progress = 15.0
            await self._emit_intermediate(
                task_id,
                context,
                f"对节点 {node_id} 执行用户重拆并再评估",
                _stamp_intermediate_sse,
            )

            async def _on_m1_agent_complete(agent_name: str, ctx: CoordinatorContext):
                if agent_name == "normalizer":
                    norm = ctx.artifacts.get("normalized_requirement")
                    payload = self.sse_factory.assemble_normalizer_preview(
                        norm, stage="需求标准化"
                    )
                    payload["pipeline_stage"] = ctx.pipeline_stage.value
                    _apply_sse_family_metadata(
                        ctx, payload, "normalizer_preview"
                    )
                    _stamp_intermediate_sse(payload)
                    _record_sse_family(ctx, payload, "normalizer_preview")
                    await self._emit(task_id, "intermediate_result", payload)
                elif agent_name == "decomposer":
                    ft = function_tree_from_artifacts(
                        {"function_list": ctx.artifacts.get("function_list")}
                    )
                    stage = "功能拆分"
                    if ctx.pipeline_stage == PipelineStage.REFINE_SUB_AR:
                        stage = "子AR递归细化"
                    payload = self.sse_factory.assemble_function_tree_preview(
                        ft, stage=stage
                    )
                    payload["pipeline_stage"] = ctx.pipeline_stage.value
                    payload["tree_version"] = getattr(ctx, "tree_version", 0)
                    _apply_sse_family_metadata(
                        ctx, payload, "function_tree_preview"
                    )
                    _stamp_intermediate_sse(payload)
                    _record_sse_family(ctx, payload, "function_tree_preview")
                    await self._emit(task_id, "intermediate_result", payload)
                elif agent_name == "dependency_classifier":
                    deps = ctx.artifacts.get("dependencies")
                    payload = self.sse_factory.assemble_dependencies_preview(
                        deps, stage="依赖分析"
                    )
                    _apply_sse_family_metadata(
                        ctx, payload, "dependencies_preview"
                    )
                    _stamp_intermediate_sse(payload)
                    _record_sse_family(ctx, payload, "dependencies_preview")
                    await self._emit(task_id, "intermediate_result", payload)
                    ft = function_tree_from_artifacts(
                        {"function_list": ctx.artifacts.get("function_list")}
                    )
                    stage = "功能拆分"
                    if ctx.pipeline_stage == PipelineStage.REFINE_SUB_AR:
                        stage = "子AR递归细化"
                    bundle = self.sse_factory.assemble_function_tree_dependencies_bundle(
                        ft,
                        deps,
                        tree_stage=stage,
                    )
                    bundle["pipeline_stage"] = ctx.pipeline_stage.value
                    bundle["tree_version"] = getattr(ctx, "tree_version", 0)
                    _apply_sse_family_metadata(
                        ctx, bundle, "function_tree_dependencies_bundle"
                    )
                    _stamp_intermediate_sse(bundle)
                    _record_sse_family(ctx, bundle, "function_tree_dependencies_bundle")
                    await self._emit(task_id, "intermediate_result", bundle)

            async def _on_m2_agent_complete(
                agent_name: str,
                ctx: CoordinatorContext,
                result_payload: Optional[Dict[str, Any]] = None,
            ):
                payload = self.sse_factory.assemble_m2_agent_complete(
                    agent_name, ctx, result_payload=result_payload
                )
                fam = f"m2:{agent_name}"
                _apply_sse_family_metadata(ctx, payload, fam)
                _stamp_intermediate_sse(payload)
                _record_sse_family(ctx, payload, fam)
                await self._emit(task_id, "intermediate_result", payload)

            async def _on_list_ready(ctx: CoordinatorContext):
                sub = ctx.artifacts.get("sub_requirement_list")
                payload = self.sse_factory.assemble_sub_requirement_list_preview(
                    sub, stage="子需求列表"
                )
                _apply_sse_family_metadata(
                    ctx, payload, "sub_requirement_list_preview"
                )
                _stamp_intermediate_sse(payload)
                _record_sse_family(ctx, payload, "sub_requirement_list_preview")
                await self._emit(task_id, "intermediate_result", payload)

            all_results = await self.pipeline_runner.refine_node_and_run_m2_tail(
                context,
                node_id,
                user_instruction=user_instruction,
                on_agent_complete=_on_m1_agent_complete,
                on_list_ready=_on_list_ready,
                on_m2_agent_complete=_on_m2_agent_complete,
            )

            if context.stop_requested:
                partial = self.final_assembler.assemble_final_result(context)
                partial["stopped_by_user"] = True
                await self._emit(task_id, "completed", partial)
                return partial

            context.progress = 85.0
            await self._emit_intermediate(
                task_id,
                context,
                "节点重拆阶段已完成",
                _stamp_intermediate_sse,
            )

            context.take_iteration_snapshot()
            if on_iteration_complete:
                await on_iteration_complete(context, context.iteration_count)

            decision = await self.decision_engine.make_iteration_decision(
                context, dict(all_results)
            )
            context.artifacts["coordinator_decision"] = decision.model_dump()

            context.update_stage(PipelineStage.DONE)
            context.progress = 100.0
            if self._on_state_change:
                try:
                    self._on_state_change(context)
                except Exception as e:
                    logger.warning(f"on_state_change 回调失败: {e}")

            global_report = await self._generate_global_report(context)
            context.artifacts["global_report"] = global_report

            final_result = self.final_assembler.assemble_final_result(context)
            final_result["coordinator_decision"] = decision.model_dump()

            await self._emit(task_id, "completed", final_result)
            logger.info(f"[{task_id}] refine-node 完成")
            return final_result

        except Exception as e:
            logger.error(f"[{task_id}] refine-node 失败: {e}", exc_info=True)
            context.update_stage(PipelineStage.ERROR)
            # 不落库 ERROR：API 层会回滚到重拆前；避免在回滚前把会话写成 error。
            await self._emit(task_id, "error", {
                "error": str(e),
                "pipeline_stage": context.pipeline_stage.value,
                "coord_kind": "refine_node",
                "refine_target_node_id": node_id,
            })
            raise
        finally:
            context.agent_span_emit = None
            self.unregister_progress_callbacks(task_id)

    async def _finish_stopped(
        self,
        task_id: str,
        context: CoordinatorContext,
    ) -> Dict[str, Any]:
        context.update_stage(PipelineStage.ERROR)
        self._notify_state_change(context)
        partial = self.final_assembler.assemble_final_result(context)
        partial["stopped_by_user"] = True
        await self._emit(task_id, "completed", partial)
        logger.info(f"[{task_id}] 编排因用户停止结束")
        return partial

    # ─────────────── 内部辅助 ───────────────

    async def _generate_global_report(self, context: CoordinatorContext) -> Dict[str, Any]:
        """调用全局报告生成器，失败时返回空报告（不中断主流程）。"""
        task_id = context.conversation_id
        try:
            invoker = self.pipeline_runner.invoker
            return await build_global_report(context, invoker._m2_integrator)
        except Exception as e:
            logger.warning(f"[{task_id}] 全局报告生成异常（已兜底跳过）: {e}")
            return {
                "summary": "",
                "recommendation": "",
                "overall_score": 0.0,
                "risk_level": "none",
                "per_scope_digest": [],
                "error": str(e),
            }

    def _notify_state_change(self, context: CoordinatorContext) -> None:
        """触发 DB 状态同步回调（无 FSM，直接通知）。"""
        if self._on_state_change:
            try:
                self._on_state_change(context)
            except Exception as e:
                logger.warning(f"on_state_change 回调失败: {e}")

    async def _emit_intermediate(
        self,
        task_id: str,
        context: CoordinatorContext,
        description: str,
        stamp_intermediate_sse: Callable[[Dict[str, Any]], None],
    ):
        """推送管线状态（与其它 intermediate_result 同信封，事件名为 intermediate_result）。"""
        cur = context.pipeline_stage.value
        payload = self.sse_factory.assemble_pipeline_status_intermediate(
            context, cur, description=description
        )
        _apply_sse_family_metadata(context, payload, "pipeline_status")
        stamp_intermediate_sse(payload)
        _record_sse_family(context, payload, "pipeline_status")
        await self._emit(task_id, "intermediate_result", payload)
