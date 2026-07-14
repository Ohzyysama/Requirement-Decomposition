#!/usr/bin/env python3
"""
手动启动脚本：串联 M1 三个智能体跑通一句话。

用法（在项目根目录执行，请先激活虚拟环境并安装依赖 pip install -r requirements.txt）：
    export PYTHONPATH=app
    python scripts/run_m1_pipeline.py

或一行：
    PYTHONPATH=app python scripts/run_m1_pipeline.py

可选环境变量：
    REQUIREMENT="你的需求描述"  默认示例见下方 DEFAULT_REQUIREMENT
"""
import asyncio
import json
import os
import sys
from pathlib import Path

# 保证以 app 为根解析 services / schemas / core
REPO_ROOT = Path(__file__).resolve().parent.parent
APP_ROOT = REPO_ROOT / "app"
if str(APP_ROOT) not in sys.path:
    sys.path.insert(0, str(APP_ROOT))

# 加载 .env（优先项目根，再试 app 目录）
from dotenv import load_dotenv
load_dotenv(REPO_ROOT / ".env")
load_dotenv(APP_ROOT / ".env")

from core.config import settings

DEFAULT_REQUIREMENT = "用户登录后可以查看自己的订单列表，并支持按状态筛选和导出为 Excel。"


def _check_openai_key():
    """检查 LLM/OpenAI API Key 是否已配置（支持 OPENAI_API_KEY 或 LLM_API_KEY），未配置时提示并退出。"""
    key = (os.environ.get("OPENAI_API_KEY") or os.environ.get("LLM_API_KEY") or "").strip()
    if not key:
        print("错误: 未设置 API 密钥，无法调用 LLM。")
        print()
        print("请在 .env 中任选一种命名配置：")
        print("  OPENAI_API_KEY=sk-你的密钥  或  LLM_API_KEY=sk-你的密钥")
        print("  OPENAI_BASE_URL=...         或  LLM_BASE_URL=...")
        print("  OPENAI_MODEL=模型名         或  LLM_MODEL=模型名")
        print()
        print("  .env 路径：", REPO_ROOT / ".env")
        sys.exit(1)


async def run_m1_pipeline(requirement_text: str, task_id: str = "manual-run", context: dict = None, config: dict = None):
    """串联三个智能体：Normalizer -> Decomposer -> DependencyClassifier"""
    from schemas.agent import AgentInput
    from services.agents.M1.agents.m1_normalizer_agent import M1NormalizerAgent
    from services.agents.M1.agents.m1_decomposer_agent import M1FunctionalDecomposerAgent
    from services.agents.M1.agents.m1_dependency_agent import M1DependencyClassifierAgent
    from services.agents.M1.focus_from_normalizer import build_focus_node_from_normalizer

    context = context or {}
    # 模型：环境变量 OPENAI_MODEL / LLM_MODEL，否则与 app 配置 LLM_MODEL 一致（勿硬编码 gpt-*，否则在通义等端会 403）
    if config is None:
        config = {}
    if "model" not in config:
        env_model = os.environ.get("OPENAI_MODEL") or os.environ.get("LLM_MODEL")
        config = {**config, "model": env_model or settings.LLM_MODEL}

    # 1) Normalizer
    print("▶ M1-Normalizer 运行中...")
    normalizer = M1NormalizerAgent()
    out_norm = await normalizer.execute(AgentInput(
        task_id=task_id,
        requirement_text=requirement_text,
        context=context,
        config=config,
    ))
    norm_result = out_norm.result.get("result") or {}
    normalized_requirement = norm_result.get("normalized_requirement") or ""
    if not normalized_requirement:
        print("⚠ Normalizer 未返回标准化需求主句，尝试继续后续步骤。")
    print("  ✓ Normalizer 完成")

    # 2) Decomposer
    print("▶ M1-FunctionalDecomposer 运行中...")
    decomposer = M1FunctionalDecomposerAgent()
    focus_node = build_focus_node_from_normalizer(
        norm_result if isinstance(norm_result, dict) else {}
    )
    out_decomp = await decomposer.execute(AgentInput(
        task_id=task_id,
        requirement_text=requirement_text,
        normalized_requirement=normalized_requirement,
        artifacts={
            "focus_node": focus_node,
            "normalizer_result": norm_result,
        },
        context=context,
        config=config,
    ))
    decomp_result = out_decomp.result.get("result") or {}
    from services.agents.M1.schemas.m1_decomposer import function_list_to_function_tree_dict

    function_list = decomp_result.get("function_list") or []
    function_tree = function_list_to_function_tree_dict(function_list)
    if isinstance(function_tree, dict):
        pass
    else:
        function_tree = function_tree.model_dump() if hasattr(function_tree, "model_dump") else function_tree
    if not function_tree or not function_list:
        print("⚠ Decomposer 未返回功能列表或无法派生树，跳过 Dependency。")
        return {
            "normalized_requirement": normalized_requirement,
            "function_list": function_list,
            "function_tree": None,
            "dependencies": None,
            "normalizer_output": norm_result,
            "decomposer_output": decomp_result,
        }
    print("  ✓ Decomposer 完成")

    # 3) DependencyClassifier（与协调器一致：function_list + normalizer_result + core_flow）
    print("▶ M1-DependencyClassifier 运行中...")
    dep_agent = M1DependencyClassifierAgent()
    core_flow = decomp_result.get("core_flow") or []
    out_dep = await dep_agent.execute(AgentInput(
        task_id=task_id,
        requirement_text=requirement_text,
        artifacts={
            "function_list": function_list,
            "normalizer_result": norm_result,
            "core_flow": core_flow,
        },
        context=context,
        config=config,
    ))
    dep_result = out_dep.result.get("result") or {}
    dependencies = dep_result.get("dependencies")
    if isinstance(dependencies, list):
        pass
    else:
        dependencies = [d.model_dump() if hasattr(d, "model_dump") else d for d in (dependencies or [])]
    print("  ✓ DependencyClassifier 完成")

    return {
        "normalized_requirement": normalized_requirement,
        "function_list": function_list,
        "function_tree": function_tree,
        "dependencies": dependencies,
        "normalizer_output": norm_result,
        "decomposer_output": decomp_result,
        "dependency_output": dep_result,
    }


def main():
    _check_openai_key()

    requirement = os.environ.get("REQUIREMENT", DEFAULT_REQUIREMENT)
    print("=" * 60)
    print("M1 三智能体串联（一句话跑通）")
    print("=" * 60)
    print("需求:", requirement)
    print()

    try:
        result = asyncio.run(run_m1_pipeline(requirement))
    except Exception as e:
        print("运行失败:", e)
        if os.environ.get("DEBUG"):
            import traceback
            traceback.print_exc()
        sys.exit(1)

    print()
    print("=" * 60)
    print("结果摘要")
    print("=" * 60)
    print("标准化需求:", (result.get("normalized_requirement") or "")[:200], "..." if len((result.get("normalized_requirement") or "")) > 200 else "")
    print()
    out_path = REPO_ROOT / "logs" / "m1_pipeline_result.json"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    # 序列化时把可能存在的 Pydantic 模型转为 dict
    def to_serializable(obj):
        if hasattr(obj, "model_dump"):
            return obj.model_dump()
        if isinstance(obj, dict):
            return {k: to_serializable(v) for k, v in obj.items()}
        if isinstance(obj, list):
            return [to_serializable(v) for v in obj]
        return obj
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(to_serializable(result), f, ensure_ascii=False, indent=2)
    print("完整结果已写入:", out_path)
    print("=" * 60)


if __name__ == "__main__":
    main()
