"""M1 Normalizer schema：校验前清洗等行为的单元测试（不调用 LLM）。"""
import unittest

from app.services.agents.M1.schemas.m1_normalizer import M1NormalizerLLMResult


def _minimal_valid_payload(**overrides):
    base = {
        "normalized_requirement": "系统应支持用户登录",
        "goal": {
            "primary_goal": "登录",
            "actors": ["用户"],
            "success_criteria": ["可登录"],
        },
        "constraints": [],
        "scope": {"in": ["登录"], "out": ["支付"]},
        "assumptions": [],
        "open_questions": [],
        "glossary_candidates": [],
    }
    base.update(overrides)
    return base


class TestM1NormalizerOpenQuestions(unittest.TestCase):
    def test_open_questions_drops_stray_top_level_field_name(self):
        data = _minimal_valid_payload(
            open_questions=[
                {
                    "question": "是否支持 SSO？",
                    "reason": "未说明",
                    "suggested_answer_options": [],
                },
                "glossary_candidates",
            ]
        )
        m = M1NormalizerLLMResult.model_validate(data)
        self.assertEqual(len(m.open_questions), 1)
        self.assertEqual(m.open_questions[0].question, "是否支持 SSO？")

    def test_open_questions_wraps_plain_question_string(self):
        data = _minimal_valid_payload(
            open_questions=["峰值 QPS 是多少？"]
        )
        m = M1NormalizerLLMResult.model_validate(data)
        self.assertEqual(len(m.open_questions), 1)
        self.assertEqual(m.open_questions[0].question, "峰值 QPS 是多少？")
        self.assertEqual(m.open_questions[0].reason, "")


if __name__ == "__main__":
    unittest.main()
