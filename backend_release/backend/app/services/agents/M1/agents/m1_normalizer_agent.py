import copy
import time
from typing import Dict, Any, Optional
from app.services.agents.base_agent import BaseAgent
from app.core.config import settings
from app.schemas.agent import AgentInput, BaseAgentOutput
from app.services.agents.M1.schemas.m1_normalizer import M1NormalizerLLMResult

DEFAULT_SYSTEM_PROMPT = """
你是“需求预处理与标准化（Normalizer）”智能体。
你的任务：把用户自然语言需求清洗、聚焦边界、显式化关键约束，输出稳定可拆分的标准化需求文本。
你只做标准化，不做功能拆分，不做可行性评估。

要求：
1) 主句只写确定信息，不包含低置信度假设
2) 约束、范围、假设、待确认问题要分开整理
3) 待确认问题 <= 8 个
4) 不要发散新需求
5) open_questions 必须是对象数组：每项含 question、reason、suggested_answer_options；禁止在数组内写入任何顶层字段名字符串；术语条目只能出现在 glossary_candidates
6) suggested_answer_options：若问题为「是否/要不要」类，可用「是/否」；若为「哪些/什么/如何/格式」等列举或定义类，必须给出具体备选（如状态枚举、列表示例）或「待定/默认方案」类选项，禁止整段问题都只用「是/否」敷衍
7) **constraints 收录原则**：只写入两类——(a) 原始需求或上下文中**明确写出**的约束；(b) 在该业务场景下按**常理必然成立**、且能用一句话说明「为何必然」的约束。**禁止**为凑条数而臆造需求中不存在的约束；若可写条目很少，宁可 `constraints` 很短或为空数组 `[]`。

输出结构规范：
- normalized_requirement: 一句话描述核心需求（自然语言，给人读），只包含确定性内容
- goal: 
  - primary_goal: 一句话描述核心目标（应简洁、适合作为会话列表标题，建议不超过约30字）
  - actors: 参与角色列表
  - success_criteria: 成功标准列表
- constraints: **数组**（可为空），每项含 type(PLATFORM/SECURITY/PERMISSION/DATA/PERFORMANCE/SCHEDULE/EXCLUSION/COMPLIANCE/BUDGET/OTHER), value, mandatory(bool), confidence(HIGH/MEDIUM/LOW)；须遵守上述收录原则，不得编造
- scope: 
  - in: 纳入范围列表
  - out: 排除范围列表
- assumptions: 假设列表，每个包含 statement, confidence(HIGH/MEDIUM/LOW), impact(HIGH/MEDIUM/LOW)
- open_questions: 待确认问题列表，每个包含 question, reason, suggested_answer_options(列表)
- glossary_candidates: 术语候选列表（如果有）
"""


def _constraints_list(result: Dict[str, Any]) -> list:
    c = result.get("constraints")
    if isinstance(c, list):
        return c
    return []


class M1NormalizerAgent(BaseAgent):

    def __init__(
        self,
        name: str = "M1-Normalizer",
        description: str = "需求预处理与标准化：输出可拆分的标准化需求文本与约束范围",
        system_prompt: str = DEFAULT_SYSTEM_PROMPT
    ):
        super().__init__(name=name, description=description, system_prompt=system_prompt)

    async def execute(self, input_data: AgentInput) -> BaseAgentOutput:
        start_time = time.perf_counter()
        messages = self._build_messages(input_data)

        llm_model = (input_data.config or {}).get("model") or settings.LLM_MODEL

        cfg = input_data.config or {}
        llm_result: M1NormalizerLLMResult = await self._call_llm_with_schema(
            llm_model=llm_model,
            messages=messages,
            response_model=M1NormalizerLLMResult,
            temperature=0.2,
            instructor_mode=cfg.get("instructor_mode"),
        )

        result_dict = llm_result.model_dump(by_alias=True)
        result_dict = self._post_process_result(result_dict)
        result_dict = M1NormalizerLLMResult.model_validate(result_dict).model_dump(by_alias=True)
        elapsed_ms = int((time.perf_counter() - start_time) * 1000)

        return BaseAgentOutput(
            agent_name=self.name,
            result={"result": result_dict},
            evidence=self._extract_evidence(result_dict),
            warnings=self._extract_warnings(result_dict),
            quality_flags=self._check_quality(result_dict),
            meta={
                "agent": self.name,
                "time_cost_ms": elapsed_ms,
                "version": "m1_normalizer_v4_constraints_policy",
                "model": llm_model,
            },
        )

    def _build_user_content(self, input_data: AgentInput) -> str:
        content = f"原始需求:\n{input_data.requirement_text}\n"
        if input_data.context:
            content += f"\n上下文:\n{input_data.context}\n"
        if input_data.config:
            content += f"\n配置:\n{input_data.config}\n"
        content += "\n请按 Normalizer 结构化输出规范返回。"
        return content

    def _extract_evidence(self, result: Dict[str, Any]) -> Optional[list]:
        evidence = []
        if result.get("normalized_requirement"):
            evidence.append("已生成标准化需求主句")
        items = _constraints_list(result)
        if items:
            evidence.append(f"已提取约束项: {len(items)} 条")
        return evidence or None

    def _extract_warnings(self, result: Dict[str, Any]) -> Optional[list]:
        warnings = []
        scope = result.get("scope") or {}
        if not scope.get("in") or not scope.get("out"):
            warnings.append("范围 in/out 不完整")
        if len(result.get("open_questions") or []) > 8:
            warnings.append("待确认问题过多")
        if self._has_low_confidence_constraint_in_main_sentence(result):
            warnings.append("LOW 置信度约束疑似进入主句，建议人工确认")
        return warnings or None

    def _check_quality(self, result: Dict[str, Any]) -> list:
        # 对齐规范：MISSING_CONTEXT|AMBIGUOUS_SCOPE|LOW_CONFIDENCE_CONSTRAINTS
        flags = []
        scope = result.get("scope") or {}
        if not scope.get("in") or not scope.get("out"):
            flags.append("AMBIGUOUS_SCOPE")
        if self._has_low_confidence_constraints(result):
            flags.append("LOW_CONFIDENCE_CONSTRAINTS")
        if self._is_missing_context(result):
            flags.append("MISSING_CONTEXT")
        return flags

    def _post_process_result(self, result: Dict[str, Any]) -> Dict[str, Any]:
        # 规范要求：待确认问题 <= 8
        open_questions = result.get("open_questions") or []
        if len(open_questions) > 8:
            result["open_questions"] = open_questions[:8]
        # 每条 open_question 的选项由 schema 校验后仍可能需二次清洗（空串等）
        for item in result.get("open_questions") or []:
            if not isinstance(item, dict):
                continue
            opts = item.get("suggested_answer_options")
            if not isinstance(opts, list):
                continue
            cleaned = [s.strip() for s in opts if isinstance(s, str) and s.strip()]
            if len(cleaned) >= 2:
                item["suggested_answer_options"] = cleaned
            elif len(cleaned) == 1:
                item["suggested_answer_options"] = [cleaned[0], "以上皆非 / 待定"]
            else:
                item["suggested_answer_options"] = ["待产品确认", "采用默认/最小可用方案"]
            self._refine_open_question_options(item)
        nr = (result.get("normalized_requirement") or "").strip()
        items = _constraints_list(result)
        if not items:
            result["constraints"] = []
        scope = result.get("scope") or {}
        if not scope.get("out"):
            scope["out"] = ["未在需求中明确排除的能力（待产品确认）"]
        if "in" not in scope:
            scope["in"] = scope.get("in") or []
        if not scope.get("in"):
            pg = (result.get("goal") or {}).get("primary_goal") or ""
            scope["in"] = [pg.strip()] if pg.strip() else [nr or "核心需求范围（待细化）"]
        result["scope"] = scope
        if not (result.get("assumptions") or []):
            result["assumptions"] = [
                {
                    "statement": "未写明的业务细节按行业常见默认实现，后续迭代可再收敛",
                    "confidence": "MEDIUM",
                    "impact": "MEDIUM",
                }
            ]
        result["constraints_copy"] = copy.deepcopy(result.get("constraints") or [])
        return result

    def _looks_like_open_question(self, question: str) -> bool:
        q = (question or "").strip()
        if not q:
            return False
        markers = ("哪些", "什么", "如何", "哪几", "列出", "格式", "字段", "具体", "包含")
        return any(m in q for m in markers)

    def _looks_like_yes_no_question(self, question: str) -> bool:
        q = (question or "").strip()
        if not q:
            return False
        markers = ("是否", "要不要", "是否需要", "有没有", "能否", "可否")
        return any(m in q for m in markers)

    def _refine_open_question_options(self, item: Dict[str, Any]) -> None:
        """把「列举类问题 + 仅是否」的明显错配改成更可用的选项。"""
        q = (item.get("question") or "").strip()
        opts = item.get("suggested_answer_options") or []
        if not isinstance(opts, list) or len(opts) < 2:
            return
        norm = tuple(s.strip() for s in opts if isinstance(s, str))
        if norm not in (("是", "否"), ("否", "是")):
            return
        if self._looks_like_yes_no_question(q) and not self._looks_like_open_question(q):
            return
        if self._looks_like_open_question(q):
            item["suggested_answer_options"] = [
                "待产品确认后再细化（迭代补充）",
                "按最小可用/行业默认先实现",
            ]

    def _has_low_confidence_constraints(self, result: Dict[str, Any]) -> bool:
        items = _constraints_list(result)
        return any((c or {}).get("confidence") == "LOW" for c in items)

    def _has_low_confidence_constraint_in_main_sentence(self, result: Dict[str, Any]) -> bool:
        normalized_requirement = (result.get("normalized_requirement") or "").strip()
        if not normalized_requirement:
            return False
        constraints = _constraints_list(result)
        for item in constraints:
            constraint = item or {}
            if constraint.get("confidence") != "LOW":
                continue
            value = (constraint.get("value") or "").strip()
            if value and value in normalized_requirement:
                return True
        return False

    def _is_missing_context(self, result: Dict[str, Any]) -> bool:
        goal = result.get("goal") or {}
        scope = result.get("scope") or {}
        has_goal = bool((goal.get("primary_goal") or "").strip())
        has_actors = len(goal.get("actors") or []) > 0
        has_scope = len(scope.get("in") or []) > 0 and len(scope.get("out") or []) > 0
        return not (has_goal and has_actors and has_scope)
