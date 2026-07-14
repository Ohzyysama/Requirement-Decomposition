"""TaskRegistry 与 SSEManager 行为测试。"""
import asyncio

from app.services.coordinator.task_registry import SSEManager, TaskRegistry


class StubTaskManager:
    """仅实现 register_progress_callback，用于验证 SSE forward 注册。"""

    def __init__(self) -> None:
        self.register_calls: list[tuple[str, object]] = []

    def register_progress_callback(self, task_id: str, callback):
        self.register_calls.append((task_id, callback))


def test_task_registry_register_get_unregister():
    reg = TaskRegistry()
    stub = object()
    assert "t1" not in reg
    reg.register("t1", stub)  # type: ignore[arg-type]
    assert reg.get("t1") is stub
    assert "t1" in reg
    reg.unregister("t1")
    assert reg.get("t1") is None
    assert "t1" not in reg


def test_task_registry_overwrite():
    reg = TaskRegistry()
    reg.register("t1", object())  # type: ignore[arg-type]
    second = object()
    reg.register("t1", second)  # type: ignore[arg-type]
    assert reg.get("t1") is second


def test_sse_manager_queues_and_remove_empty():
    mgr = SSEManager()
    q1 = mgr.add_queue("tid")
    q2 = mgr.add_queue("tid")
    assert len(mgr._queues["tid"]) == 2
    mgr.remove_queue("tid", q1)
    assert len(mgr._queues["tid"]) == 1
    mgr.remove_queue("tid", q2)
    assert "tid" not in mgr._queues


def test_sse_ensure_forward_once_and_last_seq():
    mgr = SSEManager()
    tm = StubTaskManager()
    mgr.ensure_forward("tid", tm)  # type: ignore[arg-type]
    assert len(tm.register_calls) == 1
    mgr.ensure_forward("tid", tm)  # type: ignore[arg-type]
    assert len(tm.register_calls) == 1

    _tid, cb = tm.register_calls[0]

    async def _run():
        await cb("tid", "intermediate_result", {"sse_sequence": 5, "x": 1})

    asyncio.run(_run())
    assert mgr.get_last_seq("tid") == 5


def test_sse_reregister_forward_second_registration():
    mgr = SSEManager()
    tm1 = StubTaskManager()
    tm2 = StubTaskManager()
    mgr.ensure_forward("tid", tm1)  # type: ignore[arg-type]
    assert len(tm1.register_calls) == 1
    mgr.reregister_forward("tid", tm2)  # type: ignore[arg-type]
    assert len(tm2.register_calls) == 1


def test_sse_on_task_finished_clears_forward_and_seq():
    mgr = SSEManager()
    tm = StubTaskManager()
    mgr.ensure_forward("tid", tm)  # type: ignore[arg-type]
    _tid, cb = tm.register_calls[0]

    async def _once():
        await cb("tid", "x", {"sse_sequence": 3})

    asyncio.run(_once())
    assert mgr.get_last_seq("tid") == 3
    mgr.on_task_finished("tid")
    assert mgr.get_last_seq("tid") is None
    mgr.ensure_forward("tid", tm)  # type: ignore[arg-type]
    assert len(tm.register_calls) == 2
