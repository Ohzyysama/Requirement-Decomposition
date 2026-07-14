"""GET /coordinator/tasks/{id}/evaluation-episodes 辅助逻辑单测。"""
from app.api.coordinator import _episodes_with_order


def test_episodes_with_order_skips_non_dict():
    raw = [
        {"episode_id": "e1"},
        "bad",
        {"episode_id": "e2", "bundle": {"evaluation": {}}},
    ]
    out = _episodes_with_order(raw)
    assert len(out) == 2
    assert out[0]["order"] == 1
    assert out[0]["episode_id"] == "e1"
    assert out[1]["order"] == 2
    assert out[1]["episode_id"] == "e2"


def test_episodes_with_order_empty():
    assert _episodes_with_order(None) == []
    assert _episodes_with_order({}) == []
