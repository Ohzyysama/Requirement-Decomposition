"""
智能体相关的模式
"""
from typing import List, Dict, Any, Optional
from pydantic import BaseModel, field_validator


# ─────────── 通用智能体输入 / 输出（供 BaseAgent & AgentInvoker 使用）───────────

class AgentInput(BaseModel):
    """智能体统一输入"""
    task_id: str = ""
    requirement_text: str = ""
    normalized_requirement: Optional[Any] = None
    artifacts: Optional[Dict[str, Any]] = None
    context: Optional[Dict[str, Any]] = None
    config: Optional[Dict[str, Any]] = None


class BaseAgentOutput(BaseModel):
    """智能体统一输出"""
    result: Dict[str, Any] = {}
    quality_flags: List[str] = []
    warnings: List[str] = []
    evidence: Optional[List[str]] = None
    meta: Optional[Dict[str, Any]] = None

    @field_validator("warnings", "quality_flags", mode="before")
    @classmethod
    def coerce_list(cls, v: Any) -> List:
        """None 或非列表统一转为 []，避免 Pydantic 校验报错"""
        if v is None:
            return []
        if isinstance(v, list):
            return v
        return []

    def get_payload(self) -> Dict[str, Any]:
        """获取 Agent 的实际输出载荷，消除双层 result 嵌套。

        当前约定：agents 在 ``result["result"]`` 中存放真实 payload。
        此方法统一解包，调用方无需写 ``(output.result or {}).get("result") or {}``。
        """
        raw = self.result or {}
        if isinstance(raw, dict) and "result" in raw:
            inner = raw["result"]
            if isinstance(inner, dict):
                return inner
        return raw if isinstance(raw, dict) else {}

