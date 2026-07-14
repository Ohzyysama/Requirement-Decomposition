"""供 M1/M2 在需要嵌套结构时，从 function_list 派生 function_tree（协调层不存树）。"""
from __future__ import annotations

from typing import Any, Dict, List, Optional

from app.services.agents.M1.schemas.m1_decomposer import function_list_to_function_tree_dict


def function_tree_from_artifacts(artifacts: Optional[Dict[str, Any]]) -> Dict[str, Any]:
    """
    优先使用 artifacts.function_list 组装树；否则回退 function_tree（兼容旧调用）。
    """
    if not isinstance(artifacts, dict):
        return {}
    fl = artifacts.get("function_list")
    if isinstance(fl, list) and len(fl) > 0:
        t = function_list_to_function_tree_dict(fl)
        return t if isinstance(t, dict) else {}
    ft = artifacts.get("function_tree")
    return ft if isinstance(ft, dict) else {}
