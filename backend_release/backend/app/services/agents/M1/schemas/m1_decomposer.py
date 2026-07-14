import copy
import re
from typing import Any, Dict, List, Literal, Optional, Tuple, Union
from pydantic import BaseModel, Field, field_validator, model_validator, ConfigDict

from app.services.agents.M1.schemas.m1_normalizer import NormalizedConstraint


def norm_constraint_dict(c: Any) -> Dict[str, Any]:
    if c is None or not isinstance(c, dict):
        return {}
    return {
        "type": str(c.get("type") or "").strip(),
        "value": str(c.get("value") or "").strip(),
        "mandatory": bool(c.get("mandatory", True)),
        "confidence": str(c.get("confidence") or "HIGH").strip() or "HIGH",
    }


def constraints_equal(a: Any, b: Any) -> bool:
    return norm_constraint_dict(a) == norm_constraint_dict(b)


def strip_matched_normalizer_constraints(
    normalizer_result: Dict[str, Any],
    function_list: List[Dict[str, Any]],
) -> Tuple[Dict[str, Any], int]:
    """
    对 normalizer_result 做深拷贝；若某条预处理约束与至少一行 function_list.constraints 中某条
    四元组一致，则从「总列表」中去掉该条（每条总约束只匹配一次）。未匹配的保留。
    返回 (新 normalizer dict, 被移除条数)。
    """
    out = copy.deepcopy(normalizer_result)
    orig = out.get("constraints")
    if not isinstance(orig, list):
        orig = []
    cc = out.get("constraints_copy")
    if not isinstance(cc, list) or len(cc) == 0:
        if orig:
            out["constraints_copy"] = copy.deepcopy(orig)
    matched = [False] * len(orig)
    for row in function_list or []:
        if not isinstance(row, dict):
            continue
        for pc in row.get("constraints") or []:
            if not isinstance(pc, dict):
                continue
            for j in range(len(orig)):
                if not matched[j] and constraints_equal(orig[j], pc):
                    matched[j] = True
                    break
    remaining = [orig[j] for j in range(len(orig)) if not matched[j]]
    out["constraints"] = remaining
    removed = sum(1 for m in matched if m)
    return out, removed

NodeType = Literal[
    "DOMAIN", "WORKFLOW", "CAPABILITY", "TASK",
    "EXCEPTION", "INTEGRATION", "CONFIG", "SUPPORT",
]
Granularity = Literal["EPIC", "FEATURE", "STORY", "TASK"]
SCHEMA_KEYWORDS = {"id", "title", "desc", "node_type", "granularity", "acceptance_hint", "children"}


def _norm_fid(v: Any) -> str:
    if v is None:
        return ""
    s = str(v).strip()
    if s.lower() in ("null", "none"):
        return ""
    return s


def _first_row_index(rows: List[Dict[str, Any]], node_id: str) -> int:
    for i, r in enumerate(rows):
        if isinstance(r, dict) and _norm_fid(r.get("id")) == node_id:
            return i
    return 10**9


def remap_function_list_to_f_ids(
    rows: List[Dict[str, Any]],
    *,
    mode_b: bool = False,
    focus_node: Optional[Dict[str, Any]] = None,
) -> Tuple[List[Dict[str, Any]], Dict[str, str]]:
    """
    将 id 规范为字符串形式的 F-1、F-2、F-1.1、F-2.1 等（PATH_NUMERIC）。
    模式A：多根为 F-1、F-2…；模式B：以 focus_node.id 为锚（如 F-2），子树为 F-2.1、F-2.2…
    """
    cleaned: List[Dict[str, Any]] = []
    for r in rows:
        if not isinstance(r, dict):
            continue
        rid = _norm_fid(r.get("id"))
        if not rid:
            continue
        rr = dict(r)
        rr["id"] = rid
        pid = _norm_fid(r.get("parent_id"))
        rr["parent_id"] = pid if pid else None
        cleaned.append(rr)

    if not cleaned:
        return [], {}

    rows = cleaned
    by_id: Dict[str, Dict[str, Any]] = {r["id"]: r for r in rows}
    all_ids = set(by_id.keys())

    focus_canonical = ""
    if mode_b and focus_node and isinstance(focus_node, dict):
        focus_canonical = _norm_fid(focus_node.get("id"))

    children: Dict[str, List[str]] = {}
    for r in rows:
        rid = r["id"]
        pid = _norm_fid(r.get("parent_id"))
        if not pid:
            continue
        children.setdefault(pid, []).append(rid)
    for pid in list(children.keys()):
        children[pid] = sorted(set(children[pid]), key=lambda x: _first_row_index(rows, x))

    def is_root(rid: str) -> bool:
        pid = _norm_fid(by_id[rid].get("parent_id"))
        if not pid:
            return True
        if pid in all_ids:
            return False
        if focus_canonical and pid == focus_canonical:
            return False
        return True

    roots = sorted([rid for rid in all_ids if is_root(rid)], key=lambda x: _first_row_index(rows, x))

    old_to_new: Dict[str, str] = {}

    def dfs(old_id: str, new_id: str) -> None:
        old_to_new[old_id] = new_id
        chs = [c for c in children.get(old_id, []) if c in all_ids]
        chs = sorted(chs, key=lambda x: _first_row_index(rows, x))
        for j, c in enumerate(chs, start=1):
            dfs(c, f"{new_id}.{j}")

    mapped_any = False
    if mode_b and focus_canonical:
        old_focus: Optional[str] = None
        if focus_canonical in all_ids:
            old_focus = focus_canonical
        elif len(roots) == 1:
            old_focus = roots[0]
        elif len(roots) > 1:
            ft = _norm_fid(focus_node.get("title") if focus_node else "")
            for cand in roots:
                if ft and _norm_fid(by_id[cand].get("title")) == ft:
                    old_focus = cand
                    break
            if old_focus is None:
                old_focus = roots[0]
        elif not roots:
            direct = sorted(
                [rid for rid in all_ids if _norm_fid(by_id[rid].get("parent_id")) == focus_canonical],
                key=lambda x: _first_row_index(rows, x),
            )
            for j, c in enumerate(direct, start=1):
                dfs(c, f"{focus_canonical}.{j}")
            mapped_any = bool(old_to_new)
            old_focus = None
        else:
            old_focus = None

        if old_focus is not None:
            dfs(old_focus, focus_canonical)
            mapped_any = True

    if not mapped_any:
        old_to_new.clear()
        for i, r in enumerate(roots, start=1):
            dfs(r, f"F-{i}")
    else:
        rest = [rid for rid in all_ids if rid not in old_to_new]
        if rest:
            used_nums: List[int] = []
            for nv in old_to_new.values():
                m = re.match(r"^F-(\d+)$", nv)
                if m:
                    used_nums.append(int(m.group(1)))
            k = max(used_nums) + 1 if used_nums else 1
            sub_ids = set(rest)

            def is_sub_root(rid: str) -> bool:
                pid = _norm_fid(by_id[rid].get("parent_id"))
                if not pid:
                    return True
                if pid in sub_ids:
                    return False
                return True

            sub_roots = sorted(
                [rid for rid in rest if is_sub_root(rid)],
                key=lambda x: _first_row_index(rows, x),
            )
            for sr in sub_roots:
                dfs(sr, f"F-{k}")
                k += 1

    out_rows: List[Dict[str, Any]] = []
    for r in rows:
        rid = r["id"]
        nr = dict(r)
        nr["id"] = old_to_new.get(rid, rid)
        p_old = _norm_fid(r.get("parent_id"))
        if p_old and p_old in old_to_new:
            nr["parent_id"] = old_to_new[p_old]
        elif p_old:
            nr["parent_id"] = p_old
        else:
            nr["parent_id"] = None
        out_rows.append(nr)

    return out_rows, old_to_new


def rebuild_function_list_paths(rows: List[Dict[str, Any]]) -> None:
    """按 parent_id 与 title 就地重写 path（id 重映射后建议调用）。"""
    by_id = {str(r.get("id")): r for r in rows if r.get("id")}
    memo: Dict[str, str] = {}

    def path_for(rid: str) -> str:
        if rid in memo:
            return memo[rid]
        r = by_id.get(rid)
        if not r:
            memo[rid] = ""
            return ""
        pid = _norm_fid(r.get("parent_id"))
        title = str(r.get("title") or "").strip()
        if not pid or pid not in by_id:
            memo[rid] = title
            return memo[rid]
        pp = path_for(pid)
        memo[rid] = f"{pp} > {title}" if pp else title
        return memo[rid]

    for rid in list(by_id.keys()):
        path_for(rid)
    for rid, r in by_id.items():
        r["path"] = memo.get(rid, str(r.get("title") or ""))


def apply_f_id_mapping_to_nested(
    data: Any,
    id_map: Dict[str, str],
    *,
    id_keys: Tuple[str, ...] = ("function_id",),
    list_keys: Tuple[str, ...] = ("applied_to",),
) -> Any:
    """将 core_flow 等嵌套结构中的旧 function id 替换为新 id。"""
    if not id_map:
        return data

    def map_one(x: str) -> str:
        s = _norm_fid(x)
        return id_map.get(s, s)

    if isinstance(data, dict):
        out: Dict[str, Any] = {}
        for k, v in data.items():
            if k in id_keys and isinstance(v, str):
                out[k] = map_one(v)
            elif k in list_keys and isinstance(v, list):
                out[k] = [map_one(i) if isinstance(i, str) else i for i in v]
            else:
                out[k] = apply_f_id_mapping_to_nested(v, id_map, id_keys=id_keys, list_keys=list_keys)
        return out
    if isinstance(data, list):
        return [apply_f_id_mapping_to_nested(i, id_map, id_keys=id_keys, list_keys=list_keys) for i in data]
    return data


class FunctionListItem(BaseModel):
    """与 FunctionNode 内核字段对齐的扁平行；用 parent_id/path 表达层次（M1 主输出）。
    AR 扩展字段（ar_*）对应数据集 AR Markdown 表格各列，默认空字符串，不影响旧逻辑。
    """

    model_config = ConfigDict(extra="forbid")

    id: str = Field(..., description="稳定功能ID")
    title: str = Field(..., description="功能名称")
    desc: str = Field("", description="功能描述")
    node_type: NodeType = Field(default="FEATURE", description="节点类型")
    granularity: Granularity = Field(default="STORY", description="粒度")
    acceptance_hint: List[str] = Field(default_factory=list, description="验收要点（旧字段，保留兼容）")
    parent_id: Optional[str] = Field(None, description="父节点 id；根节点为 null")
    path: str = Field("", description="自根路径展示，如 A > B > C")
    constraints: List[NormalizedConstraint] = Field(
        default_factory=list,
        description="从预处理约束列表分发到本功能点的约束（可为空）",
    )
    constraints_copy: List[NormalizedConstraint] = Field(
        default_factory=list,
        description="与 constraints 同步的完整副本（由协调层/Agent 写入；INTEGRATION 等依赖边界节点用于防分发后丢失）",
    )

    # ── AR 扩展字段（对应 AR Markdown 表格各列） ──────────────────────────
    ar_value: str = Field("", description="[需求价值] 本 AR 对用户/产品的价值说明")
    ar_scenario: str = Field("", description="[需求场景] 典型使用场景描述")
    ar_target_users: str = Field("", description="[目标用户] 适用用户群体")
    ar_constraints: str = Field("", description="[限制约束] 技术/业务约束（文本，有别于结构化 constraints 字段）")
    ar_external_deps: str = Field("", description="[外部依赖] 依赖的系统能力或三方服务")
    ar_performance: str = Field("", description="[性能指标] 响应时间等量化目标，无则填'继承所属 SR'")
    ar_power: str = Field("", description="[功耗指标] 功耗基线，无则填'继承所属 SR'")
    ar_rom_ram: str = Field("", description="[ROM&RAM] 包体/内存基线，无则填'继承所属 SR'")
    ar_acceptance: List[str] = Field(default_factory=list, description="[验收标准] 逐条可测试的验收项（替代 acceptance_hint）")
    ar_device: str = Field("", description="[验收设备] 如 HarmonyOS NEXT（API 12+）手机为主基线")
    ar_products: str = Field("", description="[适用产品] 如 手机 / 平板 / 车机")
    ar_product_diff: str = Field("", description="[适用产品差异分析] 各端行为差异说明")
    ar_extra: str = Field("", description="[视觉/生态/安全等扩展维度] 其他补充")

    @field_validator("constraints", "constraints_copy", mode="before")
    @classmethod
    def _coerce_constraints(cls, v: Any) -> List[Any]:
        if v is None:
            return []
        if not isinstance(v, list):
            return []
        return v

    @field_validator("id", mode="before")
    @classmethod
    def _coerce_id_str(cls, v: Any) -> str:
        s = _norm_fid(v)
        if not s:
            raise ValueError("功能节点 id 不能为空")
        return s

    @field_validator("parent_id", mode="before")
    @classmethod
    def _coerce_parent_id_str(cls, v: Any) -> Optional[str]:
        if v is None:
            return None
        s = _norm_fid(v)
        return s if s else None

    @field_validator("acceptance_hint", "ar_acceptance", mode="before")
    @classmethod
    def _coerce_hints(cls, v: Any) -> List[str]:
        if v is None:
            return []
        if isinstance(v, str):
            return [v] if v.strip() else []
        return v if isinstance(v, list) else []

    @field_validator(
        "ar_value", "ar_scenario", "ar_target_users", "ar_constraints",
        "ar_external_deps", "ar_performance", "ar_power", "ar_rom_ram",
        "ar_device", "ar_products", "ar_product_diff", "ar_extra",
        mode="before",
    )
    @classmethod
    def _coerce_ar_str(cls, v: Any) -> str:
        if v is None:
            return ""
        return str(v).strip()


class FunctionNode(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: str = Field(..., description="稳定功能ID，可用于依赖与定位")
    title: str = Field(..., description="功能名称")
    desc: str = Field(..., description="功能描述（业务可读）")

    node_type: NodeType = Field(default="FEATURE", description="功能节点类型，用于规则约束与展示")
    granularity: Granularity = Field(default="STORY", description="粒度标签，用于门禁与可开发性控制")

    acceptance_hint: List[str] = Field(
        default_factory=list,
        description="验收要点（建议叶子节点>=2条）"
    )

    children: List["FunctionNode"] = Field(
        default_factory=list,
        description="子节点（递归）"
    )

    @field_validator('acceptance_hint', mode='before')
    @classmethod
    def handle_none_acceptance_hint(cls, v):
        """处理 None 值或字符串输入"""
        if v is None:
            return []
        if isinstance(v, str):
            return [v] if v.strip() else []
        return v

    @field_validator('children', mode='before')
    @classmethod
    def handle_children_strings(cls, v):
        """对 children 做温和纠偏，避免因 LLM 常见格式漂移直接失败。

        注意：这里仅做“可解析化”，最终质量仍由 agent 的粗粒度门禁与二次召回保障。
        """
        if v is None:
            return []
        if isinstance(v, str):
            item = v.strip()
            if not item:
                return []
            if item.lower() in SCHEMA_KEYWORDS:
                return []
            safe_id = item.lower().replace(' ', '_')
            return [{
                "id": safe_id,
                "title": item,
                "desc": f"{item}功能处理",
                "node_type": "WORKFLOW",
                "granularity": "TASK",
                "acceptance_hint": [f"{item}流程可执行", f"{item}异常有提示"],
                "children": []
            }]
        if isinstance(v, list):
            result = []
            for item in v:
                if isinstance(item, str):
                    text = item.strip()
                    if not text:
                        continue
                    if text.lower() in SCHEMA_KEYWORDS:
                        continue
                    safe_id = text.lower().replace(' ', '_')
                    result.append({
                        "id": safe_id,
                        "title": text,
                        "desc": f"{text}功能处理",
                        "node_type": "WORKFLOW",
                        "granularity": "TASK",
                        "acceptance_hint": [f"{text}流程可执行", f"{text}异常有提示"],
                        "children": []
                    })
                else:
                    result.append(item)
            return result
        return v

    @model_validator(mode='after')
    def normalize_leaf_node(self):
        """容错归一化：避免因 LLM 小偏差导致整次流程中断。"""
        if not self.children:
            # 仅对 TASK 叶子做温和补全，不在 schema 层阻断执行。
            if self.granularity == "TASK" and len(self.acceptance_hint) < 2:
                title = self.title or self.id or "叶子功能"
                hints = list(self.acceptance_hint or [])
                while len(hints) < 2:
                    if len(hints) == 0:
                        hints.append(f"{title}流程可执行")
                    else:
                        hints.append(f"{title}异常有提示")
                self.acceptance_hint = hints
        return self


FunctionNode.model_rebuild()


def function_list_to_function_tree_dict(
    items: Union[List[FunctionListItem], List[Dict[str, Any]], None],
) -> Optional[Dict[str, Any]]:
    """
    将扁平行（parent_id）组装为嵌套 function_tree 字典；需要树形视图时在调用方内部使用（协调层不持久化树）。
    多根时自动包一层合成根节点 __ROOT__。
    """
    if not items:
        return None
    rows: List[Dict[str, Any]] = []
    for it in items:
        if isinstance(it, FunctionListItem):
            rows.append(it.model_dump())
        elif isinstance(it, dict):
            rows.append(dict(it))
    if not rows:
        return None

    node_payload: Dict[str, Dict[str, Any]] = {}
    for r in rows:
        rid = str(r.get("id") or "").strip()
        if not rid:
            continue
        node_payload[rid] = {
            "id": rid,
            "title": str(r.get("title") or "").strip(),
            "desc": str(r.get("desc") or "").strip(),
            "node_type": r.get("node_type") or "DOMAIN",
            "granularity": r.get("granularity") or "EPIC",
            "acceptance_hint": r.get("acceptance_hint") if isinstance(r.get("acceptance_hint"), list) else [],
            "children": [],
        }

    if not node_payload:
        return None

    id_set = set(node_payload.keys())
    child_ids = set()
    for r in rows:
        rid = str(r.get("id") or "").strip()
        if not rid or rid not in id_set:
            continue
        raw_pid = r.get("parent_id")
        pid = str(raw_pid).strip() if raw_pid is not None and str(raw_pid).strip() else ""
        if pid and pid in id_set and pid != rid:
            child_ids.add(rid)

    root_ids = [rid for rid in id_set if rid not in child_ids]
    for r in rows:
        rid = str(r.get("id") or "").strip()
        if not rid or rid not in id_set:
            continue
        raw_pid = r.get("parent_id")
        pid = str(raw_pid).strip() if raw_pid is not None and str(raw_pid).strip() else ""
        if pid and pid in id_set and pid != rid:
            node_payload[pid]["children"].append(node_payload[rid])

    root_nodes = [node_payload[r] for r in root_ids if r in node_payload]
    if not root_nodes:
        return None
    if len(root_nodes) == 1:
        return root_nodes[0]
    return {
        "id": "__ROOT__",
        "title": "功能根",
        "desc": "由多根列表合并",
        "node_type": "DOMAIN",
        "granularity": "EPIC",
        "acceptance_hint": [],
        "children": root_nodes,
    }


def max_parent_hops_to_root(rows: Union[List[Dict[str, Any]], None]) -> int:
    """从任一节点沿 parent_id 向上走到「根」（无父或父不在表中）的最大边数。"""
    if not rows:
        return 0
    by_id: Dict[str, Dict[str, Any]] = {}
    for r in rows:
        if not isinstance(r, dict):
            continue
        rid = _norm_fid(r.get("id"))
        if rid:
            by_id[rid] = r
    if not by_id:
        return 0
    best = 0
    for start in by_id:
        hops = 0
        cur: Optional[str] = start
        seen: set = set()
        while cur and cur in by_id and cur not in seen:
            seen.add(cur)
            pid = _norm_fid(by_id[cur].get("parent_id"))
            if not pid or pid not in by_id:
                break
            hops += 1
            cur = pid
            if hops > len(by_id):
                break
        best = max(best, hops)
    return best


def compute_function_list_metrics(items: Union[List[FunctionListItem], List[Dict[str, Any]], None]) -> Dict[str, Any]:
    """基于列表推导功能树再计算指标；列表为空则返回零值。"""
    tree_dict = function_list_to_function_tree_dict(items)
    if not tree_dict:
        return {
            "total_nodes": 0,
            "leaf_nodes": 0,
            "max_depth": 0,
            "avg_branching": 0.0,
            "domain_modules_count": 0,
            "exception_nodes_count": 0,
            "integration_nodes_count": 0,
            "task_leaf_ratio": 0.0,
        }
    try:
        root = FunctionNode.model_validate(tree_dict)
    except Exception:
        return {
            "total_nodes": 0,
            "leaf_nodes": 0,
            "max_depth": 0,
            "avg_branching": 0.0,
            "domain_modules_count": 0,
            "exception_nodes_count": 0,
            "integration_nodes_count": 0,
            "task_leaf_ratio": 0.0,
        }
    return compute_function_tree_metrics(root)


class CoreFlowStep(BaseModel):
    model_config = ConfigDict(extra="forbid")

    step: str = Field(..., description="流程步骤描述（业务口径）")
    function_id: str = Field(..., description="映射到功能树节点的ID")
    type: Literal["MAIN", "OPTIONAL"] = Field("MAIN", description="主流程/可选流程")


def compute_function_tree_metrics(root: FunctionNode) -> Dict[str, Any]:
    """供 Decomposer / Gate 复用，与功能树真实结构一致。"""
    total_nodes = 0
    leaf_nodes = 0
    exception_nodes_count = 0
    integration_nodes_count = 0
    task_leaf_nodes = 0
    domain_modules_count = 0
    total_children = 0
    non_leaf_nodes = 0
    max_depth = 0

    def walk(node: FunctionNode, depth: int):
        nonlocal total_nodes, leaf_nodes, exception_nodes_count, integration_nodes_count
        nonlocal task_leaf_nodes, domain_modules_count, total_children, non_leaf_nodes, max_depth

        total_nodes += 1
        max_depth = max(max_depth, depth)

        if node.node_type == "EXCEPTION":
            exception_nodes_count += 1
        if node.node_type == "INTEGRATION":
            integration_nodes_count += 1

        if depth == 2:
            domain_modules_count += 1

        if not node.children:
            leaf_nodes += 1
            if node.granularity == "TASK":
                task_leaf_nodes += 1
            return

        non_leaf_nodes += 1
        total_children += len(node.children)
        for child in node.children:
            walk(child, depth + 1)

    walk(root, 1)
    avg_branching = (total_children / non_leaf_nodes) if non_leaf_nodes else 0.0
    task_leaf_ratio = (task_leaf_nodes / leaf_nodes) if leaf_nodes else 0.0

    return {
        "total_nodes": total_nodes,
        "leaf_nodes": leaf_nodes,
        "max_depth": max_depth,
        "avg_branching": float(avg_branching),
        "domain_modules_count": domain_modules_count,
        "exception_nodes_count": exception_nodes_count,
        "integration_nodes_count": integration_nodes_count,
        "task_leaf_ratio": float(task_leaf_ratio),
    }


_FUNCTION_LIST_ITEM_KEYS = frozenset(
    {
        "id",
        "title",
        "desc",
        "node_type",
        "granularity",
        "acceptance_hint",
        "parent_id",
        "path",
        "constraints",
        "constraints_copy",
        # AR 扩展字段
        "ar_value",
        "ar_scenario",
        "ar_target_users",
        "ar_constraints",
        "ar_external_deps",
        "ar_performance",
        "ar_power",
        "ar_rom_ram",
        "ar_acceptance",
        "ar_device",
        "ar_products",
        "ar_product_diff",
        "ar_extra",
    }
)


def _drop_non_schema_function_list_keys(d: Dict[str, Any]) -> Dict[str, Any]:
    """只保留 FunctionListItem 白名单字段；其余（含中文键、任意杂质键）一律丢弃。"""
    return {k: v for k, v in d.items() if k in _FUNCTION_LIST_ITEM_KEYS}


def _coerce_function_list_item(raw: Any) -> Any:
    """将 LLM 常见畸形行（用中文句子当唯一 key 包一层、或混入 core_flow 行）拉平为 FunctionListItem 可解析的 dict。"""
    if not isinstance(raw, dict):
        return raw

    # core_flow 行误入 function_list：含 step/function_id 且无 node_type
    if "step" in raw and "function_id" in raw and "node_type" not in raw:
        fid = str(raw.get("function_id") or "").strip() or "flow_step"
        step = str(raw.get("step") or "").strip() or fid
        return {
            "id": fid,
            "title": step,
            "desc": "",
            "node_type": "WORKFLOW",
            "granularity": "TASK",
            "acceptance_hint": [],
            "parent_id": raw.get("parent_id"),
            "path": "",
            "constraints": [],
            "constraints_copy": [],
        }

    raw = dict(raw)
    extras = [k for k in raw if k not in _FUNCTION_LIST_ITEM_KEYS]
    if len(extras) == 1:
        wrap_key = extras[0]
        inner = raw.get(wrap_key)
        if isinstance(inner, dict):
            base_only = {k: v for k, v in raw.items() if k in _FUNCTION_LIST_ITEM_KEYS}
            inner_fli = {k: v for k, v in inner.items() if k in _FUNCTION_LIST_ITEM_KEYS}
            merged: Dict[str, Any] = {**inner_fli, **base_only}
            if not str(merged.get("title") or "").strip():
                merged["title"] = wrap_key
            if not str(merged.get("id") or "").strip():
                slug = wrap_key.strip().lower().replace(" ", "_")[:48] or "node"
                merged["id"] = slug
            if not merged.get("node_type"):
                merged["node_type"] = "CAPABILITY"
            if not merged.get("granularity"):
                merged["granularity"] = "STORY"
            return _drop_non_schema_function_list_keys(merged)

    return _drop_non_schema_function_list_keys(raw)


class M1DecomposerLLMResult(BaseModel):
    model_config = ConfigDict(extra="forbid")

    function_list: List[FunctionListItem] = Field(
        default_factory=list,
        description="功能点扁平列表（parent_id/path 表层次；协调层可再派生 function_tree）",
    )
    core_flow: List[CoreFlowStep] = Field(default_factory=list, description="主流程骨架")

    @model_validator(mode="before")
    @classmethod
    def normalize_function_list_rows(cls, data: Any) -> Any:
        if not isinstance(data, dict):
            return data
        out = dict(data)
        out.pop("metrics", None)
        out.pop("rule_trace", None)
        fl = out.get("function_list")
        if isinstance(fl, list):
            out["function_list"] = [_coerce_function_list_item(x) for x in fl]
        return out


__all__ = [
    "NodeType",
    "Granularity",
    "FunctionNode",
    "FunctionListItem",
    "NormalizedConstraint",
    "norm_constraint_dict",
    "constraints_equal",
    "strip_matched_normalizer_constraints",
    "CoreFlowStep",
    "M1DecomposerLLMResult",
    "compute_function_tree_metrics",
    "max_parent_hops_to_root",
    "compute_function_list_metrics",
    "function_list_to_function_tree_dict",
    "remap_function_list_to_f_ids",
    "rebuild_function_list_paths",
    "apply_f_id_mapping_to_nested",
]
