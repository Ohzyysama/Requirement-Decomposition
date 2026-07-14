"""
迭代仓库
"""
from typing import List, Optional, Dict, Any
from datetime import datetime
import uuid

from sqlalchemy.orm import Session
from app.models.conversation_iteration import ConversationIteration


class IterationRepository:
    """迭代数据仓库"""

    def __init__(self, db: Session):
        self.db = db

    def save_iteration(
        self,
        conversation_id: str,
        iteration_number: int,
        payload: Dict[str, Any],
    ) -> ConversationIteration:
        """
        保存一轮迭代记录。

        payload 期望包含：
          - artifacts_snapshot: dict  (产物快照)
          - quality_flags: dict       (质量标记)
          - decomposed_requirements: list
          - validation_results: dict
          - quality_score / consistency_score / feasibility_score / overall_score
          - iteration_metadata: dict  (其他元数据)
        """
        iteration = ConversationIteration(
            id=str(uuid.uuid4()),
            conversation_id=conversation_id,
            iteration_number=iteration_number,
            decomposed_requirements=payload.get("decomposed_requirements", []),
            validation_results=payload.get("validation_results", {}),
            artifacts_snapshot=payload.get("artifacts_snapshot", {}),
            quality_flags=payload.get("quality_flags", {}),
            quality_score=payload.get("quality_score"),
            consistency_score=payload.get("consistency_score"),
            feasibility_score=payload.get("feasibility_score"),
            overall_score=payload.get("overall_score"),
            is_selected=payload.get("is_selected", False),
            iteration_metadata=payload.get("iteration_metadata", {}),
        )
        self.db.add(iteration)
        self.db.commit()
        self.db.refresh(iteration)
        return iteration

    def get_iterations(
        self,
        conversation_id: str,
    ) -> List[ConversationIteration]:
        """按 iteration_number 升序返回所有迭代记录"""
        # 不在 SQL 里 ORDER BY：各行 JSON 很大时 MySQL 排序易触发 1038 Out of sort memory；
        # 迭代条数通常很少，在 Python 中排序即可。
        rows = (
            self.db.query(ConversationIteration)
            .filter(ConversationIteration.conversation_id == conversation_id)
            .all()
        )
        return sorted(rows, key=lambda r: r.iteration_number)

    def get_iteration(
        self,
        conversation_id: str,
        iteration_number: int,
    ) -> Optional[ConversationIteration]:
        """获取指定轮次的迭代记录"""
        return (
            self.db.query(ConversationIteration)
            .filter(
                ConversationIteration.conversation_id == conversation_id,
                ConversationIteration.iteration_number == iteration_number,
            )
            .first()
        )

    def get_best_iteration(
        self,
        conversation_id: str,
    ) -> Optional[ConversationIteration]:
        """获取 overall_score 最高的迭代记录"""
        return (
            self.db.query(ConversationIteration)
            .filter(ConversationIteration.conversation_id == conversation_id)
            .order_by(ConversationIteration.overall_score.desc())
            .first()
        )

    def mark_selected(
        self,
        conversation_id: str,
        iteration_number: int,
    ) -> Optional[ConversationIteration]:
        """标记某轮迭代为最终选用版本（取消其他标记）"""
        # 取消已有标记
        self.db.query(ConversationIteration).filter(
            ConversationIteration.conversation_id == conversation_id,
            ConversationIteration.is_selected == True,
        ).update({"is_selected": False})

        iteration = self.get_iteration(conversation_id, iteration_number)
        if iteration:
            iteration.is_selected = True
            self.db.commit()
            self.db.refresh(iteration)
        return iteration

    def delete_iterations_with_number_gt(
        self,
        conversation_id: str,
        iteration_number: int,
    ) -> int:
        """删除 iteration_number 严格大于给定值的所有迭代记录（用于 refine 失败回滚）。"""
        q = self.db.query(ConversationIteration).filter(
            ConversationIteration.conversation_id == conversation_id,
            ConversationIteration.iteration_number > iteration_number,
        )
        deleted = q.delete(synchronize_session=False)
        self.db.commit()
        return int(deleted or 0)
