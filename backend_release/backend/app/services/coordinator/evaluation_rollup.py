"""
跨 evaluation_episodes 的确定性汇总（rollup）与 superseded 判定。
"""
from __future__ import annotations

import copy
from typing import Any, Dict, Iterable, List, Optional, Set, Tuple

from app.schemas.evaluation_episodes import EvaluationRollup, EvaluationScopeKind


def collect_function_list_node_ids(function_list: Any) -> Set[str]:
    """从 function_list 行表收集节点 id。"""
    out: Set[str] = set()
    if not isinstance(function_list, list):
        return out
    for row in function_list:
        if not isinstance(row, dict):
            continue
        nid = row.get("id")
        if nid is None:
            continue
        s = str(nid).strip()
        if s:
            out.add(s)
    return out


def _severity_rank(sev: str) -> int:
    s = (sev or "").lower()
    if s == "error":
        return 3
    if s == "warning":
        return 2
    if s == "info":
        return 1
    return 0


def consistency_feasibility_from_episode_bundle(
    bundle: Optional[Dict[str, Any]],
) -> Tuple[Dict[str, Any], Dict[str, Any]]:
    """从 episode.bundle 的 `evaluation.consistency_result` / `evaluation.feasibility_result` 读取。"""
    if not isinstance(bundle, dict):
        return {}, {}
    ev = bundle.get("evaluation")
    if not isinstance(ev, dict):
        return {}, {}
    cr = ev.get("consistency_result")
    fr = ev.get("feasibility_result")
    c_out: Dict[str, Any] = cr if isinstance(cr, dict) else {}
    f_out: Dict[str, Any] = fr if isinstance(fr, dict) else {}
    return c_out, f_out


def _iter_rule_like_items(eval_dict: Optional[Dict[str, Any]]) -> Iterable[Dict[str, Any]]:
    if not isinstance(eval_dict, dict):
        return
    for key in ("critical_issues", "warnings", "rule_results"):
        items = eval_dict.get(key)
        if not isinstance(items, list):
            continue
        for it in items:
            if isinstance(it, dict):
                yield it


def prune_rule_like_item_to_current_ids(
    item: Dict[str, Any],
    current_ids: Set[str],
) -> Optional[Dict[str, Any]]:
    """
    将单条规则类命中裁剪到当前 function_list 仍存在的节点 id 上；不修改入参。

    - affected_nodes 仅保留 ``∈ current_ids`` 的项（稳定去重）。
    - evidence.high_complexity_functions 仅保留 function_id ∈ current_ids。
    - 若原始条目曾绑定 affected_nodes（非空）且裁剪后为空、且无剩余证据函数，
      视为引用节点已不在当前树（与 rollup superseded 一致），返回 None。
    - 原始 affected_nodes 为空的全局类条目：不因证据被删光而丢弃（与 _hit_status 空列表分支一致），
      除非调用方另有约定。
    """
    if not isinstance(item, dict):
        return None
    out = copy.deepcopy(item)

    nodes_raw = out.get("affected_nodes") or []
    if not isinstance(nodes_raw, list):
        nodes_raw = []
    orig_had_nodes = any(str(n).strip() for n in nodes_raw)

    pruned_nodes: List[str] = []
    seen_n: Set[str] = set()
    for n in nodes_raw:
        s = str(n).strip()
        if s and s in current_ids and s not in seen_n:
            seen_n.add(s)
            pruned_nodes.append(s)
    out["affected_nodes"] = pruned_nodes

    ev = out.get("evidence")
    if isinstance(ev, dict):
        hcf = ev.get("high_complexity_functions")
        if isinstance(hcf, list):
            kept: List[Dict[str, Any]] = []
            seen_f: Set[str] = set()
            for row in hcf:
                if not isinstance(row, dict):
                    continue
                fid = str(row.get("function_id") or "").strip()
                if fid and fid in current_ids and fid not in seen_f:
                    seen_f.add(fid)
                    kept.append(row)
            ev["high_complexity_functions"] = kept
        out["evidence"] = ev

    has_hcf = False
    if isinstance(out.get("evidence"), dict):
        h2 = out["evidence"].get("high_complexity_functions")
        if isinstance(h2, list) and len(h2) > 0:
            has_hcf = True

    if orig_had_nodes and not pruned_nodes and not has_hcf:
        return None
    return out


def _hit_status(
    item: Dict[str, Any],
    current_ids: Set[str],
) -> Tuple[str, bool, List[str]]:
    """
    返回 (status, affects_open, missing_node_ids).

    status:
    - neutral: passed 且 affected_nodes 为空（全局性通过，不参与 open/superseded 计数）
    - superseded: 引用节点已不在当前树
    - open: 需跟进的未通过或仍引用当前树 id 的项
    """
    passed = item.get("passed")
    nodes_raw = item.get("affected_nodes") or []
    if not isinstance(nodes_raw, list):
        nodes_raw = []
    nodes = [str(n).strip() for n in nodes_raw if str(n).strip()]
    if not nodes:
        if passed is True:
            return "neutral", False, []
        return "open", True, []
    missing = [n for n in nodes if n not in current_ids]
    if missing:
        return "superseded", False, missing
    if passed is True:
        return "open", False, []
    return "open", True, []


def _episode_scope_kind(raw: Any) -> str:
    if raw is None:
        return EvaluationScopeKind.FULL_TREE.value
    if isinstance(raw, EvaluationScopeKind):
        return raw.value
    s = str(raw).strip().lower()
    if s in ("subtree", "full_tree"):
        return s
    return EvaluationScopeKind.FULL_TREE.value


def select_episodes_for_rollup(
    evaluation_episodes: Any,
    *,
    current_tree_version: Optional[int],
    current_ids: Set[str],
) -> List[Dict[str, Any]]:
    """
    供 rollup 使用的 episode 子集：
    - full_tree：仅保留 tree_version == current_tree_version（全树一致性重评后旧全树不参与）
    - subtree：scope_root 须仍在当前树；同一 scope_root 仅保留 tree_version 最大的一条
      （该子树根下新一轮评估替代旧轮；不同子树根并列合并）
    """
    if not isinstance(evaluation_episodes, list):
        return []
    eps: List[Dict[str, Any]] = [e for e in evaluation_episodes if isinstance(e, dict)]
    if current_tree_version is None:
        return eps

    full: List[Dict[str, Any]] = []
    by_root: Dict[str, Dict[str, Any]] = {}

    for ep in eps:
        sk = _episode_scope_kind(ep.get("scope"))
        tv = int(ep.get("tree_version", 0) or 0)
        if sk == EvaluationScopeKind.FULL_TREE.value:
            if tv == int(current_tree_version):
                full.append(ep)
            continue

        root = ep.get("scope_root_node_id")
        if not root:
            root = ep.get("parent_node_id")
        sr = str(root).strip() if root else ""
        if not sr or sr not in current_ids:
            continue
        prev = by_root.get(sr)
        if prev is None or int(prev.get("tree_version", 0) or 0) < tv:
            by_root[sr] = ep

    return full + list(by_root.values())


def build_evaluation_rollup(
    function_list: Any,
    evaluation_episodes: Any,
    *,
    current_tree_version: Optional[int] = None,
    max_listed_nodes: int = 64,
) -> Dict[str, Any]:
    """
    从当前树与 evaluation_episodes 列表生成 EvaluationRollup 字典（可 JSON）。

    current_tree_version: 传入当前 context.tree_version 时按全树/子树策略筛选 episode；
    为 None 时不筛选（兼容旧调用）。
    """
    current_ids = collect_function_list_node_ids(function_list)
    raw_eps: List[Dict[str, Any]] = []
    if isinstance(evaluation_episodes, list):
        raw_eps = [e for e in evaluation_episodes if isinstance(e, dict)]
    episodes = select_episodes_for_rollup(
        raw_eps,
        current_tree_version=current_tree_version,
        current_ids=current_ids,
    )

    open_hits = 0
    superseded_hits = 0
    by_cat: Dict[str, int] = {}
    open_nodes: Set[str] = set()
    notes: List[str] = []
    hi_rank = 0
    hi_label = "none"

    for ep in episodes:
        eid = ep.get("episode_id", "?")
        bundle = ep.get("bundle") or {}
        if not isinstance(bundle, dict):
            bundle = {}
        bcons, bfeas = consistency_feasibility_from_episode_bundle(bundle)

        for label, side in (("consistency", bcons), ("feasibility", bfeas)):
            if not isinstance(side, dict):
                continue
            for item in _iter_rule_like_items(side):
                status, counts_open, missing = _hit_status(item, current_ids)
                if status == "neutral":
                    continue
                if status == "superseded":
                    superseded_hits += 1
                    rid = item.get("rule_id") or item.get("rule_name") or "rule"
                    miss_txt = ", ".join(missing[:8]) if missing else ""
                    notes.append(
                        f"episode {eid} 中规则 {rid} 因引用节点 "
                        f"({miss_txt}) 已不在当前树而 superseded"
                    )
                else:
                    if counts_open:
                        open_hits += 1
                        by_cat[label] = by_cat.get(label, 0) + 1
                        sev = str(item.get("severity") or "warning")
                        r = _severity_rank(sev)
                        if r > hi_rank:
                            hi_rank = r
                            hi_label = sev.lower() if sev else "warning"
                        for n in item.get("affected_nodes") or []:
                            s = str(n).strip()
                            if s and s in current_ids:
                                open_nodes.add(s)

    blocking = open_hits > 0 and (hi_label == "error" or hi_rank >= 3)

    listed = sorted(open_nodes)[:max_listed_nodes]

    rollup = EvaluationRollup(
        current_node_count=len(current_ids),
        open_rule_hits=open_hits,
        superseded_rule_hits=superseded_hits,
        by_category=by_cat,
        highest_severity=hi_label if open_hits else "none",
        blocking=blocking and open_hits > 0,
        still_referenced_node_ids=listed,
        superseded_notes=notes[:32],
    )
    return rollup.model_dump()
