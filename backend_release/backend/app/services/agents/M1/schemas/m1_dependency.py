from typing import Any, Dict, List, Literal, Optional
from pydantic import BaseModel, Field, field_validator, ConfigDict

DependencyType = Literal["EXEC_ORDER", "DATA", "RESOURCE"]
Severity = Literal["LOW", "MEDIUM", "HIGH"]
DegradationMode = Literal["BLOCK", "PROMPT", "SKIP", "DEFAULT"]

ResourceKind = Literal["permission", "system_api", "sdk", "infra", "hardware"]


class IOField(BaseModel):
    model_config = ConfigDict(extra="forbid")

    field: str = Field(..., description="字段名/能力名（DATA依赖重点）")
    data_type: str = Field(..., description="字段类型（string/int/object/enum等）")
    source: Literal["UI", "SYSTEM", "DB", "EXTERNAL", "CACHE", "INFRA"] = Field(
        "SYSTEM",
        description="数据来源（INFRA：运行时/中间件/平台等基础设施侧产出）",
    )
    required: bool = Field(True, description="是否必须")


class ResourceRequirement(BaseModel):
    model_config = ConfigDict(extra="forbid")

    kind: ResourceKind = Field(..., description="资源类型")
    name: str = Field(..., description="资源/权限/API/组件名")
    notes: str = Field("", description="补充说明（可选）")


class DependencyEdge(BaseModel):
    model_config = ConfigDict(extra="forbid", populate_by_name=True)

    dep_id: Optional[str] = Field(None, description="依赖ID（可选但建议）")

    from_: str = Field(..., alias="from", description="发起依赖的功能ID")
    to: str = Field(..., description="被依赖的功能ID")

    dependency_type: DependencyType = Field(
        ...,
        description="仅允许：DATA | EXEC_ORDER | RESOURCE（与 JSON schema 一致，勿输出 CONTROL/HARD/SOFT）",
    )
    description: str = Field(..., description="一句话业务描述")
    direction_explain: str = Field(..., description="为什么是这个方向的依赖")

    trigger: str = Field(..., description="触发条件/前置条件（短句）")

    requires: Optional[List[IOField]] = Field(default_factory=list, description="需要的关键字段/能力")
    provides: Optional[List[IOField]] = Field(default_factory=list, description="提供的关键字段/能力")

    resources_required: Optional[List[ResourceRequirement]] = Field(
        default_factory=list,
        description="RESOURCE依赖时的资源要求"
    )

    @field_validator("requires", "provides", mode="before")
    @classmethod
    def coerce_requires_provides_from_strings(cls, v: Any) -> Any:
        """LLM 常把语义化 IO 写成字符串列表；规范化为 IOField 对象。"""
        if v is None:
            return []
        if not isinstance(v, list):
            return v
        out: List[Any] = []
        for item in v:
            if isinstance(item, str):
                name = item.strip()
                if name:
                    out.append(
                        {
                            "field": name,
                            "data_type": "object",
                            "source": "SYSTEM",
                            "required": True,
                        }
                    )
            else:
                out.append(item)
        return out

    @field_validator("resources_required", mode="before")
    @classmethod
    def convert_none_resources_required(cls, v: Any) -> Any:
        return v if v is not None else []

    degradation_mode: DegradationMode = Field(
        "PROMPT",
        description="缺失依赖时的处理模式"
    )
    degradation_note: str = Field("", description="降级说明（可选）")

    severity: Severity = Field("MEDIUM", description="严重程度")

    @field_validator("dependency_type", mode="before")
    @classmethod
    def coerce_dependency_type_aliases(cls, v: Any) -> Any:
        """遗留别名 CONTROL → EXEC_ORDER（模型偶发沿用旧词）。"""
        if isinstance(v, str) and v.strip().upper() == "CONTROL":
            return "EXEC_ORDER"
        return v


class DependencyMetrics(BaseModel):
    model_config = ConfigDict(extra="forbid")

    total_dependencies: int = Field(..., description="依赖总数")
    avg_deps_per_leaf: float = Field(..., description="平均每个叶子节点依赖数")
    missing_trigger_count: int = Field(..., description="缺少触发条件的依赖数量")
    missing_io_count: int = Field(..., description="缺少字段化IO的依赖数量")
    resource_dep_count: int = Field(..., description="资源依赖数量")
    data_dep_count: int = Field(..., description="数据依赖数量")
    exec_dep_count: int = Field(..., description="顺序依赖数量")


class M1DependencyLLMResult(BaseModel):
    model_config = ConfigDict(extra="forbid")

    dependencies: List[DependencyEdge] = Field(default_factory=list, description="依赖集合")
    metrics: Optional[DependencyMetrics] = Field(None, description="依赖指标")


def migrate_dependency_edge_dict(raw: Any) -> Dict[str, Any]:
    """归一化 from/to；dependency_type 仅保留 DATA | EXEC_ORDER | RESOURCE。兼容旧 persisted 里的 dependency_dimension 或 HARD/SOFT。"""
    if not isinstance(raw, dict):
        return {}
    d: Dict[str, Any] = dict(raw)
    fr = d.get("from")
    if fr is None and "from_" in d:
        fr = d.get("from_")
    if fr is not None:
        d["from"] = str(fr).strip()
    to = d.get("to")
    if to is None:
        to = d.get("to_id") or d.get("target_id")
    if to is not None:
        d["to"] = str(to).strip()

    dim = str(d.pop("dependency_dimension", "") or "").strip().upper()
    dt_raw = d.get("dependency_type")
    dt = str(dt_raw or "").strip().upper()

    _OK = frozenset({"EXEC_ORDER", "DATA", "RESOURCE"})
    _FROM_DIM = {"CONTROL": "EXEC_ORDER", "DATA": "DATA", "RESOURCE": "RESOURCE"}

    def from_dim() -> str:
        return _FROM_DIM.get(dim, "EXEC_ORDER") if dim else "EXEC_ORDER"

    if dt in _OK:
        d["dependency_type"] = dt
    elif dt == "CONTROL":
        d["dependency_type"] = "EXEC_ORDER"
    elif dt in ("HARD", "SOFT"):
        d["dependency_type"] = from_dim()
    elif not str(dt_raw or "").strip():
        d["dependency_type"] = from_dim()
    else:
        d["dependency_type"] = _FROM_DIM.get(dt, from_dim())

    return d


__all__ = [
    "DependencyType",
    "Severity",
    "DegradationMode",
    "ResourceKind",
    "IOField",
    "ResourceRequirement",
    "DependencyEdge",
    "DependencyMetrics",
    "M1DependencyLLMResult",
    "migrate_dependency_edge_dict",
]
