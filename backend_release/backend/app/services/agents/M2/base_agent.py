from abc import ABC, abstractmethod
from typing import Dict, Any, Optional, Type, TypeVar
import logging
import httpx
from pydantic import BaseModel
from app.schemas.agent import AgentInput, BaseAgentOutput
import instructor
from openai import AsyncOpenAI
from app.core.config import settings

# 新增用於日誌與時間監控的庫
import time
import json

logger = logging.getLogger(__name__)
TModel = TypeVar("TModel", bound=BaseModel)


class BaseAgent(ABC):
    """智能體基類"""

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
                "未配置 LLM API Key。請在項目根目錄 .env 中設置 LLM_API_KEY，"
                "並確認 .env 已保存、無多餘空格。"
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
        """可選切換 Instructor 模式（如 TOOLS）；未知值回退 JSON。"""
        if not mode or str(mode).upper() == "JSON":
            return self.client
        m = str(mode).upper()
        if m == "TOOLS" and hasattr(instructor.Mode, "TOOLS"):
            return instructor.patch(self.raw_client, mode=instructor.Mode.TOOLS)
        logger.warning("[%s] 未知 instructor_mode=%s，使用 JSON", self.name, mode)
        return self.client

    @abstractmethod
    async def execute(self, input_data: AgentInput) -> BaseAgentOutput:
        """執行智能體任務"""
        pass

    def _build_messages(self, input_data: AgentInput) -> list:
        """構建消息"""
        return [
            {"role": "system", "content": self.system_prompt},
            {"role": "user", "content": self._build_user_content(input_data)}
        ]

    def _build_user_content(self, input_data: AgentInput) -> str:
        """構建用戶內容 - 子類可覆蓋"""
        content = f"需求: {input_data.requirement_text}\n"

        if input_data.normalized_requirement:
            content += f"\n標準化需求: {input_data.normalized_requirement}\n"

        if input_data.artifacts:
            content += f"\n已有產物: {input_data.artifacts}\n"

        if input_data.context:
            content += f"\n上下文: {input_data.context}\n"

        if input_data.config:
            content += f"\n配置: {input_data.config}\n"

        return content

    def _with_strict_json_hint(self, messages: list) -> list:
        """
        在用戶消息末尾追加強約束，降低模型輸出非結構化文本概率。
        """
        strict_suffix = (
            "\n\n【嚴格輸出要求】\n"
            "1) 只輸出一個 JSON 對象，不要輸出 markdown，不要代碼塊，不要解釋文字。\n"
            "2) JSON 字段名必須嚴格匹配約定 schema，禁止新增、重命名、翻譯字段。\n"
            "3) 缺失字段必須補齊：對象用 {}, 數組用 [], 數值用 0，布爾用 false；"
            "字符串字段必須填寫有意義的內容，禁止使用空字符串 \"\"。\n"
            "4) 所有枚舉字段只能輸出 schema 允許的值。"
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
        統一的結構化調用入口（已注入深度監控日誌）：
        - 主路徑：instructor + response_model
        - 失敗後：追加嚴格 JSON 提示重試
        - 最終兜底：OpenAI 兼容 API 的 response_format=json_object + Pydantic 效驗
        - instructor_mode: 可選 "JSON"（默認）或 "TOOLS"（需 instructor 支持）
        """
        strict_messages = self._with_strict_json_hint(messages)
        last_error: Optional[Exception] = None
        client = self._instructor_client_for_mode(instructor_mode)

        # === 1. 記錄 Agent 入參和啟動時間 ===
        logger.info(f"\n========== [AGENT 啟動: {self.name}] ==========")
        logger.info(f"[{self.name}] 使用模型: {llm_model} | 最大重試次數: {max_retries}")
        # 截斷打印 messages 避免刷屏，保留最後一條 user prompt 核心內容
        last_msg = strict_messages[-1].get("content", "")[:500] + " ...[已截斷]"
        logger.info(f"[{self.name}] 輸入 Prompt 預覽: {last_msg}")

        total_start_time = time.perf_counter()

        # === 2. 核心重試循環監控 ===
        for attempt in range(max_retries + 1):
            attempt_start = time.perf_counter()
            logger.info(f"[{self.name}] ---> 開始第 {attempt + 1}/{max_retries + 1} 次嘗試...")

            try:
                result = await client.chat.completions.create(
                    model=llm_model,
                    messages=strict_messages,
                    response_model=response_model,
                    temperature=temperature,
                    **kwargs,
                )
                attempt_cost = time.perf_counter() - attempt_start

                # === 3. 記錄成功輸出與耗時 ===
                logger.info(f"[{self.name}] ✅ 第 {attempt + 1} 次嘗試成功! 耗時: {attempt_cost:.2f}秒")
                try:
                    logger.info(f"[{self.name}] 返回結構化數據: \n{result.model_dump_json(indent=2)}")
                except Exception:
                    logger.info(f"[{self.name}] 返回結構化數據: \n{result}")
                return result

            except Exception as e:
                attempt_cost = time.perf_counter() - attempt_start
                last_error = e
                # === 4. 記錄每次失敗的精確原因與耗時 ===
                logger.warning(
                    f"[{self.name}] ❌ 第 {attempt + 1} 次嘗試失敗! 耗時: {attempt_cost:.2f}秒\n"
                    f"[{self.name}] 報錯詳情: {str(e)}"
                )

        # === 5. 兜底路徑監控 ===
        logger.warning(f"[{self.name}] ⚠️ 所有 Instructor 嘗試均失敗，進入原生 JSON 兜底路徑...")
        fallback_start = time.perf_counter()

        raw_resp = await self.raw_client.chat.completions.create(
            model=llm_model,
            messages=strict_messages,
            response_format={"type": "json_object"},
            temperature=temperature,
            **kwargs,
        )

        raw_content = (raw_resp.choices[0].message.content or "").strip()
        fallback_cost = time.perf_counter() - fallback_start
        logger.info(f"[{self.name}] 兜底請求完成，耗時: {fallback_cost:.2f}秒")
        logger.info(f"[{self.name}] 兜底原生輸出: \n{raw_content[:1000]}...[已截斷]")

        try:
            result = response_model.model_validate_json(raw_content)
            logger.info(f"[{self.name}] ✅ 兜底 Pydantic 效驗成功！")
            return result
        except Exception as e:
            total_cost = time.perf_counter() - total_start_time
            logger.error(f"[{self.name}] 🚨 兜底效驗也失敗了！總耗時: {total_cost:.2f}秒. 最終報錯: {str(e)}")
            if last_error is not None:
                raise RuntimeError(
                    f"LLM 結構化輸出失敗（主路徑 + 兜底均失敗）。最後主路徑錯誤: {last_error}; "
                    f"兜底效驗錯誤: {e}; 原始內容片段: {raw_content[:300]}"
                ) from e
            raise

    def _extract_evidence(self, result: Dict[str, Any]) -> Optional[list]:
        """提取證據 - 子類可覆蓋"""
        return None

    def _extract_warnings(self, result: Dict[str, Any]) -> Optional[list]:
        """提取警告 - 子類可覆蓋"""
        return None

    def _check_quality(self, result: Dict[str, Any]) -> list:
        """檢查質量 - 子類可覆蓋"""
        quality_flags = []

        if not result:
            quality_flags.append("empty_result")

        return quality_flags