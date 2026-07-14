"""
任务管理器 — 管理任务生命周期、与 Orchestrator 协同。
"""
from typing import Dict, Any, Optional, List, Callable, Awaitable
import copy
import logging

from app.services.coordinator.context import CoordinatorContext
from app.services.coordinator.orchestrator import Orchestrator
from app.services.coordinator.final_result_assembler import FinalResultAssembler
from app.services.coordinator.sse_payload_factory import SsePayloadFactory
from app.services.agents.function_list_bridge import function_tree_from_artifacts
from app.repositories.conversation_repo import ConversationRepository
from app.repositories.iteration_repo import IterationRepository
from app.core.enums import TaskMode, PipelineStage

logger = logging.getLogger(__name__)

# 进度回调签名
ProgressCallback = Callable[[str, str, Dict[str, Any]], Awaitable[None]]


class TaskManager:
    """任务管理器"""

    def __init__(
        self,
        conversation_repo: ConversationRepository,
        iteration_repo: IterationRepository,
        orchestrator: Optional[Orchestrator] = None,
    ):
        self.conversation_repo = conversation_repo
        self.iteration_repo = iteration_repo
        self.orchestrator = orchestrator or Orchestrator()
        self.final_assembler = FinalResultAssembler()
        self.sse_factory = SsePayloadFactory()

        # 活动任务 (task_id → context)
        self.active_tasks: Dict[str, CoordinatorContext] = {}

    # ───────────── 任务创建 ─────────────

    async def create_task(
        self,
        conversation_id: str,
        requirement_text: str,
        config: Optional[Dict[str, Any]] = None,
        user_id: Optional[str] = None,
        context: Optional[Dict[str, Any]] = None,
    ) -> str:
        """
        创建新任务。

        若 conversation_id 已存在，则复用；否则新建 conversation。
        context 可含 user_feedback 等，会传入 CoordinatorContext.context。
        """
        conversation = self.conversation_repo.get_conversation(conversation_id)
        if not conversation:
            conversation = self.conversation_repo.create(
                requirement_text=requirement_text,
                config=config or {},
                user_id=user_id,
            )
            conversation_id = conversation.id

        # 创建协调器上下文（含 user_feedback 等）
        coordinator_context = CoordinatorContext(
            conversation_id=conversation_id,
            requirement_text=requirement_text,
            mode=TaskMode.AUTO,
            config=config or {},
            context=context or {},
        )

        # 存储
        self.active_tasks[conversation_id] = coordinator_context

        return conversation_id

    # ───────────── 任务查询 ─────────────

    async def get_task_context(
        self, task_id: str
    ) -> Optional[CoordinatorContext]:
        """获取任务上下文"""
        return self.active_tasks.get(task_id)

    async def get_task_status(self, task_id: str) -> Optional[Dict[str, Any]]:
        """获取任务状态摘要"""
        context = self.active_tasks.get(task_id)
        if not context:
            return None
        return context.to_dict()

    # ───────────── 进度回调 ─────────────

    def register_progress_callback(
        self, task_id: str, callback: ProgressCallback
    ):
        """注册进度回调（委托 orchestrator）"""
        self.orchestrator.register_progress_callback(task_id, callback)

    def unregister_progress_callbacks(self, task_id: str):
        """移除进度回调"""
        self.orchestrator.unregister_progress_callbacks(task_id)

    async def _persist_title_from_normalizer_sse(
        self,
        task_id: str,
        event_type: str,
        payload: Dict[str, Any],
    ) -> None:
        """从 normalizer_preview 的 SSE 载荷写回会话标题（不连 SSE 时列表也能看到）。"""
        if event_type != "intermediate_result" or not isinstance(payload, dict):
            return
        if payload.get("content_type") != "normalizer_preview":
            return
        data = payload.get("data") or {}
        title = data.get("suggested_conversation_title")
        if not title or not isinstance(title, str):
            return
        t = title.strip()
        if not t:
            return
        try:
            self.conversation_repo.update_conversation(task_id, title=t[:255])
        except Exception as ex:
            logger.warning(
                f"[{task_id}] 根据预处理结果更新标题失败: {ex}",
            )

    async def _persist_function_tree_dependencies_bundle_sse(
        self,
        task_id: str,
        event_type: str,
        payload: Dict[str, Any],
    ) -> None:
        """将 function_tree_dependencies_bundle 的 SSE 载荷落库（与 SSE 同源，供重连后 GET 对话还原）。"""
        if event_type != "intermediate_result" or not isinstance(payload, dict):
            return
        if payload.get("content_type") != "function_tree_dependencies_bundle":
            return
        try:
            self.conversation_repo.merge_coordination_live_snapshot(
                task_id,
                "function_tree_dependencies_bundle",
                copy.deepcopy(payload),
            )
        except Exception as ex:
            logger.warning(
                f"[{task_id}] 功能树与依赖 bundle 写入 coordination_live_snapshot 失败: {ex}",
            )

    # ───────────── 任务执行 ─────────────

    async def run_task(self, task_id: str) -> Dict[str, Any]:
        """
        执行任务（在后台调用 Orchestrator.run）。
        通常由 API 层在 BackgroundTasks 中调用。
        """
        context = self.active_tasks.get(task_id)
        if not context:
            raise ValueError(f"任务 {task_id} 不存在或已结束")

        # 更新数据库状态
        self.conversation_repo.update_state(task_id, PipelineStage.IDLE.value, 0)

        # 订阅：预处理完成后将 suggested_conversation_title 落库；
        # 功能树+依赖 bundle 与 SSE 对齐写入 coordination_live_snapshot
        self.register_progress_callback(
            task_id, self._persist_title_from_normalizer_sse
        )
        self.register_progress_callback(
            task_id, self._persist_function_tree_dependencies_bundle_sse
        )

        try:
            final_result = await self.orchestrator.run(
                context=context,
                on_iteration_complete=self._on_iteration_complete,
                on_state_change=self._sync_state_to_db,
            )
            if isinstance(final_result, dict) and final_result.get("stopped_by_user"):
                await self._finalize_stopped_task(task_id, context, final_result)
            else:
                await self._finalize_task(task_id, context)
            return final_result

        except Exception as e:
            logger.error(f"[{task_id}] 任务执行失败: {e}", exc_info=True)
            context.update_stage(PipelineStage.ERROR)
            self.conversation_repo.update_state(
                task_id, PipelineStage.ERROR.value, context.progress
            )
            try:
                partial_result = self.final_assembler.assemble_final_result(context)
                partial_result["error"] = str(e)
                self.conversation_repo.update_result(task_id, partial_result)
                logger.info(f"[{task_id}] 已保存失败任务的部分结果")
            except Exception as save_err:
                logger.warning(f"[{task_id}] 保存部分结果失败: {save_err}")
            raise
        finally:
            # 清理
            self.active_tasks.pop(task_id, None)
            self.unregister_progress_callbacks(task_id)

    def request_stop(self, task_id: str) -> bool:
        """
        用户请求停止任务（协作式取消）。

        在任意阶段均可调用。
        长耗时 LLM 调用需返回后才会退出编排。
        """
        context = self.active_tasks.get(task_id)
        if not context:
            return False
        context.stop_requested = True
        return True

    # ───────────── 迭代回调 ─────────────

    async def _on_iteration_complete(
        self,
        context: CoordinatorContext,
        iteration_number: int,
    ):
        """每轮迭代结束回调 — 持久化迭代快照"""
        # 从 context 的最新快照获取数据
        snapshot = (
            context.iteration_snapshots[-1]
            if context.iteration_snapshots
            else {}
        )

        # 从 evaluation artifact 中提取评分
        evaluation = context.artifacts.get("evaluation", {})

        payload = {
            "artifacts_snapshot": snapshot.get("artifacts_snapshot", {}),
            "quality_flags": snapshot.get("quality_flags", {}),
            "decomposed_requirements": context.artifacts.get(
                "function_list", []
            ),
            "validation_results": context.artifacts.get("evaluation", {}),
            "quality_score": evaluation.get("quality_score"),
            "consistency_score": evaluation.get("consistency_score"),
            "feasibility_score": evaluation.get("feasibility_score"),
            "overall_score": evaluation.get("overall_score"),
            "iteration_metadata": {
                "state_transition_log": context.state_transition_log,
                "progress": context.progress,
                "agents_invoked": snapshot.get("agents_invoked", []),
                "score_delta": snapshot.get("score_delta"),
                "agent_spans": copy.deepcopy(
                    getattr(context, "agent_spans", []) or []
                ),
            },
        }

        self.iteration_repo.save_iteration(
            conversation_id=context.conversation_id,
            iteration_number=iteration_number,
            payload=payload,
        )

        # 同步数据库状态
        self.conversation_repo.update_state(
            context.conversation_id,
            context.pipeline_stage.value,
            context.progress,
        )

        logger.info(
            f"[{context.conversation_id}] 迭代 #{iteration_number} 已持久化"
        )

        self._persist_assistant_iteration_summary(
            context, iteration_number, snapshot
        )

    def _persist_assistant_iteration_summary(
        self,
        context: CoordinatorContext,
        iteration_number: int,
        snapshot: Dict[str, Any],
    ) -> None:
        """将本轮轻量摘要写入 messages（assistant_summary），大产物仍仅存 final_result。"""
        try:
            ft = function_tree_from_artifacts(
                {"function_list": context.artifacts.get("function_list")}
            )
            deps = context.artifacts.get("dependencies")
            ft_preview = self.sse_factory.assemble_function_tree_preview(ft)
            dep_preview = self.sse_factory.assemble_dependencies_preview(deps)
            ft_data = (ft_preview or {}).get("data") or {}
            dep_data = (dep_preview or {}).get("data") or {}
            parts = [
                f"第 {iteration_number} 轮迭代完成：功能树约 {ft_data.get('total_nodes', 0)} 个节点，最大深度 {ft_data.get('max_depth', 0)}。",
                f"依赖关系 {dep_data.get('total_dependencies', 0)} 条。",
            ]
            content = "".join(parts)

            metadata = {
                "stage": "iteration_complete",
                "iteration_number": iteration_number,
                "artifact": "mixed",
                "stats": {
                    "function_tree": {
                        "total_nodes": ft_data.get("total_nodes"),
                        "max_depth": ft_data.get("max_depth"),
                        "leaf_nodes": ft_data.get("leaf_nodes"),
                    },
                    "dependencies": {
                        "total": dep_data.get("total_dependencies"),
                    },
                },
                "detail_ref": "conversation_metadata.final_result",
                "agents_invoked": snapshot.get("agents_invoked", []),
            }
            self.conversation_repo.add_message(
                context.conversation_id,
                role="assistant",
                content=content[:2000],
                message_type="assistant_summary",
                message_metadata=metadata,
            )
        except Exception as e:
            logger.warning(
                f"[{context.conversation_id}] 写入助手迭代摘要消息失败: {e}"
            )

    def _persist_system_task_complete(
        self,
        task_id: str,
        context: CoordinatorContext,
        full_result: Dict[str, Any],
    ) -> None:
        """任务成功结束时写入 system_event，指向完整结果存储位置。"""
        try:
            n = context.iteration_count
            sel = full_result.get("selected_iteration")
            content = (
                f"任务已完成：共 {n} 轮迭代"
                + (f"，选中第 {sel} 轮版本" if sel is not None else "")
                + "。完整结构化结果见 conversation_metadata.final_result。"
            )
            self.conversation_repo.add_message(
                task_id,
                role="system",
                content=content[:2000],
                message_type="system_event",
                message_metadata={
                    "event": "task_completed",
                    "iteration_count": n,
                    "selected_iteration": sel,
                    "detail_ref": "conversation_metadata.final_result",
                },
            )
        except Exception as e:
            logger.warning(f"[{task_id}] 写入系统完成消息失败: {e}")

    # ───────────── 任务完成 ─────────────

    def _sync_state_to_db(self, context: CoordinatorContext):
        """将内存中的 context 状态/进度同步到数据库"""
        try:
            self.conversation_repo.update_state(
                context.conversation_id,
                context.pipeline_stage.value,
                context.progress,
            )
        except Exception as e:
            logger.warning(
                f"[{context.conversation_id}] DB 状态同步失败: {e}"
            )

    async def _finalize_task(
        self,
        task_id: str,
        context: CoordinatorContext,
    ):
        """完成任务 — 持久化最终结果并标记选中版本"""
        # 先将 DONE / progress=100 落库
        self.conversation_repo.update_state(
            task_id, PipelineStage.DONE.value, 100.0
        )

        # 获取迭代记录列表
        iterations = self.iteration_repo.get_iterations(task_id)

        # 使用 ResultAssembler 组装完整最终结果
        version_strategy = context.config.get("version_selection", "latest")
        full_result = self.final_assembler.assemble_final_result(
            context,
            iterations=iterations,
            version_strategy=version_strategy,
        )

        # 标记选中版本
        selected_iter_num = full_result.get("selected_iteration")
        if selected_iter_num is not None:
            self.iteration_repo.mark_selected(task_id, selected_iter_num)

        # 写入最终结果
        self.conversation_repo.update_result(task_id, full_result)

        self._persist_system_task_complete(task_id, context, full_result)

        logger.info(f"[{task_id}] 任务最终结果已持久化 (status=DONE, progress=100)")

    async def _finalize_stopped_task(
        self,
        task_id: str,
        context: CoordinatorContext,
        partial_result: Dict[str, Any],
    ):
        """用户停止后的落库（部分结果 + status=cancelled）"""
        self.conversation_repo.update_state(
            task_id, "cancelled", context.progress
        )
        self.conversation_repo.update_result(task_id, partial_result)
        logger.info(f"[{task_id}] 任务已按用户请求停止并持久化部分结果")
