"""
协调器相关的 API 端点

推荐顺序（避免错过早期进度事件）：先 GET /tasks/{conversation_id}/stream 建立 SSE，
再 POST /coordinator/start；task_id 与 conversation_id 同值。
调试 M2 时可 GET /tasks/{conversation_id}/m2-input 查看 M1 产物与各 M2 智能体收到的完整 AgentInput。
调试 M1 时可 GET .../debug/m1-normalizer（预处理产物）、.../debug/m1-decomposer-timeline（拆分调用次数与每次输入输出）。
实时智能体耗时与状态：GET /tasks/{conversation_id}/timeline；SSE 事件名 `agent_timeline`（与既有 `intermediate_result` 并列）。
默认编排为一致性优先单路径。
"""
import asyncio
import copy
import json
import logging
import time
from datetime import datetime, timezone
from typing import Dict, Any, Optional, List
from urllib.parse import quote as _url_quote

from fastapi import APIRouter, Depends, HTTPException, status, BackgroundTasks
from fastapi.responses import StreamingResponse, Response
from sqlalchemy.orm import Session

from app.core.database import get_db, SessionLocal
from app.core.dependencies import get_current_user
from app.core.enums import TaskMode, PipelineStage
from app.schemas.coordinator import (
    CoordinationRequest,
    CoordinationResponse,
    RefineNodeRequest,
)
from app.schemas.coordinator_task_config_choices import (
    CoordinatorTaskConfigChoicesResponse,
)
from app.services.coordinator.config_task_choice_catalog import (
    build_task_config_choice_catalog,
)
from app.repositories.conversation_repo import ConversationRepository
from app.repositories.iteration_repo import IterationRepository
from app.services.coordinator.task_manager import TaskManager
from app.services.coordinator.orchestrator import Orchestrator
from app.services.coordinator.final_result_assembler import FinalResultAssembler
from app.services.coordinator.context import CoordinatorContext
from app.services.coordinator.context_hydrator import ContextHydrator
from app.services.coordinator.task_registry import task_registry, sse_manager, PENDING_SSE_MAX_SECONDS
from app.services.coordinator.agent_timeline import build_timeline_api_body
from app.services.agents.M1.focus_from_normalizer import build_focus_node_from_normalizer

logger = logging.getLogger(__name__)


def _rollback_refine_node_attempt(db: Session, task_id: str, snap: Dict[str, Any]) -> None:
    """单次 refine-node 失败或用户取消本次重拆后，恢复到发起重拆前的会话状态（含可能多写的迭代记录）。"""
    try:
        it_repo = IterationRepository(db)
        it_repo.delete_iterations_with_number_gt(
            task_id, int(snap.get("max_iteration_number", 0))
        )
    except Exception as ex:
        logger.warning("[%s] refine-node 失败回滚：清理迭代记录异常: %s", task_id, ex)
    try:
        fr = snap.get("final_result")
        if not isinstance(fr, dict):
            fr = {}
        live = snap.get("coordination_live_snapshot")
        if not isinstance(live, dict):
            live = {}
        ConversationRepository(db).restore_after_failed_refine(
            task_id,
            status=str(snap.get("status") or PipelineStage.DONE.value),
            progress=float(snap.get("progress", 100.0)),
            final_result=fr,
            coordination_live_snapshot=live,
        )
        logger.info("[%s] refine-node 失败：已回退到重拆前状态", task_id)
    except Exception as ex:
        logger.warning("[%s] refine-node 失败回滚：恢复会话元数据异常: %s", task_id, ex)


def _parse_pipeline_stage(raw: Any) -> PipelineStage:
    """从持久化字段或 conversations.status 恢复管线阶段；非法则 idle。"""
    if raw is None:
        return PipelineStage.IDLE
    s = str(raw).strip()
    if not s:
        return PipelineStage.IDLE
    try:
        return PipelineStage(s)
    except ValueError:
        return PipelineStage.IDLE

router = APIRouter()


# ───────────── 解析任务 config 可选目录（前端表单） ─────────────


@router.get(
    "/config/task-choice-groups",
    response_model=CoordinatorTaskConfigChoicesResponse,
    summary="解析任务部分配置的可选值列表",
)
async def get_task_config_choice_groups(
    current_user: dict = Depends(get_current_user),
):
    """
    返回 `consistency_inner_max_retries`、`max_feasibility_refinement_depth`、
    `continue_pipeline_after_consistency_exhausted` 三组：**键说明**、**后端默认值**、
    **推荐可选值**（含 label/description）。

    前端可从每组 `options` 中选一项写入 `POST /coordinator/start` 的 `config`；
    不需要覆盖时使用 **`omit_means_default`**：直接省略该键即可采用 `default_value`。
    """
    _ = current_user  # 与其它协调器路由一致，需登录
    return build_task_config_choice_catalog()


# ───────────── 依赖注入辅助 ─────────────

def _build_task_manager(db: Session) -> TaskManager:
    """构建 TaskManager 实例（每次请求一个）"""
    conversation_repo = ConversationRepository(db)
    iteration_repo = IterationRepository(db)
    orchestrator = Orchestrator()
    return TaskManager(
        conversation_repo=conversation_repo,
        iteration_repo=iteration_repo,
        orchestrator=orchestrator,
    )


# ───────────── 1. 启动协调 ─────────────

@router.post("/start", response_model=CoordinationResponse)
async def start_coordination(
    request: CoordinationRequest,
    background_tasks: BackgroundTasks,
    current_user: dict = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    启动协调处理（真正创建任务并后台执行 orchestrator）。

    推荐先建立 SSE：GET /tasks/{conversation_id}/stream，再调用本接口，
    以免错过编排早期的 progress 事件。
    """
    conversation_repo = ConversationRepository(db)

    # 获取对话
    conversation = conversation_repo.get_conversation(request.conversation_id)
    if not conversation:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="对话不存在",
        )

    if conversation.user_id != current_user.get("id"):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="权限不足",
        )

    # 配置
    meta_cfg = {}
    if conversation.conversation_metadata and isinstance(
        conversation.conversation_metadata, dict
    ):
        meta_cfg = conversation.conversation_metadata.get("config") or {}
    if not isinstance(meta_cfg, dict):
        meta_cfg = {}
    config = {**meta_cfg, **(request.config or {})}

    # 聊天式多轮：若有 user_feedback 则先写入 messages，再加载历史反馈
    context: Dict[str, Any] = {}
    if request.user_feedback:
        conversation_repo.add_message(
            request.conversation_id,
            role="user",
            content=request.user_feedback,
            message_type="iteration_feedback",
        )
    feedbacks = conversation_repo.get_iteration_feedbacks(
        request.conversation_id, limit=10
    )
    if feedbacks:
        # 按时间正序合并（最早→最新），便于智能体理解
        merged = "\n\n".join(
            m.content for m in reversed(feedbacks) if m.content
        )
        if merged:
            context["user_feedback"] = merged

    # 构建 TaskManager
    iteration_repo = IterationRepository(db)
    orchestrator = Orchestrator()
    task_manager = TaskManager(
        conversation_repo=conversation_repo,
        iteration_repo=iteration_repo,
        orchestrator=orchestrator,
    )

    # 创建任务（传入 context 含 user_feedback）
    task_id = await task_manager.create_task(
        conversation_id=request.conversation_id,
        requirement_text=conversation.original_requirement,
        config=config,
        user_id=current_user.get("id"),
        context=context if context else None,
    )

    # 注册到全局表
    task_registry.register(task_id, task_manager)

    # 挂载已在 start 前建立的 SSE 订阅（单例 forward）
    sse_manager.ensure_forward(task_id, task_manager)

    # 后台执行（使用独立 DB session，避免 request-scoped session 生命周期问题）
    async def _run_in_background():
        bg_db = SessionLocal()
        try:
            task_manager.conversation_repo = ConversationRepository(bg_db)
            task_manager.iteration_repo = IterationRepository(bg_db)
            await task_manager.run_task(task_id)
        except Exception as e:
            logger.error(f"后台任务 {task_id} 失败: {e}", exc_info=True)
        finally:
            bg_db.close()
            task_registry.unregister(task_id)
            sse_manager.on_task_finished(task_id)

    background_tasks.add_task(_run_in_background)

    return CoordinationResponse(
        task_id=task_id,
        conversation_id=request.conversation_id,
        status="started",
        message="协调任务已启动",
    )


# ───────────── 2. 查询任务状态 ─────────────

@router.get("/status/{task_id}")
async def get_task_status(
    task_id: str,
    current_user: dict = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """获取任务状态"""
    task_manager = task_registry.get(task_id)

    if task_manager:
        # 任务仍在运行
        task_status = await task_manager.get_task_status(task_id)
        if task_status:
            return {
                "task_id": task_id,
                "status": "running",
                **task_status,
            }

    # 任务不在内存中，从数据库查
    conversation_repo = ConversationRepository(db)
    conversation = conversation_repo.get_conversation(task_id)
    if not conversation:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="任务不存在",
        )

    meta = conversation.conversation_metadata or {}
    return {
        "task_id": task_id,
        "status": conversation.status or "unknown",
        "progress": meta.get("progress", 0),
        "current_step": None,
        "iteration_count": conversation.current_iteration,
        "result": meta.get("final_result"),
        "created_at": conversation.created_at.isoformat() if conversation.created_at else None,
        "updated_at": conversation.updated_at.isoformat() if conversation.updated_at else None,
    }


# ───────────── 3. SSE 实时推送 ─────────────

@router.get("/tasks/{task_id}/stream")
async def stream_task_progress(
    task_id: str,
    current_user: dict = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    SSE — 实时推送任务进度与中间结果。

    **可在 POST /coordinator/start 之前连接**（需对话已存在且属当前用户）：
    先登记队列，待 start 后自动挂载到同一任务的广播回调，不会错过早期事件。

    task_id 与 conversation_id 相同；推荐顺序：先本接口，再 start。
    """
    conversation_repo = ConversationRepository(db)
    conversation = conversation_repo.get_conversation(task_id)
    if not conversation:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="对话不存在",
        )
    if conversation.user_id != current_user.get("id"):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="权限不足",
        )

    event_queue = sse_manager.add_queue(task_id)

    tm = task_registry.get(task_id)
    if tm is not None:
        sse_manager.ensure_forward(task_id, tm)

    ever_had_active_task = tm is not None
    pending_deadline = (
        time.monotonic() + PENDING_SSE_MAX_SECONDS
        if not ever_had_active_task
        else None
    )

    async def _event_generator():
        nonlocal ever_had_active_task, pending_deadline
        try:
            while True:
                try:
                    event = await asyncio.wait_for(
                        event_queue.get(), timeout=30
                    )
                    event_type = event.get("event", "progress")
                    data = json.dumps(
                        event.get("data", {}), ensure_ascii=False, default=str
                    )
                    yield f"event: {event_type}\ndata: {data}\n\n"

                    if event_type in ("completed", "error"):
                        break

                except asyncio.TimeoutError:
                    hb = {
                        "server_time": datetime.now(timezone.utc).isoformat(),
                        "last_sse_sequence": sse_manager.get_last_seq(task_id),
                    }
                    yield (
                        "event: heartbeat\ndata: "
                        + json.dumps(hb, ensure_ascii=False)
                        + "\n\n"
                    )

                    if task_id in task_registry:
                        ever_had_active_task = True
                        pending_deadline = None
                    elif ever_had_active_task:
                        yield (
                            f'event: completed\ndata: {json.dumps({"message": "任务已结束"}, ensure_ascii=False)}\n\n'
                        )
                        break
                    else:
                        if (
                            pending_deadline is not None
                            and time.monotonic() > pending_deadline
                        ):
                            err = {
                                "message": "等待协调启动超时，请重新连接或先 POST /coordinator/start",
                                "code": "PENDING_SSE_TIMEOUT",
                            }
                            yield (
                                f"event: error\ndata: {json.dumps(err, ensure_ascii=False)}\n\n"
                            )
                            break

        except asyncio.CancelledError:
            pass
        finally:
            sse_manager.remove_queue(task_id, event_queue)

    return StreamingResponse(
        _event_generator(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )


@router.get("/tasks/{task_id}/timeline")
async def get_task_timeline(
    task_id: str,
    current_user: dict = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    聚合时间线：事件流（与最终结果中 `timeline` 同源）+ 智能体调用跨度 `agent_spans`。

    - **running_spans**：`ended_at` 为空的调用（任务进行中时通常长度为 0 或 1）。
    - **completed_spans**：已结束调用及 **duration_minutes**（分钟）。
    - **agents_summary**：按 agent 汇总的调用次数与累计 **total_duration_minutes**。

    运行中任务读内存上下文；已结束任务读 `final_result`；若无则尝试最后一次迭代快照中的 `agent_spans`。
    """
    conversation_repo = ConversationRepository(db)
    conversation = conversation_repo.get_conversation(task_id)
    if not conversation:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="对话不存在",
        )
    if conversation.user_id != current_user.get("id"):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="权限不足",
        )

    assembler = FinalResultAssembler()
    task_manager = task_registry.get(task_id)
    if task_manager:
        ctx = await task_manager.get_task_context(task_id)
        if ctx:
            events = assembler._build_timeline(ctx)
            agent_spans = getattr(ctx, "agent_spans", None) or []
            if not isinstance(agent_spans, list):
                agent_spans = []
            return build_timeline_api_body(
                task_id=task_id,
                source="active_task",
                pipeline_stage=ctx.pipeline_stage.value,
                progress=ctx.progress,
                agent_spans=agent_spans,
                events_timeline=events,
            )

    meta = conversation.conversation_metadata or {}
    final_result = meta.get("final_result")
    if isinstance(final_result, dict):
        events = final_result.get("timeline") or []
        if not isinstance(events, list):
            events = []
        agent_spans = final_result.get("agent_spans") or []
        if not isinstance(agent_spans, list):
            agent_spans = []
        return build_timeline_api_body(
            task_id=task_id,
            source="final_result",
            pipeline_stage=final_result.get("pipeline_stage"),
            progress=final_result.get("progress"),
            agent_spans=agent_spans,
            events_timeline=events,
        )

    iteration_repo = IterationRepository(db)
    iterations = iteration_repo.get_iterations(task_id)
    if not iterations:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="尚无任务时间线数据",
        )
    last = iterations[-1]
    meta_it = last.iteration_metadata or {}
    events = meta_it.get("state_transition_log")
    if not isinstance(events, list):
        events = []
    arts = last.artifacts_snapshot or {}
    agent_spans = meta_it.get("agent_spans") or arts.get("agent_spans") or []
    if not isinstance(agent_spans, list):
        agent_spans = []
    return build_timeline_api_body(
        task_id=task_id,
        source="iteration_snapshot",
        pipeline_stage=meta_it.get("pipeline_stage"),
        progress=meta_it.get("progress"),
        agent_spans=agent_spans,
        events_timeline=events,
    )


# ───────────── 4. 获取最终结果 / JSON 导出 ─────────────

@router.get("/tasks/{task_id}/result")
async def get_task_result(
    task_id: str,
    version: Optional[str] = None,
    iteration_number: Optional[int] = None,
    current_user: dict = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    conversation_repo = ConversationRepository(db)
    iteration_repo = IterationRepository(db)

    conversation = conversation_repo.get_conversation(task_id)
    if not conversation:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="任务不存在",
        )

    if conversation.user_id != current_user.get("id"):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="权限不足",
        )

    meta = conversation.conversation_metadata or {}
    final_result = meta.get("final_result")
    iterations = iteration_repo.get_iterations(task_id)

    # 默认直接返回已保存最终结果
    if final_result and not version:
        return final_result

    if not iterations and not final_result:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="任务尚无结果",
        )

    ctx = CoordinatorContext(
        conversation_id=task_id,
        requirement_text=conversation.original_requirement or "",
        mode=TaskMode.AUTO,
        config=meta.get("config", {}) if isinstance(meta.get("config"), dict) else {},
    )

    # 恢复迭代数 / 进度
    if final_result:
        ctx.iteration_count = final_result.get("iteration_count", len(iterations))
        ctx.progress = final_result.get("progress", meta.get("progress", 100))
    elif iterations:
        ctx.iteration_count = len(iterations)
        ctx.progress = meta.get("progress", 0)

    # 恢复管线阶段（关键）
    raw_stage = None
    if isinstance(final_result, dict):
        raw_stage = final_result.get("pipeline_stage") or final_result.get("state")
    if not raw_stage:
        raw_stage = conversation.status
    ctx.pipeline_stage = _parse_pipeline_stage(raw_stage)

    # 恢复质量标记（用于 quality_summary）
    if isinstance(final_result, dict):
        by_agent = (final_result.get("quality_summary") or {}).get("by_agent") or {}
        if isinstance(by_agent, dict):
            for agent, info in by_agent.items():
                if isinstance(info, dict) and isinstance(info.get("flags"), list):
                    ctx.quality_flags[agent] = info["flags"]

    # 恢复部分 timeline（至少恢复 state_transition）
    if isinstance(final_result, dict):
        timeline = final_result.get("timeline") or []
        if isinstance(timeline, list):
            for entry in timeline:
                if entry.get("event") == "state_transition":
                    ctx.state_transition_log.append({
                        "from_state": entry.get("from_state"),
                        "to_state": entry.get("to_state"),
                        "timestamp": entry.get("timestamp"),
                    })

    assembler = FinalResultAssembler()
    result = assembler.assemble_final_result(
        ctx,
        iterations=iterations,
        version_strategy=version or "latest",
        selected_iteration_number=iteration_number,
    )
    return result


@router.get("/tasks/{task_id}/m2-input")
async def get_m2_input_snapshot(
    task_id: str,
    current_user: dict = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    返回 `m2_inputs_snapshot_history`：按时间顺序的 M2 标准输入快照。

    每条通常含：`input_phase`、`pipeline_stage`、`tree_version`、可选 `sub_ar_stack_tail`、
    可选 `target_node_id` / `feasibility_refinement_depth`（可实现性递归细化子树时）、
    以及 `snapshot`（内含 `m2_standard_input` 与可选 `m2_scope` 元数据）。

    去重键为「标准输入 + `pipeline_stage` + 可选作用域」，避免不同阶段或不同子 AR 被误合并。
    不再返回根级 `snapshot`（请用 history 最后一项或遍历全表）。已移除 `schema_version` / `note`。

    运行中任务：从内存 artifacts 读取；已结束任务：优先从 `final_result`；
    若无则根据最后一次迭代的 artifacts 快照重建（历史可能为空）。
    """
    conversation_repo = ConversationRepository(db)
    conversation = conversation_repo.get_conversation(task_id)
    if not conversation:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="对话不存在",
        )
    if conversation.user_id != current_user.get("id"):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="权限不足",
        )

    task_manager = task_registry.get(task_id)
    if task_manager:
        ctx = await task_manager.get_task_context(task_id)
        if ctx:
            hist = ctx.artifacts.get("m2_inputs_snapshot_history")
            if not isinstance(hist, list):
                hist = []
            return {
                "task_id": task_id,
                "source": "active_task",
                "m2_inputs_snapshot_history": hist,
            }

    meta = conversation.conversation_metadata or {}
    final_result = meta.get("final_result")
    if isinstance(final_result, dict) and (
        final_result.get("m2_inputs_snapshot") is not None
        or final_result.get("m2_inputs_snapshot_history")
    ):
        _hist = final_result.get("m2_inputs_snapshot_history")
        if not isinstance(_hist, list):
            _hist = []
        return {
            "task_id": task_id,
            "source": "final_result",
            "m2_inputs_snapshot_history": _hist,
        }

    iteration_repo = IterationRepository(db)
    iterations = iteration_repo.get_iterations(task_id)
    if not iterations:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="尚无模块一/模块二产物，无法构建 M2 输入快照",
        )

    last = iterations[-1]
    arts = last.artifacts_snapshot or {}
    if not arts.get("function_list") and not arts.get("dependencies"):
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="该迭代未保存功能点列表或依赖，无法重建 M2 输入快照",
        )

    _rebuild_hist = arts.get("m2_inputs_snapshot_history")
    if not isinstance(_rebuild_hist, list):
        _rebuild_hist = []
    return {
        "task_id": task_id,
        "source": "iteration_rebuild",
        "iteration_number": last.iteration_number,
        "m2_inputs_snapshot_history": _rebuild_hist,
    }


def _copy_jsonable(val: Any) -> Any:
    """深拷贝可 JSON 化的调试片段，避免响应与 ORM 会话共享可变引用。"""
    try:
        return json.loads(json.dumps(val, default=str))
    except (TypeError, ValueError):
        return val


@router.get("/tasks/{task_id}/debug/m1-normalizer")
async def get_m1_normalizer_debug(
    task_id: str,
    current_user: dict = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    返回 M1 预处理（Normalizer）写入产物的快照：`normalized_requirement`、
    `decomposition_root`（由标准化结果派生的拆分根节点），以及可选 `normalizer_meta`
   （来自管线中最近一次 normalizer 的 BaseAgentOutput.meta，若仍在 artifacts 中）。
    """
    conversation_repo = ConversationRepository(db)
    conversation = conversation_repo.get_conversation(task_id)
    if not conversation:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="对话不存在",
        )
    if conversation.user_id != current_user.get("id"):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="权限不足",
        )

    task_manager = task_registry.get(task_id)
    if task_manager:
        ctx = await task_manager.get_task_context(task_id)
        if ctx:
            norm = ctx.artifacts.get("normalized_requirement")
            root = ctx.artifacts.get("decomposition_root")
            meta = ctx.artifacts.get("normalizer_meta")
            return {
                "task_id": task_id,
                "source": "active_task",
                "normalized_requirement": _copy_jsonable(norm)
                if isinstance(norm, dict)
                else {},
                "decomposition_root": _copy_jsonable(root),
                "normalizer_meta": _copy_jsonable(meta)
                if isinstance(meta, dict)
                else None,
            }

    meta = conversation.conversation_metadata or {}
    final_result = meta.get("final_result")
    if isinstance(final_result, dict) and final_result.get("normalized_requirement") is not None:
        norm = final_result.get("normalized_requirement")
        root = final_result.get("decomposition_root")
        if root is None and isinstance(norm, dict):
            root = build_focus_node_from_normalizer(norm)
        _nm = final_result.get("normalizer_meta")
        return {
            "task_id": task_id,
            "source": "final_result",
            "normalized_requirement": _copy_jsonable(norm)
            if isinstance(norm, dict)
            else {},
            "decomposition_root": _copy_jsonable(root),
            "normalizer_meta": _copy_jsonable(_nm) if isinstance(_nm, dict) else None,
        }

    iteration_repo = IterationRepository(db)
    iterations = iteration_repo.get_iterations(task_id)
    if not iterations:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="尚无迭代快照，无法返回预处理产物",
        )
    last = iterations[-1]
    arts = last.artifacts_snapshot or {}
    norm = arts.get("normalized_requirement")
    if not isinstance(norm, dict):
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="该迭代未保存 normalized_requirement",
        )
    root = arts.get("decomposition_root")
    if root is None:
        root = build_focus_node_from_normalizer(norm)
    return {
        "task_id": task_id,
        "source": "iteration_snapshot",
        "iteration_number": last.iteration_number,
        "normalized_requirement": _copy_jsonable(norm),
        "decomposition_root": _copy_jsonable(root),
        "normalizer_meta": arts.get("normalizer_meta"),
    }


@router.get("/tasks/{task_id}/debug/m1-decomposer-timeline")
async def get_m1_decomposer_debug_timeline(
    task_id: str,
    current_user: dict = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    返回 M1 功能拆分（Decomposer）调用时间线：`call_count` 与按时间顺序的 `timeline`。
    每条含 sequence、timestamp、source（module1_pipeline / decomposer_dependency_no_gate /
    sub_ar_refinement）、pipeline_stage、tree_version、input（完整 AgentInput 字典）、
    output（payload、meta、quality_flags、warnings）。
    """
    conversation_repo = ConversationRepository(db)
    conversation = conversation_repo.get_conversation(task_id)
    if not conversation:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="对话不存在",
        )
    if conversation.user_id != current_user.get("id"):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="权限不足",
        )

    task_manager = task_registry.get(task_id)
    if task_manager:
        ctx = await task_manager.get_task_context(task_id)
        if ctx:
            tl = ctx.artifacts.get("m1_decomposer_debug_timeline")
            if not isinstance(tl, list):
                tl = []
            return {
                "task_id": task_id,
                "source": "active_task",
                "call_count": len(tl),
                "timeline": _copy_jsonable(tl),
            }

    meta = conversation.conversation_metadata or {}
    final_result = meta.get("final_result")
    if isinstance(final_result, dict) and "m1_decomposer_debug_timeline" in final_result:
        tl = final_result.get("m1_decomposer_debug_timeline")
        if not isinstance(tl, list):
            tl = []
        return {
            "task_id": task_id,
            "source": "final_result",
            "call_count": len(tl),
            "timeline": _copy_jsonable(tl),
        }

    iteration_repo = IterationRepository(db)
    iterations = iteration_repo.get_iterations(task_id)
    if not iterations:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="尚无拆分调试时间线记录",
        )
    last = iterations[-1]
    arts = last.artifacts_snapshot or {}
    tl = arts.get("m1_decomposer_debug_timeline")
    if not isinstance(tl, list):
        tl = []
    return {
        "task_id": task_id,
        "source": "iteration_snapshot",
        "iteration_number": last.iteration_number,
        "call_count": len(tl),
        "timeline": _copy_jsonable(tl),
    }


def _episodes_with_order(raw: Any) -> List[Dict[str, Any]]:
    """为每条有效 episode 附加 1-based order（跳过非 dict 项，order 连续）。"""
    if not isinstance(raw, list):
        return []
    out: List[Dict[str, Any]] = []
    order = 1
    for ep in raw:
        if not isinstance(ep, dict):
            continue
        item = dict(ep)
        item["order"] = order
        order += 1
        out.append(item)
    return out


@router.get("/tasks/{task_id}/evaluation-episodes")
async def get_evaluation_episodes(
    task_id: str,
    current_user: dict = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    按生成先后顺序返回 `evaluation_episodes`；每条含 `order` 及原有元数据与 `bundle`。

    数据来源与 `GET .../m2-input` 对齐：活跃任务 artifacts → `final_result` → 最后一次迭代快照。
    """
    conversation_repo = ConversationRepository(db)
    conversation = conversation_repo.get_conversation(task_id)
    if not conversation:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="对话不存在",
        )
    if conversation.user_id != current_user.get("id"):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="权限不足",
        )

    task_manager = task_registry.get(task_id)
    if task_manager:
        ctx = await task_manager.get_task_context(task_id)
        if ctx:
            raw = ctx.artifacts.get("evaluation_episodes")
            if not isinstance(raw, list):
                raw = []
            return {
                "task_id": task_id,
                "source": "active_task",
                "episodes": _episodes_with_order(raw),
            }

    meta = conversation.conversation_metadata or {}
    final_result = meta.get("final_result")
    if isinstance(final_result, dict):
        fe = final_result.get("evaluation_episodes")
        if isinstance(fe, list):
            return {
                "task_id": task_id,
                "source": "final_result",
                "episodes": _episodes_with_order(fe),
            }

    iteration_repo = IterationRepository(db)
    iterations = iteration_repo.get_iterations(task_id)
    if not iterations:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="尚无任务迭代或评估 episode 记录",
        )

    last = iterations[-1]
    arts = last.artifacts_snapshot or {}
    raw = arts.get("evaluation_episodes")
    if not isinstance(raw, list):
        raw = []
    return {
        "task_id": task_id,
        "source": "iteration_snapshot",
        "iteration_number": last.iteration_number,
        "episodes": _episodes_with_order(raw),
    }


# ───────────── 5. 节点重拆（用户介入）─────────────

@router.post("/tasks/{task_id}/refine-node", response_model=CoordinationResponse)
async def refine_node_coordination(
    task_id: str,
    request: RefineNodeRequest,
    background_tasks: BackgroundTasks,
    current_user: dict = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    基于已持久化的 `final_result`，对指定 `function_list` 节点重拆并重新跑
    子需求列表 → 一致性 → 可实现性尾部。推荐先建立同 task_id 的 SSE 订阅以接收进度。
    """
    conversation_repo = ConversationRepository(db)
    conversation = conversation_repo.get_conversation(task_id)
    if not conversation:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="对话不存在",
        )
    if conversation.user_id != current_user.get("id"):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="权限不足",
        )
    meta = conversation.conversation_metadata or {}
    final_result = meta.get("final_result")
    if not isinstance(final_result, dict):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="尚无最终结果，请先完成主协调任务",
        )

    node_id = (request.node_id or "").strip()
    if not node_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="node_id 不能为空",
        )
    user_instruction = (request.user_instruction or "").strip()
    config_patch = request.config or {}

    # 重拆前快照：失败或用户停止本次重拆时，将状态 / final_result / live / 迭代表回退到此，
    # 避免会话长期停留在 error/cancelled 且半成品污染 GET 还原。
    it_repo_pre = IterationRepository(db)
    max_iteration_before = max(
        (r.iteration_number for r in it_repo_pre.get_iterations(task_id)),
        default=0,
    )
    refine_rollback_snap: Dict[str, Any] = {
        "status": conversation.status,
        "progress": float(meta.get("progress"))
        if meta.get("progress") is not None
        else 100.0,
        "final_result": copy.deepcopy(final_result),
        "coordination_live_snapshot": copy.deepcopy(
            meta.get("coordination_live_snapshot") or {}
        ),
        "max_iteration_number": max_iteration_before,
    }

    # 立即落库 running，避免后台协程尚未 register 前 GET /status 仍见 done，
    # 前端可据此立刻挂 SSE。
    progress_now = meta.get("progress")
    if progress_now is None:
        progress_now = 100.0
    conversation_repo.update_state(task_id, "running", float(progress_now))

    async def _run_refine():
        bg_db = SessionLocal()
        tm: Optional[TaskManager] = None
        ctx = None
        try:
            c_repo = ConversationRepository(bg_db)
            it_repo = IterationRepository(bg_db)
            orchestrator = Orchestrator()
            tm = TaskManager(c_repo, it_repo, orchestrator)
            sse_manager.reregister_forward(task_id, tm)
            tm.register_progress_callback(
                task_id, tm._persist_function_tree_dependencies_bundle_sse
            )

            conv = c_repo.get_conversation(task_id)
            if not conv:
                return
            meta2 = dict(conv.conversation_metadata or {})
            fr = meta2.get("final_result")
            if not isinstance(fr, dict):
                logger.error("[%s] refine-node: 缺少 final_result", task_id)
                _rollback_refine_node_attempt(bg_db, task_id, refine_rollback_snap)
                return
            cfg2 = dict(meta2.get("config") or {})
            if isinstance(config_patch, dict):
                cfg2.update(config_patch)

            ctx = ContextHydrator.from_db_result(
                task_id,
                conv.original_requirement or "",
                fr,
                cfg2,
            )
            if user_instruction:
                ctx.context["user_instruction"] = user_instruction

            # 注册到全局表，使 Stop 接口能找到并设置 stop_requested
            tm.active_tasks[task_id] = ctx
            task_registry.register(task_id, tm)

            final = await orchestrator.run_refine_node(
                ctx,
                node_id,
                user_instruction=user_instruction,
                on_iteration_complete=tm._on_iteration_complete,
                on_state_change=tm._sync_state_to_db,
            )
            if isinstance(final, dict) and final.get("stopped_by_user"):
                # 与异常失败一致：用户取消本次 refine-node 应恢复重拆前会话，而非 cancelled + 半成品。
                _rollback_refine_node_attempt(bg_db, task_id, refine_rollback_snap)
                return

            # refine-node 必须以当前内存上下文为准落库：`version_selection=best_by_score`
            # 等策略会从历史迭代的 artifacts_snapshot 取产物，极易选到「重拆前」高分轮次，
            # 导致看起来像「接口跑完但功能树没变」。（迭代记录仍已由 _on_iteration_complete 写入。）
            full = tm.final_assembler.assemble_final_result(
                ctx,
                iterations=[],
                version_strategy="latest",
            )
            cd = final.get("coordinator_decision") if isinstance(final, dict) else None
            if cd is not None:
                full["coordinator_decision"] = cd
            selected_iter_num = full.get("selected_iteration")
            if selected_iter_num is not None:
                it_repo.mark_selected(task_id, selected_iter_num)
            c_repo.update_state(task_id, PipelineStage.DONE.value, 100.0)
            c_repo.update_result(task_id, full)
            tm._persist_system_task_complete(task_id, ctx, full)
        except Exception as e:
            logger.error("[%s] refine-node 后台失败: %s", task_id, e, exc_info=True)
            try:
                _rollback_refine_node_attempt(bg_db, task_id, refine_rollback_snap)
            except Exception:
                pass
        finally:
            if tm is not None:
                tm.active_tasks.pop(task_id, None)
                task_registry.unregister(task_id)
            bg_db.close()
            sse_manager.on_task_finished(task_id)

    background_tasks.add_task(_run_refine)

    return CoordinationResponse(
        task_id=task_id,
        conversation_id=task_id,
        status="started",
        message="节点重拆任务已启动",
    )


# ───────────── 6. 停止任务 ─────────────

@router.post("/stop/{task_id}")
async def stop_coordination(
    task_id: str,
    current_user: dict = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    停止协调任务（协作式取消）。

    设置 stop_requested；编排会在当前迭代边界或 LLM 调用返回后结束，
    并通过 SSE 推送带 stopped_by_user 的 completed 事件。请勿从内存中提前移除 TaskManager。
    """
    conversation_repo = ConversationRepository(db)
    conversation = conversation_repo.get_conversation(task_id)
    if not conversation:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="对话不存在",
        )
    if conversation.user_id != current_user.get("id"):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="权限不足",
        )

    task_manager = task_registry.get(task_id)
    if not task_manager:
        return {
            "task_id": task_id,
            "status": "idle_or_completed",
            "message": "当前进程内未找到运行中的任务，可能已结束或尚未启动",
        }

    if not task_manager.request_stop(task_id):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="无法停止该任务",
        )

    return {
        "task_id": task_id,
        "status": "stop_requested",
        "message": "已请求停止，智能体将在当前 LLM 调用返回后结束，并通过 SSE 推送 stopped_by_user 事件",
    }


# ───────────── 7. 报告下载 ─────────────
# ★ 新增：四类独立报告，由 GET /tasks/{task_id}/report/download?type=<name> 分发。
# type 取值：decomposition | consistency | granularity | feasibility

_REPORT_TYPES = {
    "decomposition": ("需求切分结果", "需求切分结果"),
    "consistency":   ("一致性评估报告", "一致性评估报告"),
    "granularity":   ("粒度评估报告", "粒度评估报告"),
    "feasibility":   ("可实现性评估报告", "可实现性评估报告"),
}


def _score_bar(score: float, width: int = 20) -> str:
    """生成简单文本进度条，score 为 0~1。"""
    filled = round(score * width)
    return f"[{'█' * filled}{'░' * (width - filled)}] {round(score * 100)}%"


def _report_header(title: str, conversation: Any, now: str) -> List[str]:
    """公共报告头：标题、原始需求、元数据。"""
    lines: List[str] = [
        f"# {title}",
        "",
        f"> 生成时间：{now}  ",
        f"> 对话 ID：{getattr(conversation, 'id', '') if conversation else ''}",
        "",
    ]
    orig = (getattr(conversation, "original_requirement", "") or "") if conversation else ""
    if orig:
        lines += ["**原始需求：**", "", f"> {orig}", ""]
    return lines


# ── 报告 1：需求切分结果 ──

def _build_decomposition_report(final_result: Dict[str, Any], conversation: Any) -> str:
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    lines = _report_header("需求切分结果", conversation, now)

    # 标准化需求
    norm = final_result.get("normalized_requirement") or {}
    if isinstance(norm, dict) and norm:
        lines += ["## 标准化需求摘要", ""]
        for key, label in [
            ("summary", "摘要"),
            ("scope", "范围"),
            ("primary_actors", "主体"),
            ("core_goals", "核心目标"),
        ]:
            val = norm.get(key)
            if val:
                if isinstance(val, list):
                    val = "、".join(str(v) for v in val)
                lines.append(f"- **{label}**：{val}")
        constraints = norm.get("constraints") or []
        if isinstance(constraints, list) and constraints:
            lines += ["", "**约束条件：**", ""]
            for c in constraints:
                desc = c.get("description") or c.get("rule") or str(c) if isinstance(c, dict) else str(c)
                lines.append(f"- {desc}")
        lines.append("")

    # 功能点列表
    fl = final_result.get("function_list") or []
    lines += ["## 功能点列表", ""]
    if fl:
        lines += [
            "| ID | 标题 | 类型 | 粒度 | 父节点 |",
            "|----|------|------|------|--------|",
        ]
        for node in fl:
            if not isinstance(node, dict):
                continue
            lines.append(
                f"| {node.get('id','')} | {node.get('title','')} "
                f"| {node.get('node_type','')} | {node.get('granularity','')} "
                f"| {node.get('parent_id') or '—'} |"
            )
        lines.append("")
    else:
        lines += ["_（暂无功能点数据）_", ""]

    # 子需求列表
    sub_list = final_result.get("sub_requirement_list") or []
    if isinstance(sub_list, list) and sub_list:
        lines += ["## 子需求列表", ""]
        for i, sub in enumerate(sub_list, 1):
            if isinstance(sub, dict):
                title = sub.get("title") or sub.get("name") or f"子需求 {i}"
                desc = sub.get("description") or sub.get("desc") or ""
                lines.append(f"**{i}. {title}**")
                if desc:
                    lines.append(f"   {desc}")
            elif isinstance(sub, str):
                lines.append(f"{i}. {sub}")
        lines.append("")

    lines += ["---", f"*本报告由系统自动生成，生成时间：{now}*", ""]
    return "\n".join(lines)


# ── 报告 2：一致性评估报告 ──

def _build_consistency_report(final_result: Dict[str, Any], conversation: Any) -> str:
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    lines = _report_header("一致性评估报告", conversation, now)

    episodes = final_result.get("evaluation_episodes") or []
    c_score = None
    c_issues: List[Dict[str, Any]] = []
    c_warnings: List[Dict[str, Any]] = []

    for ep in episodes:
        if not isinstance(ep, dict):
            continue
        cr = ((ep.get("bundle") or {}).get("evaluation") or {}).get("consistency_result") or {}
        if isinstance(cr, dict) and cr:
            if c_score is None and cr.get("score") is not None:
                try:
                    c_score = float(cr["score"])
                except Exception:
                    pass
            c_issues.extend(cr.get("critical_issues") or [])
            c_warnings.extend(cr.get("warnings") or [])

    if c_score is not None:
        lines += [f"**一致性评分：** {_score_bar(c_score)}", ""]

    lines += ["## 关键问题", ""]
    if c_issues:
        for issue in c_issues:
            if not isinstance(issue, dict):
                continue
            desc = issue.get("description") or issue.get("rule_name") or str(issue)
            sev = issue.get("severity", "")
            sev_tag = f"[{sev.upper()}] " if sev else ""
            lines.append(f"- {sev_tag}{desc}")
            nodes = issue.get("affected_nodes") or []
            if nodes:
                lines.append(f"  - 影响节点：{', '.join(str(n) for n in nodes)}")
    else:
        lines.append("_（无关键问题）_")
    lines.append("")

    lines += ["## 警告", ""]
    if c_warnings:
        for w in c_warnings:
            if not isinstance(w, dict):
                continue
            desc = w.get("description") or w.get("rule_name") or str(w)
            lines.append(f"- ⚠ {desc}")
    else:
        lines.append("_（无警告）_")
    lines.append("")

    # per_scope_digest（一致性评分明细）
    rollup = final_result.get("evaluation_rollup") or {}
    digest = (final_result.get("global_report") or {}).get("per_scope_digest") or []
    if digest:
        lines += ["## 分 scope 一致性得分明细", ""]
        lines += ["| scope | 一致性得分 | 可实现性得分 | 树版本 |",
                  "|-------|-----------|-------------|--------|"]
        for d in digest:
            if not isinstance(d, dict):
                continue
            scope = d.get("scope", "")
            cs = d.get("consistency_score")
            fs = d.get("feasibility_score")
            tv = d.get("tree_version", "")
            cs_str = f"{round(cs * 100)}%" if cs is not None else "—"
            fs_str = f"{round(fs * 100)}%" if fs is not None else "—"
            lines.append(f"| {scope} | {cs_str} | {fs_str} | {tv} |")
        lines.append("")

    lines += ["---", f"*本报告由系统自动生成，生成时间：{now}*", ""]
    return "\n".join(lines)


# ── 报告 3：粒度评估报告 ──

def _build_granularity_report(final_result: Dict[str, Any], conversation: Any) -> str:
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    lines = _report_header("粒度评估报告", conversation, now)

    rollup = final_result.get("evaluation_rollup") or {}
    fl = final_result.get("function_list") or []

    # rollup 中的粒度评分（若后端有写入）
    g_score = rollup.get("granularity_score")
    if g_score is not None:
        try:
            lines += [f"**粒度评分：** {_score_bar(float(g_score))}", ""]
        except Exception:
            pass

    # 从 function_list 统计粒度与类型分布
    if fl:
        gran_count: Dict[str, int] = {}
        type_count: Dict[str, int] = {}
        for node in fl:
            if not isinstance(node, dict):
                continue
            g = node.get("granularity") or "UNKNOWN"
            t = node.get("node_type") or "UNKNOWN"
            gran_count[g] = gran_count.get(g, 0) + 1
            type_count[t] = type_count.get(t, 0) + 1

        lines += ["## 功能点粒度分布", ""]
        lines += ["**按粒度（granularity）：**", ""]
        for g, cnt in sorted(gran_count.items()):
            lines.append(f"- {g}：{cnt} 个")
        lines += ["", "**按节点类型（node_type）：**", ""]
        for t, cnt in sorted(type_count.items()):
            lines.append(f"- {t}：{cnt} 个")
        lines.append("")

        # 各叶子节点粒度一览
        leaf_nodes = [n for n in fl if isinstance(n, dict) and not any(
            isinstance(m, dict) and m.get("parent_id") == n.get("id") for m in fl
        )]
        if leaf_nodes:
            lines += ["## 叶子节点粒度明细", ""]
            lines += ["| ID | 标题 | 粒度 | 类型 |", "|----|------|------|------|"]
            for n in leaf_nodes:
                lines.append(
                    f"| {n.get('id','')} | {n.get('title','')} "
                    f"| {n.get('granularity','')} | {n.get('node_type','')} |"
                )
            lines.append("")

    # rollup 中的粒度问题
    g_issues = rollup.get("granularity_issues") or []
    if g_issues:
        lines += ["## 粒度问题", ""]
        for gi in g_issues:
            if isinstance(gi, dict):
                lines.append(f"- {gi.get('description') or gi.get('node_id') or str(gi)}")
            elif isinstance(gi, str):
                lines.append(f"- {gi}")
        lines.append("")

    if not fl and not rollup:
        lines += ["_（暂无粒度评估数据）_", ""]

    lines += ["---", f"*本报告由系统自动生成，生成时间：{now}*", ""]
    return "\n".join(lines)


# ── 报告 4：可实现性评估报告 ──

def _build_feasibility_report(final_result: Dict[str, Any], conversation: Any) -> str:
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    lines = _report_header("可实现性评估报告", conversation, now)

    episodes = final_result.get("evaluation_episodes") or []
    f_score = None
    f_issues: List[Dict[str, Any]] = []
    f_warnings: List[Dict[str, Any]] = []
    fpa_analysis = None

    for ep in episodes:
        if not isinstance(ep, dict):
            continue
        fr = ((ep.get("bundle") or {}).get("evaluation") or {}).get("feasibility_result") or {}
        if isinstance(fr, dict) and fr:
            if f_score is None and fr.get("score") is not None:
                try:
                    f_score = float(fr["score"])
                except Exception:
                    pass
            f_issues.extend(fr.get("critical_issues") or [])
            f_warnings.extend(fr.get("warnings") or [])
            if fr.get("fpa_analysis") and fpa_analysis is None:
                fpa_analysis = fr["fpa_analysis"]

    if f_score is not None:
        lines += [f"**可实现性评分：** {_score_bar(f_score)}", ""]

    # 全局报告（综合摘要）
    global_report = final_result.get("global_report") or {}
    if isinstance(global_report, dict):
        if global_report.get("summary"):
            lines += ["## 综合摘要", "", global_report["summary"], ""]
        if global_report.get("recommendation"):
            lines += ["## 建议", "", global_report["recommendation"], ""]
        overall = None
        try:
            overall = float(global_report["overall_score"])
        except Exception:
            pass
        if overall is not None:
            risk = global_report.get("risk_level", "")
            risk_zh = {"low": "低", "medium": "中", "high": "高", "none": "无"}.get(risk, risk)
            lines += [
                f"**综合评分：** {_score_bar(overall)}  ",
                f"**风险等级：** {risk_zh}",
                "",
            ]

    lines += ["## 关键问题", ""]
    if f_issues:
        for issue in f_issues:
            if not isinstance(issue, dict):
                continue
            desc = issue.get("description") or issue.get("rule_name") or str(issue)
            sev = issue.get("severity", "")
            sev_tag = f"[{sev.upper()}] " if sev else ""
            lines.append(f"- {sev_tag}{desc}")
            nodes = issue.get("affected_nodes") or []
            if nodes:
                lines.append(f"  - 影响节点：{', '.join(str(n) for n in nodes)}")
    else:
        lines.append("_（无关键问题）_")
    lines.append("")

    lines += ["## 警告", ""]
    if f_warnings:
        for w in f_warnings:
            if not isinstance(w, dict):
                continue
            desc = w.get("description") or w.get("rule_name") or str(w)
            lines.append(f"- ⚠ {desc}")
    else:
        lines.append("_（无警告）_")
    lines.append("")

    if isinstance(fpa_analysis, dict):
        lines += ["## 功能点分析（FPA）", ""]
        for k, v in fpa_analysis.items():
            lines.append(f"- **{k}**：{v}")
        lines.append("")

    lines += ["---", f"*本报告由系统自动生成，生成时间：{now}*", ""]
    return "\n".join(lines)


def _build_evaluation_report(final_result: Dict[str, Any], conversation: Any) -> str:
    """将一致性、粒度、可实现性三份评估合并为一个 Markdown 文档。"""
    parts = [
        _build_consistency_report(final_result, conversation),
        _build_granularity_report(final_result, conversation),
        _build_feasibility_report(final_result, conversation),
    ]
    return "\n\n---\n\n".join(parts)


_REPORT_BUILDERS = {
    "decomposition": (_build_decomposition_report, "需求切分结果"),
    "evaluation":    (_build_evaluation_report,    "评估报告"),
    # 保留单独接口供兼容
    "consistency":   (_build_consistency_report,   "一致性评估报告"),
    "granularity":   (_build_granularity_report,   "粒度评估报告"),
    "feasibility":   (_build_feasibility_report,   "可实现性评估报告"),
}


def _build_report_markdown(final_result: Dict[str, Any], conversation: Any) -> str:
    """
    从 final_result 组装四章 Markdown 报告：
      1. 需求切分结果
      2. 一致性评估报告
      3. 粒度评估报告
      4. 可实现性评估报告
    """
    lines: List[str] = []
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    req_title = ""
    if conversation:
        meta = conversation.conversation_metadata or {}
        fr = meta.get("final_result") or {}
        req_title = (
            getattr(conversation, "title", None)
            or fr.get("title")
            or ""
        )
    req_title = req_title or "需求分析报告"

    lines += [
        f"# {req_title}",
        "",
        f"> 生成时间：{now}  ",
        f"> 对话 ID：{getattr(conversation, 'id', '') if conversation else ''}",
        "",
    ]

    # ── 原始需求 ──
    orig = ""
    if conversation:
        orig = getattr(conversation, "original_requirement", "") or ""
    if orig:
        lines += ["**原始需求：**", "", f"> {orig}", ""]

    # ══════════════════════════════════════
    # 第一章：需求切分结果
    # ══════════════════════════════════════
    lines += ["---", "## 一、需求切分结果", ""]

    # 1-A 标准化需求摘要
    norm = final_result.get("normalized_requirement") or {}
    if isinstance(norm, dict) and norm:
        lines += ["### 标准化需求摘要", ""]
        for key, label in [
            ("summary", "摘要"),
            ("scope", "范围"),
            ("primary_actors", "主体"),
            ("core_goals", "核心目标"),
        ]:
            val = norm.get(key)
            if val:
                if isinstance(val, list):
                    val = "、".join(str(v) for v in val)
                lines.append(f"- **{label}**：{val}")
        constraints = norm.get("constraints") or []
        if isinstance(constraints, list) and constraints:
            lines += ["", "**约束条件：**", ""]
            for c in constraints:
                if isinstance(c, dict):
                    desc = c.get("description") or c.get("rule") or str(c)
                elif isinstance(c, str):
                    desc = c
                else:
                    continue
                lines.append(f"- {desc}")
        lines.append("")

    # 1-B 功能点列表
    fl = final_result.get("function_list") or []
    lines += ["### 功能点列表", ""]
    if fl:
        lines += [
            "| ID | 标题 | 类型 | 粒度 | 父节点 |",
            "|----|------|------|------|--------|",
        ]
        for node in fl:
            if not isinstance(node, dict):
                continue
            nid = node.get("id", "")
            title = node.get("title", "")
            ntype = node.get("node_type", "")
            gran = node.get("granularity", "")
            pid = node.get("parent_id") or "—"
            lines.append(f"| {nid} | {title} | {ntype} | {gran} | {pid} |")
        lines.append("")
    else:
        lines += ["_（暂无功能点数据）_", ""]

    # 1-C 子需求列表
    sub_list = final_result.get("sub_requirement_list") or []
    if isinstance(sub_list, list) and sub_list:
        lines += ["### 子需求列表", ""]
        for i, sub in enumerate(sub_list, 1):
            if isinstance(sub, dict):
                title = sub.get("title") or sub.get("name") or f"子需求 {i}"
                desc = sub.get("description") or sub.get("desc") or ""
                lines.append(f"**{i}. {title}**")
                if desc:
                    lines.append(f"   {desc}")
            elif isinstance(sub, str):
                lines.append(f"{i}. {sub}")
        lines.append("")

    # ══════════════════════════════════════
    # 第二章：一致性评估报告
    # ══════════════════════════════════════
    lines += ["---", "## 二、一致性评估报告", ""]

    episodes = final_result.get("evaluation_episodes") or []
    rollup = final_result.get("evaluation_rollup") or {}

    c_score = None
    c_issues: List[Dict[str, Any]] = []
    c_warnings: List[Dict[str, Any]] = []

    for ep in episodes:
        if not isinstance(ep, dict):
            continue
        bundle = ep.get("bundle") or {}
        ev = bundle.get("evaluation") or {}
        cr = ev.get("consistency_result") or {}
        if isinstance(cr, dict) and cr:
            if c_score is None and cr.get("score") is not None:
                try:
                    c_score = float(cr["score"])
                except Exception:
                    pass
            c_issues.extend(cr.get("critical_issues") or [])
            c_warnings.extend(cr.get("warnings") or [])

    if c_score is not None:
        lines += [
            f"**一致性评分：** {_score_bar(c_score)}",
            "",
        ]
    else:
        c_score_from_rollup = rollup.get("consistency_score")
        if c_score_from_rollup is not None:
            try:
                lines += [
                    f"**一致性评分：** {_score_bar(float(c_score_from_rollup))}",
                    "",
                ]
            except Exception:
                pass

    if c_issues:
        lines += ["### 关键问题", ""]
        for issue in c_issues:
            if not isinstance(issue, dict):
                continue
            desc = issue.get("description") or issue.get("rule_name") or str(issue)
            sev = issue.get("severity", "")
            sev_tag = f"[{sev.upper()}] " if sev else ""
            lines.append(f"- {sev_tag}{desc}")
        lines.append("")

    if c_warnings:
        lines += ["### 警告", ""]
        for w in c_warnings:
            if not isinstance(w, dict):
                continue
            desc = w.get("description") or w.get("rule_name") or str(w)
            lines.append(f"- ⚠ {desc}")
        lines.append("")

    if not c_issues and not c_warnings:
        lines += ["_（一致性评估通过，无问题记录）_", ""]

    # ══════════════════════════════════════
    # 第三章：粒度评估报告
    # ══════════════════════════════════════
    lines += ["---", "## 三、粒度评估报告", ""]

    if isinstance(rollup, dict) and rollup:
        g_score = rollup.get("granularity_score")
        if g_score is not None:
            try:
                lines += [f"**粒度评分：** {_score_bar(float(g_score))}", ""]
            except Exception:
                pass
        g_stats = rollup.get("granularity_stats") or {}
        if isinstance(g_stats, dict) and g_stats:
            lines += ["### 粒度分布统计", ""]
            for k, v in g_stats.items():
                lines.append(f"- **{k}**：{v}")
            lines.append("")
        g_issues = rollup.get("granularity_issues") or []
        if isinstance(g_issues, list) and g_issues:
            lines += ["### 粒度问题", ""]
            for gi in g_issues:
                if isinstance(gi, dict):
                    desc = gi.get("description") or gi.get("node_id") or str(gi)
                    lines.append(f"- {desc}")
                elif isinstance(gi, str):
                    lines.append(f"- {gi}")
            lines.append("")

    # 补充：从 function_list 统计各粒度分布
    if fl:
        gran_count: Dict[str, int] = {}
        type_count: Dict[str, int] = {}
        for node in fl:
            if not isinstance(node, dict):
                continue
            g = node.get("granularity") or "UNKNOWN"
            t = node.get("node_type") or "UNKNOWN"
            gran_count[g] = gran_count.get(g, 0) + 1
            type_count[t] = type_count.get(t, 0) + 1

        lines += ["### 功能点粒度分布", ""]
        lines += ["**按粒度（granularity）：**", ""]
        for g, cnt in sorted(gran_count.items()):
            lines.append(f"- {g}：{cnt} 个")
        lines += ["", "**按节点类型（node_type）：**", ""]
        for t, cnt in sorted(type_count.items()):
            lines.append(f"- {t}：{cnt} 个")
        lines.append("")

    if not rollup and not fl:
        lines += ["_（暂无粒度评估数据）_", ""]

    # ══════════════════════════════════════
    # 第四章：可实现性评估报告
    # ══════════════════════════════════════
    lines += ["---", "## 四、可实现性评估报告", ""]

    f_score = None
    f_issues: List[Dict[str, Any]] = []
    f_warnings: List[Dict[str, Any]] = []
    fpa_analysis: Optional[Dict[str, Any]] = None

    for ep in episodes:
        if not isinstance(ep, dict):
            continue
        bundle = ep.get("bundle") or {}
        ev = bundle.get("evaluation") or {}
        fr = ev.get("feasibility_result") or {}
        if isinstance(fr, dict) and fr:
            if f_score is None and fr.get("score") is not None:
                try:
                    f_score = float(fr["score"])
                except Exception:
                    pass
            f_issues.extend(fr.get("critical_issues") or [])
            f_warnings.extend(fr.get("warnings") or [])
            if fr.get("fpa_analysis") and fpa_analysis is None:
                fpa_analysis = fr["fpa_analysis"]

    if f_score is not None:
        lines += [f"**可实现性评分：** {_score_bar(f_score)}", ""]
    else:
        f_score_from_rollup = rollup.get("feasibility_score")
        if f_score_from_rollup is not None:
            try:
                lines += [f"**可实现性评分：** {_score_bar(float(f_score_from_rollup))}", ""]
            except Exception:
                pass

    # 全局报告摘要（综合）
    global_report = final_result.get("global_report") or {}
    if isinstance(global_report, dict) and global_report.get("summary"):
        lines += ["### 综合摘要", "", global_report["summary"], ""]
    if isinstance(global_report, dict) and global_report.get("recommendation"):
        lines += ["### 建议", "", global_report["recommendation"], ""]
    overall = None
    if isinstance(global_report, dict) and global_report.get("overall_score") is not None:
        try:
            overall = float(global_report["overall_score"])
        except Exception:
            pass
    if overall is not None:
        risk = global_report.get("risk_level", "")
        risk_zh = {"low": "低", "medium": "中", "high": "高", "none": "无"}.get(risk, risk)
        lines += [
            f"**综合评分：** {_score_bar(overall)}  ",
            f"**风险等级：** {risk_zh}",
            "",
        ]

    if f_issues:
        lines += ["### 可实现性关键问题", ""]
        for issue in f_issues:
            if not isinstance(issue, dict):
                continue
            desc = issue.get("description") or issue.get("rule_name") or str(issue)
            sev = issue.get("severity", "")
            sev_tag = f"[{sev.upper()}] " if sev else ""
            lines.append(f"- {sev_tag}{desc}")
        lines.append("")

    if f_warnings:
        lines += ["### 可实现性警告", ""]
        for w in f_warnings:
            if not isinstance(w, dict):
                continue
            desc = w.get("description") or w.get("rule_name") or str(w)
            lines.append(f"- ⚠ {desc}")
        lines.append("")

    if fpa_analysis and isinstance(fpa_analysis, dict):
        lines += ["### 功能点分析（FPA）", ""]
        for k, v in fpa_analysis.items():
            lines.append(f"- **{k}**：{v}")
        lines.append("")

    if not f_issues and not f_warnings and not global_report:
        lines += ["_（暂无可实现性评估数据）_", ""]

    lines += ["---", f"*本报告由系统自动生成，生成时间：{now}*", ""]
    return "\n".join(lines)


def _build_ar_markdown(final_result: Dict[str, Any], conversation: Any) -> str:
    """将功能列表中的每个叶节点输出为标准 AR Markdown 格式。
    AR 编号规则：AR-{父节点序号(两位)}-{子节点序号(两位)}，
    父节点序号取父 id 中最后一段数字，子节点同理。
    若 AR 扩展字段为空，则回退到 desc / acceptance_hint 字段。
    """
    now = datetime.now(timezone.utc).astimezone().strftime("%Y-%m-%d %H:%M")
    conv_title = getattr(conversation, "title", "") or getattr(conversation, "original_requirement", "")[:40]

    # function_list 在 final_result 顶层，artifacts 为空对象
    function_list: List[Dict[str, Any]] = (
        final_result.get("function_list")
        or (final_result.get("artifacts") or {}).get("function_list")
        or []
    )

    if not function_list:
        return f"# AR 需求列表\n\n_（暂无功能拆分数据）_\n\n*生成时间：{now}*\n"

    # 找出所有非根节点（有 parent_id）作为 AR 输出对象
    id_to_row = {r.get("id", ""): r for r in function_list if isinstance(r, dict)}
    # 统计每个父节点的子节点有序列表，用于生成 AR 序号
    parent_children: Dict[str, List[str]] = {}
    for row in function_list:
        if not isinstance(row, dict):
            continue
        pid = row.get("parent_id")
        nid = row.get("id", "")
        if pid:
            parent_children.setdefault(pid, []).append(nid)

    # 生成父节点的 "显示序号"（按其在根节点下的顺序）
    root_rows = [r for r in function_list if isinstance(r, dict) and not r.get("parent_id")]
    root_index = {r.get("id", ""): idx + 1 for idx, r in enumerate(root_rows)}

    def _sr_num(nid: str) -> str:
        row = id_to_row.get(nid, {})
        pid = row.get("parent_id")
        if pid:
            parent_row = id_to_row.get(pid, {})
            grandpid = parent_row.get("parent_id")
            if not grandpid:
                # pid 是直接根节点
                p_idx = root_index.get(pid, 0)
                siblings = parent_children.get(pid, [])
                c_idx = siblings.index(nid) + 1 if nid in siblings else 0
                return f"{p_idx:02d}-{c_idx:02d}"
        return "00-00"

    lines: List[str] = [
        f"# AR 需求列表",
        f"",
        f"> 来源对话：{conv_title}",
        f"> 生成时间：{now}",
        f"",
        "---",
        "",
    ]

    for row in function_list:
        if not isinstance(row, dict):
            continue
        pid = row.get("parent_id")
        if not pid:
            continue  # 跳过根节点自身

        nid = row.get("id", "")
        sr_num = _sr_num(nid)
        ar_id = f"AR-{sr_num}"
        title = row.get("title", "")

        # AR 扩展字段，回退到旧字段
        desc = row.get("desc", "")
        def _cell(v: str) -> str:
            return v.replace("\n", "<br>").replace("|", "｜")

        ar_value = _cell(row.get("ar_value") or "")
        ar_scenario = _cell(row.get("ar_scenario") or "")
        ar_target_users = _cell(row.get("ar_target_users") or "全体用户")
        ar_constraints_text = _cell(row.get("ar_constraints") or "")
        ar_external_deps = _cell(row.get("ar_external_deps") or "")
        ar_performance = _cell(row.get("ar_performance") or "继承所属 SR")
        ar_power = _cell(row.get("ar_power") or "继承所属 SR")
        ar_rom_ram = _cell(row.get("ar_rom_ram") or "继承所属 SR")
        ar_acceptance: List[str] = row.get("ar_acceptance") or row.get("acceptance_hint") or []
        ar_device = _cell(row.get("ar_device") or "HarmonyOS NEXT（API 12+）手机为主基线")
        ar_products = _cell(row.get("ar_products") or "手机 / 平板 / 车机")
        ar_product_diff = _cell(row.get("ar_product_diff") or "各端体验一致")
        ar_extra = _cell(row.get("ar_extra") or "")

        acceptance_str = "<br>".join(
            f"{i+1}. {s}" for i, s in enumerate(ar_acceptance)
        ) if ar_acceptance else "_（待补充）_"

        # 父节点标题作为所属 SR 显示名
        parent_row = id_to_row.get(pid, {})
        parent_title = parent_row.get("title", pid)
        parent_sr_idx = root_index.get(pid, 0)
        sr_label = f"SR-{parent_sr_idx:02d} {parent_title}"

        lines += [
            f"# {ar_id} {title}",
            f"- AR-ID: {ar_id}",
            f"- 所属 SR: {sr_label}",
            "",
            "| 字段 | 填写内容 |",
            "|------|----------|",
            f"| [需求标题] | {title} |",
            f"| [需求描述] | {desc} |",
            f"| [需求价值] | {ar_value} |",
            f"| [需求场景] | {ar_scenario} |",
            f"| [目标用户] | {ar_target_users} |",
            f"| [限制约束] | {ar_constraints_text} |",
            f"| [外部依赖] | {ar_external_deps} |",
            f"| [性能指标] | {ar_performance} |",
            f"| [功耗指标] | {ar_power} |",
            f"| [ROM&RAM] | {ar_rom_ram} |",
            f"| [验收标准] | {acceptance_str} |",
            f"| [验收设备] | {ar_device} |",
            f"| [适用产品] | {ar_products} |",
            f"| [适用产品差异分析] | {ar_product_diff} |",
            f"| [视觉/生态/安全等扩展维度] | {ar_extra} |",
            "",
            "---",
            "",
        ]

    lines.append(f"*本报告由系统自动生成，生成时间：{now}*\n")
    return "\n".join(lines)


@router.get(
    "/tasks/{task_id}/report/ar-markdown",
    summary="导出 AR 格式需求文档（Markdown）",
)
async def download_ar_report(
    task_id: str,
    current_user: dict = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """将拆分结果按标准 AR 需求格式导出为 Markdown 文件，每个叶节点输出为一条 AR。"""
    conversation_repo = ConversationRepository(db)
    conversation = conversation_repo.get_conversation(task_id)
    if not conversation:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="对话不存在")
    if conversation.user_id != current_user.get("id"):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="权限不足")

    final_result: Optional[Dict[str, Any]] = None
    task_manager = task_registry.get(task_id)
    if task_manager:
        ctx = await task_manager.get_task_context(task_id)
        if ctx:
            assembler = FinalResultAssembler()
            final_result = assembler.assemble_final_result(ctx)

    if not isinstance(final_result, dict) or not final_result:
        meta = conversation.conversation_metadata or {}
        final_result = meta.get("final_result")

    if not isinstance(final_result, dict) or not final_result:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="尚无分析结果，请先完成需求分析任务",
        )

    md_content = _build_ar_markdown(final_result, conversation)
    filename = f"AR需求列表-{task_id[:8]}.md"
    encoded_filename = _url_quote(filename, safe="")
    return Response(
        content=md_content.encode("utf-8"),
        media_type="text/markdown; charset=utf-8",
        headers={"Content-Disposition": f"attachment; filename*=UTF-8''{encoded_filename}"},
    )


@router.get(
    "/tasks/{task_id}/report/download",
    summary="下载单份分析报告（Markdown）",
    # ★ 新增接口
)
async def download_report(
    task_id: str,
    type: str = "decomposition",
    current_user: dict = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    按 `type` 下载四类独立报告之一（Markdown 附件）。

    - `type=decomposition`  需求切分结果（功能点列表、子需求列表）
    - `type=consistency`    一致性评估报告
    - `type=granularity`    粒度评估报告
    - `type=feasibility`    可实现性评估报告

    优先读取运行中任务的内存上下文；任务结束后从 conversation_metadata.final_result 读取。
    """
    if type not in _REPORT_BUILDERS:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"不支持的报告类型 '{type}'，可选值：{', '.join(_REPORT_BUILDERS)}",
        )

    conversation_repo = ConversationRepository(db)
    conversation = conversation_repo.get_conversation(task_id)
    if not conversation:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="对话不存在",
        )
    if conversation.user_id != current_user.get("id"):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="权限不足",
        )

    # 优先从运行中任务读取 final_result
    final_result: Optional[Dict[str, Any]] = None
    task_manager = task_registry.get(task_id)
    if task_manager:
        ctx = await task_manager.get_task_context(task_id)
        if ctx:
            assembler = FinalResultAssembler()
            final_result = assembler.assemble_final_result(ctx)

    # 任务已结束：从持久化元数据中读取
    if not isinstance(final_result, dict) or not final_result:
        meta = conversation.conversation_metadata or {}
        final_result = meta.get("final_result")

    if not isinstance(final_result, dict) or not final_result:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="尚无分析结果，请先完成需求分析任务",
        )

    builder, label = _REPORT_BUILDERS[type]
    md_content = builder(final_result, conversation)
    filename = f"{label}-{task_id[:8]}.md"
    encoded_filename = _url_quote(filename, safe="")

    return Response(
        content=md_content.encode("utf-8"),
        media_type="text/markdown; charset=utf-8",
        headers={
            "Content-Disposition": f"attachment; filename*=UTF-8''{encoded_filename}",
        },
    )
