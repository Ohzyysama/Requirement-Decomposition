from typing import Any, List, Literal
from pydantic import BaseModel, Field, field_validator, ConfigDict, model_validator

# LLM 偶发把顶层 JSON 字段名误写入 open_questions 数组；与 OpenQuestion 对象列表冲突
_M1_RESULT_TOP_LEVEL_KEYS = frozenset(
    {
        "normalized_requirement",
        "goal",
        "constraints",
        "constraints_copy",
        "scope",
        "assumptions",
        "open_questions",
        "glossary_candidates",
    }
)

ConstraintType = Literal[
    "PLATFORM", "SECURITY", "PERMISSION", "DATA",
    "PERFORMANCE", "SCHEDULE", "EXCLUSION",
    "COMPLIANCE", "BUDGET", "OTHER"
]
ConfidenceLevel = Literal["HIGH", "MEDIUM", "LOW"]


class NormalizedGoal(BaseModel):
    model_config = ConfigDict(extra="forbid")

    primary_goal: str = Field(..., description="一句话描述核心目标")
    actors: List[str] = Field(default_factory=list, description="参与角色")
    success_criteria: List[str] = Field(default_factory=list, description="成功标准")


class NormalizedConstraint(BaseModel):
    type: ConstraintType = Field(..., description="约束类型")
    value: str = Field(
        ...,
        description=(
            "约束内容：须对应原文/上下文中明确表述，或该场景下常理必然成立且可简述依据；"
            "禁止为凑条数编造需求中不存在的约束"
        ),
    )
    mandatory: bool = Field(True, description="是否硬约束")
    confidence: ConfidenceLevel = Field("HIGH", description="可信度")


class NormalizedScope(BaseModel):
    model_config = ConfigDict(extra="forbid", populate_by_name=True)

    in_scope: List[str] = Field(default_factory=list, alias="in", description="纳入范围")
    out_scope: List[str] = Field(default_factory=list, alias="out", description="排除范围")


class AssumptionItem(BaseModel):
    model_config = ConfigDict(extra="forbid")

    statement: str = Field(..., description="假设内容")
    confidence: ConfidenceLevel = Field("MEDIUM", description="可信度")
    impact: ConfidenceLevel = Field("MEDIUM", description="影响程度")


class OpenQuestion(BaseModel):
    model_config = ConfigDict(extra="forbid")

    question: str = Field(..., description="待确认问题")
    reason: str = Field(..., description="原因")
    suggested_answer_options: List[str] = Field(default_factory=list, description="建议选项")

    @field_validator('suggested_answer_options', mode='before')
    @classmethod
    def handle_options(cls, v):
        """将 None 或字符串转换为列表"""
        if v is None:
            return []
        if isinstance(v, str):
            # 尝试按 / 分割，如果没有 / 就作为单个选项
            if '/' in v:
                return [opt.strip() for opt in v.split('/')]
            return [v]
        if isinstance(v, list):
            return v
        return []

    @field_validator("suggested_answer_options", mode="after")
    @classmethod
    def drop_empty_options(cls, v: List[str]) -> List[str]:
        """去掉空字符串，保证至少 2 个可选项（便于前端快速选择）"""
        cleaned = [s.strip() for s in (v or []) if isinstance(s, str) and s.strip()]
        if len(cleaned) >= 2:
            return cleaned
        if len(cleaned) == 1:
            return [cleaned[0], "以上皆非 / 待定"]
        return ["待产品确认", "采用默认/最小可用方案"]


class GlossaryCandidate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    term: str = Field(..., description="术语")
    meaning: str = Field(..., description="候选解释")
    ambiguity: ConfidenceLevel = Field("LOW", description="歧义程度")


class M1NormalizerLLMResult(BaseModel):
    model_config = ConfigDict(extra="forbid")

    normalized_requirement: str = Field(..., description="标准化需求主句（自然语言，给人读）")
    goal: NormalizedGoal = Field(..., description="目标提炼")
    constraints: List[NormalizedConstraint] = Field(
        default_factory=list,
        description=(
            "结构化约束：仅收录原文/上下文中明确写出的条目，以及该情境下常理必然成立、可一句话说明理由的条目；"
            "禁止臆造或凑数；条目少时宁可短列表甚至空数组"
        ),
    )
    constraints_copy: List[NormalizedConstraint] = Field(
        default_factory=list,
        description="预处理完成后 constraints 的副本；功能拆分分发后仅 constraints 可能减少，本字段保留初态供查阅",
    )
    scope: NormalizedScope = Field(default_factory=NormalizedScope, description="范围")
    assumptions: List[AssumptionItem] = Field(default_factory=list, description="假设")
    open_questions: List[OpenQuestion] = Field(default_factory=list, description="待确认问题")
    glossary_candidates: List[GlossaryCandidate] = Field(default_factory=list, description="术语候选")

    @field_validator("constraints", "constraints_copy", mode="before")
    @classmethod
    def _coerce_constraints_list(cls, v: Any) -> Any:
        if v is None:
            return []
        if isinstance(v, list):
            return v
        if isinstance(v, dict):
            return v.get("items") or []
        return []

    @model_validator(mode="before")
    @classmethod
    def _migrate_constraints_and_drop_removed_fields(cls, data: Any) -> Any:
        """兼容 constraints 曾为 {items: [...]}；丢弃已下线字段，避免 extra=forbid 失败。"""
        if not isinstance(data, dict):
            return data
        out = dict(data)
        for k in (
            "preconditions",
            "structured_exports",
            "performance_metrics",
            "external_dependencies",
            "performance_notes",
        ):
            out.pop(k, None)
        c0 = out.get("constraints")
        if isinstance(c0, dict):
            items = c0.get("items")
            out["constraints"] = list(items) if items is not None else []
        return out

    @field_validator("open_questions", mode="before")
    @classmethod
    def normalize_open_questions(cls, v: Any) -> List[Any]:
        if v is None or not isinstance(v, list):
            return []
        out: List[Any] = []
        for item in v:
            if isinstance(item, dict):
                out.append(item)
            elif isinstance(item, str):
                if item in _M1_RESULT_TOP_LEVEL_KEYS:
                    continue
                out.append(
                    {
                        "question": item,
                        "reason": "",
                        "suggested_answer_options": [],
                    }
                )
        return out


__all__ = [
    "ConstraintType",
    "ConfidenceLevel",
    "NormalizedGoal",
    "NormalizedConstraint",
    "NormalizedScope",
    "AssumptionItem",
    "OpenQuestion",
    "GlossaryCandidate",
    "M1NormalizerLLMResult",
]
