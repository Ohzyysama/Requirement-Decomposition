"""
TaskRegistry 与 SSEManager — 封装 API 层的全局内存状态。

替代原 coordinator.py 中的裸全局 dict，为未来迁移到 Redis 等外部存储做铺垫。

使用方式：
    from app.services.coordinator.task_registry import task_registry, sse_manager
"""
from __future__ import annotations

import asyncio
import logging
from typing import TYPE_CHECKING, Any, Callable, Awaitable, Dict, List, Optional, Set

if TYPE_CHECKING:
    from app.services.coordinator.task_manager import TaskManager

logger = logging.getLogger(__name__)

# SSE 连接：待 start 之前等待的最长时间（超时后关闭悬挂连接）
PENDING_SSE_MAX_SECONDS = 30 * 60


class TaskRegistry:
    """活跃 TaskManager 注册表（进程内内存，生产环境可替换为 Redis）。"""

    def __init__(self) -> None:
        self._store: Dict[str, "TaskManager"] = {}

    def register(self, task_id: str, task_manager: "TaskManager") -> None:
        self._store[task_id] = task_manager

    def unregister(self, task_id: str) -> None:
        self._store.pop(task_id, None)

    def get(self, task_id: str) -> Optional["TaskManager"]:
        return self._store.get(task_id)

    def __contains__(self, task_id: str) -> bool:
        return task_id in self._store


class SSEManager:
    """SSE 队列广播管理器（进程内内存，生产环境可替换为 Redis Pub/Sub）。"""

    def __init__(self) -> None:
        # task_id → 该任务的所有 SSE 连接队列列表
        self._queues: Dict[str, List[asyncio.Queue]] = {}
        # 已注册了 forward 回调的 task_id 集合（每个 task 仅注册一次）
        self._forward_registered: Set[str] = set()
        # 最近一次 sse_sequence（供 heartbeat 附带）
        self._last_seq: Dict[str, int] = {}

    def add_queue(self, task_id: str) -> asyncio.Queue:
        """新建并注册一个 SSE 连接队列，返回该队列。"""
        q: asyncio.Queue = asyncio.Queue()
        self._queues.setdefault(task_id, []).append(q)
        return q

    def remove_queue(self, task_id: str, queue: asyncio.Queue) -> None:
        """连接断开时从广播列表移除该队列。"""
        lst = self._queues.get(task_id)
        if not lst:
            return
        try:
            lst.remove(queue)
        except ValueError:
            return
        if not lst:
            self._queues.pop(task_id, None)

    def get_last_seq(self, task_id: str) -> Optional[int]:
        return self._last_seq.get(task_id)

    def on_task_finished(self, task_id: str) -> None:
        """任务结束时清理 forward 登记（各连接队列由各 stream 的 finally 移除）。"""
        self._forward_registered.discard(task_id)
        self._last_seq.pop(task_id, None)

    def reregister_forward(
        self,
        task_id: str,
        task_manager: "TaskManager",
    ) -> None:
        """强制重新注册广播回调（用于 refine-node 等需要绑定新 orchestrator 的场景）。

        与 ensure_forward 的区别：先清除旧注册记录，再重新注册，避免竞态条件下
        因 _forward_registered 未及时清理而跳过注册。
        """
        self._forward_registered.discard(task_id)
        self.ensure_forward(task_id, task_manager)

    def ensure_forward(
        self,
        task_id: str,
        task_manager: "TaskManager",
    ) -> None:
        """为 task_id 注册唯一的广播回调（若尚未注册）。"""
        if task_id in self._forward_registered:
            return

        async def _forward(
            tid: str, event_type: str, payload: Dict[str, Any]
        ) -> None:
            if isinstance(payload, dict):
                seq = payload.get("sse_sequence")
                if seq is not None:
                    try:
                        self._last_seq[tid] = int(seq)
                    except (TypeError, ValueError):
                        pass
            item = {
                "event": event_type,
                "data": payload,
                "task_id": tid,
            }
            for q in list(self._queues.get(tid, [])):
                try:
                    await q.put(item)
                except Exception as e:
                    logger.debug("SSE 队列写入失败: %s", e)

        task_manager.register_progress_callback(task_id, _forward)
        self._forward_registered.add(task_id)


# 全局单例（进程内共享）
task_registry = TaskRegistry()
sse_manager = SSEManager()
