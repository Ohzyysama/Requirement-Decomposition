"""
M2一致性评估智能体
负责执行一致性规则检查，采用混合评估模式：
规则引擎评估（硬编码）：
1. 依赖引用有效性
2. 循环依赖检测
3. 重复功能检测
4. 耦合度评估
5. 依赖继承合理性

LLM语义评估：
6. 子需求覆盖完整性
7. 拆分忠实性
8. 功能范围约束
"""
import asyncio
import logging
from typing import Dict, Any, List, Set, Optional
from collections import defaultdict, deque
import re
from difflib import SequenceMatcher
import json

from app.services.agents.M2.m2_base_agent import M2BaseAgent
from app.schemas.agent import AgentInput, BaseAgentOutput
from app.services.agents.M2.schemas.m2_consistency import (
    ConsistencyCheckResponse, ConsistencyEvaluationResult, RuleCheckResult
)
from app.schemas.evaluation import (
    RuleSeverity,
    RuleCategory,
    IssueType,
    PerChildRefinementHint,
    LLMSemanticAssessmentItem,
    LLMSemanticAssessmentResult,
)
from pydantic import BaseModel, Field

logger = logging.getLogger(__name__)


class M2ConsistencyEvaluatorAgent(M2BaseAgent):
    """M2一致性评估智能体（混合评估模式）"""

    def __init__(self):
        super().__init__(
            name="M2-ConsistencyEvaluator",
            description="一致性评估智能体，采用规则引擎+LLM混合模式检查功能列表和依赖关系的一致性",
            system_prompt="""你是一个专业的一致性评估专家，负责对软件需求的功能拆分结果进行语义一致性检查。

            你的任务是执行以下需要语义分析的检查项：
            1. 子需求覆盖完整性 - 确保子需求完全涵盖原始需求的所有内容
            2. 拆分忠实性 - 子需求的拆分必须忠实于原始需求文本，不得出现原始需求中未提及的功能或名词。
            3. 功能范围约束 - 子需求不得超出原始需求的功能范围
            
            对于每个检查项，你需要：
            - 基于原始需求文本和子功能描述进行语义分析
            - 明确说明是否通过检查，如果未通过则详细描述问题
            - 提供具体的建议动作和受影响的功能节点
            - 给出置信度评估
            
            请基于语义理解进行分析，提供准确、可操作的评估结果。"""
        )

    async def execute(self, input_data: AgentInput) -> BaseAgentOutput:
        """执行一致性评估（混合评估模式）"""
        try:
            art = input_data.artifacts or {}
            function_list = art.get("function_list", []) if isinstance(art, dict) else []
            dependencies = art.get("dependencies", []) if isinstance(art, dict) else []
            normalizer_result = art.get("normalizer_result", {}) if isinstance(art, dict) else {}
            requirement_text = normalizer_result.get("normalized_requirement", "") if isinstance(normalizer_result, dict) else ""

            logger.info(f"[{input_data.task_id}] 开始一致性评估（混合模式）")

            # 执行规则引擎评估
            rule_engine_results = await self._execute_rule_engine_checks(
                function_list, dependencies, normalizer_result
            )

            # 执行LLM语义评估
            llm_results = await self._execute_llm_semantic_checks(
                input_data
            )

            # 合并评估结果
            rule_results = rule_engine_results + llm_results

            # 构建评估结果
            evaluation_result = self._build_evaluation_result(rule_results)

            response = ConsistencyCheckResponse(
                result=evaluation_result,
                check_details={"rule_count": len(rule_results)},
                rule_engine_results={
                    "rule_count": len(rule_engine_results),
                    "passed_count": sum(1 for r in rule_engine_results if r.passed)
                },
                llm_assessment_results={
                    "rule_count": len(llm_results),
                    "passed_count": sum(1 for r in llm_results if r.passed)
                }
            )

            return BaseAgentOutput(
                result=response.model_dump(),
                quality_flags=self._extract_quality_flags(evaluation_result),
                warnings=self._extract_warnings(evaluation_result),
                evidence=self._extract_evidence(evaluation_result)
            )

        except Exception as e:
            logger.error(f"一致性评估失败: {str(e)}", exc_info=True)
            return BaseAgentOutput(
                result={},
                quality_flags=["execution_error"],
                warnings=[f"一致性评估执行失败: {str(e)}"]
            )

    async def _execute_rule_engine_checks(
        self,
        function_list: List[Dict[str, Any]],
        dependencies: List[Dict[str, Any]],
        normalizer_result: Dict[str, Any]
    ) -> List[RuleCheckResult]:
        """执行规则引擎评估（硬编码）"""
        rule_results = []

        # 1. 依赖引用有效性检查
        rule_results.append(self._check_dependency_references(function_list, dependencies))

        # 2. 循环依赖检测
        rule_results.append(self._check_circular_dependencies(dependencies))

        # 3. 重复功能检测
        rule_results.append(self._check_duplicate_functions(function_list))

        # 4. 耦合度评估
        rule_results.append(self._check_coupling_degree(function_list, dependencies))

        # 5. 依赖继承合理性检查
        rule_results.append(self._check_dependency_inheritance(function_list, normalizer_result))

        return rule_results

    async def _execute_llm_semantic_checks(
        self,
        input_data: AgentInput
    ) -> List[RuleCheckResult]:
        """执行LLM语义评估"""
        try:

            # 调用LLM进行语义评估
            llm_result = await self._call_llm_with_schema(
                llm_model=(input_data.config or {}).get("model") or "qwen3-max",
                messages=self._build_consistency_LLM_messages(input_data),
                response_model=LLMSemanticAssessmentResult
            )

            # 转换LLM结果为RuleCheckResult格式
            return self._convert_llm_result_to_rule_results(llm_result)

        except Exception as e:
            logger.error(f"LLM语义评估失败: {str(e)}", exc_info=True)
            # 返回默认的失败结果
            return [
                RuleCheckResult(
                    rule_id="llm_semantic_error",
                    rule_name="LLM语义评估",
                    category=RuleCategory.CONSISTENCY,
                    severity=RuleSeverity.ERROR,
                    issue_type=IssueType.INCOMPLETE_SUBREQUIREMENT_COVERAGE,
                    description=f"LLM语义评估执行失败: {str(e)}",
                    affected_nodes=[],
                    affected_dependencies=[],
                    recommendation="检查LLM服务是否正常",
                    evidence={"error": str(e)},
                    passed=False
                )
            ]

    def _build_consistency_LLM_messages(self, input_data: AgentInput) -> list:
        """构建LLM消息"""
        # 从input_data中提取所需信息
        art = input_data.artifacts or {}
        function_list = art.get("function_list", []) if isinstance(art, dict) else []
        normalizer_result = art.get("normalizer_result", {}) if isinstance(art, dict) else {}
        requirement_text = normalizer_result.get("normalized_requirement", "") if isinstance(normalizer_result,dict) else ""

        user_content = f"""
        标准化原需求文本：
        {requirement_text}
        
        功能列表：
        {function_list}
        
        请对上述功能拆分结果进行语义一致性评估。"""

        return [
            {"role": "system", "content": self.system_prompt},
            {"role": "user", "content": user_content}
        ]

    def _convert_llm_result_to_rule_results(self, llm_result: LLMSemanticAssessmentResult) -> List[RuleCheckResult]:
        """将LLM语义评估结果转换为RuleCheckResult格式"""
        rule_results = []

        # 子需求覆盖完整性
        coverage_item = llm_result.subrequirement_coverage
        rule_results.append(RuleCheckResult(
            rule_id="consistency_006",
            rule_name="子需求覆盖完整性",
            category=RuleCategory.CONSISTENCY,
            severity=RuleSeverity.ERROR if not coverage_item.passed else RuleSeverity.INFO,
            issue_type=IssueType.INCOMPLETE_SUBREQUIREMENT_COVERAGE,
            description=coverage_item.description,
            affected_nodes=coverage_item.affected_nodes,
            affected_dependencies=[],
            recommendation=coverage_item.recommendation,
            evidence={"confidence": coverage_item.confidence},
            passed=coverage_item.passed
        ))

        # 拆分忠实性
        faithfulness_item = llm_result.split_faithfulness
        rule_results.append(RuleCheckResult(
            rule_id="consistency_007",
            rule_name="拆分忠实性",
            category=RuleCategory.CONSISTENCY,
            severity=RuleSeverity.WARNING if not faithfulness_item.passed else RuleSeverity.INFO,
            issue_type=IssueType.UNFAITHFUL_SPLIT,
            description=faithfulness_item.description,
            affected_nodes=faithfulness_item.affected_nodes,
            affected_dependencies=[],
            recommendation=faithfulness_item.recommendation,
            evidence={"confidence": faithfulness_item.confidence},
            passed=faithfulness_item.passed
        ))

        # 功能范围约束
        scope_item = llm_result.scope_constraint
        rule_results.append(RuleCheckResult(
            rule_id="consistency_008",
            rule_name="功能范围约束",
            category=RuleCategory.CONSISTENCY,
            severity=RuleSeverity.ERROR if not scope_item.passed else RuleSeverity.INFO,
            issue_type=IssueType.SCOPE_EXCEEDED,
            description=scope_item.description,
            affected_nodes=scope_item.affected_nodes,
            affected_dependencies=[],
            recommendation=scope_item.recommendation,
            evidence={"confidence": scope_item.confidence},
            passed=scope_item.passed
        ))

        return rule_results

    def _check_dependency_references(self, function_list: List[Dict[str, Any]], dependencies: List[Dict[str, Any]]) -> RuleCheckResult:
        """检查依赖引用有效性（规则引擎）"""
        try:
            # 收集所有有效的节点ID
            valid_ids = {func.get("id") for func in function_list if func.get("id")}

            invalid_references = []
            for dep in dependencies:
                from_node = dep.get("from")
                to_node = dep.get("to")

                if from_node and from_node not in valid_ids:
                    invalid_references.append(f"from: {from_node}")
                if to_node and to_node not in valid_ids:
                    invalid_references.append(f"to: {to_node}")

            if invalid_references:
                return RuleCheckResult(
                    rule_id="consistency_001",
                    rule_name="依赖引用有效性",
                    category=RuleCategory.CONSISTENCY,
                    severity=RuleSeverity.ERROR,
                    issue_type=IssueType.INVALID_DEPENDENCY_REFERENCE,
                    description=f"发现无效的依赖引用: {', '.join(invalid_references)}",
                    affected_nodes=list(set([ref.split(": ")[1] for ref in invalid_references])),
                    affected_dependencies=[dep.get("dep_id") for dep in dependencies if any(ref in str(dep) for ref in invalid_references)],
                    recommendation="中断流程，重新进行依赖识别",
                    evidence={"invalid_references": invalid_references},
                    passed=False
                )
            else:
                return RuleCheckResult(
                    rule_id="consistency_001",
                    rule_name="依赖引用有效性",
                    category=RuleCategory.CONSISTENCY,
                    severity=RuleSeverity.INFO,
                    issue_type=IssueType.INVALID_DEPENDENCY_REFERENCE,
                    description="所有依赖引用均有效",
                    affected_nodes=[],
                    affected_dependencies=[],
                    recommendation="无需动作",
                    evidence={},
                    passed=True
                )

        except Exception as e:
            return RuleCheckResult(
                rule_id="consistency_001",
                rule_name="依赖引用有效性",
                category=RuleCategory.CONSISTENCY,
                severity=RuleSeverity.ERROR,
                issue_type=IssueType.INVALID_DEPENDENCY_REFERENCE,
                description=f"检查依赖引用有效性时发生错误: {str(e)}",
                affected_nodes=[],
                affected_dependencies=[],
                recommendation="检查依赖关系结构是否正确",
                evidence={"error": str(e)},
                passed=False
            )

    def _check_circular_dependencies(self, dependencies: List[Dict[str, Any]]) -> RuleCheckResult:
        """检查循环依赖（规则引擎）"""
        try:
            # 构建依赖图
            graph = defaultdict(list)
            for dep in dependencies:
                from_node = dep.get("from")
                to_node = dep.get("to")
                if from_node and to_node:
                    graph[from_node].append(to_node)

            # DFS检测循环
            visited = set()
            rec_stack = set()
            cycles = []

            def dfs(node, path):
                if node in rec_stack:
                    cycles.append(path + [node])
                    return
                if node in visited:
                    return

                visited.add(node)
                rec_stack.add(node)

                for neighbor in graph.get(node, []):
                    dfs(neighbor, path + [node])

                rec_stack.remove(node)

            for node in graph:
                if node not in visited:
                    dfs(node, [])

            if cycles:
                cycle_strs = [" -> ".join(cycle) for cycle in cycles]
                return RuleCheckResult(
                    rule_id="consistency_002",
                    rule_name="循环依赖检测",
                    category=RuleCategory.CONSISTENCY,
                    severity=RuleSeverity.WARNING,
                    issue_type=IssueType.CIRCULAR_DEPENDENCY,
                    description=f"发现循环依赖: {'; '.join(cycle_strs)}",
                    affected_nodes=list(set([node for cycle in cycles for node in cycle])),
                    affected_dependencies=[],
                    recommendation="标记问题，建议重构依赖关系",
                    evidence={"cycles": cycles},
                    passed=False
                )
            else:
                return RuleCheckResult(
                    rule_id="consistency_002",
                    rule_name="循环依赖检测",
                    category=RuleCategory.CONSISTENCY,
                    severity=RuleSeverity.INFO,
                    issue_type=IssueType.CIRCULAR_DEPENDENCY,
                    description="未发现循环依赖",
                    affected_nodes=[],
                    affected_dependencies=[],
                    recommendation="无需动作",
                    evidence={},
                    passed=True
                )

        except Exception as e:
            return RuleCheckResult(
                rule_id="consistency_002",
                rule_name="循环依赖检测",
                category=RuleCategory.CONSISTENCY,
                severity=RuleSeverity.ERROR,
                issue_type=IssueType.CIRCULAR_DEPENDENCY,
                description=f"检查循环依赖时发生错误: {str(e)}",
                affected_nodes=[],
                affected_dependencies=[],
                recommendation="检查依赖关系结构是否正确",
                evidence={"error": str(e)},
                passed=False
            )

    def _check_duplicate_functions(self, function_list: List[Dict[str, Any]]) -> RuleCheckResult:
        """检查重复功能（规则引擎）"""
        try:
            # 基于文本相似度检测重复功能
            duplicates = []
            threshold = 0.8  # 相似度阈值

            for i, func1 in enumerate(function_list):
                desc1 = func1.get("desc", "") + " " + func1.get("title", "")
                for j, func2 in enumerate(function_list[i+1:], i+1):
                    desc2 = func2.get("desc", "") + " " + func2.get("title", "")
                    similarity = SequenceMatcher(None, desc1.lower(), desc2.lower()).ratio()

                    if similarity >= threshold:
                        duplicates.append({
                            "func1": func1.get("id"),
                            "func2": func2.get("id"),
                            "similarity": similarity,
                            "description": f"功能 {func1.get('id')} 和 {func2.get('id')} 相似度 {similarity:.2f}"
                        })

            if duplicates:
                dup_descriptions = [d["description"] for d in duplicates]
                return RuleCheckResult(
                    rule_id="consistency_003",
                    rule_name="重复功能检测",
                    category=RuleCategory.CONSISTENCY,
                    severity=RuleSeverity.WARNING,
                    issue_type=IssueType.DUPLICATE_FUNCTION,
                    description=f"发现重复功能: {', '.join(dup_descriptions)}",
                    affected_nodes=list(set([d["func1"] for d in duplicates] + [d["func2"] for d in duplicates])),
                    affected_dependencies=[],
                    recommendation="标记重复，建议合并或删除",
                    evidence={"duplicates": duplicates},
                    passed=False
                )
            else:
                return RuleCheckResult(
                    rule_id="consistency_003",
                    rule_name="重复功能检测",
                    category=RuleCategory.CONSISTENCY,
                    severity=RuleSeverity.INFO,
                    issue_type=IssueType.DUPLICATE_FUNCTION,
                    description="未发现重复功能",
                    affected_nodes=[],
                    affected_dependencies=[],
                    recommendation="无需动作",
                    evidence={},
                    passed=True
                )

        except Exception as e:
            return RuleCheckResult(
                rule_id="consistency_003",
                rule_name="重复功能检测",
                category=RuleCategory.CONSISTENCY,
                severity=RuleSeverity.ERROR,
                issue_type=IssueType.DUPLICATE_FUNCTION,
                description=f"检查重复功能时发生错误: {str(e)}",
                affected_nodes=[],
                affected_dependencies=[],
                recommendation="检查功能列表结构是否正确",
                evidence={"error": str(e)},
                passed=False
            )

    def _check_coupling_degree(self, function_list: List[Dict[str, Any]], dependencies: List[Dict[str, Any]]) -> RuleCheckResult:
        """检查耦合度（规则引擎）"""
        try:
            # 统计每个功能的依赖数量
            dep_count = defaultdict(int)
            for dep in dependencies:
                from_node = dep.get("from")
                to_node = dep.get("to")
                if from_node:
                    dep_count[from_node] += 1
                if to_node:
                    dep_count[to_node] += 1

            # 评估耦合度
            high_coupling_nodes = []
            for func_id, count in dep_count.items():
                if count >= 5:  # 阈值：5个以上依赖为高耦合
                    high_coupling_nodes.append({
                        "func_id": func_id,
                        "dependency_count": count
                    })

            if high_coupling_nodes:
                node_descriptions = [f"{n['func_id']}({n['dependency_count']}个依赖)" for n in high_coupling_nodes]
                return RuleCheckResult(
                    rule_id="consistency_004",
                    rule_name="耦合度评估",
                    category=RuleCategory.CONSISTENCY,
                    severity=RuleSeverity.WARNING,
                    issue_type=IssueType.HIGH_COUPLING,
                    description=f"发现高耦合功能: {', '.join(node_descriptions)}",
                    affected_nodes=[n["func_id"] for n in high_coupling_nodes],
                    affected_dependencies=[],
                    recommendation="高耦合功能建议重新设计依赖关系",
                    evidence={"high_coupling_nodes": high_coupling_nodes},
                    passed=False
                )
            else:
                return RuleCheckResult(
                    rule_id="consistency_004",
                    rule_name="耦合度评估",
                    category=RuleCategory.CONSISTENCY,
                    severity=RuleSeverity.INFO,
                    issue_type=IssueType.HIGH_COUPLING,
                    description="所有功能耦合度均在合理范围内",
                    affected_nodes=[],
                    affected_dependencies=[],
                    recommendation="无需动作",
                    evidence={},
                    passed=True
                )

        except Exception as e:
            return RuleCheckResult(
                rule_id="consistency_004",
                rule_name="耦合度评估",
                category=RuleCategory.CONSISTENCY,
                severity=RuleSeverity.ERROR,
                issue_type=IssueType.HIGH_COUPLING,
                description=f"检查耦合度时发生错误: {str(e)}",
                affected_nodes=[],
                affected_dependencies=[],
                recommendation="检查依赖关系结构是否正确",
                evidence={"error": str(e)},
                passed=False
            )

    def _check_dependency_inheritance(self, function_list: List[Dict[str, Any]], normalizer_result: Dict[str, Any]) -> RuleCheckResult:
        """检查依赖继承合理性（规则引擎）"""
        try:
            # 获取原始需求的约束
            original_constraints = normalizer_result.get("constraints_copy", [])
            if not isinstance(original_constraints, list):
                original_constraints = []

            # 检查功能列表中的约束是否在原始约束中
            invalid_inheritance = []
            for func in function_list:
                func_constraints = func.get("constraints", [])
                if not isinstance(func_constraints, list):
                    continue

                for constraint in func_constraints:
                    if constraint not in original_constraints:
                        invalid_inheritance.append({
                            "func_id": func.get("id"),
                            "constraint": constraint
                        })

            if invalid_inheritance:
                invalid_descriptions = [f"功能 {item['func_id']} 的约束 {item['constraint']}" for item in invalid_inheritance]
                return RuleCheckResult(
                    rule_id="consistency_005",
                    rule_name="依赖继承合理性",
                    category=RuleCategory.CONSISTENCY,
                    severity=RuleSeverity.WARNING,
                    issue_type=IssueType.INVALID_DEPENDENCY_INHERITANCE,
                    description=f"发现无效的约束继承: {', '.join(invalid_descriptions)}",
                    affected_nodes=[item["func_id"] for item in invalid_inheritance],
                    affected_dependencies=[],
                    recommendation="调整依赖关系，确保合理继承",
                    evidence={"invalid_inheritance": invalid_inheritance},
                    passed=False
                )
            else:
                return RuleCheckResult(
                    rule_id="consistency_005",
                    rule_name="依赖继承合理性",
                    category=RuleCategory.CONSISTENCY,
                    severity=RuleSeverity.INFO,
                    issue_type=IssueType.INVALID_DEPENDENCY_INHERITANCE,
                    description="所有约束继承均合理",
                    affected_nodes=[],
                    affected_dependencies=[],
                    recommendation="无需动作",
                    evidence={},
                    passed=True
                )

        except Exception as e:
            return RuleCheckResult(
                rule_id="consistency_005",
                rule_name="依赖继承合理性",
                category=RuleCategory.CONSISTENCY,
                severity=RuleSeverity.ERROR,
                issue_type=IssueType.INVALID_DEPENDENCY_INHERITANCE,
                description=f"检查依赖继承合理性时发生错误: {str(e)}",
                affected_nodes=[],
                affected_dependencies=[],
                recommendation="检查约束结构是否正确",
                evidence={"error": str(e)},
                passed=False
            )

    def _build_evaluation_result(self, rule_results: List[RuleCheckResult]) -> ConsistencyEvaluationResult:
        """构建一致性评估结果"""
        total_checks = len(rule_results)
        passed_checks = sum(1 for r in rule_results if r.passed)
        failed_checks = total_checks - passed_checks

        # 计算基础评分（通过检查项数 / 总检查项数）
        base_score = passed_checks / total_checks if total_checks > 0 else 0.0

        # 关键问题扣分：每个ERROR级别问题额外扣分
        critical_issues = [r for r in rule_results if not r.passed and r.severity == RuleSeverity.ERROR]
        penalty = len(critical_issues) * 0.1

        # 最终评分 = 基础评分 - 关键问题扣分
        score = max(0.0, base_score - penalty)
        score = min(1.0, score)  # 限制在0-1范围内

        # 分离关键问题和警告
        warnings = [r for r in rule_results if not r.passed and r.severity == RuleSeverity.WARNING]

        # 生成修复建议
        remediation_instruction = None
        if critical_issues:
            remediation_instruction = "存在关键一致性问题，建议重新进行功能拆分或依赖识别"
        elif warnings:
            remediation_instruction = "存在一致性警告，建议优化功能设计"

        return ConsistencyEvaluationResult(
            score=score,
            total_checks=total_checks,
            passed_checks=passed_checks,
            failed_checks=failed_checks,
            rule_results=rule_results,
            critical_issues=critical_issues,
            warnings=warnings,
            remediation_instruction=remediation_instruction,
            per_child=[]  #TODO 暂时为空，可根据需要扩展
        )

    def _extract_quality_flags(self, evaluation_result: ConsistencyEvaluationResult) -> List[str]:
        """提取质量标记"""
        flags = []
        
        if evaluation_result.score < 0.7:
            flags.append("low_consistency_score")
        
        if len(evaluation_result.critical_issues) > 0:
            flags.append("critical_consistency_issues")
        
        if len(evaluation_result.warnings) > 3:
            flags.append("many_consistency_warnings")
            
        return flags

    def _extract_warnings(self, evaluation_result: ConsistencyEvaluationResult) -> List[str]:
        """提取警告信息"""
        warnings = []
        
        for issue in evaluation_result.critical_issues:
            warnings.append(f"关键一致性问题: {issue.description}")
        
        for warning in evaluation_result.warnings:
            warnings.append(f"一致性警告: {warning.description}")
            
        return warnings

    def _extract_evidence(self, evaluation_result: ConsistencyEvaluationResult) -> List[str]:
        """提取证据信息"""
        evidence = []
        
        for result in evaluation_result.rule_results:
            if not result.passed and result.evidence:
                evidence.append(f"{result.rule_name}: {str(result.evidence)}")
                
        return evidence