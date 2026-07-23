"""
模块二评估相关模式定义
"""
from typing import List, Dict, Any, Optional, Union
from enum import Enum
from pydantic import BaseModel, Field
from app.schemas.base import BaseModel as AppBaseModel


class RuleSeverity(str, Enum):
    """规则严重程度"""
    ERROR = "error"
    WARNING = "warning"
    INFO = "info"


class RuleCategory(str, Enum):
    """规则类别"""
    CONSISTENCY = "consistency"
    FEASIBILITY = "feasibility"


class IssueType(str, Enum):
    """问题类型"""
    # 一致性问题
    INVALID_DEPENDENCY_REFERENCE = "invalid_dependency_reference"
    CIRCULAR_DEPENDENCY = "circular_dependency"
    DUPLICATE_FUNCTION = "duplicate_function"
    HIGH_COUPLING = "high_coupling"
    INCOMPLETE_SUBREQUIREMENT_COVERAGE = "incomplete_subrequirement_coverage"
    UNFAITHFUL_SPLIT = "unfaithful_split"
    SCOPE_EXCEEDED = "scope_exceeded"
    INVALID_DEPENDENCY_INHERITANCE = "invalid_dependency_inheritance"

    # 可实现性问题
    LOW_COHESION = "low_cohesion"
    FUNCTION_POINT_SCALE_ISSUE = "function_point_scale_issue"
    WORKLOAD_EXCEEDED = "workload_exceeded"
    GRANULARITY_ISSUE = "granularity_issue"
    RESOURCE_CONSTRAINT_MISMATCH = "resource_constraint_mismatch"
    HIGH_TECHNICAL_COMPLEXITY = "high_technical_complexity"


class RuleCheckResult(AppBaseModel):
    """单个规则检查结果"""
    rule_id: str = Field(..., description="规则ID")
    rule_name: str = Field(..., description="规则名称")
    category: RuleCategory = Field(..., description="规则类别")
    severity: RuleSeverity = Field(..., description="严重程度")
    issue_type: IssueType = Field(..., description="问题类型")
    description: str = Field(..., description="问题描述")
    affected_nodes: List[str] = Field(default_factory=list, description="受影响的功能节点ID")
    affected_dependencies: List[str] = Field(default_factory=list, description="受影响的依赖关系ID")
    recommendation: str = Field(..., description="建议动作")
    evidence: Optional[Dict[str, Any]] = Field(default=None, description="证据数据")
    passed: bool = Field(..., description="是否通过检查")


class PerChildRefinementHint(AppBaseModel):
    """整层一致性通过后，对单个子 AR / 子功能节点的下钻建议（与整层 rule 评分分离）。"""
    node_id: str = Field(..., description="子功能节点 id")
    need_further_split: bool = Field(
        False,
        description="是否建议对该节点继续拆分（递归子 AR）",
    )
    split_reason: Optional[str] = Field(
        default=None,
        description="判定原因（与整层 remediation 区分）",
    )
    split_instruction: Optional[str] = Field(
        default=None,
        description="可执行的下钻/细化提示，供下一轮 M1 子范围拆分使用",
    )

############################## 一致性评估相关##############################
class LLMSemanticAssessmentItem(BaseModel):
    """LLM语义评估单项结果"""
    rule_name: str = Field(..., description="规则名称")
    passed: bool = Field(..., description="是否通过")
    description: str = Field(..., description="评估描述")
    confidence: float = Field(..., ge=0.0, le=1.0, description="置信度")
    affected_nodes: List[str] = Field(default_factory=list, description="受影响节点")
    recommendation: str = Field(..., description="建议动作")


class LLMSemanticAssessmentResult(BaseModel):
    """LLM语义评估结果"""
    subrequirement_coverage: LLMSemanticAssessmentItem = Field(..., description="子需求覆盖完整性")
    split_faithfulness: LLMSemanticAssessmentItem = Field(..., description="拆分忠实性")
    scope_constraint: LLMSemanticAssessmentItem = Field(..., description="功能范围约束")
    overall_assessment: str = Field(..., description="总体评估")
    detailed_analysis: str = Field(..., description="详细分析")


class ConsistencyEvaluationResult(AppBaseModel):
    """一致性评估结果"""
    score: float = Field(..., ge=0.0, le=1.0, description="一致性评分")
    total_checks: int = Field(..., description="总检查项数")
    passed_checks: int = Field(..., description="通过检查项数")
    failed_checks: int = Field(..., description="失败检查项数")
    rule_results: List[RuleCheckResult] = Field(default_factory=list, description="详细规则检查结果")
    critical_issues: List[RuleCheckResult] = Field(default_factory=list, description="关键问题列表")
    warnings: List[RuleCheckResult] = Field(default_factory=list, description="警告列表")
    remediation_instruction: Optional[str] = Field(
        default=None,
        description="供下一轮拆分回填的可执行修改建议",
    )
    per_child: List[PerChildRefinementHint] = Field(
        default_factory=list,
        description="逐子节点粒度/下钻提示；与 score 驱动的整层门禁解耦",
    )

############################## 可实现性相关##############################

class DeveloperEffortEstimate(BaseModel):
    """LLM 对单个子功能的开发工作量估算（按开发者经验分层）"""
    function_id: str = Field(..., description="功能节点 ID")

    # ── FPA 语义分类（LLM 判断，替代关键词匹配）──
    function_type: str = Field(
        ..., description="功能类型: EI/EO/EQ/ILF/EIF",
        pattern="^(EI|EO|EQ|ILF|EIF)$"
    )
    complexity: str = Field(
        ..., description="复杂度: LOW/MEDIUM/HIGH",
        pattern="^(LOW|MEDIUM|HIGH)$"
    )
    classification_reason: str = Field(
        default="", description="FPA 分类理由"
    )

    # ── 按开发者经验估算实现时间（核心新增）──
    junior_dev_days: float = Field(
        ..., description="1-2年经验的初级开发者预计实现天数（含自测）"
    )
    mid_dev_days: float = Field(
        ..., description="3-5年经验的中级开发者预计实现天数（含自测）"
    )
    senior_dev_days: float = Field(
        ..., description="5年+经验的高级开发者预计实现天数（含自测）"
    )

    # ── 拆分合理性判断 ──
    needs_further_split: bool = Field(
        default=False,
        description="基于经验判断，该功能是否建议进一步拆分"
    )
    split_reason: Optional[str] = Field(
        default=None, description="如需拆分，说明原因"
    )

    # ── 置信度 ──
    confidence: float = Field(default=0.8, ge=0.0, le=1.0)


class PerFunctionEffortEstimateResult(BaseModel):
    """批量功能开发工作量估算结果"""
    estimates: List[DeveloperEffortEstimate] = Field(
        default_factory=list, description="逐功能估算列表"
    )
    overall_notes: Optional[str] = Field(
        default=None, description="整体说明"
    )


class FPAFunctionClassification(BaseModel):
    """FPA功能分类结果"""
    function_id: str = Field(..., description="功能ID")
    function_type: str = Field(..., description="功能类型: EI/EO/EQ/ILF/EIF")
    complexity: str = Field(..., description="复杂度: LOW/MEDIUM/HIGH")
    function_points: int = Field(..., description="功能点数")
    description: str = Field(..., description="分类说明")


class FPAAssessmentResult(BaseModel):
    """FPA评估结果"""
    total_ufp: int = Field(..., description="总未调整功能点")
    total_afp: float = Field(..., description="总调整后功能点")
    tcf: float = Field(..., description="技术复杂性因子")
    estimated_workload: float = Field(..., description="估算工作量（人月）")
    estimated_cost: float = Field(..., description="估算成本（元）")
    estimated_duration: float = Field(..., description="基于基本cocomo模型估算工期（月）")
    function_classifications: List[FPAFunctionClassification] = Field(default_factory=list, description="功能分类结果")
    detailed_analysis: Dict[str, Any] = Field(default_factory=dict, description="详细分析")


class CohesionAssessmentItem(BaseModel):
    """内聚度评估单项结果"""
    function_id: str = Field(..., description="功能ID")
    cohesion_level: str = Field(..., description="内聚度等级: HIGH/MEDIUM/LOW")
    assessment: str = Field(..., description="评估说明")
    confidence: float = Field(..., ge=0.0, le=1.0, description="置信度")


class CohesionAssessmentResult(BaseModel):
    """内聚度评估结果"""
    low_cohesion_functions: List[CohesionAssessmentItem] = Field(default_factory=list, description="低内聚功能列表")
    medium_cohesion_functions: List[CohesionAssessmentItem] = Field(default_factory=list, description="中内聚功能列表")
    high_cohesion_functions: List[CohesionAssessmentItem] = Field(default_factory=list, description="高内聚功能列表")
    overall_assessment: str = Field(..., description="总体评估")
    recommendations: List[str] = Field(default_factory=list, description="改进建议")


class FeasibilityEvaluationResult(AppBaseModel):
    """可实现性评估结果"""
    score: float = Field(..., ge=0.0, le=1.0, description="可实现性评分")
    total_checks: int = Field(..., description="总检查项数")
    passed_checks: int = Field(..., description="通过检查项数")
    failed_checks: int = Field(..., description="失败检查项数")
    rule_results: List[RuleCheckResult] = Field(default_factory=list, description="详细规则检查结果")
    critical_issues: List[RuleCheckResult] = Field(default_factory=list, description="关键问题列表")
    warnings: List[RuleCheckResult] = Field(default_factory=list, description="警告列表")

    # FPA分析相关字段
    fpa_analysis: Optional[Union[FPAAssessmentResult, List[FPAAssessmentResult]]] = Field(default=None, description="FPA分析结果（支持单个结果或子功能结果列表）")
    cohesion_assessment: Dict[str, str] = Field(default_factory=dict, description="内聚度评估")
    granularity_assessment: Dict[str, str] = Field(default_factory=dict, description="粒度合理性评估")
    resource_constraint_match: Dict[str, bool] = Field(default_factory=dict, description="资源约束匹配情况")

    # 规模适应性调整因子
    scale_adjustment_factor: float = Field(default=1.0, description="规模适应性调整因子")
    technical_complexity_factor: float = Field(default=1.0, description="技术复杂性调整因子")

############################## 综合评估相关##############################
class LLMIntegrationAnalysisResult(BaseModel):
    """LLM综合评估分析结果"""
    recommendation: str = Field(..., description="建议动作: proceed/revise/terminate")
    summary: str = Field(..., description="评估总结")



class IntegratedEvaluationResult(AppBaseModel):
    """综合评估结果"""
    overall_score: float = Field(..., ge=0.0, le=1.0, description="综合评分")
    consistency_score: float = Field(..., ge=0.0, le=1.0, description="一致性评分")
    feasibility_score: float = Field(..., ge=0.0, le=1.0, description="可实现性评分")

    # 子评估结果详情
    consistency_result: ConsistencyEvaluationResult = Field(..., description="一致性评估详情")
    feasibility_result: FeasibilityEvaluationResult = Field(..., description="可实现性评估详情")

    # 综合评估信息
    recommendation: str = Field(..., description="建议动作: proceed/revise/terminate")
    risk_level: str = Field(..., description="风险等级: low/medium/high/critical")
    summary: str = Field(..., description="评估总结")

    # 管线语义：未跑可实现性评估但已跑 Integrator 时由协调层/Integrator 写入
    feasibility_evaluation_skipped: Optional[bool] = Field(
        None,
        description="为 True 表示本轮未执行可实现性评估（如一致性内层耗尽早停）",
    )
    integration_scope: Optional[str] = Field(
        None,
        description="综合报告覆盖范围，如 consistency_only 表示仅基于一致性侧",
    )

