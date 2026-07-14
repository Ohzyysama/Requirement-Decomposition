"""
对话模型
"""
from datetime import datetime
from typing import Dict, List, Optional, Any
from sqlalchemy import Column, String, Text, Integer, DateTime, JSON, ForeignKey
from sqlalchemy.orm import relationship
from app.core.database import Base


class Conversation(Base):
    """对话模型"""
    __tablename__ = "conversations"

    id = Column(String(36), primary_key=True)
    user_id = Column(String(36), nullable=False, index=True)
    title = Column(String(255), nullable=False)
    description = Column(Text, nullable=True)

    # 需求信息
    original_requirement = Column(Text, nullable=False)
    current_iteration = Column(Integer, default=1)

    # 状态信息
    status = Column(String(50), default="active")  # active, completed, failed

    # 分解结果
    decomposed_requirements = Column(JSON, default=list)
    validation_results = Column(JSON, default=dict)
    quality_flags = Column(JSON, default=dict)

    # 元数据
    conversation_metadata = Column(JSON, default=dict)

    # 时间戳
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    completed_at = Column(DateTime, nullable=True)

    # 关系
    messages = relationship("Message", back_populates="conversation", cascade="all, delete-orphan")

    def to_dict(self, include_messages: bool = False) -> Dict[str, Any]:
        """
        转换为字典。

        include_messages: 为 True 时嵌入 messages 列表；默认 False，避免与
        GET /conversations/{id}/messages 重复且放大响应体。
        """
        base = {
            "id": self.id,
            "user_id": self.user_id,
            "title": self.title,
            "description": self.description,
            "original_requirement": self.original_requirement,
            "current_iteration": self.current_iteration,
            "status": self.status,
            "decomposed_requirements": self.decomposed_requirements,
            "validation_results": self.validation_results,
            "quality_flags": self.quality_flags,
            "conversation_metadata": self.conversation_metadata,
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "updated_at": self.updated_at.isoformat() if self.updated_at else None,
            "completed_at": self.completed_at.isoformat() if self.completed_at else None,
        }
        if include_messages:
            base["messages"] = [
                msg.to_dict() for msg in self.messages
            ] if hasattr(self, "messages") else []
        else:
            base["messages"] = []
        return base


class Message(Base):
    """消息模型"""
    __tablename__ = "messages"

    id = Column(String(36), primary_key=True)
    conversation_id = Column(String(36), ForeignKey("conversations.id"), nullable=False)

    # 消息内容
    role = Column(String(20), nullable=False)
    content = Column(Text, nullable=False)

    # 消息元数据
    message_type = Column(String(50), default="text")  # text, requirement, validation
    message_metadata = Column(JSON, default=dict)

    # 时间戳
    created_at = Column(DateTime, default=datetime.utcnow)

    # 关系
    conversation = relationship("Conversation", back_populates="messages")

    def to_dict(self) -> Dict[str, Any]:
        """转换为字典"""
        return {
            "id": self.id,
            "conversation_id": self.conversation_id,
            "role": self.role,
            "content": self.content,
            "message_type": self.message_type,
            "message_metadata": self.message_metadata,
            "created_at": self.created_at.isoformat() if self.created_at else None,
        }
