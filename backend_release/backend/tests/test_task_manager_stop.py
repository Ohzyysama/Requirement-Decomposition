"""TaskManager.request_stop 与用户停止落库路径（Orchestrator mock）。"""
import asyncio
import copy
from typing import Any, Dict, List

import pytest

from app.core.enums import TaskMode
from app.services.coordinator.context import CoordinatorContext
from app.services.coordinator.orchestrator import Orchestrator
from app.services.coordinator.task_manager import TaskManager


class FakeConversationRepo:
    def __init__(self) -> None:
        self.states: List[tuple[str, str, float]] = []
        self.results: List[tuple[str, Dict[str, Any]]] = []

    def update_state(self, conversation_id: str, state: str, progress: float = 0):
        self.states.append((conversation_id, state, progress))
        return None

    def update_result(self, conversation_id: str, result: Dict[str, Any]):
        self.results.append((conversation_id, copy.deepcopy(result)))
        return None


class FakeIterationRepo:
    def get_iterations(self, conversation_id: str):
        return []


@pytest.fixture()
def fake_conv_repo():
    return FakeConversationRepo()


@pytest.fixture()
def fake_iter_repo():
    return FakeIterationRepo()


def test_request_stop_sets_flag_and_unknown_task_returns_false(fake_conv_repo, fake_iter_repo):
    tm = TaskManager(fake_conv_repo, fake_iter_repo)
    ctx = CoordinatorContext(
        conversation_id="tid-a",
        requirement_text="r",
        mode=TaskMode.AUTO,
        config={},
    )
    tm.active_tasks["tid-a"] = ctx
    assert tm.request_stop("tid-a") is True
    assert ctx.stop_requested is True
    assert tm.request_stop("missing") is False


def test_run_task_stopped_by_user_finalizes_cancelled(fake_conv_repo, fake_iter_repo, monkeypatch):
    ctx = CoordinatorContext(
        conversation_id="tid-b",
        requirement_text="r",
        mode=TaskMode.AUTO,
        config={},
    )
    tm = TaskManager(fake_conv_repo, fake_iter_repo)

    async def fake_run(orchestrator_self, context, on_iteration_complete=None, on_state_change=None):
        partial = tm.final_assembler.assemble_final_result(context)
        partial["stopped_by_user"] = True
        return partial

    monkeypatch.setattr(Orchestrator, "run", fake_run)

    tm.active_tasks["tid-b"] = ctx

    out = asyncio.run(tm.run_task("tid-b"))

    assert isinstance(out, dict)
    assert out.get("stopped_by_user") is True
    assert fake_conv_repo.states and fake_conv_repo.states[-1][1] == "cancelled"
    assert fake_conv_repo.results and fake_conv_repo.results[-1][1].get("stopped_by_user") is True
    assert "tid-b" not in tm.active_tasks
