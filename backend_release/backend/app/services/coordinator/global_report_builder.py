"""
全局报告生成器

在管线所有 M2 episode 完成后，聚合跨 episode 的一致性/可实现性结果，
调用 M2EvaluationIntegratorAgent 生成一份全局可读报告（LLM 叙事）。

若 ``select_episodes_for_rollup`` 后仅一条 ``full_tree`` 且 ``tree_version`` 与当前一致、
且存在根 ``artifacts["evaluation"]``，则短路复用该结果，不再二次调用 Integrator LLM。

聚合策略：按当前树裁剪失效节点后保留每条规则命中（同一 rule_id 可多行），并按规则键排序便于阅读。

不修改 context；调用方负责把结果写入 context.artifacts["global_report"]。
"""
from __future__ import annotations

import logging
from typing import Any, Dict, List, Optional, Set, Tuple

from app.schemas.agent import AgentInput
from app.schemas.evaluation_episodes import EvaluationScopeKind
from app.services.coordinator.evaluation_rollup import (
    collect_function_list_node_ids,
    consistency_feasibility_from_episode_bundle,
    prune_rule_like_item_to_current_ids,
    select_episodes_for_rollup,
)

logger = logging.getLogger(__name__)


def _rule_group_key(item: Dict[str, Any]) -> str:
    return str(
        item.get("rule_id")
        or item.get("rule_name")
        or item.get("description")
        or ""
    )


def _aggregate_rule_like_list(
    raw_items: List[Dict[str, Any]],
    current_ids: Set[str],
) -> List[Dict[str, Any]]:
    """
    裁剪到当前树仍存在的节点 / 证据；保留每一条命中（同一 rule_id 可出现多行，不做跨命中合并）。
    结果按 ``rule_id → rule_name → description`` 分组键 **稳定排序**，使同规则条目在列表中相邻。
    """
    pruned: List[Dict[str, Any]] = []
    for it in raw_items:
        if not isinstance(it, dict):
            continue
        p = prune_rule_like_item_to_current_ids(it, current_ids)
        if p is None:
            continue
        pruned.append(p)

    return sorted(pruned, key=_rule_group_key)


def _avg(values: List[float]) -> float:
    return sum(values) / len(values) if values else 0.0


def _episode_scope_str(ep: Dict[str, Any]) -> str:
    """与 aggregate_episodes / evaluation_rollup 对 scope 的归一化一致。"""
    scope_raw = ep.get("scope", EvaluationScopeKind.FULL_TREE.value)
    if isinstance(scope_raw, EvaluationScopeKind):
        return scope_raw.value
    s = str(scope_raw).strip().lower()
    if s in ("subtree", EvaluationScopeKind.FULL_TREE.value):
        return s
    return EvaluationScopeKind.FULL_TREE.value


def _try_global_report_short_circuit(
    context: Any,
    *,
    episodes: List[Any],
    function_list: Any,
    tree_version: int,
) -> Optional[Dict[str, Any]]:
    """
    若 rollup 后仅一条 full_tree 且 tree_version 与当前一致（无并列子树 episode），
    则复用根层 ``artifacts["evaluation"]``，不再调用 Integrator LLM。
    """
    current_ids = collect_function_list_node_ids(function_list)
    raw_eps = [e for e in episodes if isinstance(e, dict)]
    selected = select_episodes_for_rollup(
        raw_eps,
        current_tree_version=tree_version,
        current_ids=current_ids,
    )
    if len(selected) != 1:
        return None
    ep = selected[0]
    if _episode_scope_str(ep) != EvaluationScopeKind.FULL_TREE.value:
        return None
    if int(ep.get("tree_version", 0) or 0) != int(tree_version):
        return None

    arts = getattr(context, "artifacts", None)
    if not isinstance(arts, dict):
        return None
    ev = arts.get("evaluation")
    if not isinstance(ev, dict):
        return None
    # 根 Integrator 落库的 IntegratedEvaluationResult 形态
    if "summary" not in ev and "overall_score" not in ev:
        return None

    _, _, per_scope_digest = aggregate_episodes(
        [ep], function_list, tree_version
    )
    task_id = getattr(context, "conversation_id", "")
    logger.info(
        f"[{task_id}] 全局报告短路：单条全树 episode(tv={tree_version})，复用根 evaluation"
    )
    return {
        "summary": ev.get("summary") or "",
        "recommendation": ev.get("recommendation") or "",
        "overall_score": float(ev.get("overall_score") or 0.0),
        "risk_level": ev.get("risk_level") or "none",
        "per_scope_digest": per_scope_digest,
    }


def aggregate_episodes(
    evaluation_episodes: Any,
    function_list: Any,
    current_tree_version: int,
) -> Tuple[Dict[str, Any], Dict[str, Any], List[Dict[str, Any]]]:
    """
    从相关 episode 集合聚合一致性 + 可实现性结果。

    返回 (consistency_agg, feasibility_agg, per_scope_digest)
    - consistency_agg / feasibility_agg 结构与单次 M2 评估结果相同，可直接送入 Integrator
    - per_scope_digest 为每条 episode 的轻量摘要列表，供展示用
    - issues / warnings：先按当前 function_list 裁剪节点与 evidence；保留全部命中条数（同 rule_id 可多行）；
      再按规则键稳定排序；已拆分或删除的节点不再出现。
    """
    current_ids = collect_function_list_node_ids(function_list)
    raw_eps = [e for e in (evaluation_episodes or []) if isinstance(e, dict)]
    episodes = select_episodes_for_rollup(
        raw_eps,
        current_tree_version=current_tree_version,
        current_ids=current_ids,
    )

    c_issues: List[Dict[str, Any]] = []
    c_warnings: List[Dict[str, Any]] = []
    c_scores: List[float] = []
    f_issues: List[Dict[str, Any]] = []
    f_warnings: List[Dict[str, Any]] = []
    f_scores: List[float] = []
    latest_fpa: Optional[Dict[str, Any]] = None
    per_scope_digest: List[Dict[str, Any]] = []

    for ep in episodes:
        bundle = ep.get("bundle") or {}
        cr, fr = consistency_feasibility_from_episode_bundle(bundle)

        scope_raw = ep.get("scope", "full_tree")
        scope_str = scope_raw.value if hasattr(scope_raw, "value") else str(scope_raw)
        scope_root = ep.get("scope_root_node_id") or ep.get("parent_node_id")

        digest_entry: Dict[str, Any] = {
            "episode_id": ep.get("episode_id"),
            "scope": scope_str,
            "scope_root_node_id": scope_root,
            "tree_version": ep.get("tree_version", 0),
        }

        if isinstance(cr, dict):
            c_issues.extend(cr.get("critical_issues") or [])
            c_warnings.extend(cr.get("warnings") or [])
            try:
                score = float(cr["score"])
                c_scores.append(score)
                digest_entry["consistency_score"] = round(score, 4)
            except (KeyError, TypeError, ValueError):
                pass

        if isinstance(fr, dict):
            f_issues.extend(fr.get("critical_issues") or [])
            f_warnings.extend(fr.get("warnings") or [])
            try:
                score = float(fr["score"])
                f_scores.append(score)
                digest_entry["feasibility_score"] = round(score, 4)
            except (KeyError, TypeError, ValueError):
                pass
            if fr.get("fpa_analysis"):
                latest_fpa = fr["fpa_analysis"]

        per_scope_digest.append(digest_entry)

    c_agg_issues = _aggregate_rule_like_list(c_issues, current_ids)
    c_agg_warnings = _aggregate_rule_like_list(c_warnings, current_ids)
    f_agg_issues = _aggregate_rule_like_list(f_issues, current_ids)
    f_agg_warnings = _aggregate_rule_like_list(f_warnings, current_ids)

    c_avg = _avg(c_scores)
    f_avg = _avg(f_scores)

    consistency_agg: Dict[str, Any] = {
        "score": round(c_avg, 4),
        "total_checks": len(c_agg_issues) + len(c_agg_warnings),
        "passed_checks": 0,
        "critical_issues": c_agg_issues,
        "warnings": c_agg_warnings,
    }
    feasibility_agg: Dict[str, Any] = {
        "score": round(f_avg, 4),
        "total_checks": len(f_agg_issues) + len(f_agg_warnings),
        "passed_checks": 0,
        "critical_issues": f_agg_issues,
        "warnings": f_agg_warnings,
    }
    if latest_fpa is not None:
        feasibility_agg["fpa_analysis"] = latest_fpa

    return consistency_agg, feasibility_agg, per_scope_digest


async def build_global_report(
    context: Any,
    m2_integrator: Any,
) -> Dict[str, Any]:
    """
    聚合所有 evaluation_episodes，调用 M2EvaluationIntegratorAgent 生成全局报告。

    单条全树 episode 且无子树评估时短路复用根 ``evaluation``，跳过 Integrator LLM。

    context: CoordinatorContext（类型标注用 Any 避免循环导入）
    m2_integrator: M2EvaluationIntegratorAgent 实例

    返回 dict：{summary, recommendation, overall_score, risk_level, per_scope_digest}
    调用方写入 context.artifacts["global_report"]。
    """
    task_id = getattr(context, "conversation_id", "")
    logger.info(f"[{task_id}] 生成全局报告开始")

    episodes = context.artifacts.get("evaluation_episodes") or []
    function_list = context.artifacts.get("function_list")
    tree_version = int(getattr(context, "tree_version", 0) or 0)

    if not episodes:
        logger.warning(f"[{task_id}] 无 evaluation_episodes，跳过全局报告生成")
        return {
            "summary": "",
            "recommendation": "",
            "overall_score": 0.0,
            "risk_level": "none",
            "per_scope_digest": [],
        }

    try:
        short = _try_global_report_short_circuit(
            context,
            episodes=episodes,
            function_list=function_list,
            tree_version=tree_version,
        )
        if short is not None:
            return short

        consistency_agg, feasibility_agg, per_scope_digest = aggregate_episodes(
            episodes, function_list, tree_version
        )

        agent_input = AgentInput(
            task_id=task_id,
            requirement_text=context.requirement_text or "",
            artifacts={
                "consistency_result": consistency_agg,
                "feasibility_result": feasibility_agg,
            },
            config=(context.config or {}),
        )

        output = await m2_integrator.execute(agent_input)
        payload = output.get_payload()

        result: Dict[str, Any] = {
            "summary": payload.get("summary") or "",
            "recommendation": payload.get("recommendation") or "",
            "overall_score": float(payload.get("overall_score") or 0.0),
            "risk_level": payload.get("risk_level") or "none",
            "per_scope_digest": per_scope_digest,
        }
        logger.info(
            f"[{task_id}] 全局报告生成完成: recommendation={result['recommendation']}"
        )
        return result

    except Exception as e:
        logger.error(f"[{task_id}] 全局报告生成失败: {e}", exc_info=True)
        return {
            "summary": "",
            "recommendation": "",
            "overall_score": 0.0,
            "risk_level": "none",
            "per_scope_digest": [],
            "error": str(e),
        }
