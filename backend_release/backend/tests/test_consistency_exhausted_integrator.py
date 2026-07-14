"""一致性内层耗尽早停仍跑 Integrator 的标记与文案。"""
import asyncio
from unittest.mock import AsyncMock

import pytest

from app.core.enums import TaskMode
from app.schemas.agent import AgentInput, BaseAgentOutput
from app.services.coordinator.agent_invoker import AgentInvoker
from app.services.coordinator.context import CoordinatorContext
from app.services.agents.M2.agents.m2_integrator_agent import M2EvaluationIntegratorAgent


def test_integrator_sets_skip_feasibility_markers(monkeypatch):
    async def fake_llm(self, consistency_result, feasibility_result, input_data):
        return "继续修订", "未执行可实现性评估（测试桩）。"

    monkeypatch.setattr(
        M2EvaluationIntegratorAgent,
        "_generate_llm_based_analysis",
        fake_llm,
    )
    agent = M2EvaluationIntegratorAgent()
    inp = AgentInput(
        task_id="t1",
        requirement_text="",
        artifacts={
            "consistency_result": {"score": 0.5, "rule_results": []},
            "feasibility_result": {},
            "feasibility_evaluation_skipped": True,
        },
    )
    out = asyncio.run(agent.execute(inp))
    inner = (out.result or {}).get("result") or {}
    assert inner.get("feasibility_evaluation_skipped") is True
    assert inner.get("integration_scope") == "consistency_only"
    assert "未执行可实现性评估" in (inner.get("summary") or "")


def test_integrator_full_path_no_skip_markers():
    agent = M2EvaluationIntegratorAgent()
    inp = AgentInput(
        task_id="t1",
        requirement_text="",
        artifacts={
            "consistency_result": {"score": 0.9, "rule_results": []},
            "feasibility_result": {"score": 0.8, "rule_results": []},
        },
    )
    out = asyncio.run(agent.execute(inp))
    inner = (out.result or {}).get("result") or {}
    assert inner.get("feasibility_evaluation_skipped") is None
    assert inner.get("integration_scope") is None


def test_invoker_invoke_m2_integrator_skip_feasibility_writes_artifacts():
    ctx = CoordinatorContext(
        conversation_id="cid1",
        requirement_text="x",
        mode=TaskMode.AUTO,
        config={},
    )
    ctx.artifacts["function_list"] = []
    ctx.artifacts["dependencies"] = []
    ctx.artifacts["normalized_requirement"] = {}
    ctx.artifacts["consistency_evaluation"] = {"score": 0.3, "rule_results": []}

    inv = AgentInvoker()
    inv._m2_integrator.execute = AsyncMock(
        return_value=BaseAgentOutput(
            result={
                "result": {
                    "summary": "stub",
                    "feasibility_evaluation_skipped": True,
                    "integration_scope": "consistency_only",
                    "consistency_result": {},
                    "feasibility_result": {},
                },
                "processing_time": 0.0,
                "integration_details": {},
                "scoring_details": {},
                "decision_support": {},
            }
        )
    )

    merged = asyncio.run(inv.invoke_m2_integrator_skip_feasibility(ctx))
    assert "evaluation_integrator" in merged
    assert ctx.artifacts.get("feasibility_evaluation") == {}
    assert ctx.artifacts.get("evaluation", {}).get("feasibility_evaluation_skipped") is True
    eps = ctx.artifacts.get("evaluation_episodes")
    assert isinstance(eps, list) and len(eps) == 1
