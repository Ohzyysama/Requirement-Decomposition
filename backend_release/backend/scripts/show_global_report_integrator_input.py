#!/usr/bin/env python3
"""
调试脚本：跑完整 Orchestrator 管线，在生成全局报告前打印传给 M2 整合智能体的输入。

打印内容（与线上一致）：
  0) tree_version、current_ids、function_list（JSON）、per_scope_digest — 用于对照「裁剪后仍保留的节点」；
     同 rule_id 可对应多条命中（多行），列表按规则键排序，不对跨 episode 做节点并集合并。
  1) AgentInput — global_report_builder.build_global_report 传入 execute() 的结构（JSON）
  2) assessment_summary — M2EvaluationIntegratorAgent 内部拼给 LLM 的分析正文（user 消息核心）

管线结束后：
  **3) Rollup 选用的 evaluation_episodes**（与 ``aggregate_episodes`` / ``select_episodes_for_rollup`` 一致）：
     每条 episode 的一致性评分、以及 ``consistency_result`` 中未通过规则（critical_issues；warnings/rule_results 中
     ``passed is False``）涉及的 ``affected_nodes``。精简表打印到终端，完整结构化结果写入
     ``logs/show_global_report_rollup_episodes.json``。

  **4) 各作用域 M2 尾部 Integrator** 写入 episode 的 ``bundle.evaluation``（叙事摘要）；与最终「全局报告」
     那一次 Integrator 调用相互独立。

数据说明（必读）：
  - 全局聚合使用的 episode **子集**由 ``select_episodes_for_rollup`` 决定（当前 ``tree_version`` 的全树一条 +
    仍挂在树上的各子树根最新 subtree 等），与 ``result["evaluation_episodes"]`` **原始列表长度**不必一致。
  - 协调层在追加新的 ``full_tree`` episode 时会 **丢弃更早的全树 episode**（仅保留最新一条全树快照）；
    因此无法从该列表还原「历史上每一轮全树评估」，rollup 也只能基于仍存在的快照。

管线结束后会将 **完整最终 result** 写入项目下 ``logs/show_global_report_integrator_result.json``（便于与终端节选对照）。
若需把完整 JSON 再打一遍到标准输出，可设置环境变量 ``DUMP_RESULT_STDOUT=1``（体积可能很大）。

用法（在项目根目录执行，需已配置 .env 中的 LLM 密钥；将触发完整 M1+M2 管线，产生较多 Token 费用）：

    python scripts/show_global_report_integrator_input.py

（脚本会自动把项目根目录加入 sys.path，无需手动设置 PYTHONPATH。）

Windows PowerShell 亦可：
    py scripts/show_global_report_integrator_input.py

可选环境变量：
    REQUIREMENT="你的需求描述"  — 覆盖下方默认示例需求；不写则使用 DEFAULT_REQUIREMENT。
    DUMP_RESULT_STDOUT=1  — 将完整 result JSON 再打印到终端（可能很长）。
    INTEGRATOR_EPISODES_FULL_JSON=1  — 额外将每条 episode 的完整 ``bundle.evaluation`` 写入
        ``logs/show_global_report_integrator_episodes_full.json``。

配置：
    context.config 含 max_feasibility_refinement_depth=2；model 来自 OPENAI_MODEL / LLM_MODEL 或 core.config.settings.LLM_MODEL。

说明：
    包装函数会先打印再调用真实的 build_global_report，全局报告 Integrator 仅调用 LLM 一次；
    aggregate_episodes 会执行两次（打印路径一次 + 真实 build 一次），开销可忽略。
"""
from __future__ import annotations

import asyncio
import json
import os
import sys
import uuid
from pathlib import Path
from typing import Any, Dict, List, Set

REPO_ROOT = Path(__file__).resolve().parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from dotenv import load_dotenv

APP_ROOT = REPO_ROOT / "app"
load_dotenv(REPO_ROOT / ".env")
load_dotenv(APP_ROOT / ".env")

from app.core.config import settings

from app.services.coordinator.evaluation_rollup import (
    collect_function_list_node_ids,
    consistency_feasibility_from_episode_bundle,
    select_episodes_for_rollup,
)


DEFAULT_REQUIREMENT = (
    "实现一个在线课程平台，支持学生注册登录、浏览课程列表、购买课程、观看视频，并提供作业提交和老师评分功能。"
)


def _consistency_non_pass_node_ids(consistency_result: Dict[str, Any]) -> List[str]:
    """
    从单次 consistency_result dict 收集「门禁语义」相关节点 id。

    与 ``AgentInvoker.consistency_evaluation_passes`` 对齐：critical_issues 非空即视为未通过；
    节点列表来自 critical_issues 全部条目的 affected_nodes，以及 warnings / rule_results 中
    ``passed is False`` 的条目。
    """
    seen: Set[str] = set()
    out: List[str] = []

    def _push_nodes(nodes: object) -> None:
        if not isinstance(nodes, list):
            return
        for n in nodes:
            s = str(n).strip()
            if s and s not in seen:
                seen.add(s)
                out.append(s)

    crit = consistency_result.get("critical_issues") or []
    if isinstance(crit, list):
        for item in crit:
            if isinstance(item, dict):
                _push_nodes(item.get("affected_nodes"))

    for key in ("warnings", "rule_results"):
        items = consistency_result.get(key) or []
        if not isinstance(items, list):
            continue
        for item in items:
            if not isinstance(item, dict):
                continue
            if item.get("passed") is not False:
                continue
            _push_nodes(item.get("affected_nodes"))

    return out


def _rollup_payload_for_result(result: Dict[str, Any]) -> Dict[str, Any]:
    """构建与 aggregate_episodes 相同的 rollup episode 子集及每条一致性摘要。"""
    fl = result.get("function_list")
    raw_eps = result.get("evaluation_episodes") or []
    tv = int(result.get("tree_version", 0) or 0)
    current_ids = collect_function_list_node_ids(fl)
    eps_list = raw_eps if isinstance(raw_eps, list) else []
    selected = select_episodes_for_rollup(
        eps_list,
        current_tree_version=tv,
        current_ids=current_ids,
    )

    entries: List[Dict[str, Any]] = []
    for ep in selected:
        if not isinstance(ep, dict):
            continue
        bundle = ep.get("bundle") if isinstance(ep.get("bundle"), dict) else {}
        cr, _fr = consistency_feasibility_from_episode_bundle(bundle)

        sk = ep.get("scope")
        scope_str = sk.value if hasattr(sk, "value") else str(sk or "")
        root = ep.get("scope_root_node_id") or ep.get("parent_node_id")

        score: Any = None
        if isinstance(cr, dict):
            try:
                score = round(float(cr["score"]), 4)
            except (KeyError, TypeError, ValueError):
                score = cr.get("score")

        node_ids = _consistency_non_pass_node_ids(cr) if isinstance(cr, dict) else []

        entries.append(
            {
                "episode_id": ep.get("episode_id"),
                "scope": scope_str,
                "scope_root_node_id": root,
                "tree_version": ep.get("tree_version", 0),
                "consistency_score": score,
                "consistency_non_pass_node_ids": node_ids,
                "consistency_critical_issues_count": len(cr.get("critical_issues") or [])
                if isinstance(cr, dict)
                else 0,
            }
        )

    return {
        "tree_version": tv,
        "current_node_count": len(current_ids),
        "raw_evaluation_episode_count": len([e for e in eps_list if isinstance(e, dict)]),
        "rollup_selected_episode_count": len(entries),
        "rollup_note": (
            "与 global_report_builder.aggregate_episodes 使用的 episode 子集一致；"
            "原始列表含多条 full_tree 时仅当前 tree_version 的一条参与 rollup。"
        ),
        "episodes": entries,
    }


def _write_and_print_rollup_report(result: Dict[str, Any], log_dir: Path) -> None:
    payload = _rollup_payload_for_result(result)
    out_path = log_dir / "show_global_report_rollup_episodes.json"
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2, default=str)

    print()
    print("=" * 60)
    print("3) Rollup 选用的 evaluation_episodes（与全局报告 aggregate_episodes 一致）")
    print("=" * 60)
    print(
        "说明: 下列条目经 select_episodes_for_rollup 筛选；"
        "consistency_non_pass_node_ids 来自 consistency_result 中 "
        "critical_issues 全部条目 + warnings/rule_results 中 passed=False 的 affected_nodes。"
    )
    print(f"tree_version={payload['tree_version']}  "
          f"原始 episode 数={payload['raw_evaluation_episode_count']}  "
          f"rollup 选用={payload['rollup_selected_episode_count']}")
    print("详细 JSON:", out_path)
    print()

    for i, ep in enumerate(payload.get("episodes") or [], start=1):
        print("-" * 60)
        print(
            f"#{i}  {ep.get('episode_id')}  scope={ep.get('scope')}  "
            f"root={ep.get('scope_root_node_id')}  tv={ep.get('tree_version')}"
        )
        print(f"    consistency_score={ep.get('consistency_score')}  "
              f"critical_issues={ep.get('consistency_critical_issues_count')}")
        nodes = ep.get("consistency_non_pass_node_ids") or []
        print(f"    consistency_non_pass_node_ids ({len(nodes)}): {nodes}")
    print("=" * 60)


def _maybe_write_full_integrator_episodes_json(
    episodes: object,
    log_dir: Path,
) -> None:
    if os.environ.get("INTEGRATOR_EPISODES_FULL_JSON", "").strip() not in (
        "1",
        "true",
        "yes",
    ):
        return
    if not isinstance(episodes, list):
        return
    rows: List[Dict[str, Any]] = []
    for ep in episodes:
        if not isinstance(ep, dict):
            continue
        bundle = ep.get("bundle") if isinstance(ep.get("bundle"), dict) else {}
        ev = bundle.get("evaluation") if isinstance(bundle, dict) else {}
        rows.append(
            {
                "episode_id": ep.get("episode_id"),
                "scope": ep.get("scope"),
                "tree_version": ep.get("tree_version"),
                "scope_root_node_id": ep.get("scope_root_node_id"),
                "bundle_evaluation": ev if isinstance(ev, dict) else {},
            }
        )
    path = log_dir / "show_global_report_integrator_episodes_full.json"
    with open(path, "w", encoding="utf-8") as f:
        json.dump(rows, f, ensure_ascii=False, indent=2, default=str)
    print()
    print("INTEGRATOR_EPISODES_FULL_JSON: 已写入完整 bundle.evaluation ->", path)


def _scope_label(ep: dict) -> str:
    sk = ep.get("scope")
    if hasattr(sk, "value"):
        sk = sk.value
    sk = str(sk or "")
    root = ep.get("scope_root_node_id") or ep.get("parent_node_id")
    if sk == "subtree" and root:
        return f"subtree @ {root}"
    if sk:
        return sk
    return "unknown_scope"


def _print_per_scope_integrator_reports(episodes: object) -> None:
    """打印每条 evaluation_episode 中 Integrator 写入的 bundle.evaluation（各次 M2 尾部综合报告）。"""
    print()
    print("=" * 60)
    print("4) 各作用域 M2 整合智能体报告（evaluation_episodes[].bundle.evaluation，原始列表全量）")
    print("=" * 60)
    if not isinstance(episodes, list) or not episodes:
        print("（无 evaluation_episodes）")
        print("=" * 60)
        return

    for idx, ep in enumerate(episodes, start=1):
        if not isinstance(ep, dict):
            continue
        bundle = ep.get("bundle") if isinstance(ep.get("bundle"), dict) else {}
        ev = bundle.get("evaluation") if isinstance(bundle, dict) else None
        if not isinstance(ev, dict):
            ev = {}

        eid = ep.get("episode_id", "")
        tv = ep.get("tree_version", "")
        label = _scope_label(ep)

        print()
        print("-" * 60)
        print(f"#{idx}  episode_id={eid}  tree_version={tv}  scope={label}")
        print("-" * 60)

        if not ev:
            print("（bundle.evaluation 为空，可能该次 Integrator 未写入或失败）")
            continue

        rec = ev.get("recommendation")
        summ = ev.get("summary") or ""
        overall = ev.get("overall_score")
        risk = ev.get("risk_level")
        cs = ev.get("consistency_score")
        fs = ev.get("feasibility_score")
        skipped = ev.get("feasibility_evaluation_skipped")
        iscope = ev.get("integration_scope")

        meta_parts = [
            f"overall_score={overall}",
            f"consistency_score={cs}",
            f"feasibility_score={fs}",
            f"risk_level={risk}",
        ]
        if skipped is not None:
            meta_parts.append(f"feasibility_evaluation_skipped={skipped}")
        if iscope:
            meta_parts.append(f"integration_scope={iscope}")
        print(" | ".join(str(p) for p in meta_parts))
        print()
        print("recommendation:")
        print(rec if rec is not None else "(无)")
        print()
        print("summary:")
        print(summ if summ else "(无)")

    print()
    print("=" * 60)


def _check_openai_key() -> None:
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


def _patch_global_report_printer() -> None:
    """将 orchestrator 模块内的 build_global_report 替换为「先打印、再调用原版」。"""
    import app.services.coordinator.orchestrator as orch_mod
    from app.schemas.agent import AgentInput
    from app.services.coordinator.evaluation_rollup import collect_function_list_node_ids
    from app.services.coordinator.global_report_builder import (
        aggregate_episodes,
        build_global_report as _real_build_global_report,
    )

    async def _print_then_build(context: object, m2_integrator: object):
        episodes = getattr(context, "artifacts", {}).get("evaluation_episodes") or []
        if not episodes:
            print()
            print("-" * 60)
            print("[全局报告] 无 evaluation_episodes，跳过 Integrator 输入打印")
            print("-" * 60)
            print()
            return await _real_build_global_report(context, m2_integrator)

        function_list = getattr(context, "artifacts", {}).get("function_list")
        tree_version = int(getattr(context, "tree_version", 0) or 0)
        consistency_agg, feasibility_agg, per_scope_digest = aggregate_episodes(
            episodes, function_list, tree_version
        )

        current_ids = sorted(collect_function_list_node_ids(function_list))
        print()
        print("=" * 60)
        print("0) 当前树 / function_list / 参与聚合的 episode 摘要")
        print("=" * 60)
        print(
            "说明: 全局报告聚合会先按当前树裁剪失效节点，再保留每条命中（同一 rule_id 可出现多行）；"
            "列表按规则键稳定排序。单条内的 affected_nodes 仍可能含多个 id（M2 原始语义）；"
            "若要看 episode 原文请查 evaluation_episodes 或写入的 result JSON。"
        )
        print(f"tree_version: {tree_version}")
        print(f"节点数: {len(current_ids)}")
        print("current_ids:", current_ids)
        print()
        print("function_list（JSON）:")
        print(json.dumps(function_list, ensure_ascii=False, indent=2, default=str))
        print()
        print("per_scope_digest:")
        print(json.dumps(per_scope_digest, ensure_ascii=False, indent=2, default=str))
        print("=" * 60)

        task_id = getattr(context, "conversation_id", "") or ""
        agent_input = AgentInput(
            task_id=task_id,
            requirement_text=getattr(context, "requirement_text", "") or "",
            artifacts={
                "consistency_result": consistency_agg,
                "feasibility_result": feasibility_agg,
            },
            config=(getattr(context, "config", None) or {}),
        )

        print()
        print("=" * 60)
        print("1) AgentInput（传给 M2EvaluationIntegratorAgent.execute）")
        print("=" * 60)
        print(json.dumps(agent_input.model_dump(), ensure_ascii=False, indent=2, default=str))

        cs = m2_integrator._calculate_consistency_score(consistency_agg)
        fs = m2_integrator._calculate_feasibility_score(feasibility_agg)
        overall = m2_integrator._calculate_overall_score(cs, fs)
        assessment = m2_integrator._build_assessment_summary(
            consistency_agg, feasibility_agg, overall
        )

        print()
        print("=" * 60)
        print("2) assessment_summary（整合智能体内部传给 LLM 的分析正文）")
        print("=" * 60)
        print(assessment)
        print("=" * 60)
        print()

        return await _real_build_global_report(context, m2_integrator)

    orch_mod.build_global_report = _print_then_build


async def _run() -> None:
    _patch_global_report_printer()

    from app.core.enums import TaskMode
    from app.services.coordinator.context import CoordinatorContext
    from app.services.coordinator.orchestrator import Orchestrator

    requirement = os.environ.get("REQUIREMENT", DEFAULT_REQUIREMENT).strip() or DEFAULT_REQUIREMENT
    env_model = os.environ.get("OPENAI_MODEL") or os.environ.get("LLM_MODEL")
    config = {
        "max_feasibility_refinement_depth": 2,
        "model": env_model or settings.LLM_MODEL,
    }

    task_id = f"show-gr-input-{uuid.uuid4().hex[:12]}"
    context = CoordinatorContext(
        conversation_id=task_id,
        requirement_text=requirement,
        mode=TaskMode.AUTO,
        config=config,
    )

    print("=" * 60)
    print("展示全局报告 Integrator 输入（完整 Orchestrator 管线）")
    print("=" * 60)
    print("conversation_id:", task_id)
    print("max_feasibility_refinement_depth:", config["max_feasibility_refinement_depth"])
    print("model:", config["model"])
    print("需求:", requirement[:200] + ("..." if len(requirement) > 200 else ""))
    print()

    orch = Orchestrator()
    result = await orch.run(context)

    log_dir = REPO_ROOT / "logs"
    log_dir.mkdir(parents=True, exist_ok=True)
    out_json = log_dir / "show_global_report_integrator_result.json"
    with open(out_json, "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False, indent=2, default=str)

    print()
    print("=" * 60)
    print("管线已完成")
    print("=" * 60)
    print("完整最终结果 JSON 已写入:", out_json)
    if os.environ.get("DUMP_RESULT_STDOUT", "").strip() in ("1", "true", "yes"):
        print()
        print("--- result（stdout，可能很长）---")
        print(json.dumps(result, ensure_ascii=False, indent=2, default=str))

    if isinstance(result, dict):
        _write_and_print_rollup_report(result, log_dir)
        _maybe_write_full_integrator_episodes_json(
            result.get("evaluation_episodes"), log_dir
        )
        _print_per_scope_integrator_reports(result.get("evaluation_episodes"))

    gr = (result.get("global_report") or {}) if isinstance(result, dict) else {}
    summary = gr.get("summary") or ""
    print()
    print("global_report.summary（节选）:")
    print((summary[:500] + "...") if len(summary) > 500 else summary)
    er = result.get("evaluation_rollup") or {}
    if er:
        print()
        print(
            "evaluation_rollup 摘要: node_count=",
            er.get("current_node_count"),
            "open_rule_hits=",
            er.get("open_rule_hits"),
            "still_referenced_node_ids=",
            er.get("still_referenced_node_ids"),
        )
    print("=" * 60)


def main() -> None:
    _check_openai_key()
    try:
        asyncio.run(_run())
    except KeyboardInterrupt:
        print("\n已中断")
        sys.exit(130)
    except Exception as e:
        print("运行失败:", e)
        if os.environ.get("DEBUG"):
            import traceback

            traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
