"""global_report_builder：episode 聚合逻辑与 build_global_report 单测。"""
import asyncio

import pytest

from app.core.enums import TaskMode
from app.services.coordinator.context import CoordinatorContext
from app.services.coordinator.global_report_builder import (
    aggregate_episodes,
    build_global_report,
)


# ─────────────── 辅助 ───────────────

def _make_episode(
    episode_id: str,
    *,
    scope: str = "full_tree",
    tree_version: int = 0,
    scope_root: str | None = None,
    c_issues: list | None = None,
    c_warnings: list | None = None,
    c_score: float | None = None,
    f_issues: list | None = None,
    f_warnings: list | None = None,
    f_score: float | None = None,
    fpa: dict | None = None,
) -> dict:
    cr: dict = {}
    if c_score is not None:
        cr["score"] = c_score
    if c_issues is not None:
        cr["critical_issues"] = c_issues
    if c_warnings is not None:
        cr["warnings"] = c_warnings

    fr: dict = {}
    if f_score is not None:
        fr["score"] = f_score
    if f_issues is not None:
        fr["critical_issues"] = f_issues
    if f_warnings is not None:
        fr["warnings"] = f_warnings
    if fpa is not None:
        fr["fpa_analysis"] = fpa

    ep: dict = {
        "episode_id": episode_id,
        "scope": scope,
        "tree_version": tree_version,
        "bundle": {
            "evaluation": {
                "consistency_result": cr,
                "feasibility_result": fr,
            }
        },
    }
    if scope_root:
        ep["scope_root_node_id"] = scope_root
    return ep


# ─────────────── aggregate_episodes ───────────────

def test_aggregate_episodes_merges_issues():
    fl = [{"id": "n1", "parent_id": None}]
    eps = [
        _make_episode(
            "ep1",
            tree_version=0,
            c_issues=[{"rule_id": "ci1", "description": "X"}],
            c_warnings=[{"rule_id": "cw1", "description": "Y"}],
            c_score=0.6,
            f_issues=[{"rule_id": "fi1", "description": "Z"}],
            f_score=0.7,
        ),
    ]
    c_agg, f_agg, digest = aggregate_episodes(eps, fl, current_tree_version=0)
    assert len(c_agg["critical_issues"]) == 1
    assert c_agg["critical_issues"][0]["rule_id"] == "ci1"
    assert len(c_agg["warnings"]) == 1
    assert len(f_agg["critical_issues"]) == 1
    assert c_agg["score"] == pytest.approx(0.6)
    assert f_agg["score"] == pytest.approx(0.7)
    assert len(digest) == 1
    assert digest[0]["episode_id"] == "ep1"


def test_aggregate_episodes_same_rule_keeps_multiple_hits():
    """同一 rule_id 跨 episode 保留多条命中，不做并集合并。"""
    fl = [{"id": "n1", "parent_id": None}, {"id": "n2", "parent_id": None}]
    eps = [
        _make_episode(
            "ep1",
            tree_version=0,
            c_issues=[
                {
                    "rule_id": "r1",
                    "description": "a",
                    "affected_nodes": ["n1"],
                    "passed": False,
                }
            ],
            c_score=0.5,
        ),
        _make_episode(
            "ep2",
            scope="subtree",
            scope_root="n1",
            tree_version=0,
            c_issues=[
                {
                    "rule_id": "r1",
                    "description": "b",
                    "affected_nodes": ["n2"],
                    "passed": False,
                }
            ],
            c_score=0.5,
        ),
    ]
    c_agg, _, _ = aggregate_episodes(eps, fl, current_tree_version=0)
    assert len(c_agg["critical_issues"]) == 2
    assert all(x["rule_id"] == "r1" for x in c_agg["critical_issues"])
    nodes_per_row = [x["affected_nodes"] for x in c_agg["critical_issues"]]
    assert {"n1"} in [set(x) for x in nodes_per_row]
    assert {"n2"} in [set(x) for x in nodes_per_row]


def test_aggregate_episodes_prunes_stale_parent_node():
    """父节点已不在 function_list 中时不再出现在合并结果中。"""
    fl = [{"id": "F-1.5.1", "parent_id": None}]
    eps = [
        _make_episode(
            "ep1",
            tree_version=0,
            f_warnings=[
                {
                    "rule_id": "feasibility_006",
                    "affected_nodes": ["F-1.5"],
                    "passed": False,
                    "evidence": {"high_complexity_functions": []},
                }
            ],
            f_score=0.5,
        ),
    ]
    _, f_agg, _ = aggregate_episodes(eps, fl, current_tree_version=0)
    assert f_agg["warnings"] == []


def test_aggregate_episodes_prune_then_multiple_rows_same_rule():
    """父 id 被滤除后子 id 仍保留；同 rule 多条命中分行保留。"""
    fl = [
        {"id": "F-1.5.1", "parent_id": None},
        {"id": "F-1.5.2", "parent_id": None},
    ]
    eps = [
        _make_episode(
            "ep1",
            tree_version=0,
            f_warnings=[
                {
                    "rule_id": "feasibility_006",
                    "affected_nodes": ["F-1.5", "F-1.5.1"],
                    "passed": False,
                    "evidence": {
                        "high_complexity_functions": [
                            {"function_id": "F-1.5", "complexity": "HIGH"},
                            {"function_id": "F-1.5.1", "complexity": "HIGH"},
                        ]
                    },
                }
            ],
            f_score=0.5,
        ),
        _make_episode(
            "ep2",
            scope="subtree",
            scope_root="F-1.5.1",
            tree_version=0,
            f_warnings=[
                {
                    "rule_id": "feasibility_006",
                    "affected_nodes": ["F-1.5.2"],
                    "passed": False,
                    "evidence": {
                        "high_complexity_functions": [
                            {"function_id": "F-1.5.2", "complexity": "HIGH"},
                        ]
                    },
                }
            ],
            f_score=0.55,
        ),
    ]
    _, f_agg, _ = aggregate_episodes(eps, fl, current_tree_version=0)
    assert len(f_agg["warnings"]) == 2
    rows_by_nodes = [tuple(sorted(w["affected_nodes"])) for w in f_agg["warnings"]]
    assert ("F-1.5.1",) in rows_by_nodes
    assert ("F-1.5.2",) in rows_by_nodes
    for w in f_agg["warnings"]:
        assert w["rule_id"] == "feasibility_006"
    hcf_ids = set()
    for w in f_agg["warnings"]:
        for x in w["evidence"]["high_complexity_functions"]:
            hcf_ids.add(x["function_id"])
    assert hcf_ids == {"F-1.5.1", "F-1.5.2"}


def test_aggregate_episodes_picks_latest_fpa():
    fl = [{"id": "n1", "parent_id": None}]
    eps = [
        _make_episode("ep1", tree_version=0, fpa={"total_afp": 10.0}),
        _make_episode(
            "ep2",
            scope="subtree",
            scope_root="n1",
            tree_version=0,
            fpa={"total_afp": 20.0},
        ),
    ]
    _, f_agg, _ = aggregate_episodes(eps, fl, current_tree_version=0)
    assert f_agg["fpa_analysis"]["total_afp"] == 20.0


def test_aggregate_episodes_empty_returns_zeros():
    c_agg, f_agg, digest = aggregate_episodes([], None, current_tree_version=0)
    assert c_agg["score"] == 0.0
    assert f_agg["score"] == 0.0
    assert digest == []


def test_aggregate_episodes_per_scope_digest_structure():
    fl = [{"id": "n1", "parent_id": None}]
    eps = [
        _make_episode("ep1", tree_version=0, c_score=0.75, f_score=0.80),
    ]
    _, _, digest = aggregate_episodes(eps, fl, current_tree_version=0)
    assert digest[0]["consistency_score"] == pytest.approx(0.75)
    assert digest[0]["feasibility_score"] == pytest.approx(0.80)
    assert digest[0]["scope"] == "full_tree"


# ─────────────── build_global_report ───────────────

class _FakeIntegrator:
    """模拟 M2EvaluationIntegratorAgent，同步返回固定 payload。"""

    class _FakeOutput:
        def get_payload(self):
            return {
                "summary": "全局评估通过",
                "recommendation": "proceed",
                "overall_score": 0.78,
                "risk_level": "low",
            }

    async def execute(self, input_data):
        return self._FakeOutput()


class _FakeErrorIntegrator:
    async def execute(self, input_data):
        raise RuntimeError("LLM unreachable")


def _ctx_with_episodes() -> CoordinatorContext:
    ctx = CoordinatorContext(
        conversation_id="test-task",
        requirement_text="需求文本",
        mode=TaskMode.AUTO,
        config={},
    )
    ctx.tree_version = 0
    ctx.artifacts["function_list"] = [{"id": "n1", "parent_id": None}]
    ctx.artifacts["evaluation_episodes"] = [
        _make_episode("ep1", tree_version=0, c_score=0.8, f_score=0.75),
    ]
    return ctx


def test_build_global_report_returns_summary():
    ctx = _ctx_with_episodes()
    result = asyncio.run(build_global_report(ctx, _FakeIntegrator()))
    assert result["summary"] == "全局评估通过"
    assert result["recommendation"] == "proceed"
    assert result["overall_score"] == pytest.approx(0.78)
    assert isinstance(result["per_scope_digest"], list)


def test_build_global_report_short_circuits_single_full_tree():
    """单条全树 episode + 根 evaluation 存在时不调用 Integrator。"""
    ctx = _ctx_with_episodes()
    ctx.artifacts["evaluation"] = {
        "summary": "根层综合摘要",
        "recommendation": "revise",
        "overall_score": 0.82,
        "risk_level": "high",
        "consistency_score": 0.8,
        "feasibility_score": 0.84,
    }

    class _RaisingIntegrator:
        async def execute(self, input_data):
            raise AssertionError("短路时不应调用 Integrator")

    result = asyncio.run(build_global_report(ctx, _RaisingIntegrator()))
    assert result["summary"] == "根层综合摘要"
    assert result["recommendation"] == "revise"
    assert result["overall_score"] == pytest.approx(0.82)
    assert result["risk_level"] == "high"
    assert len(result["per_scope_digest"]) == 1
    assert result["per_scope_digest"][0]["episode_id"] == "ep1"
    assert result["per_scope_digest"][0]["scope"] == "full_tree"


def test_build_global_report_no_short_circuit_when_subtree_episode():
    """rollup 后含多条 episode（全树 + 子树）时不短路，仍调用 Integrator。"""
    ctx = _ctx_with_episodes()
    ctx.artifacts["evaluation_episodes"] = [
        _make_episode("ep_full", tree_version=0, c_score=0.8, f_score=0.75),
        _make_episode(
            "ep_sub",
            scope="subtree",
            scope_root="n1",
            tree_version=0,
            c_score=0.7,
            f_score=0.65,
        ),
    ]
    ctx.artifacts["evaluation"] = {
        "summary": "根摘要若短路会错误采用",
        "overall_score": 0.99,
    }

    result = asyncio.run(build_global_report(ctx, _FakeIntegrator()))
    assert result["summary"] == "全局评估通过"
    assert result["recommendation"] == "proceed"


def test_build_global_report_no_episodes_returns_empty():
    ctx = CoordinatorContext(
        conversation_id="empty",
        requirement_text="req",
        mode=TaskMode.AUTO,
        config={},
    )
    result = asyncio.run(build_global_report(ctx, _FakeIntegrator()))
    assert result["summary"] == ""
    assert result["recommendation"] == ""


def test_build_global_report_integrator_error_returns_fallback():
    ctx = _ctx_with_episodes()
    result = asyncio.run(build_global_report(ctx, _FakeErrorIntegrator()))
    assert result["summary"] == ""
    assert "error" in result
