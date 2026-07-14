"""
对话相关的模式
"""
from typing import Optional, List, Dict, Any
from datetime import datetime
from pydantic import Field
from app.schemas.base import BaseModel, TimestampMixin


# 与 messages 表 message_type 列及协调器写入约定一致（非穷举，可扩展）
MESSAGE_TYPE_DOC = (
    "text: 普通文本 | requirement | validation | "
    "iteration_feedback: 用户迭代反馈 | "
    "assistant_summary: 助手侧轻量摘要（功能树/依赖条数/Gate 等统计，非全文产物）| "
    "system_event: 系统事件（如任务完成）"
)


class MessageBase(BaseModel):
    """消息基础（聊天时间线；大 JSON 产物见 conversation_metadata.final_result）"""
    role: str  # user, assistant, system
    content: str
    message_type: str = Field(
        default="text",
        description=MESSAGE_TYPE_DOC,
    )
    message_metadata: Dict[str, Any] = Field(
        default_factory=dict,
        description="轻量结构化信息；完整功能树等请通过 detail_ref 或 final_result 获取",
    )


class MessageCreate(MessageBase):
    """消息创建"""
    pass


class MessageResponse(MessageBase, TimestampMixin):
    """消息响应"""
    id: str
    conversation_id: str


class ConversationBase(BaseModel):
    """对话基础"""
    title: str
    description: Optional[str] = None
    original_requirement: str


class ConversationCreate(BaseModel):
    """创建对话：仅提交原始需求；标题由预处理 SSE/落库后提供，不再接受 title/description。"""

    original_requirement: str = Field(
        ...,
        min_length=1,
        description="用户原始自然语言需求",
    )


class ConversationUpdate(BaseModel):
    """对话更新"""
    title: Optional[str] = None
    description: Optional[str] = None
    status: Optional[str] = None  # active, completed, failed
    current_iteration: Optional[int] = None
    decomposed_requirements: Optional[List[str]] = None
    validation_results: Optional[Dict[str, bool]] = None
    quality_flags: Optional[Dict[str, List[str]]] = None
    conversation_metadata: Optional[Dict[str, Any]] = None


class ConversationListItem(BaseModel):
    """对话列表项（瘦身：仅 id、title、original_requirement）"""
    id: str
    title: str
    original_requirement: str


class ConversationResponse(ConversationBase, TimestampMixin):
    """对话响应"""
    id: str
    user_id: str
    status: str = "active"
    current_iteration: int = 1
    decomposed_requirements: List[str] = []
    validation_results: Dict[str, bool] = {}
    quality_flags: Dict[str, List[str]] = {}
    conversation_metadata: Dict[str, Any] = {}
    completed_at: Optional[datetime] = None
    messages: List[MessageResponse] = []

    class Config:
        from_attributes = True