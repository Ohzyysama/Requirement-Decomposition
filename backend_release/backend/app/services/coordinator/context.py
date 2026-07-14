"""
协调器上下文 — 存储当前任务的所有运行时状态信息
"""
import copy
import logging
import uuid
from typing import Dict, Any, Optional, List
from dataclasses import dataclass, field
from datetime import datetime, timezone
from app.core.enums import TaskMode, PipelineStage

logger = logging.getLogger(__name__)


@dataclass
class CoordinatorContext:
    """协调器上下文，存储当前任务的所有状态信息"""

    conversation_id: str
    requirement_text: str
    mode: TaskMode
    config: Dict[str, Any]

    # 状态
    iteration_count: int = 0
    progress: float = 0.0

    # 存储中间产物（当前轮）
    artifacts: Dict[str, Any] = field(default_factory=dict)

    # 工作区（已废弃：请使用 artifacts 存储中间状态；此字段仅保留用于旧格式兼容）
    workspace: Dict[str, Any] = field(default_factory=dict)

    # 质量跟踪
    quality_flags: Dict[str, List[str]] = field(default_factory=dict)

    # 执行历史（agent 产物生成等）
    execution_history: List[Dict[str, Any]] = field(default_factory=list)

    # 状态转移日志
    state_transition_log: List[Dict[str, Any]] = field(default_factory=list)

    # 每轮迭代快照列表 (iteration_number → snapshot)
    iteration_snapshots: List[Dict[str, Any]] = field(default_factory=list)

    # 上下文信息
    context: Dict[str, Any] = field(default_factory=dict)

    # POST /coordinator/stop 协作式取消（在迭代边界与长调用返回后生效）
    stop_requested: bool = False

    # 「一致性优先」编排：跨子步骤的返工上下文（instruction、上一档评分等）
    retry_context: Dict[str, Any] = field(default_factory=dict)

    # 子 AR 递归：编排栈（仅协调层使用，可序列化到会话）
    sub_ar_refinement_stack: List[Dict[str, Any]] = field(default_factory=list)

    # 功能树结构版本号（每次子 AR 写回整树后 +1，供 SSE / 前端区分）
    tree_version: int = 0

    # SSE：按产物族记录最近一次事件的 sse_sequence，用于 supersedes_sse_sequence
    sse_last_by_family: Dict[str, int] = field(default_factory=dict)

    # 智能体 LLM 调用跨度（用于 /timeline 与 SSE agent_timeline）
    agent_spans: List[Dict[str, Any]] = field(default_factory=list)

    # 由 Orchestrator 注入：async (phase, context, span_id) -> None
    agent_span_emit: Any = None

    # 当前管线阶段（唯一权威状态源）
    pipeline_stage: PipelineStage = PipelineStage.IDLE

    # 时间戳（UTC，与 SSE completed_at 一致）
    created_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
    updated_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))

    # ─────── 状态管理 ───────

    def update_stage(self, new_stage: PipelineStage) -> None:
        """更新管线阶段（唯一权威状态源），并记录转移日志（值为 pipeline 字符串）。"""
        old_stage = self.pipeline_stage
        if old_stage == new_stage:
            self.updated_at = datetime.now(timezone.utc)
            return

        self.pipeline_stage = new_stage
        self.updated_at = datetime.now(timezone.utc)

        self.state_transition_log.append({
            "from_state": old_stage.value,
            "to_state": new_stage.value,
            "timestamp": datetime.now(timezone.utc).isoformat(),
        })

        logger.debug(
            "[%s] 管线阶段: %s → %s",
            self.conversation_id, old_stage, new_stage,
        )

    # ─────── 产物管理 ───────

    def sync_workspace_from_artifacts(self) -> None:
        """已废弃：workspace 字段不再主动同步，保留方法体避免调用方报错。"""

    def add_artifact(self, key: str, value: Any, agent: Optional[str] = None):
        """添加中间产物"""
        self.artifacts[key] = value
        self.updated_at = datetime.now(timezone.utc)
        if agent:
            self.execution_history.append({
                "timestamp": datetime.now(timezone.utc),
                "agent": agent,
                "action": "artifact_generated",
                "key": key,
            })

    def begin_agent_span(self, agent: str, label: Optional[str] = None) -> str:
        """开始记录一次智能体调用（通常为单次 LLM execute）。"""
        span_id = uuid.uuid4().hex[:16]
        now = datetime.now(timezone.utc)
        row: Dict[str, Any] = {
            "span_id": span_id,
            "agent": agent,
            "label": label or "",
            "pipeline_stage": self.pipeline_stage.value,
            "status": "running",
            "started_at": now.isoformat(),
            "ended_at": None,
            "duration_minutes": None,
        }
        self.agent_spans.append(row)
        self.updated_at = now
        return span_id

    def end_agent_span(self, span_id: str, status: str = "completed") -> None:
        """结束 span 并计算 duration_minutes（墙钟时间，分钟）。"""
        row: Optional[Dict[str, Any]] = None
        for s in self.agent_spans:
            if s.get("span_id") == span_id:
                row = s
                break
        if row is None:
            return
        now = datetime.now(timezone.utc)
        row["ended_at"] = now.isoformat()
        row["status"] = status
        try:
            raw_start = str(row.get("started_at") or "")
            start = datetime.fromisoformat(raw_start.replace("Z", "+00:00"))
            if start.tzinfo is None:
                start = start.replace(tzinfo=timezone.utc)
            row["duration_minutes"] = round(
                (now - start).total_seconds() / 60.0, 6
            )
        except (TypeError, ValueError):
            row["duration_minutes"] = None
        self.updated_at = now

    def get_agent_span(self, span_id: str) -> Optional[Dict[str, Any]]:
        for s in self.agent_spans:
            if s.get("span_id") == span_id:
                return s
        return None

    def list_running_agent_spans(self) -> List[Dict[str, Any]]:
        return [
            copy.deepcopy(s)
            for s in self.agent_spans
            if s.get("ended_at") is None
        ]

    # ─────── 质量标记 ───────

    def add_quality_flag(self, agent: str, flag: str):
        """添加质量标记"""
        if agent not in self.quality_flags:
            self.quality_flags[agent] = []
        self.quality_flags[agent].append(flag)

    # ─────── 迭代快照 ───────

    def take_iteration_snapshot(self):
        """
        为当前迭代拍摄快照（artifacts 副本 + 质量标记 + 时间戳），
        并追加到 iteration_snapshots。

        增强字段（文档 3.4.9）：
        - agents_invoked: 本轮使用的智能体列表
        - score_delta: 与上一轮的评分变化
        """
        agents_invoked: List[str] = []
        if self.artifacts.get("normalized_requirement") is not None:
            agents_invoked.append("normalizer")
        if self.artifacts.get("function_list") is not None:
            agents_invoked.append("decomposer")
        if self.artifacts.get("dependencies") is not None:
            agents_invoked.append("dependency_classifier")

        score_delta: Optional[float] = None
        eval_data = self.artifacts.get("evaluation") or {}
        curr_score = None
        if isinstance(eval_data, dict) and eval_data.get("overall_score") is not None:
            curr_score = float(eval_data["overall_score"]) * 100.0
        if curr_score is not None and len(self.iteration_snapshots) >= 1:
            prev_snap = self.iteration_snapshots[-1]
            prev_arts = prev_snap.get("artifacts_snapshot") or {}
            prev_eval = prev_arts.get("evaluation") or {}
            prev_score = None
            if isinstance(prev_eval, dict) and prev_eval.get("overall_score") is not None:
                prev_score = float(prev_eval["overall_score"]) * 100.0
            if prev_score is not None:
                score_delta = curr_score - prev_score

        snapshot = {
            "iteration_number": self.iteration_count,
            "artifact_keys": list(self.artifacts.keys()),
            "artifacts_snapshot": {k: v for k, v in self.artifacts.items()},
            "quality_flags": {k: list(v) for k, v in self.quality_flags.items()},
            "agents_invoked": agents_invoked,
            "score_delta": score_delta,
            "created_at": datetime.now(timezone.utc).isoformat(),
        }
        self.iteration_snapshots.append(snapshot)

    # ─────── 序列化 ───────

    @classmethod
    def from_saved_final_result(
        cls,
        conversation_id: str,
        requirement_text: str,
        final_result: Dict[str, Any],
        config: Dict[str, Any],
    ) -> "CoordinatorContext":
        """从持久化的 final_result 恢复上下文，供 refine-node 等续跑。

        已迁移至 ContextHydrator.from_db_result()；此方法保留为向后兼容入口。
        """
        from app.services.coordinator.context_hydrator import ContextHydrator
        return ContextHydrator.from_db_result(
            conversation_id, requirement_text, final_result, config
        )

    def to_dict(self) -> Dict[str, Any]:
        """转换为摘要字典（不含完整 artifacts 内容）"""
        return {
            "conversation_id": self.conversation_id,
            "pipeline_stage": self.pipeline_stage.value,
            "mode": self.mode.value if hasattr(self.mode, "value") else self.mode,
            "iteration_count": self.iteration_count,
            "progress": self.progress,
            "artifact_keys": list(self.artifacts.keys()),
            "quality_flags": self.quality_flags,
            "state_transition_log": self.state_transition_log,
            "created_at": self.created_at.isoformat(),
            "updated_at": self.updated_at.isoformat(),
        }
