"""
SSE 载荷工厂 — 专门生成所有 SSE 中间推送载荷。

所有方法均为纯函数语义（只读 context / 传入数据），不修改任何共享状态。
"""
import copy
from typing import Dict, Any, List, Optional
from app.services.coordinator.context import CoordinatorContext
from app.services.coordinator.tree_utils import (
    count_tree_nodes,
    calc_tree_depth,
    count_leaf_nodes,
    build_tree_preview_str,
)
from app.services.agents.M1.dependency_trigger_zh import localize_dependency_triggers


def derive_suggested_conversation_title(
    norm_dict: Dict[str, Any],
    max_len: int = 50,
) -> str:
    """由标准化产物生成会话标题：优先 goal.primary_goal，否则 normalized_requirement 主句截断。"""
    goal = norm_dict.get("goal")
    primary = ""
    if isinstance(goal, dict):
        primary = (goal.get("primary_goal") or "").strip()
    if primary:
        return primary[:max_len]
    nr = norm_dict.get("normalized_requirement") or ""
    if isinstance(nr, dict):
        nr = nr.get("normalized_requirement") or ""
    s = str(nr).strip()
    return s[:max_len] if s else ""


class SsePayloadFactory:
    """生成 SSE 中间结果载荷的工厂类（无副作用）。"""

    def assemble_normalizer_preview(
        self,
        normalized: Any,
        stage: str = "需求标准化",
    ) -> Dict[str, Any]:
        """Normalizer 完成后推送。"""
        norm_dict = normalized if isinstance(normalized, dict) else {}
        nr = norm_dict.get("normalized_requirement") or ""
        if isinstance(nr, dict):
            nr = nr.get("normalized_requirement") or ""
        snippet = (str(nr)[:120] + "…") if len(str(nr)) > 120 else str(nr)
        summary = "需求标准化完成" if nr else "需求标准化（空）"
        if snippet:
            summary = f"{summary}：{snippet}"
        suggested_title = derive_suggested_conversation_title(norm_dict)
        return {
            "stage": stage,
            "content_type": "normalizer_preview",
            "data": {
                "normalized_requirement": copy.deepcopy(norm_dict),
                "summary": summary,
                "suggested_conversation_title": suggested_title,
            },
        }

    def assemble_m2_agent_complete(
        self,
        agent_name: str,
        context: CoordinatorContext,
        *,
        result_payload: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        """M2 单步（一致性 / 可实现性 / 集成）完成时的 SSE 载荷。

        result_payload: 本次评估的实际结果字典。子 AR 作用域评估时（write_to_artifacts=False）
        context.artifacts 仍保留根层旧值，必须通过此参数透传当前作用域的评估结果；
        为 None 时 fallback 到 context.artifacts（根层路径向后兼容）。
        """
        m2_scope = context.artifacts.get("m2_scope")
        pipe = getattr(context, "pipeline_stage", "") or ""
        if agent_name == "evaluation_integrator":
            pipe = "integration"
        data: Dict[str, Any] = {
            "agent": agent_name,
            "pipeline_stage": pipe,
        }
        if isinstance(m2_scope, dict) and m2_scope.get("scope_root_node_id"):
            data["m2_scope"] = copy.deepcopy(m2_scope)

        if agent_name == "consistency_evaluator":
            ce = result_payload if result_payload is not None \
                else (context.artifacts.get("consistency_evaluation") or {})
            if isinstance(ce, dict):
                crit = ce.get("critical_issues") or []
                data["consistency_evaluation"] = copy.deepcopy(ce)
                data["summary"] = {
                    "score": ce.get("score"),
                    "critical_issues_count": len(crit) if isinstance(crit, list) else 0,
                }
        elif agent_name == "feasibility_evaluator":
            fe = result_payload if result_payload is not None \
                else (context.artifacts.get("feasibility_evaluation") or {})
            if isinstance(fe, dict):
                data["feasibility_evaluation"] = copy.deepcopy(fe)
                rr = fe.get("rule_results") or []
                ci = fe.get("critical_issues") or []
                data["summary"] = {
                    "rule_results_count": len(rr) if isinstance(rr, list) else 0,
                    "critical_issues_count": len(ci) if isinstance(ci, list) else 0,
                }
        elif agent_name == "evaluation_integrator":
            ev = result_payload if result_payload is not None \
                else (context.artifacts.get("evaluation") or {})
            if isinstance(ev, dict):
                data["evaluation"] = copy.deepcopy(ev)
                data["summary"] = {
                    "overall_score": ev.get("overall_score"),
                }

        return {
            "stage": "模块二评估",
            "content_type": "m2_agent_complete",
            "data": data,
        }

    def assemble_function_tree_preview(
        self,
        function_tree: Any,
        stage: str = "功能拆分",
    ) -> Dict[str, Any]:
        """从功能树生成简化预览，用于 SSE 中间结果推送。"""
        if not function_tree:
            return {
                "stage": stage,
                "content_type": "function_tree_preview",
                "data": {
                    "total_nodes": 0,
                    "max_depth": 0,
                    "leaf_nodes": 0,
                    "preview": "",
                    "summary": "功能树为空",
                    "function_tree": {},
                },
            }

        total_nodes = count_tree_nodes(function_tree)
        max_depth = calc_tree_depth(function_tree)
        leaf_nodes = count_leaf_nodes(function_tree)
        preview = build_tree_preview_str(function_tree, max_items=None)

        root_title = ""
        if isinstance(function_tree, dict):
            root_title = (function_tree.get("title") or "").strip()
        summary = f"功能树共 {total_nodes} 个节点、{leaf_nodes} 个叶子，最大深度 {max_depth}"
        if root_title:
            summary = f"{root_title}：{summary}"

        return {
            "stage": stage,
            "content_type": "function_tree_preview",
            "data": {
                "total_nodes": total_nodes,
                "max_depth": max_depth,
                "leaf_nodes": leaf_nodes,
                "preview": preview,
                "summary": summary,
                "function_tree": copy.deepcopy(function_tree),
            },
        }

    def assemble_dependencies_preview(
        self,
        dependencies: Any,
        stage: str = "依赖分析",
    ) -> Dict[str, Any]:
        """从依赖集合生成简化预览，用于 SSE 中间结果推送。"""
        if not dependencies:
            return {
                "stage": stage,
                "content_type": "dependencies_preview",
                "data": {
                    "total_dependencies": 0,
                    "by_type": {},
                    "preview": "",
                    "dependencies": [],
                },
            }

        deps_list = (
            dependencies
            if isinstance(dependencies, list)
            else (dependencies.get("dependencies") or [])
        )
        if not isinstance(deps_list, list):
            deps_list = []

        by_type: Dict[str, int] = {}
        for dep in deps_list:
            if isinstance(dep, dict):
                t = dep.get("dependency_type") or dep.get("dependencyType") or "UNKNOWN"
                by_type[t] = by_type.get(t, 0) + 1

        preview_parts = []
        for dep in deps_list:
            if isinstance(dep, dict):
                f = dep.get("from") or dep.get("from_", "")
                t = dep.get("to", "")
                desc = dep.get("description", "")
                if f and t:
                    preview_parts.append(f"{f} → {t}: {desc}")
        preview = "; ".join(preview_parts) if preview_parts else f"共 {len(deps_list)} 条依赖"

        return {
            "stage": stage,
            "content_type": "dependencies_preview",
            "data": {
                "total_dependencies": len(deps_list),
                "by_type": by_type,
                "preview": preview,
                "dependencies": localize_dependency_triggers(deps_list),
            },
        }

    def assemble_function_tree_dependencies_bundle(
        self,
        function_tree: Any,
        dependencies: Any,
        *,
        tree_stage: str = "功能拆分",
        dependency_stage: str = "依赖分析",
    ) -> Dict[str, Any]:
        """依赖分析完成后的组合快照：同一 intermediate_result 内含功能树与依赖（依赖可为空）。"""
        tree_payload = self.assemble_function_tree_preview(
            function_tree, stage=tree_stage
        )
        deps_payload = self.assemble_dependencies_preview(
            dependencies, stage=dependency_stage
        )
        return {
            "stage": "功能树与依赖",
            "content_type": "function_tree_dependencies_bundle",
            "data": {
                "tree": tree_payload["data"],
                "dependencies": deps_payload["data"],
            },
        }

    def assemble_sub_requirement_list_preview(
        self,
        sub_list: Any,
        stage: str = "子需求列表",
        max_items: Optional[int] = None,
    ) -> Dict[str, Any]:
        """列表阶段预览（一致性优先管线），供 SSE intermediate_result 推送。"""
        items = sub_list if isinstance(sub_list, list) else []
        cap: Optional[int] = max_items
        slice_items = items if cap is None else items[:cap]
        preview_lines: List[str] = []
        for it in slice_items:
            if not isinstance(it, dict):
                continue
            tid = it.get("id") or ""
            title = (it.get("title") or "").strip()
            line = f"{tid}: {title}" if tid else title
            if line:
                preview_lines.append(line)
        more = ""
        if cap is not None and len(items) > cap:
            more = f"\n… 共 {len(items)} 项"
        preview = "\n".join(preview_lines) + more

        return {
            "stage": stage,
            "content_type": "sub_requirement_list_preview",
            "data": {
                "total_items": len(items),
                "preview": preview,
                "sub_requirement_list": copy.deepcopy(items),
            },
        }

    def assemble_pipeline_status_intermediate(
        self,
        context: CoordinatorContext,
        current_stage: str,
        description: Optional[str] = None,
    ) -> Dict[str, Any]:
        """管线状态 SSE：与其它 intermediate_result 一致的信封。"""
        pv = float(context.progress)
        st = context.pipeline_stage.value
        data: Dict[str, Any] = {
            "conversation_id": context.conversation_id,
            "pipeline_stage": st,
            "overall_progress": pv,
            "quality_flags": context.quality_flags,
            "iteration_count": context.iteration_count,
            "description": description or "",
            "tree_version": getattr(context, "tree_version", 0),
        }
        return {
            "stage": "管线状态",
            "content_type": "pipeline_status",
            "data": data,
        }
