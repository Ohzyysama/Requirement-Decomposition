"""可实现性驱动子 AR 递归与 M2 快照去重相关单元测试。"""
import asyncio
from types import SimpleNamespace
import pytest

from app.core.enums import PipelineStage, TaskMode
from app.schemas.agent import BaseAgentOutput
from app.schemas.evaluation_episodes import EvaluationScopeKind
from app.services.coordinator.agent_invoker import AgentInvoker
from app.services.coordinator.context import CoordinatorContext
from app.services.coordinator.sub_ar_refiner import SubARRefiner
from app.services.coordinator.tree_utils import (
    calc_node_depth_from_root,
    collect_subtree_ids_from_rows,
    filter_dependencies_for_node_ids,
    max_subtree_depth_from_root,
)


def _make_inv_sub():
    inv = AgentInvoker()
    sub = SubARRefiner(inv)
    return inv, sub


# ─────────────── tree_utils 深度工具 ───────────────

def test_calc_node_depth_from_root_same_node():
    rows = [{"id": "F-1", "parent_id": None}]
    assert calc_node_depth_from_root(rows, "F-1", "F-1") == 0


def test_calc_node_depth_from_root_direct_child():
    rows = [
        {"id": "F-1", "parent_id": None},
        {"id": "F-1.1", "parent_id": "F-1"},
    ]
    assert calc_node_depth_from_root(rows, "F-1", "F-1.1") == 1


def test_calc_node_depth_from_root_deep():
    rows = [
        {"id": "F-1", "parent_id": None},
        {"id": "F-1.1", "parent_id": "F-1"},
        {"id": "F-1.1.1", "parent_id": "F-1.1"},
        {"id": "F-1.1.1.1", "parent_id": "F-1.1.1"},
    ]
    assert calc_node_depth_from_root(rows, "F-1", "F-1.1.1.1") == 3


def test_calc_node_depth_from_root_not_in_subtree():
    rows = [
        {"id": "F-1", "parent_id": None},
        {"id": "F-2", "parent_id": None},
        {"id": "F-2.1", "parent_id": "F-2"},
    ]
    assert calc_node_depth_from_root(rows, "F-1", "F-2.1") is None


def test_calc_node_depth_from_root_cycle_unreachable():
    """A 和 B 互为父子形成环，且都不是目标根 ROOT；从 ROOT 找 B 无法沿父链到达。"""
    rows = [
        {"id": "ROOT", "parent_id": None},
        {"id": "A", "parent_id": "B"},
        {"id": "B", "parent_id": "A"},
    ]
    assert calc_node_depth_from_root(rows, "ROOT", "B") is None


def test_calc_node_depth_from_root_node_missing():
    rows = [{"id": "F-1", "parent_id": None}]
    assert calc_node_depth_from_root(rows, "F-1", "not-exist") is None


def test_max_subtree_depth_from_root_flat():
    rows = [
        {"id": "F-1", "parent_id": None},
        {"id": "F-1.1", "parent_id": "F-1"},
        {"id": "F-1.2", "parent_id": "F-1"},
    ]
    assert max_subtree_depth_from_root(rows, "F-1") == 1


def test_max_subtree_depth_from_root_deep():
    rows = [
        {"id": "F-1", "parent_id": None},
        {"id": "F-1.1", "parent_id": "F-1"},
        {"id": "F-1.1.1", "parent_id": "F-1.1"},
        {"id": "F-1.1.1.1", "parent_id": "F-1.1.1"},
    ]
    assert max_subtree_depth_from_root(rows, "F-1") == 3


def test_max_subtree_depth_single_node():
    rows = [{"id": "F-1", "parent_id": None}]
    assert max_subtree_depth_from_root(rows, "F-1") == 0


# ─────────────── 可实现性细化核心 ───────────────

def test_extract_feasibility_failed_node_ids():
    inv, _ = _make_inv_sub()
    feas = {
        "critical_issues": [
            {"affected_nodes": ["a", "b"], "passed": False},
        ],
        "rule_results": [
            {"affected_nodes": ["c"], "passed": False},
            {"affected_nodes": ["a"], "passed": True},
        ],
    }
    ids = inv._extract_feasibility_failed_node_ids(feas)
    assert ids == ["a", "b", "c"]


def test_m2_snapshot_history_signature_differs_by_pipeline_stage():
    inv, _ = _make_inv_sub()
    snap = {"m2_standard_input": {"k": 1}}
    assert inv._m2_snapshot_history_signature(snap, "consistency") != inv._m2_snapshot_history_signature(
        snap, "feasibility"
    )


def test_m2_snapshot_history_signature_differs_by_m2_scope():
    inv, _ = _make_inv_sub()
    base = {"m2_standard_input": {"k": 1}}
    a = inv._m2_snapshot_history_signature(
        {**base, "m2_scope": {"scope_root_node_id": "n1"}}, "feasibility"
    )
    b = inv._m2_snapshot_history_signature(
        {**base, "m2_scope": {"scope_root_node_id": "n2"}}, "feasibility"
    )
    assert a != b


def test_feasibility_failed_walk_processes_all_failed_node_ids(monkeypatch):
    """可实现性失败节点应全部尝试细化，不因每轮节点数上限截断。"""
    inv, sub = _make_inv_sub()
    ctx = CoordinatorContext(
        conversation_id="t-all-nodes",
        requirement_text="",
        mode=TaskMode.AUTO,
        config={"max_feasibility_refinement_depth": 3},
    )
    # 构造树：根 F-1，子节点 a/b/c/d/e 均为深度 1（< 3）
    ctx.artifacts["function_list"] = [
        {"id": "F-1", "parent_id": None},
        {"id": "a", "parent_id": "F-1"},
        {"id": "b", "parent_id": "F-1"},
        {"id": "c", "parent_id": "F-1"},
        {"id": "d", "parent_id": "F-1"},
        {"id": "e", "parent_id": "F-1"},
    ]
    merged = {}
    refined = []

    async def fake_refine(_ctx, _merged, nid, _hint, on_agent_complete=None):
        refined.append(nid)
        return False

    monkeypatch.setattr(sub, "_refine_one_sub_ar_node", fake_refine)

    asyncio.run(
        sub._feasibility_failed_walk(
            ctx, merged, None, ["a", "b", "c", "d", "e"], "F-1", [], None
        )
    )
    assert refined == ["a", "b", "c", "d", "e"]


def test_feasibility_failed_walk_depth_limit_blocks_deep_nodes(monkeypatch):
    """相对深度 >= max_feasibility_refinement_depth 的节点应被跳过，不触发重拆。"""
    inv, sub = _make_inv_sub()
    ctx = CoordinatorContext(
        conversation_id="t-depth-limit",
        requirement_text="",
        mode=TaskMode.AUTO,
        config={"max_feasibility_refinement_depth": 2},
    )
    # F-1.1.1.1 相对 F-1 深度=3，超过上限 2，应被跳过
    ctx.artifacts["function_list"] = [
        {"id": "F-1", "parent_id": None},
        {"id": "F-1.1", "parent_id": "F-1"},
        {"id": "F-1.1.1", "parent_id": "F-1.1"},
        {"id": "F-1.1.1.1", "parent_id": "F-1.1.1"},
    ]
    refined = []

    async def fake_refine(_ctx, _merged, nid, _hint, on_agent_complete=None):
        refined.append(nid)
        return False

    monkeypatch.setattr(sub, "_refine_one_sub_ar_node", fake_refine)

    asyncio.run(
        sub._feasibility_failed_walk(
            ctx, {}, None, ["F-1.1.1.1"], "F-1", [], None
        )
    )
    assert refined == []
    assert "feasibility_refinement_depth_exceeded" in (
        ctx.quality_flags.get("coordinator") or []
    )


def test_feasibility_failed_walk_allows_node_at_depth_below_limit(monkeypatch):
    """相对深度 < max_feasibility_refinement_depth 的节点应允许细化。"""
    inv, sub = _make_inv_sub()
    ctx = CoordinatorContext(
        conversation_id="t-depth-allow",
        requirement_text="",
        mode=TaskMode.AUTO,
        config={"max_feasibility_refinement_depth": 3},
    )
    # F-1.1.1 相对 F-1 深度 = 2，允许细化（< 3）
    ctx.artifacts["function_list"] = [
        {"id": "F-1", "parent_id": None},
        {"id": "F-1.1", "parent_id": "F-1"},
        {"id": "F-1.1.1", "parent_id": "F-1.1"},
    ]
    refined = []

    async def fake_refine(_ctx, _merged, nid, _hint, on_agent_complete=None):
        refined.append(nid)
        return False

    monkeypatch.setattr(sub, "_refine_one_sub_ar_node", fake_refine)

    asyncio.run(
        sub._feasibility_failed_walk(
            ctx, {}, None, ["F-1.1.1"], "F-1", [], None
        )
    )
    assert "F-1.1.1" in refined


def test_feasibility_failed_walk_mixed_depth_partial_skip(monkeypatch):
    """多节点位于不同深度时，低于上限的处理，达到上限的跳过，互不影响。"""
    inv, sub = _make_inv_sub()
    ctx = CoordinatorContext(
        conversation_id="t-mixed",
        requirement_text="",
        mode=TaskMode.AUTO,
        config={"max_feasibility_refinement_depth": 2},
    )
    ctx.artifacts["function_list"] = [
        {"id": "F-1", "parent_id": None},
        {"id": "F-1.1", "parent_id": "F-1"},       # depth=1, 允许
        {"id": "F-1.1.1", "parent_id": "F-1.1"},   # depth=2, 跳过（>=2）
    ]
    refined = []

    async def fake_refine(_ctx, _merged, nid, _hint, on_agent_complete=None):
        refined.append(nid)
        return False

    monkeypatch.setattr(sub, "_refine_one_sub_ar_node", fake_refine)

    asyncio.run(
        sub._feasibility_failed_walk(
            ctx, {}, None, ["F-1.1", "F-1.1.1"], "F-1", [], None
        )
    )
    assert "F-1.1" in refined
    assert "F-1.1.1" not in refined


def test_filter_dependencies_for_node_ids():
    deps = [
        {"from": "a", "to": "b"},
        {"from": "a", "to": "x"},
    ]
    s = collect_subtree_ids_from_rows(
        [
            {"id": "a", "parent_id": None},
            {"id": "b", "parent_id": "a"},
        ],
        "a",
    )
    out = filter_dependencies_for_node_ids(deps, s)
    assert len(out) == 1
    assert out[0]["from"] == "a"


def test_max_feasibility_refinement_depth_zero_skips_walk(monkeypatch):
    """max_feasibility_refinement_depth<=0 时不进入可实现性驱动细化（无重拆调用）。"""
    inv, sub = _make_inv_sub()
    ctx = CoordinatorContext(
        conversation_id="t1",
        requirement_text="",
        mode=TaskMode.AUTO,
        config={
            "max_feasibility_refinement_depth": 0,
        },
    )
    ctx.artifacts["feasibility_evaluation"] = {
        "critical_issues": [
            {"affected_nodes": ["n1"], "passed": False},
        ],
        "rule_results": [],
    }
    ctx.artifacts["evaluation"] = {"overall_score": 0.5}
    ctx.artifacts["consistency_evaluation"] = {"score": 0.9}
    ctx.artifacts["function_list"] = []
    ctx.artifacts["dependencies"] = []

    called = {"refine": 0}

    async def _no_refine(*_a, **_k):
        called["refine"] += 1
        return False

    monkeypatch.setattr(sub, "_refine_one_sub_ar_node", _no_refine)

    asyncio.run(sub._run_feasibility_refinement_after_root(ctx, {}, None))
    assert called["refine"] == 0


def test_refine_node_depth_zero_raises():
    """max_feasibility_refinement_depth=0 时 refine_node_and_run_m2_tail 应抛出 ValueError。"""
    from app.services.coordinator.pipeline_runner import PipelineRunner

    inv, sub = _make_inv_sub()
    runner = PipelineRunner(inv, sub)

    ctx = CoordinatorContext(
        conversation_id="t-zero",
        requirement_text="",
        mode=TaskMode.AUTO,
        config={"max_feasibility_refinement_depth": 0},
    )

    with pytest.raises(ValueError, match="max_feasibility_refinement_depth=0"):
        asyncio.run(runner.refine_node_and_run_m2_tail(ctx, "F-1.1"))


def test_refine_node_uses_selected_node_as_root(monkeypatch):
    """refine-node 应以用户选择节点为深度根，并将 refinement_root_id 传给 _cf_list_consistency_m2_tail。"""
    from app.services.coordinator.pipeline_runner import PipelineRunner

    inv, sub = _make_inv_sub()
    runner = PipelineRunner(inv, sub)

    ctx = CoordinatorContext(
        conversation_id="t-refine-root",
        requirement_text="",
        mode=TaskMode.AUTO,
        config={"max_feasibility_refinement_depth": 1},
    )
    ctx.artifacts["function_list"] = [
        {"id": "F-1", "parent_id": None, "title": "root", "desc": ""},
        {"id": "F-1.1", "parent_id": "F-1", "title": "mid", "desc": ""},
        {"id": "F-1.1.1", "parent_id": "F-1.1", "title": "leaf", "desc": ""},
    ]
    ctx.artifacts["dependencies"] = []

    captured_root: list = []

    async def fake_refine_one(_ctx, _merged, nid, _hint, on_agent_complete=None):
        return True

    async def fake_cf_tail(context, merged, on_agent_complete=None,
                           on_list_ready=None, on_m2_agent_complete=None, *,
                           refinement_root_id=""):
        captured_root.append(refinement_root_id)
        return merged

    monkeypatch.setattr(sub, "_refine_one_sub_ar_node", fake_refine_one)
    monkeypatch.setattr(runner, "_cf_list_consistency_m2_tail", fake_cf_tail)

    asyncio.run(runner.refine_node_and_run_m2_tail(ctx, "F-1.1"))
    assert captured_root == ["F-1.1"]


def test_scoped_consistency_fail_inner_max_zero_skips_feasibility(monkeypatch):
    """收窄作用域一致性失败且 consistency_inner_max_retries=0 时不跑可实现性。"""
    inv, sub = _make_inv_sub()
    ctx = CoordinatorContext(
        conversation_id="t-scoped-0",
        requirement_text="",
        mode=TaskMode.AUTO,
        config={
            "consistency_inner_max_retries": 0,
            "consistency_pass_threshold": 0.7,
            "max_feasibility_refinement_depth": 3,
        },
    )
    ctx.artifacts["function_list"] = [
        {"id": "n1", "parent_id": None, "title": "t", "desc": "d"},
        {"id": "n2", "parent_id": "n1", "title": "t2", "desc": "d2"},
    ]
    ctx.artifacts["dependencies"] = [
        {"from": "n1", "to": "n2"},
    ]
    merged = {}
    calls = {"feasibility": 0}

    async def fake_refine(*_a, **_k):
        return True

    async def fake_consistency(_ctx, function_list_override=None,
                               dependencies_override=None, on_m2_agent_complete=None,
                               write_to_artifacts=True):
        return SimpleNamespace(
            result={
                "result": {
                    "score": 0.1,
                    "critical_issues": ["x"],
                    "remediation_instruction": "",
                }
            }
        )

    async def fake_feasibility(*_a, **_k):
        calls["feasibility"] += 1
        return {}

    monkeypatch.setattr(sub, "_refine_one_sub_ar_node", fake_refine)
    monkeypatch.setattr(inv, "invoke_m2_consistency_only", fake_consistency)
    monkeypatch.setattr(inv, "invoke_m2_feasibility_integrator_only", fake_feasibility)

    # n1 是根（depth=0 < 3），其子节点 n2 存在，id_set 有 2 个节点可继续处理
    asyncio.run(
        sub._feasibility_failed_walk(ctx, merged, None, ["n1"], "n1", [], None)
    )
    assert calls["feasibility"] == 0
    assert "feasibility_refinement_scoped_consistency_failed" in (
        ctx.quality_flags.get("consistency_evaluator") or []
    )


def test_scoped_consistency_inner_retry_then_feasibility(monkeypatch):
    """收窄作用域下首次一致性失败、内层重拆后通过则调用可实现性。"""
    inv, sub = _make_inv_sub()
    ctx = CoordinatorContext(
        conversation_id="t-scoped-retry",
        requirement_text="",
        mode=TaskMode.AUTO,
        config={
            "consistency_inner_max_retries": 1,
            "consistency_pass_threshold": 0.7,
            "max_feasibility_refinement_depth": 3,
        },
    )
    ctx.artifacts["function_list"] = [
        {"id": "n1", "parent_id": None, "title": "t", "desc": "d"},
        {"id": "n2", "parent_id": "n1", "title": "t2", "desc": "d2"},
    ]
    ctx.artifacts["dependencies"] = [{"from": "n1", "to": "n2"}]
    merged = {}
    calls = {"feasibility": 0, "consistency": 0}
    reasons = []

    async def track_refine(_ctx, _merged, _nid, hint, on_agent_complete=None):
        reasons.append(hint.get("split_reason"))
        return True

    async def fake_consistency(_ctx, function_list_override=None,
                               dependencies_override=None, on_m2_agent_complete=None,
                               write_to_artifacts=True):
        calls["consistency"] += 1
        if calls["consistency"] == 1:
            return SimpleNamespace(
                result={
                    "result": {
                        "score": 0.1,
                        "critical_issues": ["x"],
                        "remediation_instruction": "split more",
                    }
                }
            )
        return SimpleNamespace(
            result={
                "result": {
                    "score": 0.95,
                    "critical_issues": [],
                    "remediation_instruction": "",
                }
            }
        )

    async def fake_feasibility(*_a, **_k):
        calls["feasibility"] += 1
        return {}

    monkeypatch.setattr(sub, "_refine_one_sub_ar_node", track_refine)
    monkeypatch.setattr(inv, "invoke_m2_consistency_only", fake_consistency)
    monkeypatch.setattr(inv, "invoke_m2_feasibility_integrator_only", fake_feasibility)

    # n1 是根（depth=0 < 3），其子节点 n2 存在，id_set 有 2 个节点可继续处理
    asyncio.run(
        sub._feasibility_failed_walk(ctx, merged, None, ["n1"], "n1", [], None)
    )
    assert calls["consistency"] == 2
    assert calls["feasibility"] == 1
    assert reasons == ["feasibility_failed", "scoped_consistency_failed"]


def test_scoped_feasibility_integrator_episode_scope_is_subtree(monkeypatch):
    """子树可实现性+Integrator 追加的 episode 必须为 subtree（不得因过早 pop m2_scope 标成 full_tree）。"""
    inv, sub = _make_inv_sub()
    ctx = CoordinatorContext(
        conversation_id="t-ep-scope",
        requirement_text="",
        mode=TaskMode.AUTO,
        config={
            "consistency_inner_max_retries": 1,
            "consistency_pass_threshold": 0.7,
            "max_feasibility_refinement_depth": 3,
        },
    )
    ctx.artifacts["normalized_requirement"] = {"text": "nr"}
    ctx.artifacts["function_list"] = [
        {"id": "n1", "parent_id": None, "title": "t", "desc": "d"},
        {"id": "n2", "parent_id": "n1", "title": "t2", "desc": "d2"},
    ]
    ctx.artifacts["dependencies"] = [{"from": "n1", "to": "n2"}]

    async def fake_refine(*_a, **_k):
        return True

    pass_cons = BaseAgentOutput(
        result={"result": {"score": 0.95, "critical_issues": [], "remediation_instruction": ""}}
    )
    empty_feas = BaseAgentOutput(
        result={"result": {"critical_issues": [], "rule_results": []}}
    )
    integr_payload = BaseAgentOutput(
        result={"result": {"overall_score": 1.0, "consistency_result": {}}}
    )

    async def fake_consistency_execute(_inp):
        return pass_cons

    async def fake_feas_execute(_inp):
        return empty_feas

    async def fake_integrator_execute(_inp):
        return integr_payload

    monkeypatch.setattr(inv._m2_consistency, "execute", fake_consistency_execute)
    monkeypatch.setattr(inv._m2_feasibility, "execute", fake_feas_execute)
    monkeypatch.setattr(inv._m2_integrator, "execute", fake_integrator_execute)
    monkeypatch.setattr(sub, "_refine_one_sub_ar_node", fake_refine)

    asyncio.run(
        sub._feasibility_failed_walk(ctx, {}, None, ["n1"], "n1", [], None)
    )

    eps = ctx.artifacts.get("evaluation_episodes") or []
    assert len(eps) >= 1
    last = eps[-1]
    assert last.get("scope") == EvaluationScopeKind.SUBTREE.value
    assert last.get("scope_root_node_id") == "n1"


def test_feasibility_refinement_root_m2_snapshots_in_workspace_not_restored_to_artifacts(
    monkeypatch,
):
    """子 AR walk 后根层 Integrator 快照进 workspace，不再覆盖 artifacts 中的子树 evaluation。"""
    inv, sub = _make_inv_sub()
    ctx = CoordinatorContext(
        conversation_id="t-ws",
        requirement_text="",
        mode=TaskMode.AUTO,
        config={
            "enable_feasibility_refinement": True,
            "max_feasibility_refinement_depth": 3,
        },
    )
    ctx.artifacts["evaluation"] = {"overall_score": 0.9, "from": "root"}
    ctx.artifacts["consistency_evaluation"] = {"score": 0.9}
    ctx.artifacts["feasibility_evaluation"] = {
        "critical_issues": [
            {"affected_nodes": ["n1"], "passed": False},
        ],
        "rule_results": [],
    }
    ctx.artifacts["function_list"] = []
    ctx.artifacts["dependencies"] = []

    async def fake_walk(*_a, **_k):
        ctx.artifacts["evaluation"] = {"overall_score": 0.2, "from": "subtree"}

    monkeypatch.setattr(sub, "_feasibility_failed_walk", fake_walk)

    asyncio.run(sub._run_feasibility_refinement_after_root(ctx, {}, None))
    assert ctx.artifacts["m2_root_evaluation_snapshot"].get("from") == "root"
    assert ctx.artifacts["m2_root_consistency_evaluation_snapshot"].get("score") == 0.9
    assert ctx.artifacts["evaluation"].get("from") == "subtree"


def test_root_cf_tail_consistency_retries_exhausted_skips_feasibility(monkeypatch):
    """根层一致性内层重试用尽且未开启 continue 时跳过可实现性，仅走 skip Integrator。"""
    from app.services.coordinator.pipeline_runner import PipelineRunner

    inv, sub = _make_inv_sub()
    runner = PipelineRunner(inv, sub)
    ctx = CoordinatorContext(
        conversation_id="t-root-cf-exhausted",
        requirement_text="",
        mode=TaskMode.AUTO,
        config={
            "consistency_inner_max_retries": 1,
            "consistency_pass_threshold": 0.7,
        },
    )
    ctx.artifacts["function_list"] = [
        {"id": "F-1", "parent_id": None, "title": "r", "desc": "d"},
        {"id": "F-1.1", "parent_id": "F-1", "title": "c", "desc": "d2"},
    ]
    ctx.artifacts["dependencies"] = [{"from": "F-1", "to": "F-1.1"}]

    calls = {"consistency": 0, "feasibility": 0, "skip": 0}

    async def fake_consistency(*_a, **_k):
        calls["consistency"] += 1
        return SimpleNamespace(
            result={
                "result": {
                    "score": 0.1,
                    "critical_issues": ["x"],
                    "remediation_instruction": "hint",
                }
            }
        )

    async def fake_m1(*_a, **_k):
        return {}

    async def fake_feasibility(*_a, **_k):
        calls["feasibility"] += 1
        return {}

    async def fake_skip(*_a, **_k):
        calls["skip"] += 1
        return {
            "evaluation_integrator": BaseAgentOutput(
                result={
                    "result": {
                        "summary": "stub",
                        "feasibility_evaluation_skipped": True,
                        "integration_scope": "consistency_only",
                    }
                }
            )
        }

    monkeypatch.setattr(inv, "invoke_m2_consistency_only", fake_consistency)
    monkeypatch.setattr(inv, "invoke_m2_feasibility_integrator_only", fake_feasibility)
    monkeypatch.setattr(inv, "invoke_m2_integrator_skip_feasibility", fake_skip)
    monkeypatch.setattr(runner, "invoke_m1_decomposer_and_dependency_no_gate", fake_m1)

    merged = {}
    asyncio.run(runner._cf_list_consistency_m2_tail(ctx, merged))

    assert calls["consistency"] == 2
    assert calls["feasibility"] == 0
    assert calls["skip"] == 1
    assert "consistency_not_passed_after_inner_retries" in (
        ctx.quality_flags.get("consistency_evaluator") or []
    )
    assert ctx.pipeline_stage == PipelineStage.CONSISTENCY


def test_root_cf_tail_consistency_exhausted_continue_runs_feasibility(monkeypatch):
    """耗尽后若 continue_pipeline_after_consistency_exhausted=True 则仍跑可实现性尾段，不调用 skip。"""
    from app.services.coordinator.pipeline_runner import PipelineRunner

    inv, sub = _make_inv_sub()
    runner = PipelineRunner(inv, sub)
    ctx = CoordinatorContext(
        conversation_id="t-root-cf-continue",
        requirement_text="",
        mode=TaskMode.AUTO,
        config={
            "consistency_inner_max_retries": 1,
            "consistency_pass_threshold": 0.7,
            "continue_pipeline_after_consistency_exhausted": True,
        },
    )
    ctx.artifacts["function_list"] = [
        {"id": "F-1", "parent_id": None, "title": "r", "desc": "d"},
        {"id": "F-1.1", "parent_id": "F-1", "title": "c", "desc": "d2"},
    ]
    ctx.artifacts["dependencies"] = [{"from": "F-1", "to": "F-1.1"}]

    calls = {"consistency": 0, "feasibility": 0, "skip": 0}

    async def fake_consistency(*_a, **_k):
        calls["consistency"] += 1
        return SimpleNamespace(
            result={
                "result": {
                    "score": 0.1,
                    "critical_issues": ["x"],
                    "remediation_instruction": "hint",
                }
            }
        )

    async def fake_m1(*_a, **_k):
        return {}

    async def fake_feasibility(*_a, **_k):
        calls["feasibility"] += 1
        return {
            "feasibility_evaluator": BaseAgentOutput(result={"result": {}}),
            "evaluation_integrator": BaseAgentOutput(result={"result": {}}),
        }

    async def fake_skip(*_a, **_k):
        calls["skip"] += 1
        return {}

    async def fake_refinement_after_root(*_a, **_k):
        return None

    monkeypatch.setattr(inv, "invoke_m2_consistency_only", fake_consistency)
    monkeypatch.setattr(inv, "invoke_m2_feasibility_integrator_only", fake_feasibility)
    monkeypatch.setattr(inv, "invoke_m2_integrator_skip_feasibility", fake_skip)
    monkeypatch.setattr(runner, "invoke_m1_decomposer_and_dependency_no_gate", fake_m1)
    monkeypatch.setattr(sub, "_run_feasibility_refinement_after_root", fake_refinement_after_root)

    merged = {}
    asyncio.run(runner._cf_list_consistency_m2_tail(ctx, merged))

    assert calls["consistency"] == 2
    assert calls["feasibility"] == 1
    assert calls["skip"] == 0
    assert "consistency_not_passed_after_inner_retries" in (
        ctx.quality_flags.get("consistency_evaluator") or []
    )


def test_context_from_saved_final_result():
    fr = {
        "function_list": [{"id": "a", "parent_id": None}],
        "dependencies": [],
        "tree_version": 2,
        "iteration_count": 1,
    }
    ctx = CoordinatorContext.from_saved_final_result(
        "c1", "requirement text", fr, {"consistency_pass_threshold": 0.8}
    )
    assert ctx.conversation_id == "c1"
    assert ctx.requirement_text == "requirement text"
    assert ctx.config.get("consistency_pass_threshold") == 0.8
    assert ctx.artifacts.get("function_list") == fr["function_list"]
    assert ctx.tree_version == 2
    assert ctx.iteration_count == 1
