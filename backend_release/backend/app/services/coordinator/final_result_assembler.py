"""
最终结果组装器 — 仅负责将 CoordinatorContext 组装为落库/API 的最终 JSON。

不写 context（无副作用）：调用方若需将 evaluation_rollup 持久化到 context.artifacts，
应在调用后自行写入。

Schema 边界约束：M1/M2 内部 Pydantic schema（如 ConsistencyEvaluationResult、
FeasibilityEvaluationResult 等）不得直接出现在 API 响应 dict 中。
assemble_final_result 在返回前通过 _sanitize_for_api() 做显式转换，确保任何
Pydantic 模型实例均序列化为普通 dict。
"""
import copy
from typing import Dict, Any, List, Optional
from datetime import datetime, timezone
from app.services.coordinator.context import CoordinatorContext
from app.models.conversation_iteration import ConversationIteration
from app.services.agents.function_list_bridge import function_tree_from_artifacts
from app.services.agents.M1.focus_from_normalizer import build_focus_node_from_normalizer
from app.services.coordinator.evaluation_rollup import build_evaluation_rollup
from app.services.agents.M1.dependency_trigger_zh import localize_dependency_triggers
from app.services.coordinator.tree_utils import count_tree_nodes


class FinalResultAssembler:
    """最终结果组装器（纯读 context，无副作用）。"""

    def assemble_final_result(
        self,
        context: CoordinatorContext,
        iterations: Optional[List[ConversationIteration]] = None,
        version_strategy: str = "latest",
        selected_iteration_number: Optional[int] = None,
    ) -> Dict[str, Any]:
        """
        组装最终结果并返回。不修改 context。

        version_strategy:
          - "latest"        : 使用最后一轮迭代
          - "best_by_score" : 使用 overall_score 最高的一轮
          - "specified"     : 使用 selected_iteration_number 指定的一轮
        """
        iterations = iterations or []

        selected_iter = self._select_iteration(
            iterations, version_strategy, selected_iteration_number
        )

        artifacts_source = (
            selected_iter.artifacts_snapshot
            if selected_iter and selected_iter.artifacts_snapshot
            else context.artifacts
        )

        # ── 基础运行元数据 ──
        result: Dict[str, Any] = {
            "conversation_id": context.conversation_id,
            "requirement_text": context.requirement_text,
            "pipeline_stage": context.pipeline_stage.value,
            "iteration_count": context.iteration_count,
            # tree_version 保留：ContextHydrator.from_db_result 恢复 ctx.tree_version 时读取，
            # refine-node 续跑依赖该值确认当前树版本
            "tree_version": int(getattr(context, "tree_version", 0) or 0),
            "agent_spans": copy.deepcopy(getattr(context, "agent_spans", []) or []),
            "generated_at": datetime.now(timezone.utc).isoformat(),
        }

        # ── 拆分结果 ──
        result["function_list"] = artifacts_source.get("function_list")
        result["dependencies"] = localize_dependency_triggers(
            artifacts_source.get("dependencies")
        )
        result["sub_requirement_list"] = artifacts_source.get("sub_requirement_list")

        _norm = artifacts_source.get("normalized_requirement")
        result["normalized_requirement"] = (
            copy.deepcopy(_norm) if isinstance(_norm, dict) else {}
        )

        _droot = artifacts_source.get("decomposition_root")
        if _droot is None:
            _droot = build_focus_node_from_normalizer(
                result["normalized_requirement"]
            )
        result["decomposition_root"] = copy.deepcopy(_droot)

        # ── 功能树（带评估元数据） ──
        fl = result.get("function_list")
        ft = function_tree_from_artifacts(
            {"function_list": fl} if isinstance(fl, list) else {}
        )
        ne = artifacts_source.get("node_evaluations") or {}
        result["function_tree_with_evaluation_meta"] = self._attach_evaluation_meta_to_tree(
            ft, ne
        )

        # ── 评估 episodes ──
        _eps = artifacts_source.get("evaluation_episodes")
        if not isinstance(_eps, list):
            _eps = context.artifacts.get("evaluation_episodes")
        result["evaluation_episodes"] = _eps if isinstance(_eps, list) else []

        # ── 确定性 rollup（定量汇总） ──
        tree_ver = int(getattr(context, "tree_version", 0) or 0)
        rollup = build_evaluation_rollup(
            result.get("function_list"),
            result.get("evaluation_episodes"),
            current_tree_version=tree_ver,
        )
        result["evaluation_rollup"] = rollup

        # ── 全局报告（LLM 叙事，由 Orchestrator 预生成后存入 artifacts） ──
        _gr = context.artifacts.get("global_report")
        result["global_report"] = _gr if isinstance(_gr, dict) else {}
        result["evaluation_summary_text"] = (
            result["global_report"].get("summary") or ""
        )

        # ── Schema 边界：确保 M1/M2 内部 Pydantic schema 不泄漏至 API 层 ──
        return self._sanitize_for_api(result)

    @staticmethod
    def _sanitize_for_api(value: Any) -> Any:
        """递归将所有 Pydantic BaseModel 实例序列化为普通 dict，实施 Schema 边界硬约束。"""
        try:
            from pydantic import BaseModel as PydanticBaseModel
            if isinstance(value, PydanticBaseModel):
                return value.model_dump()
        except Exception:
            pass
        if isinstance(value, dict):
            return {k: FinalResultAssembler._sanitize_for_api(v) for k, v in value.items()}
        if isinstance(value, list):
            return [FinalResultAssembler._sanitize_for_api(item) for item in value]
        return value

    @staticmethod
    def _attach_evaluation_meta_to_tree(
        tree: Any,
        node_evaluations: Optional[Dict[str, Any]],
    ) -> Any:
        """在功能树节点上挂载 node_evaluations 中对应条目的 evaluation_meta（深拷贝）。"""
        if not tree or not isinstance(tree, dict) or not node_evaluations:
            return tree
        out = copy.deepcopy(tree)

        def walk(n: Dict[str, Any]) -> None:
            nid = n.get("id")
            if nid is not None and str(nid) in node_evaluations:
                n["evaluation_meta"] = node_evaluations.get(str(nid))
            for c in n.get("children") or []:
                if isinstance(c, dict):
                    walk(c)

        walk(out)
        return out

    def _select_iteration(
        self,
        iterations: List[ConversationIteration],
        strategy: str,
        specified_number: Optional[int],
    ) -> Optional[ConversationIteration]:
        if not iterations:
            return None
        if strategy == "best_by_score":
            scored = [it for it in iterations if it.overall_score is not None]
            if scored:
                return max(scored, key=lambda it: it.overall_score)
            return iterations[-1]
        if strategy == "specified" and specified_number is not None:
            for it in iterations:
                if it.iteration_number == specified_number:
                    return it
            return iterations[-1]
        return iterations[-1]
