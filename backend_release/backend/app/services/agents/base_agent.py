from abc import ABC, abstractmethod
from typing import Dict, Any, Optional, Type, TypeVar
import logging
import httpx
from pydantic import BaseModel
from app.schemas.agent import AgentInput, BaseAgentOutput
import instructor
from openai import AsyncOpenAI
from app.core.config import settings

logger = logging.getLogger(__name__)
TModel = TypeVar("TModel", bound=BaseModel)


class BaseAgent(ABC):
    """智能体基类"""

    def __init__(
            self,
            name: str,
            description: str,
            system_prompt: str
    ):
        self.name = name
        self.description = description
        self.system_prompt = system_prompt

        api_key = (settings.LLM_API_KEY or "").strip()
        if not api_key:
            raise ValueError(
                "未配置 LLM API Key。请在项目根目录 .env 中设置 LLM_API_KEY，"
                "并确认 .env 已保存、无多余空格。"
            )
        base_url = (settings.LLM_BASE_URL or "").strip() or "https://api.openai.com/v1"

        http_client = httpx.AsyncClient(
            timeout=httpx.Timeout(
                connect=float(settings.LLM_CONNECT_TIMEOUT_SECONDS),
                read=float(settings.LLM_READ_TIMEOUT_SECONDS),
                write=float(settings.LLM_WRITE_TIMEOUT_SECONDS),
                pool=float(settings.LLM_POOL_TIMEOUT_SECONDS),
            ),
            limits=httpx.Limits(
                max_keepalive_connections=settings.LLM_MAX_CONNECTIONS,
                max_connections=settings.LLM_MAX_CONNECTIONS,
            ),
        )
        raw_openai = AsyncOpenAI(
            api_key=api_key,
            base_url=base_url,
            http_client=http_client,
        )
        self.raw_client = raw_openai
        self.client = instructor.patch(raw_openai, mode=instructor.Mode.JSON)

    def _instructor_client_for_mode(self, mode: Optional[str]):
        """可选切换 Instructor 模式（如 TOOLS）；未知值回退 JSON。"""
        if not mode or str(mode).upper() == "JSON":
            return self.client
        m = str(mode).upper()
        if m == "TOOLS" and hasattr(instructor.Mode, "TOOLS"):
            return instructor.patch(self.raw_client, mode=instructor.Mode.TOOLS)
        logger.warning("[%s] 未知 instructor_mode=%s，使用 JSON", self.name, mode)
        return self.client

    @abstractmethod
    async def execute(self, input_data: AgentInput) -> BaseAgentOutput:
        """执行智能体任务"""
        pass

    def _build_messages(self, input_data: AgentInput) -> list:
        """构建消息"""
        return [
            {"role": "system", "content": self.system_prompt},
            {"role": "user", "content": self._build_user_content(input_data)}
        ]

    def _build_user_content(self, input_data: AgentInput) -> str:
        """构建用户内容 - 子类可覆盖"""
        content = f"需求: {input_data.requirement_text}\n"

        if input_data.normalized_requirement:
            content += f"\n标准化需求: {input_data.normalized_requirement}\n"

        if input_data.artifacts:
            content += f"\n已有产物: {input_data.artifacts}\n"

        if input_data.context:
            content += f"\n上下文: {input_data.context}\n"

        if input_data.config:
            content += f"\n配置: {input_data.config}\n"

        return content

    def _with_strict_json_hint(self, messages: list) -> list:
        """
        在用户消息末尾追加强约束，降低模型输出非结构化文本概率。
        """
        strict_suffix = (
            "\n\n【严格输出要求】\n"
            "1) 只输出一个 JSON 对象，不要输出 markdown，不要代码块，不要解释文字。\n"
            "2) JSON 字段名必须严格匹配约定 schema，禁止新增、重命名、翻译字段。\n"
            "3) 缺失字段必须补齐：对象用 {}, 数组用 [], 数值用 0，布尔用 false；"
            "字符串字段必须填写有意义的内容，禁止使用空字符串 \"\"。\n"
            "4) 所有枚举字段只能输出 schema 允许的值。"
        )
        patched = [dict(m) for m in messages]
        for i in range(len(patched) - 1, -1, -1):
            if patched[i].get("role") == "user":
                content = patched[i].get("content") or ""
                patched[i]["content"] = f"{content}{strict_suffix}"
                return patched
        return patched

    async def _call_llm_with_schema(
        self,
        *,
        llm_model: str,
        messages: list,
        response_model: Type[TModel],
        temperature: float = 0.2,
        max_retries: int = 2,
        instructor_mode: Optional[str] = None,
        **kwargs: Any,
    ) -> TModel:
        """
        统一的结构化调用入口：
        - 主路径：instructor + response_model
        - 失败后：追加严格 JSON 提示重试
        - 最终兜底：OpenAI 兼容 API 的 response_format=json_object + Pydantic 校验
        - instructor_mode: 可选 "JSON"（默认）或 "TOOLS"（需 instructor 支持）
        """
        strict_messages = self._with_strict_json_hint(messages)
        last_error: Optional[Exception] = None
        client = self._instructor_client_for_mode(instructor_mode)

        for attempt in range(max_retries + 1):
            try:
                return await client.chat.completions.create(
                    model=llm_model,
                    messages=strict_messages,
                    response_model=response_model,
                    temperature=temperature,
                    **kwargs,
                )
            except Exception as e:
                last_error = e
                logger.warning(
                    "[%s] structured parse failed (attempt %s/%s): %s",
                    self.name,
                    attempt + 1,
                    max_retries + 1,
                    str(e),
                )

        raw_resp = await self.raw_client.chat.completions.create(
            model=llm_model,
            messages=strict_messages,
            response_format={"type": "json_object"},
            temperature=temperature,
            **kwargs,
        )
        raw_content = (raw_resp.choices[0].message.content or "").strip()
        try:
            return response_model.model_validate_json(raw_content)
        except Exception as e:
            if last_error is not None:
                raise RuntimeError(
                    f"LLM 结构化输出失败（主路径 + 兜底均失败）。最后主路径错误: {last_error}; "
                    f"兜底校验错误: {e}; 原始内容片段: {raw_content[:300]}"
                ) from e
            raise

    def _extract_evidence(self, result: Dict[str, Any]) -> Optional[list]:
        """提取证据 - 子类可覆盖"""
        return None

    def _extract_warnings(self, result: Dict[str, Any]) -> Optional[list]:
        """提取警告 - 子类可覆盖"""
        return None

    def _check_quality(self, result: Dict[str, Any]) -> list:
        """检查质量 - 子类可覆盖"""
        quality_flags = []

        if not result:
            quality_flags.append("empty_result")

        return quality_flags