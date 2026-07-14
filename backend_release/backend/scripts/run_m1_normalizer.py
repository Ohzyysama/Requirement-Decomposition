#!/usr/bin/env python3
"""
单独跑 M1 预处理（Normalizer）智能体，便于查看结构化输出。

用法（项目根目录，已安装依赖并配置 API Key）：
    python scripts/run_m1_normalizer.py

（脚本会把项目根目录加入 sys.path，使 `app.*` 包内导入与主程序一致；也可手动：
    PYTHONPATH=. python scripts/run_m1_normalizer.py）

或：
    REQUIREMENT="你的需求" python scripts/run_m1_normalizer.py

完整结果会写入 logs/m1_normalizer_result.json；终端打印摘要 + 完整 result 字典。
"""
import asyncio
import json
import os
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
APP_ROOT = REPO_ROOT / "app"
# 与包内 `from app.xxx` 一致：须以仓库根为根，而不是仅把 app/ 当作顶层
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from dotenv import load_dotenv
load_dotenv(REPO_ROOT / ".env")
load_dotenv(APP_ROOT / ".env")

from app.core.config import settings

DEFAULT_REQUIREMENT = "用户登录后可以查看自己的订单列表，并支持按状态筛选和导出为 Excel。"


def _check_openai_key():
    key = (os.environ.get("OPENAI_API_KEY") or os.environ.get("LLM_API_KEY") or "").strip()
    if not key:
        print("错误: 未设置 OPENAI_API_KEY 或 LLM_API_KEY，无法调用 LLM。")
        print("参见 scripts/run_m1_pipeline.py 顶部的 .env 说明。")
        sys.exit(1)


def _to_jsonable(obj):
    if hasattr(obj, "model_dump"):
        return obj.model_dump()
    if isinstance(obj, dict):
        return {k: _to_jsonable(v) for k, v in obj.items()}
    if isinstance(obj, list):
        return [_to_jsonable(v) for v in obj]
    return obj


async def run_normalizer(requirement_text: str, task_id: str = "normalizer-preview") -> dict:
    from app.schemas.agent import AgentInput
    from app.services.agents.M1.agents.m1_normalizer_agent import M1NormalizerAgent

    config = {}
    env_model = os.environ.get("OPENAI_MODEL") or os.environ.get("LLM_MODEL")
    if env_model:
        config["model"] = env_model
    else:
        config["model"] = settings.LLM_MODEL

    agent = M1NormalizerAgent()
    out = await agent.execute(
        AgentInput(
            task_id=task_id,
            requirement_text=requirement_text,
            context={},
            config=config,
        )
    )
    meta = _to_jsonable(out.meta) if out.meta else {}
    # BaseAgentOutput 未声明 agent_name，构造时传入的字段会被丢弃；名称在 meta.agent
    return {
        "agent": meta.get("agent") or "M1-Normalizer",
        "result": _to_jsonable(out.result),
        "evidence": out.evidence,
        "warnings": out.warnings,
        "quality_flags": out.quality_flags,
        "meta": meta,
    }


def main():
    _check_openai_key()
    requirement = os.environ.get("REQUIREMENT", DEFAULT_REQUIREMENT)

    print("=" * 60)
    print("M1 Normalizer（预处理）单独运行")
    print("=" * 60)
    print("需求:", requirement[:500] + ("…" if len(requirement) > 500 else ""))
    print()

    try:
        bundle = asyncio.run(run_normalizer(requirement))
    except Exception as e:
        print("调用失败:", e)
        if os.environ.get("DEBUG"):
            import traceback
            traceback.print_exc()
        sys.exit(1)

    inner = (bundle.get("result") or {}).get("result") or {}

    print("— meta —")
    print(json.dumps(bundle.get("meta") or {}, ensure_ascii=False, indent=2))
    print()
    print("— evidence —", bundle.get("evidence"))
    print("— warnings —", bundle.get("warnings"))
    print("— quality_flags —", bundle.get("quality_flags"))
    print()
    print("— 预处理结构化结果 result.result（完整）—")
    print(json.dumps(inner, ensure_ascii=False, indent=2))
    print()

    out_path = REPO_ROOT / "logs" / "m1_normalizer_result.json"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(bundle, f, ensure_ascii=False, indent=2)
    print("已写入:", out_path)
    print("=" * 60)


if __name__ == "__main__":
    main()
