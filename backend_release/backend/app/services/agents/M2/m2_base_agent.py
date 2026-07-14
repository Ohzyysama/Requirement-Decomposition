"""
M2 智能体基类：用户消息仅含原始需求与瘦 artifacts（JSON），不把编排 context/config 整包灌入 prompt。
"""
import json

from app.services.agents.base_agent import BaseAgent
from app.schemas.agent import AgentInput


class M2BaseAgent(BaseAgent):
    """模块二共用：瘦身 LLM user 内容。"""

    def _build_user_content(self, input_data: AgentInput) -> str:
        parts: list[str] = [f"需求: {input_data.requirement_text}\n"]
        arts = input_data.artifacts
        if arts:
            try:
                payload = json.dumps(arts, ensure_ascii=False, default=str)
            except TypeError:
                payload = str(arts)
            parts.append("\n评估输入(JSON):\n")
            parts.append(payload)
            parts.append("\n")
        return "".join(parts)
