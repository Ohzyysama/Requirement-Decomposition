"""
M2综合评估集成智能体相关模式
"""
from typing import Dict, Any
from pydantic import BaseModel, Field
from app.schemas.evaluation import IntegratedEvaluationResult


class IntegrationResponse(BaseModel):
    """综合评估集成响应"""
    result: IntegratedEvaluationResult = Field(..., description="综合评估结果")
    integration_details: Dict[str, Any] = Field(default_factory=dict, description="集成详情")

    # 新增：评分算法详情
    scoring_details: Dict[str, Any] = Field(default_factory=dict, description="评分算法详情")