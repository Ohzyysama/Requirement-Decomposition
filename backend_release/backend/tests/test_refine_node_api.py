"""节点重拆接口：SQLite 内存库 + mock Orchestrator（无真实 LLM）。"""
import asyncio

import httpx
import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.api import coordinator as coordinator_module
from app.core.database import Base, get_db
from app.core.dependencies import get_current_user
from app.main import create_app
from app.models.conversation import Conversation
from app.services.coordinator.orchestrator import Orchestrator


@pytest.fixture()
def memory_session_factory():
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(bind=engine)
    return sessionmaker(bind=engine)


def test_refine_node_400_without_final_result(memory_session_factory, monkeypatch):
    SessionLocalTest = memory_session_factory
    db = SessionLocalTest()
    conv = Conversation(
        id="no-fr",
        user_id="u1",
        title="t",
        original_requirement="r",
        conversation_metadata={"config": {}},
    )
    db.add(conv)
    db.commit()
    db.close()

    monkeypatch.setattr(coordinator_module, "SessionLocal", SessionLocalTest)

    def override_db():
        s = SessionLocalTest()
        try:
            yield s
        finally:
            s.close()

    app = create_app()
    app.dependency_overrides[get_db] = override_db
    app.dependency_overrides[get_current_user] = lambda: {"id": "u1", "is_active": True}

    async def _req():
        transport = httpx.ASGITransport(app=app)
        async with httpx.AsyncClient(
            transport=transport, base_url="http://test"
        ) as client:
            return await client.post(
                "/api/v1/coordinator/tasks/no-fr/refine-node",
                json={"node_id": "F-1"},
            )

    try:
        r = asyncio.run(_req())
        assert r.status_code == 400
        assert "最终结果" in r.json().get("detail", "")
    finally:
        app.dependency_overrides.clear()


def test_refine_node_starts_and_persists_stopped_result(
    memory_session_factory, monkeypatch
):
    SessionLocalTest = memory_session_factory
    db = SessionLocalTest()
    conv = Conversation(
        id="with-fr",
        user_id="u1",
        title="t",
        original_requirement="r",
        conversation_metadata={
            "config": {"max_feasibility_refinement_depth": 3},
            "final_result": {
                "pipeline_stage": "done",
                "tree_version": 1,
                "iteration_count": 1,
                "function_list": [{"id": "F-1", "parent_id": None}],
            },
        },
    )
    db.add(conv)
    db.commit()
    db.close()

    monkeypatch.setattr(coordinator_module, "SessionLocal", SessionLocalTest)

    class FakeOrchestrator(Orchestrator):
        async def run_refine_node(self, *args, **kwargs):
            return {"stopped_by_user": True}

    monkeypatch.setattr(
        coordinator_module,
        "Orchestrator",
        FakeOrchestrator,
    )

    def override_db():
        s = SessionLocalTest()
        try:
            yield s
        finally:
            s.close()

    app = create_app()
    app.dependency_overrides[get_db] = override_db
    app.dependency_overrides[get_current_user] = lambda: {"id": "u1", "is_active": True}

    async def _req():
        transport = httpx.ASGITransport(app=app)
        async with httpx.AsyncClient(
            transport=transport, base_url="http://test"
        ) as client:
            return await client.post(
                "/api/v1/coordinator/tasks/with-fr/refine-node",
                json={"node_id": "F-1", "user_instruction": "hint"},
            )

    try:
        r = asyncio.run(_req())
        assert r.status_code == 200
        body = r.json()
        assert body.get("status") == "started"

        db2 = SessionLocalTest()
        row = db2.query(Conversation).filter(Conversation.id == "with-fr").one()
        db2.close()
        assert row.status == "cancelled"
        fr = (row.conversation_metadata or {}).get("final_result") or {}
        assert fr.get("stopped_by_user") is True
    finally:
        app.dependency_overrides.clear()
