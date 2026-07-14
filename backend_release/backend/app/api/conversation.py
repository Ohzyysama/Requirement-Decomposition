"""
对话相关的API端点

职责划分：
- GET /conversations/{id}：会话资源（元数据与状态），默认不包含 messages 嵌入；
  需要内嵌消息时传 include_messages=true。
- DELETE /conversations/{id}：删除会话（含 messages 级联与 conversation_iterations）。
- GET /conversations/{id}/messages：聊天时间线（用户消息 + 助手摘要 + 系统事件），
  大产物仅存于 conversation_metadata.final_result 等，见 message_metadata.detail_ref。
"""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List

from app.core.database import get_db
from app.core.dependencies import get_current_user
from app.schemas.conversation import (
    ConversationCreate,
    ConversationListItem,
    ConversationResponse,
    ConversationUpdate,
    MessageCreate,
    MessageResponse,
)
from app.repositories.conversation_repo import ConversationRepository
from app.core.config import settings

# 创建路由器
router = APIRouter()


@router.get("/", response_model=List[ConversationListItem])
async def list_conversations(
    skip: int = 0,
    limit: int = 100,
    current_user: dict = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """获取用户的对话列表"""
    repo = ConversationRepository(db)
    conversations = repo.get_user_conversations(
        user_id=current_user.get("id"),
        limit=limit,
        offset=skip
    )
    return [
        {
            "id": conv.id,
            "title": conv.title,
            "original_requirement": conv.original_requirement,
        }
        for conv in conversations
    ]


@router.post("/", response_model=ConversationResponse, status_code=status.HTTP_201_CREATED)
async def create_conversation(
    conversation_data: ConversationCreate,
    current_user: dict = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """创建新对话"""
    repo = ConversationRepository(db)

    conversation = repo.create_conversation(
        user_id=current_user.get("id"),
        title=settings.CONVERSATION_PLACEHOLDER_TITLE,
        description=None,
        original_requirement=conversation_data.original_requirement,
    )

    return conversation.to_dict(include_messages=False)


@router.get("/{conversation_id}", response_model=ConversationResponse)
async def get_conversation(
    conversation_id: str,
    include_messages: bool = False,
    current_user: dict = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    获取特定对话（会话资源：元数据与状态）。

    默认不嵌入 messages，请使用 GET .../messages 拉取聊天时间线；
    仅当需要单次响应内嵌消息时设 include_messages=true。
    """
    repo = ConversationRepository(db)
    conversation = repo.get_conversation(conversation_id)

    if not conversation:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Conversation not found"
        )

    # 检查权限
    if conversation.user_id != current_user.get("id"):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not enough permissions"
        )

    return conversation.to_dict(include_messages=include_messages)


@router.put("/{conversation_id}", response_model=ConversationResponse)
async def update_conversation(
    conversation_id: str,
    conversation_data: ConversationUpdate,
    current_user: dict = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """更新对话"""
    repo = ConversationRepository(db)

    # 先获取对话检查权限
    conversation = repo.get_conversation(conversation_id)
    if not conversation:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Conversation not found"
        )

    if conversation.user_id != current_user.get("id"):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not enough permissions"
        )

    # 更新对话
    updated_conversation = repo.update_conversation(
        conversation_id=conversation_id,
        **conversation_data.dict(exclude_unset=True)
    )

    if not updated_conversation:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Conversation not found"
        )

    return updated_conversation.to_dict(include_messages=False)


@router.delete("/{conversation_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_conversation(
    conversation_id: str,
    current_user: dict = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """删除对话"""
    repo = ConversationRepository(db)

    # 先获取对话检查权限
    conversation = repo.get_conversation(conversation_id)
    if not conversation:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Conversation not found"
        )

    if conversation.user_id != current_user.get("id"):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not enough permissions"
        )

    # 删除对话
    success = repo.delete_conversation(conversation_id)
    if not success:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Conversation not found"
        )

    return None


@router.post("/{conversation_id}/messages", response_model=MessageResponse)
async def add_message(
    conversation_id: str,
    message_data: MessageCreate,
    current_user: dict = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    向对话添加消息（通常为 user；迭代反馈请使用 message_type=iteration_feedback）。

    message_type 约定见 Schema 中 MessageBase 说明。
    """
    repo = ConversationRepository(db)

    # 先获取对话检查权限
    conversation = repo.get_conversation(conversation_id)
    if not conversation:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Conversation not found"
        )

    if conversation.user_id != current_user.get("id"):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not enough permissions"
        )

    # 添加消息
    message = repo.add_message(
        conversation_id=conversation_id,
        role=message_data.role,
        content=message_data.content,
        message_type=message_data.message_type,
        message_metadata=message_data.message_metadata
    )

    if not message:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Failed to add message"
        )

    return message.to_dict()


@router.get("/{conversation_id}/messages", response_model=List[MessageResponse])
async def list_messages(
    conversation_id: str,
    limit: int = 100,
    current_user: dict = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    获取对话消息时间线（用户、assistant 摘要、system 事件）。

    大体积产物不在 content 中返回，详见各条的 message_metadata.detail_ref。
    """
    repo = ConversationRepository(db)

    # 先获取对话检查权限
    conversation = repo.get_conversation(conversation_id)
    if not conversation:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Conversation not found"
        )

    if conversation.user_id != current_user.get("id"):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not enough permissions"
        )

    # 获取消息
    messages = repo.get_conversation_messages(conversation_id, limit=limit)
    return [msg.to_dict() for msg in messages]