"""
协调器相关的模式
"""
from typing import Any, Dict, List, Optional

from pydantic import BaseModel, Field, model_validator
from datetime import datetime

_MAX_FEASIBILITY_REFINEMENT_DEPTH_KEY = "max_feasibility_refinement_depth"


def reject_zero_max_feasibility_refinement_depth(config: Optional[Dict[str, Any]]) -> None:
    """HTTP 请求体中的 config 片段：勿传 max_feasibility_refinement_depth=0（与「省略则默认」易混）。"""
    if not config or _MAX_FEASIBILITY_REFINEMENT_DEPTH_KEY not in config:
        return
    raw = config[_MAX_FEASIBILITY_REFINEMENT_DEPTH_KEY]
    if raw is None:
        raise ValueError(
            f"{_MAX_FEASIBILITY_REFINEMENT_DEPTH_KEY} 不可为 null；请省略该键以使用默认值。"
        )
    try:
        v = int(raw)
    except (TypeError, ValueError) as e:
        raise ValueError(
            f"{_MAX_FEASIBILITY_REFINEMENT_DEPTH_KEY} 须为整数"
        ) from e
    if v <= 0:
        raise ValueError(
            f"{_MAX_FEASIBILITY_REFINEMENT_DEPTH_KEY} 须为正整数；"
            "请省略该键以使用默认值 3。"
            "若需关闭可实现性驱动的子树自动细化，请设置 enable_feasibility_refinement 为 false。"
        )


# ────────────────────────── 请求 / 响应 ──────────────────────────

class CoordinationRequest(BaseModel):
    """协调请求。推荐先 GET /coordinator/tasks/{conversation_id}/stream 再 POST /start，以免错过早期 SSE 事件。"""
    conversation_id: str
    config: Optional[Dict[str, Any]] = Field(
        default=None,
        description=(
            "任务配置分两类（均存于会话 CoordinatorContext.config）："
            "(1) 编排/阈值——仅协调器读取，不会注入 M1 的 LLM 用户消息："
            "consistency_pass_threshold、consistency_inner_max_retries（默认 1）、"
            "continue_pipeline_after_consistency_exhausted、enable_feasibility_refinement、"
            "max_feasibility_refinement_depth（当前拆分根下最大非根深度，默认 3，不含根；请求体中勿传 0 或负数，省略该键即用默认）、"
            "version_selection；"
            "(2) LLM 覆盖——经瘦身传入 M1/M2：model、temperature（M2）、instructor_mode、max_tokens（M1 Dependency）；"
            "一致性内层重试时协调器可能写入 split_retry_hints。"
            "若需让模型看到业务侧补充说明，请用 user_feedback 或需求正文，勿依赖将任意自定义键塞进 config 以进入 M1 prompt。"
        ),
    )
    user_feedback: Optional[str] = None

    @model_validator(mode="after")
    def _config_max_feasibility_depth_no_zero(self) -> "CoordinationRequest":
        reject_zero_max_feasibility_refinement_depth(self.config)
        return self


class RefineNodeRequest(BaseModel):
    """对功能树某节点发起重拆并重新跑列表→一致性→可实现性尾部。"""
    node_id: str = Field(..., description="function_list 中的节点 id")
    user_instruction: Optional[str] = Field(
        default=None,
        description="可选，写入拆分提示",
    )
    config: Optional[Dict[str, Any]] = Field(
        default=None,
        description=(
            "覆盖会话级 config 的片段；键语义见 CoordinationRequest.config（编排键与 LLM 键分类说明）。"
            "可通过 max_feasibility_refinement_depth 单独指定本次 refine-node 的深度上限（以选定节点为根）；"
            "勿传 0 或负数，省略则沿用会话 config 中的值（或默认）。"
        ),
    )

    @model_validator(mode="after")
    def _config_max_feasibility_depth_no_zero(self) -> "RefineNodeRequest":
        reject_zero_max_feasibility_refinement_depth(self.config)
        return self


class CoordinationResponse(BaseModel):
    """协调响应；task_id 与 conversation_id 取值相同（会话主键）。"""
    task_id: str = Field(
        ...,
        description="与 conversation_id 相同，用于 /status/{id}、/tasks/{id}/stream 等",
    )
    conversation_id: str = Field(..., description="会话 ID")
    status: str
    message: str


class TaskStatus(BaseModel):
    """任务状态"""
    task_id: str
    status: str
    progress: float = 0
    current_step: Optional[str] = None
    estimated_time_remaining: Optional[int] = None
    iteration_count: int = 0
    result: Optional[Dict[str, Any]] = None
    error_message: Optional[str] = None
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None


class TaskStatusResponse(TaskStatus):
    """任务状态响应"""
    pass


# ────────────────────────── 迭代决策（摘要） ──────────────────────────

class IterationDecision(BaseModel):
    """单次运行结束时的质量摘要（无外层自动重试）。"""
    should_retry: bool = False
    reason: Optional[str] = None
    target_agent: Optional[str] = None
    requires_user_confirmation: bool = False

