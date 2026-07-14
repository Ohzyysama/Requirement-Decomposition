"""
决策引擎 — 单次管线结束后汇总质量与评估说明（无外层自动重试；用户按节点重拆见 API）。
"""
from typing import Dict, Any, List

from app.schemas.coordinator import IterationDecision
from app.services.coordinator.context import CoordinatorContext

_ISSUE_LABEL_MAP: Dict[str, str] = {
    "cycle_detected": "检测到循环依赖",
    "empty_function_tree": "功能树为空",
    "empty_function_list": "功能点列表为空",
    "insufficient_nodes": "功能点数量不足",
    "excessive_depth": "功能层次过深",
    "low_confidence": "拆分结果置信度较低",
    "incomplete_structure": "结构不完整",
    "missing_fields": "缺少必要字段",
    "conflict": "存在冲突项",
    "unrealistic": "可行性存疑",
    "empty_normalized_requirement": "标准化需求为空",
    "no_constraints_identified": "未识别到关键约束",
    "no_dependencies": "未检测到依赖关系",
    "empty_dependencies_list": "依赖列表为空",
    "missing_dependency_type": "依赖缺少类型标注",
    "missing_trigger": "依赖缺少触发条件",
    "consistency_not_passed_after_inner_retries": "一致性评估内层重试后仍未通过",
}


class DecisionEngine:
    """决策引擎（仅生成摘要，不触发外层重试）"""

    async def make_iteration_decision(
        self,
        context: CoordinatorContext,
        agent_results: Dict[str, Any],
    ) -> IterationDecision:
        """汇总质量问题与人类可读说明；should_retry 恒为 False。"""
        quality_issues = self._collect_quality_issues(context, agent_results)
        return self._make_summary_decision(quality_issues)

    def _collect_quality_issues(
        self,
        context: CoordinatorContext,
        agent_results: Dict[str, Any],
    ) -> Dict[str, List[str]]:
        issues: Dict[str, List[str]] = {}

        for agent, flags in context.quality_flags.items():
            issues[agent] = list(flags)

        for agent_name, result in agent_results.items():
            if hasattr(result, "quality_flags") and result.quality_flags:
                if agent_name not in issues:
                    issues[agent_name] = []
                issues[agent_name].extend(result.quality_flags)

        return issues

    def _make_summary_decision(
        self,
        quality_issues: Dict[str, List[str]],
    ) -> IterationDecision:
        if quality_issues:
            message = self._build_issue_message(quality_issues)
        else:
            message = "管线单次执行完成，未记录额外质量问题标记。"
        return IterationDecision(
            should_retry=False,
            reason=message,
            requires_user_confirmation=False,
        )

    @staticmethod
    def _build_issue_message(quality_issues: Dict[str, List[str]]) -> str:
        descriptions: List[str] = []
        for issues in quality_issues.values():
            for issue in issues:
                label = _ISSUE_LABEL_MAP.get(issue, issue)
                if label not in descriptions:
                    descriptions.append(label)
        if not descriptions:
            return "存在质量标记，详见 quality_flags。"
        problem_text = "、".join(descriptions[:8])
        if len(descriptions) > 8:
            problem_text += f" 等 {len(descriptions)} 项"
        return (
            f"质量摘要：{problem_text}。"
            "可使用 refine-node 对指定节点补充拆分。"
        )
