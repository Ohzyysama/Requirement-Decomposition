"""
编排层：按次 M2 评估 episode 与跨 episode 汇总（rollup）契约。

与 artifacts 键 evaluation_episodes、evaluation_rollup 对应。
"""
from __future__ import annotations

from enum import Enum
from typing import Any, Dict, List, Optional

from pydantic import Field

from app.schemas.base import BaseModel as AppBaseModel


class EvaluationScopeKind(str, Enum):
    """单次 M2 评估作用域。"""

    FULL_TREE = "full_tree"
    SUBTREE = "subtree"


class EpisodeM2Bundle(AppBaseModel):
    """
    单次 M2 尾部（Integrator 完成后）的快照。

    规则与明细均在 `evaluation.consistency_result` / `evaluation.feasibility_result`。
    """

    evaluation: Dict[str, Any] = Field(
        default_factory=dict,
        description="Integrator 综合结果（含 consistency_result / feasibility_result）",
    )


class EvaluationEpisodeRecord(AppBaseModel):
    """单次 M2 完成（含 Integrator）后追加的一条记录。"""

    episode_id: str = Field(..., description="全任务唯一 episode id")
    parent_node_id: Optional[str] = Field(
        None,
        description="本轮拆分父节点；根层全树可为 null",
    )
    tree_version: int = Field(0, description="写入时的 context.tree_version")
    scope: EvaluationScopeKind = Field(
        EvaluationScopeKind.FULL_TREE,
        description="full_tree 或 subtree",
    )
    scope_root_node_id: Optional[str] = Field(
        None,
        description="subtree 时子树根节点 id",
    )
    captured_at: str = Field(..., description="ISO 时间戳")
    bundle: EpisodeM2Bundle = Field(
        default_factory=EpisodeM2Bundle,
        description="该次评估快照（仅 evaluation，见 EpisodeM2Bundle）",
    )


class EvaluationRollup(AppBaseModel):
    """确定性汇总（无 LLM）；供展示与可选叙事润色。"""

    current_node_count: int = Field(0, description="当前树节点数")
    open_rule_hits: int = Field(
        0,
        description="仍引用当前树 id 且未通过（或严重）的规则命中估计数",
    )
    superseded_rule_hits: int = Field(
        0,
        description="因引用已删除节点而 superseded 的规则命中数",
    )
    by_category: Dict[str, int] = Field(
        default_factory=dict,
        description="consistency / feasibility 等开放命中计数",
    )
    highest_severity: str = Field(
        "none",
        description="error / warning / info / none",
    )
    blocking: bool = Field(
        False,
        description="是否存在 error 或未通过关键项（启发式）",
    )
    still_referenced_node_ids: List[str] = Field(
        default_factory=list,
        description="开放问题涉及的节点 id（去重，节选）",
    )
    superseded_notes: List[str] = Field(
        default_factory=list,
        description="简短说明，如某 episode 中规则因节点已删除而失效",
    )
