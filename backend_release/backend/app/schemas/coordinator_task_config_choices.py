"""
协调器解析任务 — 部分 config 键的前端可选值目录（GET 返回）。

默认值与 pipeline_runner / sub_ar_refiner 中 .get(..., default) 保持一致。
"""
from typing import List, Literal, Union

from pydantic import BaseModel, Field


class CoordinatorTaskConfigChoiceOption(BaseModel):
    """单个可选取值（供下拉、单选）。"""

    value: Union[int, bool] = Field(..., description="写入 CoordinationRequest.config 的值")
    label: str = Field(..., description="短标题，用于 UI")
    description: str = Field(default="", description="该取值的补充说明")
    is_default: bool = Field(default=False, description="是否与后端省略该键时的默认行为一致")


class CoordinatorTaskConfigChoiceGroup(BaseModel):
    """一项配置键及其可选列表。"""

    key: str = Field(..., description="config 中的键名")
    title: str = Field(..., description="配置项标题")
    summary: str = Field(..., description="整体语义与使用建议（含不传键时的默认行为）")
    value_type: Literal["integer", "boolean"] = Field(..., description="值类型提示")
    default_value: Union[int, bool] = Field(..., description="与后端默认值相等；omit 时使用")
    omit_means_default: bool = Field(
        True,
        description="为 true：请求 body 不传该键时后端采用 default_value（与 .get 默认一致）",
    )
    options: List[CoordinatorTaskConfigChoiceOption] = Field(
        ...,
        description="推荐可选值列表；仍可传列表外的合法整数（整数项）",
    )


class CoordinatorTaskConfigChoicesResponse(BaseModel):
    """GET /coordinator/config/task-choice-groups 响应。"""

    groups: List[CoordinatorTaskConfigChoiceGroup]
    usage_hint: str = Field(
        ...,
        description="前端用法说明：可从 options 中选一项写入 POST /coordinator/start 的 config；省略键则用 default_value",
    )
