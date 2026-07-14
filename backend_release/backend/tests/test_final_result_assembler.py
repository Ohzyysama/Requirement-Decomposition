"""FinalResultAssembler：关键字段与 JSON 可序列化性。"""
import json

from app.core.enums import PipelineStage, TaskMode
from app.services.coordinator.context import CoordinatorContext
from app.services.coordinator.final_result_assembler import FinalResultAssembler


def _minimal_context_for_assembler() -> CoordinatorContext:
    ctx = CoordinatorContext(
        conversation_id="asm-1",
        requirement_text="hello",
        mode=TaskMode.AUTO,
        config={},
    )
    ctx.pipeline_stage = PipelineStage.DONE
    ctx.iteration_count = 1
    ctx.tree_version = 2
    ctx.artifacts["function_list"] = [{"id": "n1", "parent_id": None}]
    ctx.artifacts["evaluation_episodes"] = [
        {
            "episode_id": "ep1",
            "tree_version": 2,
            "parent_node_id": "n1",
            "bundle": {
                "evaluation": {
                    "consistency_result": {"rule_results": []},
                    "feasibility_result": {"rule_results": []},
                },
            },
        }
    ]
    return ctx


def test_assemble_final_result_contains_core_fields_and_rollup():
    ctx = _minimal_context_for_assembler()
    out = FinalResultAssembler().assemble_final_result(ctx, iterations=[])

    assert out["pipeline_stage"] == PipelineStage.DONE.value
    assert out["conversation_id"] == "asm-1"
    assert out["tree_version"] == 2
    assert isinstance(out.get("evaluation_rollup"), dict)
    assert out["evaluation_episodes"][0]["episode_id"] == "ep1"
    assert "open_rule_hits" in out["evaluation_rollup"]


def test_assemble_final_result_contains_global_report():
    ctx = _minimal_context_for_assembler()
    ctx.artifacts["global_report"] = {
        "summary": "整体评估良好",
        "recommendation": "proceed",
        "overall_score": 0.82,
        "risk_level": "low",
        "per_scope_digest": [],
    }
    out = FinalResultAssembler().assemble_final_result(ctx, iterations=[])

    gr = out.get("global_report")
    assert isinstance(gr, dict)
    assert gr["recommendation"] == "proceed"
    assert out.get("evaluation_summary_text") == "整体评估良好"


def test_assemble_final_result_evaluation_summary_text_fallback():
    """无 global_report 时 evaluation_summary_text 应为空串。"""
    ctx = _minimal_context_for_assembler()
    out = FinalResultAssembler().assemble_final_result(ctx, iterations=[])
    assert out.get("evaluation_summary_text") == ""


def test_assemble_final_result_omits_coordinator_internal_fields():
    """精简后结果不含协调内部字段。"""
    ctx = _minimal_context_for_assembler()
    out = FinalResultAssembler().assemble_final_result(ctx, iterations=[])

    for removed in (
        "timeline",
        "iteration_history",
        "key_improvements",
        "execution_summary",
        "quality_summary",
        "retry_context",
        "coordinator_workspace",
        "sub_ar_refinement_stack",
        "m2_inputs_snapshot_history",
        "m1_decomposer_debug_timeline",
        "function_tree_with_episode_meta",
        "node_evaluations",
        "normalizer_meta",
        "mode",
    ):
        assert removed not in out, f"字段 {removed!r} 应已从结果中移除"


def test_assemble_final_result_json_serializable():
    ctx = _minimal_context_for_assembler()
    out = FinalResultAssembler().assemble_final_result(ctx, iterations=[])
    json.dumps(out, default=str)
