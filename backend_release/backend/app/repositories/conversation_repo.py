"""
对话仓库
"""
from typing import List, Optional, Dict, Any
from datetime import datetime
import copy
import uuid

from sqlalchemy.orm import Session, load_only
from sqlalchemy.orm.attributes import flag_modified
from app.models.conversation import Conversation, Message
from app.models.conversation_iteration import ConversationIteration
from app.core.config import settings


class ConversationRepository:
    """对话数据仓库"""

    def __init__(self, db: Session):
        self.db = db

    # ───────── 兼容 TaskManager 调用的 create 方法 ─────────

    def create(
        self,
        requirement_text: str,
        config: Optional[Dict[str, Any]] = None,
        context: Optional[Dict[str, Any]] = None,
        user_id: Optional[str] = None,
        title: Optional[str] = None,
    ) -> Conversation:
        """
        创建对话（供 TaskManager 使用）。
        将 requirement_text 映射到 Conversation.original_requirement，
        自动生成 title（截取前 50 字符）和 id。
        """
        auto_title = title or settings.CONVERSATION_PLACEHOLDER_TITLE
        conversation = Conversation(
            id=str(uuid.uuid4()),
            user_id=user_id or "system",
            title=auto_title,
            original_requirement=requirement_text,
            conversation_metadata={
                "config": config or {},
                "context": context or {},
            },
        )
        self.db.add(conversation)
        self.db.commit()
        self.db.refresh(conversation)
        return conversation

    # ───────── 状态与结果更新（供 TaskManager 使用）─────────

    def update_state(
        self,
        conversation_id: str,
        state: str,
        progress: float = 0,
    ) -> Optional[Conversation]:
        """更新对话状态与进度"""
        conversation = self.get_conversation(conversation_id)
        if not conversation:
            return None
        conversation.status = state if isinstance(state, str) else state.value
        conversation.updated_at = datetime.utcnow()
        meta = dict(conversation.conversation_metadata or {})
        meta["progress"] = progress
        conversation.conversation_metadata = meta
        flag_modified(conversation, "conversation_metadata")
        self.db.commit()
        self.db.refresh(conversation)
        return conversation

    def update_result(
        self,
        conversation_id: str,
        result: Dict[str, Any],
    ) -> Optional[Conversation]:
        """写入最终结果"""
        conversation = self.get_conversation(conversation_id)
        if not conversation:
            return None
        meta = dict(conversation.conversation_metadata or {})
        meta["final_result"] = result
        conversation.conversation_metadata = meta
        flag_modified(conversation, "conversation_metadata")
        conversation.completed_at = datetime.utcnow()
        conversation.updated_at = datetime.utcnow()
        self.db.commit()
        self.db.refresh(conversation)
        return conversation

    def merge_coordination_live_snapshot(
        self,
        conversation_id: str,
        artifact_key: str,
        snapshot: Dict[str, Any],
    ) -> Optional[Conversation]:
        """
        将中间协调产物写入 conversation_metadata.coordination_live_snapshot，
        便于前端在未订阅 SSE / 切换页面后 GET 对话仍能还原最新结构化预览。
        """
        conversation = self.get_conversation(conversation_id)
        if not conversation:
            return None
        meta = dict(conversation.conversation_metadata or {})
        live = dict(meta.get("coordination_live_snapshot") or {})
        live[artifact_key] = snapshot
        meta["coordination_live_snapshot"] = live
        conversation.conversation_metadata = meta
        flag_modified(conversation, "conversation_metadata")
        conversation.updated_at = datetime.utcnow()
        self.db.commit()
        self.db.refresh(conversation)
        return conversation

    def restore_after_failed_refine(
        self,
        conversation_id: str,
        *,
        status: str,
        progress: float,
        final_result: Dict[str, Any],
        coordination_live_snapshot: Dict[str, Any],
    ) -> Optional[Conversation]:
        """
        refine-node 失败时将会话元数据恢复为重拆前快照（状态、进度、final_result、live 预览）。
        """
        conversation = self.get_conversation(conversation_id)
        if not conversation:
            return None
        meta = dict(conversation.conversation_metadata or {})
        meta["progress"] = float(progress)
        meta["final_result"] = copy.deepcopy(final_result)
        meta["coordination_live_snapshot"] = copy.deepcopy(coordination_live_snapshot)
        conversation.conversation_metadata = meta
        flag_modified(conversation, "conversation_metadata")
        conversation.status = status if isinstance(status, str) else str(status)
        conversation.updated_at = datetime.utcnow()
        self.db.commit()
        self.db.refresh(conversation)
        return conversation

    # ───────── 原有方法 ─────────

    def create_conversation(self, **kwargs) -> Conversation:
        """创建对话"""
        conversation = Conversation(
            id=str(uuid.uuid4()),
            **kwargs
        )
        self.db.add(conversation)
        self.db.commit()
        self.db.refresh(conversation)
        return conversation

    def get_conversation(self, conversation_id: str) -> Optional[Conversation]:
        """获取对话"""
        return self.db.query(Conversation).filter(Conversation.id == conversation_id).first()

    def get_user_conversations(self, user_id: str, limit: int = 100, offset: int = 0) -> List[Conversation]:
        """
        获取用户的对话列表。

        仅加载列表所需列（id/title/original_requirement/updated_at），避免大 JSON 列
        进入 ORDER BY 排序，防止 MySQL 1038 Out of sort memory。
        """
        return (
            self.db.query(Conversation)
            .options(
                load_only(
                    Conversation.id,
                    Conversation.title,
                    Conversation.original_requirement,
                    Conversation.updated_at,
                )
            )
            .filter(Conversation.user_id == user_id)
            .order_by(Conversation.updated_at.desc())
            .offset(offset)
            .limit(limit)
            .all()
        )

    def update_conversation(self, conversation_id: str, **kwargs) -> Optional[Conversation]:
        """更新对话"""
        conversation = self.get_conversation(conversation_id)
        if not conversation:
            return None

        for key, value in kwargs.items():
            if hasattr(conversation, key):
                setattr(conversation, key, value)
                if key == "conversation_metadata":
                    flag_modified(conversation, "conversation_metadata")

        conversation.updated_at = datetime.utcnow()
        self.db.commit()
        self.db.refresh(conversation)
        return conversation

    def delete_conversation(self, conversation_id: str) -> bool:
        """删除对话及其关联迭代记录（messages 由 Conversation 关系级联删除）。"""
        conversation = self.get_conversation(conversation_id)
        if not conversation:
            return False

        self.db.query(ConversationIteration).filter(
            ConversationIteration.conversation_id == conversation_id
        ).delete(synchronize_session=False)
        self.db.delete(conversation)
        self.db.commit()
        return True

    def add_message(self, conversation_id: str, role: str, content: str, **kwargs) -> Optional[Message]:
        """添加消息"""
        conversation = self.get_conversation(conversation_id)
        if not conversation:
            return None

        message = Message(
            id=str(uuid.uuid4()),
            conversation_id=conversation_id,
            role=role,
            content=content,
            **kwargs
        )
        self.db.add(message)

        # 更新对话时间戳
        conversation.updated_at = datetime.utcnow()
        self.db.commit()
        self.db.refresh(message)
        return message

    def get_conversation_messages(self, conversation_id: str, limit: int = 100) -> List[Message]:
        """获取对话的消息列表"""
        return (
            self.db.query(Message)
            .filter(Message.conversation_id == conversation_id)
            .order_by(Message.created_at.asc())
            .limit(limit)
            .all()
        )

    def get_iteration_feedbacks(
        self, conversation_id: str, limit: int = 10
    ) -> List[Message]:
        """获取对话的迭代反馈消息（message_type=iteration_feedback），按时间倒序取最近 N 条"""
        return (
            self.db.query(Message)
            .filter(
                Message.conversation_id == conversation_id,
                Message.message_type == "iteration_feedback",
            )
            .order_by(Message.created_at.desc())
            .limit(limit)
            .all()
        )