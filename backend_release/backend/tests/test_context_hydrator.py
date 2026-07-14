"""ContextHydrator 与 CoordinatorContext.update_stage 单元测试。"""

from app.core.enums import PipelineStage, TaskMode
from app.services.coordinator.context import CoordinatorContext
from app.services.coordinator.context_hydrator import ContextHydrator


def test_from_db_result_restores_stage_tree_iteration_and_artifacts():
    final_result = {
        "pipeline_stage": "feasibility",
        "tree_version": 7,
        "iteration_count": 3,
        "function_list": [{"id": "F-1", "parent_id": None}],
        "dependencies": [{"from": "a", "to": "b"}],
        "normalized_requirement": {"title": "t"},
        "evaluation_episodes": [{"episode_id": "e1"}],
        "m2_inputs_snapshot_history": [{"phase": "consistency"}],
        "node_evaluations": {"F-1": {}},
    }
    ctx = ContextHydrator.from_db_result(
        "conv-1",
        "req text",
        final_result,
        {"version_selection": "latest"},
    )
    assert ctx.conversation_id == "conv-1"
    assert ctx.requirement_text == "req text"
    assert ctx.mode == TaskMode.AUTO
    assert ctx.config == {"version_selection": "latest"}
    assert ctx.pipeline_stage == PipelineStage.FEASIBILITY
    assert ctx.tree_version == 7
    assert ctx.iteration_count == 3
    assert ctx.artifacts["function_list"][0]["id"] == "F-1"
    assert ctx.artifacts["evaluation_episodes"][0]["episode_id"] == "e1"
    assert ctx.artifacts["m2_inputs_snapshot_history"][0]["phase"] == "consistency"


def test_from_db_result_deep_copies_artifacts():
    fr = {
        "pipeline_stage": "done",
        "tree_version": 1,
        "iteration_count": 1,
        "function_list": [{"id": "x"}],
    }
    ctx = ContextHydrator.from_db_result("c", "r", fr, {})
    fr["function_list"][0]["id"] = "mutated"
    assert ctx.artifacts["function_list"][0]["id"] == "x"


def test_from_db_result_legacy_state_field():
    fr = {"state": "split", "tree_version": 0, "iteration_count": 0}
    ctx = ContextHydrator.from_db_result("c", "r", fr, {})
    assert ctx.pipeline_stage == PipelineStage.SPLIT


def test_from_db_result_legacy_evaluation_from_workspace():
    """evaluation 为占位且 workspace 含快照时，恢复到 artifacts。"""
    fr = {
        "pipeline_stage": "done",
        "tree_version": 0,
        "iteration_count": 1,
        "evaluation": {"source": "deprecated_use_evaluation_rollup"},
        "coordinator_workspace": {
            "m2_root_evaluation_snapshot": {"overall_score": 0.9},
            "m2_root_consistency_evaluation_snapshot": {"c": 1},
            "m2_root_feasibility_evaluation_snapshot": {"f": 2},
        },
    }
    ctx = ContextHydrator.from_db_result("c", "r", fr, {})
    assert ctx.artifacts["evaluation"]["overall_score"] == 0.9
    assert ctx.artifacts["consistency_evaluation"] == {"c": 1}
    assert ctx.artifacts["feasibility_evaluation"] == {"f": 2}


def test_update_stage_logs_transition():
    ctx = CoordinatorContext(
        conversation_id="x",
        requirement_text="",
        mode=TaskMode.AUTO,
        config={},
    )
    assert ctx.pipeline_stage == PipelineStage.IDLE
    ctx.update_stage(PipelineStage.SPLIT)
    assert len(ctx.state_transition_log) == 1
    assert ctx.state_transition_log[0]["from_state"] == PipelineStage.IDLE.value
    assert ctx.state_transition_log[0]["to_state"] == PipelineStage.SPLIT.value
    ctx.update_stage(PipelineStage.CONSISTENCY)
    assert len(ctx.state_transition_log) == 2
    assert ctx.state_transition_log[1]["to_state"] == PipelineStage.CONSISTENCY.value


def test_update_stage_same_stage_no_extra_log():
    ctx = CoordinatorContext(
        conversation_id="x",
        requirement_text="",
        mode=TaskMode.AUTO,
        config={},
    )
    ctx.update_stage(PipelineStage.SPLIT)
    n = len(ctx.state_transition_log)
    ctx.update_stage(PipelineStage.SPLIT)
    assert len(ctx.state_transition_log) == n


def test_update_stage_repeat_then_change():
    ctx = CoordinatorContext(
        conversation_id="x",
        requirement_text="",
        mode=TaskMode.AUTO,
        config={},
    )
    ctx.update_stage(PipelineStage.SPLIT)
    ctx.update_stage(PipelineStage.SPLIT)
    ctx.update_stage(PipelineStage.DONE)
    assert [e["to_state"] for e in ctx.state_transition_log] == [
        PipelineStage.SPLIT.value,
        PipelineStage.DONE.value,
    ]
