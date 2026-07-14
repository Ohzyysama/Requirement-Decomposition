"""
上下文恢复器 — 将持久化的 final_result 重建为运行时 CoordinatorContext。

CoordinatorContext 是纯数据容器；ContextHydrator 封装所有 legacy 格式兼容与
多版本 workspace 快照重建逻辑，使数据容器不承担恢复策略。
"""
import copy
from typing import Dict, Any

from app.core.enums import TaskMode, PipelineStage
from app.services.coordinator.context import CoordinatorContext


class ContextHydrator:
    """从 DB 持久化结果重建 CoordinatorContext。"""

    @staticmethod
    def from_db_result(
        conversation_id: str,
        requirement_text: str,
        final_result: Dict[str, Any],
        config: Dict[str, Any],
    ) -> CoordinatorContext:
        """
        从持久化的 final_result 恢复上下文，供 refine-node 等续跑使用。

        处理内容：
        - 还原 artifacts（function_list / dependencies / evaluation 等核心键）
        - 兼容旧 coordinator_workspace 格式（m2_root_*_snapshot）
        - 兼容 evaluation 字段 legacy placeholder
        - 恢复 tree_version / iteration_count
        """
        ctx = CoordinatorContext(
            conversation_id=conversation_id,
            requirement_text=requirement_text,
            mode=TaskMode.AUTO,
            config=dict(config or {}),
        )

        cw = final_result.get("coordinator_workspace")
        if isinstance(cw, dict):
            ctx.workspace = copy.deepcopy(cw)

        keys = (
            # ── 拆分结果（always present in final_result） ──
            "function_list",
            "dependencies",
            "normalized_requirement",
            "decomposition_root",
            "sub_requirement_list",
            "evaluation_episodes",
            # ── 评估报告（present in final_result after 全局报告步骤） ──
            "global_report",
            # ── 以下字段可能不在 final_result 中（精简后版本），但保留 key 以兼容历史数据 ──
            "normalizer_meta",
            "evaluation",
            "io_contract",
            "node_evaluations",
            "m2_inputs_snapshot",
            "m2_inputs_snapshot_history",
            "m1_decomposer_debug_timeline",
            "decomposer_full",
            "dependency_full",
            "consistency_evaluation",
        )
        for k in keys:
            if k in final_result and final_result[k] is not None:
                ctx.artifacts[k] = copy.deepcopy(final_result[k])

        wk = ctx.workspace if isinstance(ctx.workspace, dict) else {}
        ev = ctx.artifacts.get("evaluation")
        legacy_placeholder = (
            isinstance(ev, dict)
            and ev.get("source") == "deprecated_use_evaluation_rollup"
        )
        if ev is None or legacy_placeholder:
            snap = wk.get("m2_root_evaluation_snapshot")
            if isinstance(snap, dict) and snap:
                ctx.artifacts["evaluation"] = copy.deepcopy(snap)
            cs = wk.get("m2_root_consistency_evaluation_snapshot")
            if isinstance(cs, dict) and cs:
                ctx.artifacts["consistency_evaluation"] = copy.deepcopy(cs)
            fs = wk.get("m2_root_feasibility_evaluation_snapshot")
            if isinstance(fs, dict) and fs:
                ctx.artifacts["feasibility_evaluation"] = copy.deepcopy(fs)

        tv = final_result.get("tree_version")
        if tv is not None:
            try:
                ctx.tree_version = int(tv)
            except (TypeError, ValueError):
                ctx.tree_version = 0

        ic = final_result.get("iteration_count")
        if ic is not None:
            try:
                ctx.iteration_count = int(ic)
            except (TypeError, ValueError):
                ctx.iteration_count = 0

        raw_ps = final_result.get("pipeline_stage") or final_result.get("state")
        if raw_ps is not None:
            s = str(raw_ps).strip()
            if s:
                try:
                    ctx.pipeline_stage = PipelineStage(s)
                except ValueError:
                    pass

        _spans = final_result.get("agent_spans")
        if isinstance(_spans, list):
            ctx.agent_spans = copy.deepcopy(_spans)

        return ctx
