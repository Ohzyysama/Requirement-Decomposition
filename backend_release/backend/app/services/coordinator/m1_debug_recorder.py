"""
M1 调试记录 — 在协调器路径上追加拆分智能体调用时间线（不入 LLM，仅落内存/持久化产物）。
"""
from __future__ import annotations

from datetime import datetime, timezone
from typing import TYPE_CHECKING, Any, Dict

from app.schemas.agent import AgentInput, BaseAgentOutput

if TYPE_CHECKING:
    from app.services.coordinator.agent_invoker import AgentInvoker
    from app.services.coordinator.context import CoordinatorContext


def record_m1_decomposer_invocation(
    invoker: "AgentInvoker",
    context: "CoordinatorContext",
    *,
    source: str,
    decomp_input: AgentInput,
    decomp_output: BaseAgentOutput,
) -> None:
    """
    追加一条 M1 功能拆分智能体调用记录到 context.artifacts["m1_decomposer_debug_timeline"]。

    source 约定：
    - module1_pipeline：首轮 M1 全线中的拆分
    - decomposer_dependency_no_gate：一致性内层重拆等仅 Decomposer→Dependency 路径
    - sub_ar_refinement：子 AR 单节点细化
    """
    hist = context.artifacts.get("m1_decomposer_debug_timeline")
    if not isinstance(hist, list):
        hist = []
    seq = len(hist) + 1
    inp_dict = invoker._to_serializable(decomp_input.model_dump())
    out_dict: Dict[str, Any] = {
        "payload": invoker._to_serializable(decomp_output.get_payload()),
        "meta": invoker._to_serializable(decomp_output.meta or {}),
        "quality_flags": list(decomp_output.quality_flags or []),
        "warnings": list(decomp_output.warnings or []),
    }
    entry = {
        "sequence": seq,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "source": source,
        "pipeline_stage": context.pipeline_stage.value,
        "tree_version": int(getattr(context, "tree_version", 0) or 0),
        "input": inp_dict,
        "output": out_dict,
    }
    hist.append(entry)
    context.artifacts["m1_decomposer_debug_timeline"] = hist
