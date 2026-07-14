"""
M2综合评估集成智能体
负责整合一致性评估和可实现性评估的结果，
应用评分算法生成综合评估报告和决策支持。
"""
import logging
from typing import Dict, Any, List
from datetime import datetime

from app.services.agents.M2.m2_base_agent import M2BaseAgent
from app.schemas.agent import AgentInput, BaseAgentOutput
from app.services.agents.M2.schemas.m2_integrator import (
    IntegrationResponse
)
from app.schemas.evaluation import (
    ConsistencyEvaluationResult, FeasibilityEvaluationResult,
    IntegratedEvaluationResult, RuleCheckResult,LLMIntegrationAnalysisResult
)

logger = logging.getLogger(__name__)


class M2EvaluationIntegratorAgent(M2BaseAgent):
    """M2综合评估集成智能体"""

    def __init__(self):
        super().__init__(
            name="M2-EvaluationIntegrator",
            description="综合评估集成智能体，整合一致性和可实现性评估结果",
            system_prompt="""你是一个专业的软件项目评估专家，负责整合一致性评估和可实现性评估的结果。
            
            你的任务是：
            1. 综合分析一致性评估结果（基于8个一致性规则）
            2. 综合分析可实现性评估结果（包含FPA功能点分析）
            3. 应用评分算法生成综合评估报告
            4. 提供数据驱动的决策支持（继续/修订/终止）
            
            请基于评估数据提供客观、准确、可操作的综合评估报告。"""
        )

    async def execute(self, input_data: AgentInput) -> BaseAgentOutput:
        """执行综合评估集成"""
        try:
            consistency_result = input_data.artifacts.get("consistency_result", {})
            feasibility_result = input_data.artifacts.get("feasibility_result", {})
            feasibility_skipped = bool(input_data.artifacts.get("feasibility_evaluation_skipped"))

            logger.info(f"[{input_data.task_id}] 开始综合评估集成")

            # 使用LLM生成智能建议和总结
            recommendation, summary = await self._generate_llm_based_analysis(
                consistency_result, feasibility_result, input_data
            )

            integrated_result = self._build_integrated_result(
                consistency_result,
                feasibility_result,
                feasibility_skipped=feasibility_skipped,
                recommendation=recommendation,
                summary=summary
            )

            response = IntegrationResponse(
                result=integrated_result,
                integration_details={
                    "integration_timestamp": datetime.now().isoformat(),
                },
                scoring_details={
                    "consistency_algorithm": "规则引擎+LLM混合评估",
                    "feasibility_algorithm": "FPA功能点分析+资源约束匹配",
                    "overall_algorithm": "一致性×0.4 + 可实现性×0.6",
                }
            )

            return BaseAgentOutput(
                result=response.model_dump(),
                quality_flags=self._extract_quality_flags(integrated_result),
                warnings=self._extract_warnings(integrated_result),
                evidence=self._extract_evidence(integrated_result)
            )

        except Exception as e:
            logger.error(f"综合评估集成失败: {str(e)}", exc_info=True)
            return BaseAgentOutput(
                result={},
                quality_flags=["integration_error"],
                warnings=[f"综合评估集成执行失败: {str(e)}"]
            )

    def _build_integrated_result(
        self,
        consistency_result: Dict[str, Any],
        feasibility_result: Dict[str, Any],
        *,
        feasibility_skipped: bool = False,
        recommendation: str = None,
        summary: str = None
    ) -> IntegratedEvaluationResult:
        """构建综合评估结果"""

        # 计算各项评分
        consistency_score = self._calculate_consistency_score(consistency_result)
        feasibility_score = self._calculate_feasibility_score(feasibility_result)
        overall_score = self._calculate_overall_score(consistency_score, feasibility_score)

        # 如果没有LLM生成的结果，使用默认方法
        if not recommendation:
            recommendation = self._determine_recommendation(overall_score, consistency_result, feasibility_result)
        
        if not summary:
            summary = self._generate_summary(overall_score, consistency_score, feasibility_score, recommendation)

        # 统计问题数量
        critical_issues_count = len(consistency_result.get("critical_issues", [])) + len(feasibility_result.get("critical_issues", []))
        warnings_count = len(consistency_result.get("warnings", [])) + len(feasibility_result.get("warnings", []))
        total_checks = consistency_result.get("total_checks", 0) + feasibility_result.get("total_checks", 0)

        # 确定风险等级
        risk_level = self._determine_risk_level(overall_score, critical_issues_count, warnings_count)

        # 构建一致性评估结果对象
        consistency_eval_result = self._build_consistency_result(consistency_result)

        # 构建可实现性评估结果对象
        feasibility_eval_result = self._build_feasibility_result(feasibility_result)

        # 构建兼容的IntegratedEvaluationResult对象
        return IntegratedEvaluationResult(
            overall_score=overall_score,
            consistency_score=consistency_score,
            feasibility_score=feasibility_score,
            recommendation=recommendation,
            summary=summary,
            consistency_result=consistency_eval_result,
            feasibility_result=feasibility_eval_result,
            risk_level=risk_level,
            feasibility_evaluation_skipped=True if feasibility_skipped else None,
            integration_scope="consistency_only" if feasibility_skipped else None,
        )

    def _calculate_consistency_score(self, consistency_result: Dict[str, Any]) -> float:
        """提取一致性评分"""
        # 直接从评估结果中提取score字段
        return consistency_result.get("score", 0.0)

    def _calculate_feasibility_score(self, feasibility_result: Dict[str, Any]) -> float:
        """提取可实现性评分"""
        # 直接从评估结果中提取score字段
        return feasibility_result.get("score", 0.0)

    def _calculate_overall_score(self, consistency_score: float, feasibility_score: float) -> float:
        """计算综合评分"""
        # 一致性权重：40%（结构质量）
        # 可实现性权重：60%（实现可行性）
        return (consistency_score * 0.4) + (feasibility_score * 0.6)

    async def _generate_llm_based_analysis(
        self,
        consistency_result: Dict[str, Any],
        feasibility_result: Dict[str, Any],
        input_data: AgentInput
    ) -> tuple[str, str]:
        """使用LLM生成智能建议和总结"""
        try:
            # 计算基础评分
            consistency_score = self._calculate_consistency_score(consistency_result)
            feasibility_score = self._calculate_feasibility_score(feasibility_result)
            overall_score = self._calculate_overall_score(consistency_score, feasibility_score)

            # 构建评估数据摘要供LLM分析
            assessment_summary = self._build_assessment_summary(
                consistency_result, feasibility_result, overall_score
            )

            # 调用LLM进行分析
            llm_response = await self._call_llm_for_analysis(assessment_summary, input_data)
            
            # 使用LLM生成的结果
            return llm_response.recommendation, llm_response.summary

        except Exception as e:
            logger.warning(f"LLM分析失败，使用默认方法: {str(e)}")
            consistency_score = self._calculate_consistency_score(consistency_result)
            feasibility_score = self._calculate_feasibility_score(feasibility_result)
            overall_score = self._calculate_overall_score(consistency_score, feasibility_score)
            recommendation = self._determine_recommendation(overall_score, consistency_result, feasibility_result)
            summary = self._generate_summary(overall_score, consistency_score, feasibility_score, recommendation)
            return recommendation, summary

    def _build_assessment_summary(
        self,
        consistency_result: Dict[str, Any],
        feasibility_result: Dict[str, Any],
        overall_score: float
    ) -> str:
        """构建评估数据摘要供LLM分析"""
        consistency_score = self._calculate_consistency_score(consistency_result)
        feasibility_score = self._calculate_feasibility_score(feasibility_result)
        
        summary = f"综合评分: {overall_score:.2f} (一致性×0.4 + 可实现性×0.6)\n"
        
        # 一致性评估结果
        summary += "=== 一致性评估 ===\n"
        summary += f"评分: {consistency_score:.2f}\n"
        summary += f"检查项数: {consistency_result.get('total_checks', 0)}\n"
        summary += f"通过项数: {consistency_result.get('passed_checks', 0)}\n"
        
        critical_issues = consistency_result.get("critical_issues", [])
        warnings = consistency_result.get("warnings", [])
        summary += f"关键问题数: {len(critical_issues)}\n"

        if critical_issues:
            summary += "关键问题:\n"
            for issue in critical_issues:  # 显示所有关键问题
                summary += f"- {issue.get('rule_name', '')}: {issue.get('description', '')}\n"

        summary += f"警告数: {len(warnings)}\n"

        if warnings:
            summary += "警告:\n"
            for issue in warnings:  # 显示所有警告
                summary += f"- {issue.get('rule_name', '')}: {issue.get('description', '')}\n"

        # 可实现性评估结果
        summary += "\n=== 可实现性评估 ===\n"
        summary += f"评分: {feasibility_score:.2f}\n"
        summary += f"检查项数: {feasibility_result.get('total_checks', 0)}\n"
        summary += f"通过项数: {feasibility_result.get('passed_checks', 0)}\n"
        
        feasibility_critical = feasibility_result.get("critical_issues", [])
        feasibility_warnings = feasibility_result.get("warnings", [])
        summary += f"关键问题数: {len(feasibility_critical)}\n"

        if feasibility_critical:
            summary += "关键问题:\n"
            for issue in feasibility_critical:  # 显示所有关键问题
                summary += f"- {issue.get('rule_name', '')}: {issue.get('description', '')}\n"

        summary += f"警告数: {len(feasibility_warnings)}\n"

        if feasibility_warnings:
            summary += "警告:\n"
            for issue in feasibility_warnings:  # 显示所有警告
                summary += f"- {issue.get('rule_name', '')}: {issue.get('description', '')}\n"

        # FPA分析结果
        fpa_analysis = feasibility_result.get("fpa_analysis")
        if fpa_analysis:
            summary += "\n=== FPA功能点分析 ===\n"
            if isinstance(fpa_analysis, dict):
                summary += f"总功能点: {fpa_analysis.get('total_afp', 0):.1f}\n"
                summary += f"估算工作量: {fpa_analysis.get('estimated_workload', 0):.1f}人月\n"
            elif hasattr(fpa_analysis, 'total_afp'):
                summary += f"总功能点: {fpa_analysis.total_afp:.1f}\n"
                summary += f"估算工作量: {fpa_analysis.estimated_workload:.1f}人月\n"
        
        return summary

    async def _call_llm_for_analysis(self, assessment_summary: str, input_data: AgentInput) -> LLMIntegrationAnalysisResult:
        """调用LLM进行智能分析"""
        try:
            # 构建LLM提示词
            messages = self._build_integration_analysis_messages(assessment_summary)
            
            # 调用LLM（使用与M2其他智能体相同的调用方式）
            llm_response = await self._call_llm_with_schema(
                llm_model=(input_data.config or {}).get("model") or "qwen3-max",
                messages=messages,
                response_model=LLMIntegrationAnalysisResult
            )
            
            return llm_response
            
        except Exception as e:
            logger.error(f"LLM分析调用失败: {str(e)}")
            raise

    def _build_integration_analysis_messages(self, assessment_summary: str) -> List[Dict[str, str]]:
        """构建综合评估分析的LLM消息"""
        system_prompt = """你是一个专业的软件项目评估专家，负责整合一致性评估和可实现性评估的结果。
        
        基于提供的评估数据，请进行综合分析并返回以下信息：
        1. 建议动作 (recommendation): 基于评估结果给出明确的建议
        2. 评估总结 (summary): 简洁的项目整体评估总结
        
        评估标准：
        - 综合评分 >= 0.8: 优秀，建议继续 (proceed)
        - 综合评分 >= 0.6: 良好，可以谨慎继续 (proceed)  
        - 综合评分 >= 0.4: 一般，建议修订 (revise)
        - 综合评分 < 0.4: 较差，建议重新评估 (terminate)
        
        请基于评估数据提供客观、准确、可操作的综合评估报告。"""

        user_content = f"""请分析以下评估数据：

        {assessment_summary}
        
        请基于以上数据提供专业的综合评估分析。"""

        return [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_content}
        ]

    def _determine_recommendation(self, overall_score: float, consistency_result: Dict[str, Any], feasibility_result: Dict[str, Any]) -> str:
        """确定建议动作（默认方法）"""
        # 基础评分标准
        if overall_score >= 0.8:
            base_recommendation = "proceed"
        elif overall_score >= 0.6:
            base_recommendation = "proceed"
        elif overall_score >= 0.4:
            base_recommendation = "revise"
        else:
            base_recommendation = "terminate"

        # 检查是否有严重的一致性问题
        consistency_critical = len(consistency_result.get("critical_issues", []))
        if consistency_critical > 0:
            return "revise"

        # 检查是否有严重的可实现性问题
        feasibility_critical = len(feasibility_result.get("critical_issues", []))
        if feasibility_critical > 0 and overall_score < 0.6:
            return "revise"

        return base_recommendation

    def _generate_summary(self, overall_score: float, consistency_score: float, feasibility_score: float, recommendation: str) -> str:
        """生成评估总结（默认方法）"""
        score_level = ""
        if overall_score >= 0.8:
            score_level = "优秀"
        elif overall_score >= 0.6:
            score_level = "良好"
        elif overall_score >= 0.4:
            score_level = "一般"
        else:
            score_level = "较差"

        summary = f"综合评估结果：{score_level}（综合评分：{overall_score:.2f}）"
        summary += f"\n一致性评分：{consistency_score:.2f}，可实现性评分：{feasibility_score:.2f}"
        summary += f"\n建议动作：{recommendation}"

        return summary

    def _determine_risk_level(self, overall_score: float, critical_issues: int, warnings: int) -> str:
        """确定风险等级"""
        if overall_score < 0.4 or critical_issues > 3:
            return "critical"
        elif overall_score < 0.6 or critical_issues > 0:
            return "high"
        elif overall_score < 0.8 or warnings > 5:
            return "medium"
        else:
            return "low"

    def _build_consistency_result(self, consistency_data: Dict[str, Any]) -> ConsistencyEvaluationResult:
        """构建一致性评估结果对象"""
        return ConsistencyEvaluationResult(
            score=consistency_data.get("score", 0.0),
            total_checks=consistency_data.get("total_checks", 0),
            passed_checks=consistency_data.get("passed_checks", 0),
            failed_checks=consistency_data.get("failed_checks", 0),
            rule_results=[RuleCheckResult(**rule) for rule in consistency_data.get("rule_results", [])],
            critical_issues=[RuleCheckResult(**issue) for issue in consistency_data.get("critical_issues", [])],
            warnings=[RuleCheckResult(**warning) for warning in consistency_data.get("warnings", [])],
            remediation_instruction=consistency_data.get("remediation_instruction"),
            per_child=consistency_data.get("per_child", [])
        )

    def _build_feasibility_result(self, feasibility_data: Dict[str, Any]) -> FeasibilityEvaluationResult:
        """构建可实现性评估结果对象"""
        return FeasibilityEvaluationResult(
            score=feasibility_data.get("score", 0.0),
            total_checks=feasibility_data.get("total_checks", 0),
            passed_checks=feasibility_data.get("passed_checks", 0),
            failed_checks=feasibility_data.get("failed_checks", 0),
            rule_results=[RuleCheckResult(**rule) for rule in feasibility_data.get("rule_results", [])],
            critical_issues=[RuleCheckResult(**issue) for issue in feasibility_data.get("critical_issues", [])],
            warnings=[RuleCheckResult(**warning) for warning in feasibility_data.get("warnings", [])],
            fpa_analysis=feasibility_data.get("fpa_analysis"),
            cohesion_assessment=feasibility_data.get("cohesion_assessment", {}),
            granularity_assessment=feasibility_data.get("granularity_assessment", {}),
            resource_constraint_match=feasibility_data.get("resource_constraint_match", {}),
            scale_adjustment_factor=feasibility_data.get("scale_adjustment_factor", 1.0),
            technical_complexity_factor=feasibility_data.get("technical_complexity_factor", 1.0)
        )

    def _extract_quality_flags(self, integrated_result: IntegratedEvaluationResult) -> List[str]:
        """提取质量标志"""
        flags = []
        if integrated_result.overall_score >= 0.8:
            flags.append("excellent")
        elif integrated_result.overall_score >= 0.6:
            flags.append("good")
        elif integrated_result.overall_score >= 0.4:
            flags.append("fair")
        else:
            flags.append("poor")

        if integrated_result.risk_level == "critical":
            flags.append("high_risk")
        elif integrated_result.risk_level == "high":
            flags.append("medium_risk")

        return flags

    def _extract_warnings(self, integrated_result: IntegratedEvaluationResult) -> List[str]:
        """提取警告信息"""
        warnings = []

        if integrated_result.overall_score < 0.6:
            warnings.append("综合评分较低，建议仔细审查评估结果")

        if integrated_result.risk_level in ["high", "critical"]:
            warnings.append("项目风险较高，需要重点关注")

        if integrated_result.recommendation == "revise":
            warnings.append("建议对功能分解进行修订")
        elif integrated_result.recommendation == "terminate":
            warnings.append("建议重新评估项目可行性")

        return warnings

    def _extract_evidence(self, integrated_result: IntegratedEvaluationResult) -> list[str] | None:
        """提取证据信息"""
        evidence = []
        
        evidence.append(f"综合评分: {integrated_result.overall_score:.2f}")
        evidence.append(f"一致性评分: {integrated_result.consistency_score:.2f}")
        evidence.append(f"可实现性评分: {integrated_result.feasibility_score:.2f}")
        evidence.append(f"建议动作: {integrated_result.recommendation}")
        evidence.append(f"风险等级: {integrated_result.risk_level}")
        
        if integrated_result.feasibility_evaluation_skipped:
            evidence.append("可实现性评估被跳过")
        
        if integrated_result.integration_scope:
            evidence.append(f"评估范围: {integrated_result.integration_scope}")
        
        return evidence if evidence else None