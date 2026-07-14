"""子 AR 列表拼接：聚焦拆分无父行时补锚点。"""
import unittest

from app.services.coordinator.tree_utils import (
    ensure_subtree_splice_anchor_rows,
    splice_subtree_into_function_list,
)


class TestSubtreeSpliceAnchor(unittest.TestCase):
    def test_splice_fails_without_anchor_child_only_new_list(self):
        full = [
            {
                "id": "F-1",
                "title": "根",
                "parent_id": None,
            },
            {
                "id": "F-1.1",
                "title": "子",
                "parent_id": "F-1",
            },
        ]
        # 模拟 Decomposer 仅返回重映射后的子节点
        new_only_children = [
            {"id": "F-1.1.1", "title": "a", "parent_id": "F-1.1"},
            {"id": "F-1.1.2", "title": "b", "parent_id": "F-1.1"},
        ]
        self.assertIsNone(
            splice_subtree_into_function_list(full, "F-1.1", new_only_children)
        )

    def test_ensure_anchor_then_splice_succeeds(self):
        full = [
            {"id": "F-1", "title": "根", "parent_id": None},
            {"id": "F-1.1", "title": "子", "parent_id": "F-1"},
        ]
        anchor_template = {
            "id": "F-1.1",
            "title": "子",
            "parent_id": "F-1",
        }
        new_only_children = [
            {"id": "F-1.1.1", "title": "a", "parent_id": "F-1.1"},
            {"id": "F-1.1.2", "title": "b", "parent_id": "F-1.1"},
        ]
        patched = ensure_subtree_splice_anchor_rows(
            new_only_children, "F-1.1", anchor_template
        )
        merged = splice_subtree_into_function_list(full, "F-1.1", patched)
        self.assertIsNotNone(merged)
        ids = {r["id"] for r in merged if isinstance(r, dict)}
        self.assertEqual(ids, {"F-1", "F-1.1", "F-1.1.1", "F-1.1.2"})
        row_f11 = next(r for r in merged if r.get("id") == "F-1.1")
        self.assertEqual(row_f11.get("parent_id"), "F-1")

    def test_idempotent_when_anchor_already_present(self):
        anchor_template = {"id": "F-1.1", "title": "x", "parent_id": "F-1"}
        already = [
            {"id": "F-1.1", "title": "子", "parent_id": "F-1"},
            {"id": "F-1.1.1", "title": "a", "parent_id": "F-1.1"},
        ]
        out = ensure_subtree_splice_anchor_rows(already, "F-1.1", anchor_template)
        self.assertEqual(len(out), 2)


if __name__ == "__main__":
    unittest.main()
