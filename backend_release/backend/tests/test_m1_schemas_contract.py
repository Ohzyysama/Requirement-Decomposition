"""M1 LLM 输出 schema：extra=forbid 与 model_json_schema 冒烟（不调用 LLM）。"""
import unittest

from pydantic import ValidationError

from app.services.agents.M1.schemas.m1_decomposer import (
    M1DecomposerLLMResult,
    FunctionListItem,
    remap_function_list_to_f_ids,
    max_parent_hops_to_root,
)
from app.services.agents.M1.schemas.m1_dependency import M1DependencyLLMResult
from app.services.agents.M1.schemas.m1_normalizer import M1NormalizerLLMResult
from app.services.agents.M1.focus_from_normalizer import (
    DECOMPOSITION_ROOT_ID,
    build_focus_node_from_normalizer,
)


def _minimal_normalizer(**extra):
    base = {
        "normalized_requirement": "x",
        "goal": {"primary_goal": "g", "actors": [], "success_criteria": []},
        "constraints": [],
        "constraints_copy": [],
        "scope": {"in": [], "out": []},
        "assumptions": [],
        "open_questions": [],
        "glossary_candidates": [],
    }
    base.update(extra)
    return base


class TestM1FocusFromNormalizer(unittest.TestCase):
    def test_build_focus_uses_primary_goal_and_f1_id(self):
        norm = _minimal_normalizer()
        norm["normalized_requirement"] = "详细说明文本"
        norm["goal"]["primary_goal"] = "核心目标一句"
        f = build_focus_node_from_normalizer(norm)
        self.assertEqual(f["id"], DECOMPOSITION_ROOT_ID)
        self.assertEqual(f["title"], "核心目标一句")
        self.assertEqual(f["desc"], "详细说明文本")
        self.assertEqual(f["node_type"], "DOMAIN")

    def test_build_focus_copies_constraints_from_normalizer(self):
        norm = _minimal_normalizer()
        norm["constraints"] = [
            {"type": "DATA", "value": "仅内网", "mandatory": True, "confidence": "HIGH"},
        ]
        norm["constraints_copy"] = []
        f = build_focus_node_from_normalizer(norm)
        self.assertEqual(len(f["constraints"]), 1)
        self.assertEqual(len(f["constraints_copy"]), 1)
        self.assertEqual(f["constraints"][0]["value"], "仅内网")
        self.assertIsNot(f["constraints"], norm["constraints"])

    def test_max_parent_hops_depth(self):
        rows = [
            {"id": "F-1", "parent_id": None},
            {"id": "F-1.1", "parent_id": "F-1"},
            {"id": "F-1.1.1", "parent_id": "F-1.1"},
        ]
        self.assertEqual(max_parent_hops_to_root(rows), 2)


class TestM1ExtraForbid(unittest.TestCase):
    def test_normalizer_rejects_extra_top_level_field(self):
        data = _minimal_normalizer(unknown_llm_field="should_fail")
        with self.assertRaises(ValidationError):
            M1NormalizerLLMResult.model_validate(data)

    def test_remap_function_list_mode_a_f_path(self):
        rows = [
            {
                "id": "1",
                "title": "根",
                "desc": "",
                "node_type": "DOMAIN",
                "granularity": "EPIC",
                "acceptance_hint": [],
                "parent_id": None,
                "path": "",
            },
            {
                "id": "2",
                "title": "子",
                "desc": "",
                "node_type": "TASK",
                "granularity": "TASK",
                "acceptance_hint": ["a", "b"],
                "parent_id": "1",
                "path": "",
            },
        ]
        out, _ = remap_function_list_to_f_ids(rows, mode_b=False)
        self.assertEqual(out[0]["id"], "F-1")
        self.assertEqual(out[1]["id"], "F-1.1")
        self.assertEqual(out[1]["parent_id"], "F-1")

    def test_remap_function_list_mode_b_children_under_f2(self):
        rows = [
            {
                "id": "F-2",
                "title": "父",
                "desc": "",
                "node_type": "CAPABILITY",
                "granularity": "STORY",
                "acceptance_hint": [],
                "parent_id": None,
                "path": "",
            },
            {
                "id": "99",
                "title": "子A",
                "desc": "",
                "node_type": "TASK",
                "granularity": "TASK",
                "acceptance_hint": ["a", "b"],
                "parent_id": "F-2",
                "path": "",
            },
            {
                "id": "100",
                "title": "子B",
                "desc": "",
                "node_type": "TASK",
                "granularity": "TASK",
                "acceptance_hint": ["a", "b"],
                "parent_id": "F-2",
                "path": "",
            },
        ]
        out, _ = remap_function_list_to_f_ids(
            rows,
            mode_b=True,
            focus_node={"id": "F-2", "title": "父"},
        )
        ids = {r["id"]: r for r in out}
        self.assertIn("F-2", ids)
        self.assertEqual(ids["F-2.1"]["parent_id"], "F-2")
        self.assertEqual(ids["F-2.2"]["parent_id"], "F-2")

    def test_normalizer_legacy_list_constraints_coerced(self):
        data = _minimal_normalizer()
        data["constraints"] = [{"type": "OTHER", "value": "v", "mandatory": True, "confidence": "HIGH"}]
        m = M1NormalizerLLMResult.model_validate(data)
        self.assertEqual(len(m.constraints), 1)

    def test_normalizer_accepts_empty_constraints(self):
        """收录策略允许 constraints 为空；与 m1_normalizer_v4 不再注入占位条一致。"""
        data = _minimal_normalizer()
        data["constraints"] = []
        data["constraints_copy"] = []
        m = M1NormalizerLLMResult.model_validate(data)
        self.assertEqual(m.constraints, [])
        self.assertEqual(m.constraints_copy, [])

    def test_normalizer_strips_removed_top_level_keys(self):
        data = _minimal_normalizer()
        data["preconditions"] = [{"key": "k", "value": "v", "description": ""}]
        data["performance_metrics"] = ["noise"]
        m = M1NormalizerLLMResult.model_validate(data)
        self.assertFalse(hasattr(m, "preconditions"))
        self.assertFalse(hasattr(m, "performance_metrics"))

    def test_decomposer_rejects_extra_top_level_field(self):
        data = {
            "function_list": [],
            "core_flow": [],
            "extra_field": 1,
        }
        with self.assertRaises(ValidationError):
            M1DecomposerLLMResult.model_validate(data)

    def test_function_list_item_rejects_extra_field(self):
        with self.assertRaises(ValidationError):
            FunctionListItem.model_validate({
                "id": "a",
                "title": "t",
                "desc": "",
                "node_type": "DOMAIN",
                "granularity": "EPIC",
                "acceptance_hint": [],
                "parent_id": None,
                "bogus": True,
            })

    def test_decomposer_unwraps_title_as_sole_key(self):
        """LLM 偶发把一行包成 { \"某中文标题\": { ... } }，归一化后应能校验通过。"""
        data = {
            "function_list": [
                {
                    "老师可以输入评分": {
                        "id": "n28",
                        "desc": "",
                        "node_type": "TASK",
                        "granularity": "TASK",
                        "acceptance_hint": [],
                    },
                    "parent_id": "10",
                }
            ],
            "core_flow": [],
        }
        m = M1DecomposerLLMResult.model_validate(data)
        self.assertEqual(len(m.function_list), 1)
        self.assertEqual(m.function_list[0].title, "老师可以输入评分")
        self.assertEqual(m.function_list[0].parent_id, "10")

    def test_decomposer_strips_sentence_key_with_empty_string(self):
        """LLM 偶发把验收句写成非法键: {\"某句\": \"\"}；非白名单键一律丢弃，不并入 acceptance_hint。"""
        data = {
            "function_list": [
                {
                    "id": "n3",
                    "title": "用户注册",
                    "desc": "",
                    "node_type": "TASK",
                    "granularity": "TASK",
                    "acceptance_hint": [],
                    "parent_id": "1",
                    "用户提交的信息被正确存储在数据库中": "",
                }
            ],
            "core_flow": [],
        }
        m = M1DecomposerLLMResult.model_validate(data)
        self.assertEqual(len(m.function_list), 1)
        self.assertEqual(m.function_list[0].acceptance_hint, [])

    def test_decomposer_drops_non_empty_illegal_keys(self):
        """非法键无论值是否为空一律丢弃，避免 extra_forbidden。"""
        data = {
            "function_list": [
                {
                    "id": "n3",
                    "title": "用户注册",
                    "desc": "",
                    "node_type": "TASK",
                    "granularity": "TASK",
                    "acceptance_hint": [],
                    "parent_id": "1",
                    "邮箱格式正确": "yes",
                    "支付信息被安全处理": "",
                }
            ],
            "core_flow": [],
        }
        m = M1DecomposerLLMResult.model_validate(data)
        self.assertEqual(m.function_list[0].title, "用户注册")

    def test_dependency_rejects_extra_top_level(self):
        with self.assertRaises(ValidationError):
            M1DependencyLLMResult.model_validate({"dependencies": [], "metrics": None, "x": 1})

    def test_dependency_coerces_string_requires_provides(self):
        """与 LLM 常见输出一致：requires/provides 为业务字段名字符串列表。"""
        data = {
            "dependencies": [
                {
                    "from": "F-1",
                    "to": "F-2",
                    "dependency_type": "DATA",
                    "description": "d",
                    "direction_explain": "why",
                    "trigger": "t",
                    "requires": ["student_session"],
                    "provides": ["course_list"],
                }
            ],
            "metrics": None,
        }
        m = M1DependencyLLMResult.model_validate(data)
        self.assertEqual(m.dependencies[0].requires[0].field, "student_session")
        self.assertEqual(m.dependencies[0].requires[0].data_type, "object")
        self.assertEqual(m.dependencies[0].provides[0].field, "course_list")


class TestM1JsonSchemaSmoke(unittest.TestCase):
    def test_models_expose_json_schema(self):
        for m in (
            M1NormalizerLLMResult,
            M1DecomposerLLMResult,
            M1DependencyLLMResult,
        ):
            s = m.model_json_schema()
            self.assertIn("title", s or {})
            self.assertIn("properties", s or {})


if __name__ == "__main__":
    unittest.main()
