"""
子需求列表 / 树形辅助 — 供协调层使用。

M1 主产物为 function_list。Dependency/M2 在各自智能体内按需将 list 组装为树（见
function_list_bridge）；协调层**不**持久化 function_tree。

本模块提供：列表统计、子 AR **列表级拼接**（`splice_subtree_into_function_list`，避免全图
list→嵌套树→list）、节点评估历史、以及嵌套 dict 与 list 互转（兼容旧路径）等。
"""
from __future__ import annotations

import copy
import json
import time
from typing import Any, Dict, List, Optional

# #region agent log
_DEBUG_LOG_PATH = "/Users/xuxiao/Desktop/complex-functional-requirements-automated-decomposition-system/.cursor/debug-e5c18e.log"


def _dbg_splice(reason: str, data: Dict[str, Any]) -> None:
    try:
        with open(_DEBUG_LOG_PATH, "a", encoding="utf-8") as f:
            f.write(
                json.dumps(
                    {
                        "sessionId": "e5c18e",
                        "timestamp": int(time.time() * 1000),
                        "location": "tree_utils.py:splice_subtree_into_function_list",
                        "message": "splice_return_none",
                        "hypothesisId": "H1-H3-H5",
                        "data": {"reason": reason, **data},
                    },
                    ensure_ascii=False,
                )
                + "\n"
            )
    except Exception:
        pass


# #endregion


def norm_function_id(v: Any) -> str:
    """与 M1 m1_decomposer._norm_fid 一致，供列表级子树操作使用。"""
    if v is None:
        return ""
    s = str(v).strip()
    if s.lower() in ("null", "none"):
        return ""
    return s


def collect_subtree_ids_from_rows(
    rows: List[Dict[str, Any]], root_id: str
) -> set:
    """
    收集 root_id 及其所有后代在 function_list 中的 id（按 parent_id 链向下闭包）。
    """
    rid = norm_function_id(root_id)
    if not rid:
        return set()
    ids = {rid}
    changed = True
    while changed:
        changed = False
        for r in rows:
            if not isinstance(r, dict):
                continue
            i = norm_function_id(r.get("id"))
            p = norm_function_id(r.get("parent_id"))
            if not i or i in ids:
                continue
            if p and p in ids:
                ids.add(i)
                changed = True
    return ids


def collect_direct_child_ids_from_rows(
    rows: List[Dict[str, Any]], parent_id: str
) -> set:
    """收集 parent_id 的直接子节点 id（仅一层，不含 parent_id 自身）。"""
    pid = norm_function_id(parent_id)
    if not pid:
        return set()
    return {
        norm_function_id(r.get("id"))
        for r in rows
        if isinstance(r, dict)
        and norm_function_id(r.get("parent_id")) == pid
        and norm_function_id(r.get("id"))
    }


def filter_dependencies_for_node_ids(
    deps: Optional[List[Dict[str, Any]]],
    id_set: set,
) -> List[Dict[str, Any]]:
    """仅保留两端节点 id 均在 id_set 内的依赖边（扁平行 dict）。"""
    if not deps or not id_set:
        return []
    out: List[Dict[str, Any]] = []
    for d in deps:
        if not isinstance(d, dict):
            continue
        fr = d.get("from") or d.get("from_id")
        to = d.get("to") or d.get("to_id") or d.get("target_id")
        fi = norm_function_id(fr)
        ti = norm_function_id(to)
        if fi in id_set and ti in id_set:
            out.append(d)
    return out


def find_function_list_row_by_id(
    rows: Optional[List[Dict[str, Any]]], node_id: str
) -> Optional[Dict[str, Any]]:
    """在扁平行中按 id 查找一行（返回原引用）。"""
    nid = norm_function_id(node_id)
    if not nid:
        return None
    for r in rows or []:
        if isinstance(r, dict) and norm_function_id(r.get("id")) == nid:
            return r
    return None


def calc_node_depth_from_root(
    rows: List[Dict[str, Any]], root_id: str, node_id: str
) -> Optional[int]:
    """计算 node_id 相对 root_id 的深度（root_id 自身返回 0，直接子节点返回 1）。

    root_id 或 node_id 不在 rows 中、断链、或检测到环时返回 None。
    """
    rid = norm_function_id(root_id)
    nid = norm_function_id(node_id)
    if not rid or not nid:
        return None
    if rid == nid:
        return 0

    by_id: Dict[str, str] = {}
    for r in rows:
        if not isinstance(r, dict):
            continue
        i = norm_function_id(r.get("id"))
        if i:
            by_id[i] = norm_function_id(r.get("parent_id"))

    if nid not in by_id or rid not in by_id:
        return None

    depth = 0
    cur: Optional[str] = nid
    seen: set = set()
    while cur:
        if cur == rid:
            return depth
        if cur in seen:
            return None  # 环
        seen.add(cur)
        p = by_id.get(cur)
        if p is None:
            return None  # 不在表中
        if not p:
            return None  # 到达非 rid 的根
        depth += 1
        cur = p
    return None


def max_subtree_depth_from_root(
    rows: List[Dict[str, Any]], root_id: str
) -> int:
    """计算 root_id 子树内相对 root_id 的最大深度（root_id 自身为 0，无子时为 0）。"""
    rid = norm_function_id(root_id)
    if not rid:
        return 0
    subtree_ids = collect_subtree_ids_from_rows(rows, rid)
    max_d = 0
    for nid in subtree_ids:
        if nid == rid:
            continue
        d = calc_node_depth_from_root(rows, rid, nid)
        if d is not None and d > max_d:
            max_d = d
    return max_d


def ensure_subtree_splice_anchor_rows(
    new_rows: List[Any],
    target_id: str,
    anchor_template: Dict[str, Any],
) -> List[Dict[str, Any]]:
    """
    `splice_subtree_into_function_list` 要求 new_rows 中含 id == target_id 的根行。

    聚焦拆分时 Decomposer 按提示仅输出子节点，经 remap 后多为 F-x.y.1、F-x.y.2，
    而没有 id 为 F-x.y 的父行本身，会导致拼接返回 None。此处用原功能树中的该行深拷贝补锚点。
    """
    tid = norm_function_id(target_id)
    rows = [r for r in (new_rows or []) if isinstance(r, dict)]
    if not tid or not isinstance(anchor_template, dict):
        return rows
    if any(norm_function_id(r.get("id")) == tid for r in rows):
        return rows
    anchor = copy.deepcopy(anchor_template)
    anchor["id"] = tid
    return [anchor] + rows


def splice_subtree_into_function_list(
    full_rows: List[Dict[str, Any]],
    target_id: str,
    new_rows: List[Dict[str, Any]],
) -> Optional[List[Dict[str, Any]]]:
    """
    将 Decomposer 在 focus（target_id）下产出的 new_rows 拼回 full_rows：
    删除 target 及其后代行，插入 new_rows，并把新子树根（id==target_id）的 parent_id
    接回原父节点。保留各行 dict 中的 constraints 等字段（深拷贝 new_rows）。

    失败时返回 None（未找到锚点、new_rows 无锚点 id 等）。
    """
    if not isinstance(full_rows, list) or not isinstance(new_rows, list):
        # #region agent log
        _dbg_splice(
            "not_list",
            {
                "full_is_list": isinstance(full_rows, list),
                "new_is_list": isinstance(new_rows, list),
                "target_id": target_id,
            },
        )
        # #endregion
        return None
    tid = norm_function_id(target_id)
    if not tid:
        # #region agent log
        _dbg_splice("empty_tid", {"target_id": target_id})
        # #endregion
        return None

    by_id: Dict[str, Dict[str, Any]] = {}
    for r in full_rows:
        if not isinstance(r, dict):
            continue
        i = norm_function_id(r.get("id"))
        if i:
            by_id[i] = r

    if tid not in by_id:
        # #region agent log
        _dbg_splice(
            "tid_not_in_full",
            {"tid": tid, "full_row_ids_sample": [norm_function_id(r.get("id")) for r in full_rows[:15] if isinstance(r, dict)]},
        )
        # #endregion
        return None

    old_parent_raw = by_id[tid].get("parent_id")
    old_parent = norm_function_id(old_parent_raw) or None

    to_remove = collect_subtree_ids_from_rows(full_rows, tid)
    kept: List[Dict[str, Any]] = [
        copy.deepcopy(r)
        for r in full_rows
        if isinstance(r, dict) and norm_function_id(r.get("id")) not in to_remove
    ]

    fresh_new: List[Dict[str, Any]] = [
        copy.deepcopy(r) for r in new_rows if isinstance(r, dict)
    ]
    if not fresh_new:
        # #region agent log
        _dbg_splice("empty_fresh_new", {"tid": tid, "raw_new_len": len(new_rows)})
        # #endregion
        return None

    root_row: Optional[Dict[str, Any]] = None
    for r in fresh_new:
        if norm_function_id(r.get("id")) == tid:
            root_row = r
            break
    if root_row is None:
        # #region agent log
        _dbg_splice(
            "no_root_row_in_new",
            {
                "tid": tid,
                "new_row_ids_sample": [
                    norm_function_id(r.get("id")) for r in fresh_new[:20]
                ],
            },
        )
        # #endregion
        return None

    root_row["parent_id"] = old_parent if old_parent else None

    merged = kept + fresh_new
    seen: set = set()
    for r in merged:
        i = norm_function_id(r.get("id"))
        if i:
            if i in seen:
                # #region agent log
                _dbg_splice(
                    "duplicate_ids",
                    {"tid": tid, "duplicate_id": i},
                )
                # #endregion
                return None
            seen.add(i)
    return merged


def sub_requirement_list_stats(items: List[Dict[str, Any]]) -> Dict[str, Any]:
    """列表阶段简要统计，供预览与日志。"""
    return {
        "count": len(items),
        "with_id": sum(1 for x in items if x.get("id")),
        "leaf_like": sum(
            1 for x in items
            if str(x.get("granularity") or "").upper() == "TASK"
        ),
    }


def append_node_evaluation_history(
    store: Dict[str, Any],
    node_id: str,
    entry: Dict[str, Any],
) -> Dict[str, Any]:
    """在 node_evaluations[node_id].history 追加一条记录。"""
    if not isinstance(store, dict):
        store = {}
    nid = str(node_id or "")
    if not nid:
        return store
    cur = store.get(nid)
    if not isinstance(cur, dict):
        cur = {"node_id": nid, "history": []}
    hist = cur.get("history")
    if not isinstance(hist, list):
        hist = []
    hist.append(entry)
    cur["history"] = hist
    store[nid] = cur
    return store


# ─────────────── 功能树统计 ───────────────

def count_tree_nodes(tree: Any) -> int:
    """计算功能树节点总数（嵌套 dict 树）。"""
    if not tree:
        return 0
    node = tree if isinstance(tree, dict) else getattr(tree, "__dict__", {})
    children = node.get("children", [])
    count = 1
    for c in (children or []):
        count += count_tree_nodes(c)
    return count


def calc_tree_depth(tree: Any, depth: int = 0) -> int:
    """计算功能树最大深度。"""
    if not tree:
        return depth
    node = tree if isinstance(tree, dict) else getattr(tree, "__dict__", {})
    children = node.get("children", [])
    if not children:
        return depth + 1
    return max(calc_tree_depth(c, depth + 1) for c in children)


def count_leaf_nodes(tree: Any) -> int:
    """计算叶子节点数。"""
    if not tree:
        return 0
    node = tree if isinstance(tree, dict) else getattr(tree, "__dict__", {})
    children = node.get("children", [])
    if not children:
        return 1
    return sum(count_leaf_nodes(c) for c in children)


def build_tree_preview_str(tree: Any, max_items: Optional[int] = 8) -> str:
    """生成功能树预览字符串，如 '功能A > 子功能A1, 功能B > 子功能B1...'

    max_items 为 None 时不限制条数，与完整 function_tree 载荷配合用于 SSE。
    路径上每个节点标题只出现一次，避免「父 > 父」式重复。
    """
    if not tree:
        return ""
    parts: List[str] = []
    limit = max_items

    def _collect(node: Any, ancestor_titles: List[str]) -> None:
        if limit is not None and len(parts) >= limit:
            return
        node_dict = node if isinstance(node, dict) else getattr(node, "__dict__", {})
        raw_title = node_dict.get("title", "")
        title = str(raw_title).strip() if raw_title else ""
        if title:
            line_titles = ancestor_titles + [title]
            parts.append(" > ".join(line_titles))
            child_prefix = line_titles
        else:
            child_prefix = ancestor_titles
        children = node_dict.get("children", [])
        for c in (children or []):
            if limit is not None and len(parts) >= limit:
                return
            _collect(c, child_prefix)

    _collect(tree, [])

    suffix = ""
    if limit is not None and count_tree_nodes(tree) > limit:
        suffix = "..."
    return ", ".join(parts) + suffix
