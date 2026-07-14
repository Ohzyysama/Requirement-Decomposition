"""
对话迭代模型
"""
from datetime import datetime
from typing import Dict, Any
from sqlalchemy import Column, String, Text, Integer, Float, Boolean, DateTime, JSON, ForeignKey
from sqlalchemy.orm import relationship
from app.core.database import Base
from app.models.conversation import Conversation  # 可选，引入类本身


class ConversationIteration(Base):
    """对话迭代模型"""
    __tablename__ = "conversation_iterations"

    id = Column(String(36), primary_key=True)
    conversation_id = Column(String(36), ForeignKey("conversations.id"), nullable=False)

    # 迭代信息
    iteration_number = Column(Integer, nullable=False)
    decomposed_requirements = Column(JSON, default=list)
    validation_results = Column(JSON, default=dict)

    # 中间产物快照
    artifacts_snapshot = Column(JSON, default=dict)

    # 质量标记
    quality_flags = Column(JSON, default=dict)

    # 评估结果
    quality_score = Column(Float, nullable=True)
    consistency_score = Column(Float, nullable=True)
    feasibility_score = Column(Float, nullable=True)
    overall_score = Column(Float, nullable=True)

    # 是否为最终选用版本
    is_selected = Column(Boolean, default=False)

    # 元数据
    iteration_metadata = Column(JSON, default=dict)

    # 时间戳
    created_at = Column(DateTime, default=datetime.utcnow)

    # 关系
    conversation = relationship("Conversation", backref="iterations")

    def to_dict(self) -> Dict[str, Any]:
        """转换为字典"""
        return {
            "id": self.id,
            "conversation_id": self.conversation_id,
            "iteration_number": self.iteration_number,
            "decomposed_requirements": self.decomposed_requirements,
            "validation_results": self.validation_results,
            "artifacts_snapshot": self.artifacts_snapshot,
            "quality_flags": self.quality_flags,
            "quality_score": self.quality_score,
            "consistency_score": self.consistency_score,
            "feasibility_score": self.feasibility_score,
            "overall_score": self.overall_score,
            "is_selected": self.is_selected,
            "iteration_metadata": self.iteration_metadata,
            "created_at": self.created_at.isoformat() if self.created_at else None,
        }