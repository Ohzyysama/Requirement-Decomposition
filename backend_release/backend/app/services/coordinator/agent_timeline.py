"""
智能体时间线 — LLM 调用跨度记录与 SSE 辅助。

通过 context.begin_agent_span / end_agent_span 记录每次智能体调用的起止与耗时；
context.agent_span_emit 由 Orchestrator 注入，用于实时推送 agent_timeline 事件。
"""
from __future__ import annotations

import copy
from typing import Any, Awaitable, Callable, Dict, List, Optional, TYPE_CHECKING, TypeVar

from app.services.coordinator.context import CoordinatorContext
from app.services.coordinator.tree_utils import sub_requirement_list_stats

if TYPE_CHECKING:
    from app.services.coordinator.agent_invoker import AgentInvoker

T = TypeVar("T")

AgentSpanEmit = Optional[Callable[[str, CoordinatorContext, str], Awaitable[None]]]


async def with_llm_agent_span(
    context: CoordinatorContext,
    agent: str,
    label: Optional[str],
    emit: AgentSpanEmit,
    awaitable: Awaitable[T],
) -> T:
    """包裹单次 awaitable（通常为 Agent.execute），记录 span 并可选推送 SSE。"""
    span_id = context.begin_agent_span(agent, label)
    if emit:
        await emit("started", context, span_id)
    try:
        result = await awaitable
        context.end_agent_span(span_id, "completed")
        if emit:
            await emit("completed", context, span_id)
        return result
    except Exception:
        context.end_agent_span(span_id, "error")
        if emit:
            await emit("error", context, span_id)
        raise


async def apply_sub_requirement_list_artifacts(
    context: CoordinatorContext,
    invoker: "AgentInvoker",
) -> List[Dict[str, Any]]:
    """从功能树生成子需求列表并写入 artifacts，带 coordinator 跨度。"""
    emit = getattr(context, "agent_span_emit", None)
    span_id = context.begin_agent_span("coordinator", "sub_requirement_list")
    if emit:
        await emit("started", context, span_id)
    try:
        sub_list = invoker.sub_requirement_list_from_context(context)
        context.add_artifact("sub_requirement_list", sub_list, agent="coordinator")
        context.add_artifact(
            "sub_requirement_list_stats",
            sub_requirement_list_stats(sub_list),
            agent="coordinator",
        )
        context.end_agent_span(span_id, "completed")
        if emit:
            await emit("completed", context, span_id)
        return sub_list
    except Exception:
        context.end_agent_span(span_id, "error")
        if emit:
            await emit("error", context, span_id)
        raise


def span_duration_minutes(s: Dict[str, Any]) -> Optional[float]:
    """读取跨度耗时（分钟）。兼容旧数据中的 duration_ms。"""
    dm = s.get("duration_minutes")
    if isinstance(dm, (int, float)):
        return round(float(dm), 6)
    dms = s.get("duration_ms")
    if isinstance(dms, (int, float)):
        return round(float(dms) / 60000.0, 6)
    return None


def normalize_span_dict_for_api(s: Dict[str, Any]) -> Dict[str, Any]:
    """统一为 duration_minutes，去掉已废弃的 duration_ms（仅用于 API 输出）。"""
    row = dict(s) if isinstance(s, dict) else {}
    row["duration_minutes"] = span_duration_minutes(row)
    row.pop("duration_ms", None)
    return row


def summarize_spans_by_agent(spans: List[Dict[str, Any]]) -> Dict[str, Dict[str, Any]]:
    """按 agent 汇总调用次数与已完成调用的耗时之和（分钟；running 无 duration 不计入总和）。"""
    out: Dict[str, Dict[str, Any]] = {}
    for s in spans:
        ag = str(s.get("agent") or "unknown")
        if ag not in out:
            out[ag] = {"invocations": 0, "total_duration_minutes": 0.0, "errors": 0}
        out[ag]["invocations"] += 1
        st = str(s.get("status") or "")
        if st == "error":
            out[ag]["errors"] += 1
        dm = span_duration_minutes(s)
        if dm is not None:
            out[ag]["total_duration_minutes"] = round(
                out[ag]["total_duration_minutes"] + dm, 6
            )
    return out


def merge_span_order_index(spans: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """为每条 span 附加 1-based order，并统一耗时单位为分钟。"""
    merged: List[Dict[str, Any]] = []
    for i, s in enumerate(spans, start=1):
        row = normalize_span_dict_for_api(dict(s) if isinstance(s, dict) else {})
        row["order"] = i
        merged.append(row)
    return merged


def build_timeline_api_body(
    *,
    task_id: str,
    source: str,
    pipeline_stage: Optional[str],
    progress: Optional[float],
    agent_spans: List[Dict[str, Any]],
    events_timeline: Optional[List[Dict[str, Any]]] = None,
) -> Dict[str, Any]:
    """构造 GET .../timeline 响应体。"""
    spans = merge_span_order_index(agent_spans or [])
    running = [copy.deepcopy(s) for s in spans if s.get("ended_at") is None]
    completed = [copy.deepcopy(s) for s in spans if s.get("ended_at") is not None]
    return {
        "task_id": task_id,
        "source": source,
        "pipeline_stage": pipeline_stage,
        "progress": progress,
        "running_spans": running,
        "completed_spans": completed,
        "spans": spans,
        "agents_summary": summarize_spans_by_agent(spans),
        "events_timeline": events_timeline or [],
    }
