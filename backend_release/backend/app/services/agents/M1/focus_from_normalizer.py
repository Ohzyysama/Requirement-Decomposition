"""由 Normalizer 产物确定性构造「分解锚点」功能点（首轮与细化共用同一形状）。"""

import copy
from typing import Any, Dict

DECOMPOSITION_ROOT_ID = "F-1"


def build_focus_node_from_normalizer(norm_result: Dict[str, Any]) -> Dict[str, Any]:
    """
    根据预处理结构化结果生成根功能点，供 M1 Decomposer 作为唯一父锚点。

    不调用 LLM；字段与 function_list 行 / focus_node 约定对齐。
    """
    if not isinstance(norm_result, dict):
        norm_result = {}
    nr = str(norm_result.get("normalized_requirement") or "").strip()
    goal = norm_result.get("goal")
    primary = ""
    if isinstance(goal, dict):
        primary = str(goal.get("primary_goal") or "").strip()
    title = primary if primary else (nr[:120] if nr else "需求根节点")
    desc = nr if nr else title
    path = title
    raw_c = norm_result.get("constraints")
    constraints = copy.deepcopy(raw_c) if isinstance(raw_c, list) else []
    raw_cc = norm_result.get("constraints_copy")
    if isinstance(raw_cc, list) and len(raw_cc) > 0:
        constraints_copy = copy.deepcopy(raw_cc)
    else:
        constraints_copy = copy.deepcopy(constraints)
    return {
        "id": DECOMPOSITION_ROOT_ID,
        "title": title,
        "desc": desc,
        "node_type": "DOMAIN",
        "granularity": "EPIC",
        "acceptance_hint": [],
        "parent_id": None,
        "path": path,
        "constraints": constraints,
        "constraints_copy": constraints_copy,
    }
