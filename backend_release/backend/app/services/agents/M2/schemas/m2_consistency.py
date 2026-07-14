"""
M2一致性评估智能体相关模式
"""
from typing import Dict, Any
from pydantic import BaseModel, Field
from app.schemas.evaluation import ConsistencyEvaluationResult, RuleCheckResult


class ConsistencyCheckResponse(BaseModel):
    """一致性检查响应"""
    result: ConsistencyEvaluationResult = Field(..., description="一致性评估结果")
    check_details: Dict[str, Any] = Field(default_factory=dict, description="检查详情")

    # 新增：混合评估模式结果
    rule_engine_results: Dict[str, Any] = Field(default_factory=dict, description="规则引擎评估结果")
    llm_assessment_results: Dict[str, Any] = Field(default_factory=dict, description="LLM语义评估结果")
