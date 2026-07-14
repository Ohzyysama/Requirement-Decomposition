"""
协调器服务包

子模块可直接 ``from app.services.coordinator.decision_engine import ...``；
包级 ``from app.services.coordinator import Orchestrator`` 通过惰性加载，避免导入无关依赖。
"""
from typing import Any, List

__all__ = [
    "Orchestrator",
    "TaskManager",
    "CoordinatorContext",
    "DecisionEngine",
    "ResultAssembler",
    "FinalResultAssembler",
    "SsePayloadFactory",
    "AgentInvoker",
    "PipelineRunner",
    "SubARRefiner",
    "ContextHydrator",
]


def __getattr__(name: str) -> Any:
    if name == "Orchestrator":
        from app.services.coordinator.orchestrator import Orchestrator
        return Orchestrator
    if name == "TaskManager":
        from app.services.coordinator.task_manager import TaskManager
        return TaskManager
    if name == "CoordinatorContext":
        from app.services.coordinator.context import CoordinatorContext
        return CoordinatorContext
    if name == "DecisionEngine":
        from app.services.coordinator.decision_engine import DecisionEngine
        return DecisionEngine
    if name == "ResultAssembler":
        from app.services.coordinator.result_assembler import ResultAssembler
        return ResultAssembler
    if name == "FinalResultAssembler":
        from app.services.coordinator.final_result_assembler import FinalResultAssembler
        return FinalResultAssembler
    if name == "SsePayloadFactory":
        from app.services.coordinator.sse_payload_factory import SsePayloadFactory
        return SsePayloadFactory
    if name == "AgentInvoker":
        from app.services.coordinator.agent_invoker import AgentInvoker
        return AgentInvoker
    if name == "PipelineRunner":
        from app.services.coordinator.pipeline_runner import PipelineRunner
        return PipelineRunner
    if name == "SubARRefiner":
        from app.services.coordinator.sub_ar_refiner import SubARRefiner
        return SubARRefiner
    if name == "ContextHydrator":
        from app.services.coordinator.context_hydrator import ContextHydrator
        return ContextHydrator
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")


def __dir__() -> List[str]:
    return list(__all__)
