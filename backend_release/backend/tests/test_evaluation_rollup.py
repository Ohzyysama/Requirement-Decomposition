"""evaluation_episodes 与 rollup 确定性汇总单测。"""
from app.core.enums import TaskMode
from app.services.coordinator.context import CoordinatorContext
from app.services.coordinator.evaluation_rollup import (
    build_evaluation_rollup,
    collect_function_list_node_ids,
    consistency_feasibility_from_episode_bundle,
    prune_rule_like_item_to_current_ids,
    select_episodes_for_rollup,
)
from app.services.coordinator.result_assembler import ResultAssembler


def test_prune_rule_like_keeps_only_current_ids():
    current = {"F-1.5.1", "F-1.5.2"}
    item = {
        "rule_id": "feasibility_006",
        "affected_nodes": ["F-1.5", "F-1.5.1"],
        "evidence": {
            "high_complexity_functions": [
                {"function_id": "F-1.5", "complexity": "HIGH"},
                {"function_id": "F-1.5.1", "complexity": "HIGH"},
            ]
        },
    }
    out = prune_rule_like_item_to_current_ids(item, current)
    assert out is not None
    assert out["affected_nodes"] == ["F-1.5.1"]
    assert len(out["evidence"]["high_complexity_functions"]) == 1
    assert out["evidence"]["high_complexity_functions"][0]["function_id"] == "F-1.5.1"


def test_prune_rule_like_returns_none_when_all_stale():
    current = {"F-1.5.1"}
    item = {
        "rule_id": "feasibility_006",
        "affected_nodes": ["F-1.5"],
        "evidence": {"high_complexity_functions": []},
    }
    assert prune_rule_like_item_to_current_ids(item, current) is None


def test_collect_function_list_node_ids():
    fl = [
        {"id": "a", "parent_id": None},
        {"id": "b", "parent_id": "a"},
    ]
    s = collect_function_list_node_ids(fl)
    assert s == {"a", "b"}


def test_consistency_feasibility_from_evaluation_only_bundle():
    """episode 仅含 evaluation 时从嵌套 result 解析。"""
    b = {
        "evaluation": {
            "consistency_result": {"rule_results": [{"x": 1}]},
            "feasibility_result": {"score": 0.5},
        },
    }
    c, f = consistency_feasibility_from_episode_bundle(b)
    assert c.get("rule_results") == [{"x": 1}]
    assert f.get("score") == 0.5


def test_rollup_from_evaluation_only_bundle():
    fl = [{"id": "n1", "parent_id": None}]
    episodes = [
        {
            "episode_id": "ep1",
            "bundle": {
                "evaluation": {
                    "consistency_result": {"rule_results": []},
                    "feasibility_result": {
                        "rule_results": [
                            {
                                "rule_id": "r2",
                                "passed": False,
                                "affected_nodes": ["n1"],
                                "severity": "error",
                            }
                        ]
                    },
                },
            },
        }
    ]
    r = build_evaluation_rollup(fl, episodes)
    assert r["open_rule_hits"] >= 1
    assert "n1" in (r.get("still_referenced_node_ids") or [])


def test_rollup_passed_empty_affected_nodes_not_superseded():
    """passed 且 affected_nodes 为空的全局性规则不计入 superseded。"""
    fl = [{"id": "n1", "parent_id": None}]
    episodes = [
        {
            "episode_id": "ep1",
            "tree_version": 0,
            "scope": "full_tree",
            "bundle": {
                "evaluation": {
                    "consistency_result": {
                        "rule_results": [
                            {
                                "rule_id": "c1",
                                "passed": True,
                                "affected_nodes": [],
                                "severity": "info",
                            }
                        ]
                    },
                    "feasibility_result": {
                        "rule_results": [
                            {
                                "rule_id": "f1",
                                "passed": True,
                                "affected_nodes": [],
                                "severity": "info",
                            }
                        ]
                    },
                },
            },
        }
    ]
    r = build_evaluation_rollup(fl, episodes, current_tree_version=0)
    assert r["superseded_rule_hits"] == 0
    assert r["superseded_notes"] == []
    assert r["open_rule_hits"] == 0


def test_rollup_full_tree_only_current_tree_version():
    """旧 tree_version 的 full_tree episode 不参与 rollup。"""
    fl = [{"id": "n1", "parent_id": None}]
    episodes = [
        {
            "episode_id": "ep_old",
            "tree_version": 0,
            "scope": "full_tree",
            "bundle": {
                "evaluation": {
                    "consistency_result": {
                        "rule_results": [
                            {
                                "rule_id": "stale",
                                "passed": False,
                                "affected_nodes": ["n1"],
                                "severity": "error",
                            }
                        ]
                    },
                    "feasibility_result": {},
                },
            },
        },
        {
            "episode_id": "ep_new",
            "tree_version": 1,
            "scope": "full_tree",
            "bundle": {
                "evaluation": {
                    "consistency_result": {"rule_results": []},
                    "feasibility_result": {"rule_results": []},
                },
            },
        },
    ]
    r = build_evaluation_rollup(fl, episodes, current_tree_version=1)
    assert r["open_rule_hits"] == 0
    r0 = build_evaluation_rollup(fl, episodes, current_tree_version=0)
    assert r0["open_rule_hits"] >= 1


def test_select_episodes_subtree_keeps_latest_per_root():
    """同一子树根保留 tree_version 最大的一条；不同根并列保留。"""
    cur = {"a", "b", "c"}
    eps = [
        {
            "episode_id": "e1",
            "tree_version": 1,
            "scope": "subtree",
            "scope_root_node_id": "a",
            "bundle": {"evaluation": {}},
        },
        {
            "episode_id": "e2",
            "tree_version": 2,
            "scope": "subtree",
            "scope_root_node_id": "a",
            "bundle": {"evaluation": {}},
        },
        {
            "episode_id": "e3",
            "tree_version": 1,
            "scope": "subtree",
            "scope_root_node_id": "b",
            "bundle": {"evaluation": {}},
        },
    ]
    sel = select_episodes_for_rollup(
        eps, current_tree_version=2, current_ids=cur
    )
    ids = {e["episode_id"] for e in sel}
    assert ids == {"e2", "e3"}


def test_rollup_open_vs_superseded():
    """开放命中与 superseded 均来自 evaluation 内嵌 consistency / feasibility result。"""
    fl = [{"id": "n1", "parent_id": None}]
    episodes = [
        {
            "episode_id": "ep1",
            "parent_node_id": None,
            "bundle": {
                "evaluation": {
                    "consistency_result": {
                        "rule_results": [
                            {
                                "rule_id": "r1",
                                "passed": False,
                                "affected_nodes": ["gone"],
                                "severity": "warning",
                            }
                        ]
                    },
                    "feasibility_result": {
                        "rule_results": [
                            {
                                "rule_id": "r2",
                                "passed": False,
                                "affected_nodes": ["n1"],
                                "severity": "error",
                            }
                        ]
                    },
                },
            },
        }
    ]
    r = build_evaluation_rollup(fl, episodes)
    assert r["superseded_rule_hits"] >= 1
    assert r["open_rule_hits"] >= 1
    assert "n1" in (r.get("still_referenced_node_ids") or [])


def test_assemble_final_omits_evaluation_rollup_has_open_hits():
    """最终报告不含顶层 evaluation artifact；rollup 统计开放命中。"""
    ctx = CoordinatorContext(
        conversation_id="c1",
        requirement_text="r",
        mode=TaskMode.AUTO,
        config={},
    )
    ctx.artifacts["function_list"] = [{"id": "n1", "parent_id": None}]
    ctx.artifacts["evaluation_episodes"] = [
        {
            "episode_id": "ep1",
            "tree_version": 1,
            "scope": "full_tree",
            "bundle": {
                "evaluation": {
                    "feasibility_result": {
                        "rule_results": [
                            {
                                "rule_id": "r1",
                                "passed": False,
                                "affected_nodes": ["n1"],
                                "severity": "warning",
                            }
                        ]
                    },
                }
            },
        }
    ]
    ctx.tree_version = 1
    out = ResultAssembler().assemble_final_result(ctx)
    assert "evaluation" not in out
    assert "quality_summary" not in out
    assert out["evaluation_rollup"]["open_rule_hits"] >= 1


def test_from_saved_final_result_hydrates_m2_root_snapshots():
    """无 evaluation 键时从 coordinator_workspace 根快照还原续跑用 artifacts。"""
    fr = {
        "function_list": [{"id": "a", "parent_id": None}],
        "dependencies": [],
        "tree_version": 1,
        "iteration_count": 1,
        "coordinator_workspace": {
            "m2_root_evaluation_snapshot": {"overall_score": 0.8, "restored": True},
            "m2_root_consistency_evaluation_snapshot": {"score": 0.7},
            "m2_root_feasibility_evaluation_snapshot": {"score": 0.6},
        },
    }
    ctx = CoordinatorContext.from_saved_final_result("c1", "req", fr, {})
    assert ctx.artifacts["evaluation"].get("restored") is True
    assert ctx.artifacts["consistency_evaluation"]["score"] == 0.7
    assert ctx.artifacts["feasibility_evaluation"]["score"] == 0.6


def test_from_saved_final_result_legacy_placeholder_hydrates():
    """旧库中占位 evaluation 仍可经 workspace 还原为根快照。"""
    fr = {
        "function_list": [{"id": "a", "parent_id": None}],
        "dependencies": [],
        "tree_version": 1,
        "iteration_count": 1,
        "evaluation": {
            "source": "deprecated_use_evaluation_rollup",
            "evaluation_episodes_count": 0,
        },
        "coordinator_workspace": {
            "m2_root_evaluation_snapshot": {"overall_score": 0.9},
        },
    }
    ctx = CoordinatorContext.from_saved_final_result("c1", "req", fr, {})
    assert ctx.artifacts["evaluation"].get("overall_score") == 0.9
    assert ctx.artifacts["evaluation"].get("source") is None


