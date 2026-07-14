"""
M2可实现性评估智能体相关模式
"""
from typing import Dict, Any, Optional
from pydantic import BaseModel, Field
from app.schemas.evaluation import FeasibilityEvaluationResult, FPAAssessmentResult


class FeasibilityCheckResponse(BaseModel):
    """可实现性检查响应"""
    result: FeasibilityEvaluationResult = Field(..., description="可实现性评估结果")
    check_details: Dict[str, Any] = Field(default_factory=dict, description="检查详情")

    # 新增：项目规模分类
    project_scale_classification: Dict[str, Any] = Field(default_factory=dict, description="项目规模分类结果")
