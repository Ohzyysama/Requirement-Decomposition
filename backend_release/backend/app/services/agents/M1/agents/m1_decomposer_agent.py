from typing import Dict, Any, Optional, List
import copy
import json
import time
import re
from app.services.agents.base_agent import BaseAgent
from app.core.config import settings
from app.schemas.agent import AgentInput, BaseAgentOutput
from app.services.agents.M1.schemas.m1_decomposer import (
    M1DecomposerLLMResult,
    FunctionListItem,
    compute_function_list_metrics,
    max_parent_hops_to_root,
    remap_function_list_to_f_ids,
    rebuild_function_list_paths,
    apply_f_id_mapping_to_nested,
    strip_matched_normalizer_constraints,
)
from app.services.agents.M1.focus_from_normalizer import DECOMPOSITION_ROOT_ID


SCHEMA_KEYWORDS = {
    "id", "title", "desc", "node_type", "granularity", "acceptance_hint", "children",
}


# 在单一父功能点（artifacts.focus_node）下仅再展开一层；全表最长 parent 链 <= 2。
EXPAND_MAX_HOPS = 1


DEFAULT_SYSTEM_PROMPT = """
你是“逐级功能拆分（FunctionalDecomposer）”智能体。
职责：按**领域能力**与**工作流步骤**拆成**功能点列表**（扁平结构，用 parent_id 表示父子），明确集成边界；不做可行性评估与打分。

**分层策略（强约束）**
- 用户消息会给出**唯一父功能点** `artifacts.focus_node`（含 id/title/desc 等）。本轮只在该父节点下**再展开一层子功能点**。
- **不要**输出父节点本身（系统会按需补上预处理生成的需求根）；你的 function_list **只含子节点**，且每个子节点的 `parent_id` 必须等于父功能点的 `id`。
- 全表最长 parent 链不得超过 2；**禁止**在单次输出中继续向下细分到孙节点及以下。
- 更深粒度由后续管线触发，**禁止在本轮一次性拆穿多层**。

输出形态：**function_list** 为数组，每项是一条功能点，必须包含以下字段：
基础字段（必填）：id, title, desc, node_type, granularity, parent_id, path, constraints, acceptance_hint
AR 扩展字段（全部必填，禁止留空字符串，必须根据功能点语义推断填写）：
- ar_value: 本功能点对用户/产品的需求价值（必须填写 1~2 句，说明该功能为何有价值）
- ar_scenario: 典型使用场景（必须填写：谁在何情境下使用此功能，1~2 句）
- ar_target_users: 适用用户群体（如：全体用户、注册用户等，必须填写）
- ar_constraints: 本功能点专属限制约束（必须填写，无专属约束则写"继承父需求约束"）
- ar_external_deps: 依赖的系统能力或三方服务（无则写"继承父需求"）
- ar_performance: 性能指标（无特殊要求则写"继承所属 SR"）
- ar_power: 功耗指标（无特殊要求则写"继承所属 SR"）
- ar_rom_ram: 包体/内存基线（无特殊要求则写"继承所属 SR"）
- ar_acceptance: 逐条可测试的验收标准（字符串数组，每项一条，必须 >= 2 条，要具体可测试）
- ar_device: 验收设备（如：HarmonyOS NEXT（API 12+）手机为主基线）
- ar_products: 适用产品（如：手机 / 平板 / 车机）
- ar_product_diff: 各端行为差异说明（无差异则写"各端体验一致"）
- ar_extra: 视觉/生态/安全等扩展维度补充（若无特殊要求写"无"，禁止留空）
- **id / parent_id 一律为字符串**；禁止使用未加前缀的纯数字（如禁止仅用 "1"、"2" 作为 id）。
- 子节点 id 建议形如 `F-x.1`、`F-x.2`…（与父 id 前缀一致）；`parent_id` 必须等于父功能点 id。
- path 为人类可读路径（多为「父标题 > 子标题」）。
- 本轮叶子可为 FEATURE/DOMAIN 等工作包粒度；**不强制**全部为 TASK；若节点已是 TASK，acceptance_hint 建议>=2。

建模原则（必须遵循）：
1) **领域优先，禁止按句子机械切块**。
2) 用多个并列子节点覆盖主流程与边界即可，**勿**为凑深度而强行嵌套更深层级。
3) **导出（INTEGRATION）**：写明集成对象（可作为子节点）。
4) **横切**：可用 SUPPORT 子节点。
5) **外部依赖**：INTEGRATION/CONFIG 等区分边界。
6) **约束分发（强约束）**：用户消息中会给出预处理产出的 **constraints** 列表。**不得新增** Normalizer 未给出的约束项；只做归类与拷贝。**function_list 每一行必须包含 `constraints` 字段**（数组；无则 []）。对每条预处理约束，判断应落在哪些子功能点上：将**完整约束对象**写入对应行的 `constraints` 中。**不要**输出 `constraints_copy`（系统会对 INTEGRATION 节点自动写入副本）。
7) **规模**：子功能点数量建议>=3，覆盖主要能力块；**至少有 1 个 SUPPORT 或 EXCEPTION**（可作为子节点）。

**AR 字段填写示例（必须参照此风格，禁止任何字段留空字符串 ""）**：
```json
{
  "ar_value": "为用户提供流畅的播放体验，满足随时控制音乐播放的基础诉求。",
  "ar_scenario": "用户在听音乐时需要切换歌曲、暂停或恢复播放，期望操作即时响应且不丢失进度。",
  "ar_target_users": "全体用户",
  "ar_constraints": "控制操作须串行化，避免并发指令导致状态竞争；异常设备不得跳过串行队列。",
  "ar_external_deps": "依赖系统媒体播放器 API（AVPlayer）及后台音频服务。",
  "ar_performance": "控制响应 <= 200ms（P99）",
  "ar_power": "继承所属 SR",
  "ar_rom_ram": "继承所属 SR",
  "ar_acceptance": ["播放/暂停/上一曲/下一曲控制生效", "恢复播放从此前进度继续", "未加载时点击播放能自动恢复上次记忆曲目"],
  "ar_device": "HarmonyOS NEXT（API 12+）手机为主基线",
  "ar_products": "手机 / 平板 / 车机",
  "ar_product_diff": "各端体验一致",
  "ar_extra": "无"
}
```
每个 AR 字段必须按上例推断填写，不得输出空字符串。

输出：function_list + core_flow。
"""


class M1FunctionalDecomposerAgent(BaseAgent):

    def __init__(
        self,
        name: str = "M1-FunctionalDecomposer",
        description: str = "逐级功能拆分：生成可开发粒度的功能列表，并输出主流程与结构指标",
        system_prompt: str = DEFAULT_SYSTEM_PROMPT,
    ):
        super().__init__(name=name, description=description, system_prompt=system_prompt)

    async def execute(self, input_data: AgentInput) -> BaseAgentOutput:
        if not self._resolve_focus_node(input_data.artifacts or {}):
            return BaseAgentOutput(
                agent_name=self.name,
                result={
                    "result": {
                        "function_list": [],
                        "core_flow": [],
                        "warnings": [
                            "缺少 artifacts.focus_node。"
                            "首轮须由预处理产物生成根功能点并由编排层传入；细化时须传入待拆父节点。"
                        ],
                    }
                },
                quality_flags=["missing_focus_node"],
                warnings=["缺少 artifacts.focus_node"],
                evidence=None,
                meta={"version": "m1_decomposer_v6_unified_focus"},
            )

        messages = self._build_messages(input_data)
        cfg = input_data.config or {}
        llm_model = cfg.get("model") or settings.LLM_MODEL
        _imode = cfg.get("instructor_mode")
        _max_tokens = cfg.get("max_tokens", settings.LLM_MAX_TOKENS)

        start = time.perf_counter()
        used_builtin_fallback = False
        llm_result: M1DecomposerLLMResult = await self._call_llm_with_schema(
            llm_model=llm_model,
            messages=messages,
            response_model=M1DecomposerLLMResult,
            temperature=0.2,
            instructor_mode=_imode,
            max_tokens=_max_tokens,
        )

        result_dict = llm_result.model_dump()
        raw_list = result_dict.get("function_list") or []
        fl = self._normalize_function_list(raw_list)
        invalid_kw = self._count_schema_keyword_in_list(fl)
        if invalid_kw > 0:
            fl = self._remove_schema_keyword_items(fl)

        result_dict["function_list"] = fl
        hop_limit = EXPAND_MAX_HOPS
        metrics = compute_function_list_metrics(fl)
        hops = max_parent_hops_to_root(fl)
        hop_bad = hops > hop_limit
        too_shallow = self._list_too_shallow(metrics, under_focus=True)

        if fl and (too_shallow or hop_bad or invalid_kw > 0):
            extra = self._build_retry_instruction(
                input_data=input_data,
                metrics=metrics,
                hops=hops,
                hop_limit=hop_limit,
                invalid_keyword_nodes=invalid_kw,
                too_shallow=too_shallow,
                hop_bad=hop_bad,
            )
            messages2 = list(messages) + [{"role": "user", "content": extra}]
            llm_result2: M1DecomposerLLMResult = await self._call_llm_with_schema(
                llm_model=llm_model,
                messages=messages2,
                response_model=M1DecomposerLLMResult,
                temperature=0.2,
                instructor_mode=_imode,
                max_tokens=_max_tokens,
            )
            result_dict2 = llm_result2.model_dump()
            fl2 = self._normalize_function_list(result_dict2.get("function_list") or [])
            invalid_kw2 = self._count_schema_keyword_in_list(fl2)
            if invalid_kw2 > 0:
                fl2 = self._remove_schema_keyword_items(fl2)
            result_dict2["function_list"] = fl2
            if invalid_kw2 > 0:
                result_dict2.setdefault("warnings", [])
                if isinstance(result_dict2["warnings"], list):
                    result_dict2["warnings"].append("检测到字段名污染节点，已自动清理")
            result_dict = result_dict2

        final_list = result_dict.get("function_list") or []
        final_metrics = compute_function_list_metrics(final_list)
        final_hops = max_parent_hops_to_root(final_list)
        final_invalid = self._count_schema_keyword_in_list(final_list)
        hop_bad_f = final_hops > hop_limit
        shallow_f = self._list_too_shallow(final_metrics, under_focus=True)

        if shallow_f or hop_bad_f or final_invalid > 0:
            result_dict = self._build_fallback_result(input_data)
            used_builtin_fallback = True

        result_dict = self._apply_f_id_scheme(result_dict, input_data)
        result_dict = self._prepend_synthetic_decomposition_root(result_dict, input_data)
        self._sync_integration_constraints_copy(result_dict.get("function_list") or [])

        art = input_data.artifacts or {}
        nrm = art.get("normalizer_result") if isinstance(art, dict) else None
        meta_extra: Dict[str, Any] = {
            "version": "m1_decomposer_v6_unified_focus",
            "model": llm_model,
            "time_cost_ms": int((time.perf_counter() - start) * 1000),
        }
        if isinstance(nrm, dict):
            nrm_out, removed_n = strip_matched_normalizer_constraints(
                nrm, result_dict.get("function_list") or []
            )
            meta_extra["normalizer_result"] = nrm_out
            meta_extra["constraint_distribution_removed_count"] = removed_n
            summary: List[Dict[str, Any]] = []
            for row in result_dict.get("function_list") or []:
                if not isinstance(row, dict):
                    continue
                rid = str(row.get("id") or "").strip()
                cons = row.get("constraints")
                if not isinstance(cons, list):
                    cons = []
                if rid and len(cons) > 0:
                    summary.append({"function_id": rid, "constraint_count": len(cons)})
            meta_extra["constraint_routing_summary"] = summary

        return BaseAgentOutput(
            agent_name=self.name,
            result={"result": result_dict},
            evidence=self._extract_evidence(result_dict),
            warnings=self._extract_warnings(result_dict),
            quality_flags=self._check_quality(
                result_dict, used_builtin_fallback=used_builtin_fallback
            ),
            meta=meta_extra,
        )

    @staticmethod
    def _sync_integration_constraints_copy(rows: List[Dict[str, Any]]) -> None:
        """INTEGRATION（外部依赖/集成边界）节点：写入 constraints 的深拷贝，避免后续链路改写 constraints 后无法追溯。"""
        for row in rows:
            if not isinstance(row, dict):
                continue
            nt = str(row.get("node_type") or "").strip().upper()
            cons = row.get("constraints")
            if not isinstance(cons, list):
                cons = []
            if nt == "INTEGRATION":
                row["constraints_copy"] = copy.deepcopy(cons)
            else:
                row["constraints_copy"] = []

    def _resolve_focus_node(self, art: Any) -> Optional[Dict[str, Any]]:
        if not isinstance(art, dict):
            return None
        focus = art.get("focus_node")
        if isinstance(focus, dict) and str(focus.get("id") or "").strip():
            return focus
        return None

    def _apply_f_id_scheme(self, result_dict: Dict[str, Any], input_data: AgentInput) -> Dict[str, Any]:
        fl = result_dict.get("function_list") or []
        if not fl:
            return result_dict
        art = input_data.artifacts or {}
        focus = self._resolve_focus_node(art)
        fl2, id_map = remap_function_list_to_f_ids(
            fl,
            mode_b=True,
            focus_node=focus,
        )
        rebuild_function_list_paths(fl2)
        out = dict(result_dict)
        out["function_list"] = fl2
        out["core_flow"] = apply_f_id_mapping_to_nested(out.get("core_flow") or [], id_map)
        return out

    def _prepend_synthetic_decomposition_root(
        self, result_dict: Dict[str, Any], input_data: AgentInput
    ) -> Dict[str, Any]:
        """首轮预处理根（F-1）：子节点由模型产出，父行在此补上以便下游树一致。"""
        focus = self._resolve_focus_node(input_data.artifacts or {})
        if not focus:
            return result_dict
        fid = str(focus.get("id") or "").strip()
        if fid != DECOMPOSITION_ROOT_ID:
            return result_dict
        fl = list(result_dict.get("function_list") or [])
        existing = {str(r.get("id") or "").strip() for r in fl if isinstance(r, dict)}
        if fid in existing:
            return result_dict
        fc = focus.get("constraints")
        constraints = copy.deepcopy(fc) if isinstance(fc, list) else []
        fcc = focus.get("constraints_copy")
        if isinstance(fcc, list) and len(fcc) > 0:
            constraints_copy = copy.deepcopy(fcc)
        else:
            constraints_copy = copy.deepcopy(constraints)
        root_row: Dict[str, Any] = {
            "id": fid,
            "title": str(focus.get("title") or "").strip() or "需求根节点",
            "desc": str(focus.get("desc") or "").strip(),
            "node_type": str(focus.get("node_type") or "DOMAIN").strip() or "DOMAIN",
            "granularity": str(focus.get("granularity") or "EPIC").strip() or "EPIC",
            "acceptance_hint": focus.get("acceptance_hint")
            if isinstance(focus.get("acceptance_hint"), list)
            else [],
            "parent_id": None,
            "path": str(focus.get("path") or focus.get("title") or "").strip()
            or str(focus.get("title") or ""),
            "constraints": constraints,
            "constraints_copy": constraints_copy,
        }
        try:
            root_row = FunctionListItem.model_validate(root_row).model_dump()
        except Exception:
            pass
        out = dict(result_dict)
        out["function_list"] = [root_row] + fl
        rebuild_function_list_paths(out["function_list"])
        return out

    def _normalize_function_list(self, raw: Any) -> List[Dict[str, Any]]:
        out: List[Dict[str, Any]] = []
        if not isinstance(raw, list):
            return out
        for item in raw:
            if isinstance(item, FunctionListItem):
                out.append(item.model_dump())
            elif isinstance(item, dict):
                try:
                    out.append(FunctionListItem.model_validate(item).model_dump())
                except Exception:
                    continue
        return out

    def _build_fallback_result(self, input_data: AgentInput) -> Dict[str, Any]:
        focus = self._resolve_focus_node(input_data.artifacts or {}) or {}
        parent_id = str(focus.get("id") or DECOMPOSITION_ROOT_ID).strip()
        text = str(input_data.normalized_requirement or input_data.requirement_text or "").strip()
        root_title = "功能拆分结果"
        if "订单" in text:
            root_title = "用户订单管理"
            return self._order_fallback_shallow(text, root_title, parent_id)
        if "任务" in text or "计划" in text:
            root_title = "任务计划管理"

        fl = [
            {
                "id": "fb_fb_1",
                "title": "核心业务流程",
                "desc": "需求中的主干业务能力",
                "node_type": "DOMAIN",
                "granularity": "FEATURE",
                "acceptance_hint": ["流程可闭环", "关键结果可验证"],
                "parent_id": parent_id,
                "path": "",
                "constraints": [],
                "constraints_copy": [],
            },
            {
                "id": "fb_fb_2",
                "title": "横切与可观测性",
                "desc": "统一错误提示、重试与日志",
                "node_type": "SUPPORT",
                "granularity": "FEATURE",
                "acceptance_hint": ["异常有用户可理解提示", "关键失败可重试或引导"],
                "parent_id": parent_id,
                "path": "",
                "constraints": [],
                "constraints_copy": [],
            },
            {
                "id": "fb_fb_3",
                "title": "范围与集成边界",
                "desc": "与外部系统或配置的边界说明",
                "node_type": "INTEGRATION",
                "granularity": "FEATURE",
                "acceptance_hint": ["集成对象明确", "失败可降级或提示"],
                "parent_id": parent_id,
                "path": "",
                "constraints": [],
                "constraints_copy": [],
            },
        ]
        core_flow = [
            {"step": "核心业务", "function_id": "fb_fb_1", "type": "MAIN"},
        ]
        return {"function_list": fl, "core_flow": core_flow}

    def _order_fallback_shallow(
        self, text: str, root_title: str, parent_id: str
    ) -> Dict[str, Any]:
        base = root_title
        fl: List[Dict[str, Any]] = [
            {
                "id": "fb_ord_1",
                "title": "账户与鉴权",
                "desc": "登录会话与访问个人订单的前置条件",
                "node_type": "DOMAIN",
                "granularity": "FEATURE",
                "acceptance_hint": ["未登录不可访问订单数据", "登录态可恢复"],
                "parent_id": parent_id,
                "path": "",
                "constraints": [],
                "constraints_copy": [],
            },
            {
                "id": "fb_ord_2",
                "title": "订单查询与列表展示",
                "desc": "列表、状态筛选、分页同属查询能力",
                "node_type": "DOMAIN",
                "granularity": "FEATURE",
                "acceptance_hint": ["查询条件可组合", "结果与条件一致"],
                "parent_id": parent_id,
                "path": "",
                "constraints": [],
                "constraints_copy": [],
            },
        ]
        next_idx = 3
        export_id: Optional[str] = None
        if "导出" in text:
            export_id = f"fb_ord_{next_idx}"
            next_idx += 1
            fl.append({
                "id": export_id,
                "title": "订单导出",
                "desc": "集成导出与下载",
                "node_type": "INTEGRATION",
                "granularity": "FEATURE",
                "acceptance_hint": ["导出格式与列一致", "大数据量有策略"],
                "parent_id": parent_id,
                "path": "",
                "constraints": [],
                "constraints_copy": [],
            })
        sup_id = f"fb_ord_{next_idx}"
        fl.append({
            "id": sup_id,
            "title": "横切：错误与可观测性",
            "desc": "统一错误提示、重试",
            "node_type": "SUPPORT",
            "granularity": "FEATURE",
            "acceptance_hint": ["异常有用户可理解提示", "关键失败可重试"],
            "parent_id": parent_id,
            "path": "",
            "constraints": [],
            "constraints_copy": [],
        })

        core_flow = [
            {"step": "账户与鉴权", "function_id": "fb_ord_1", "type": "MAIN"},
            {"step": "订单查询与展示", "function_id": "fb_ord_2", "type": "MAIN"},
        ]
        if export_id:
            core_flow.append({"step": "导出订单", "function_id": export_id, "type": "MAIN"})
        return {"function_list": fl, "core_flow": core_flow}

    def _build_user_content(self, input_data: AgentInput) -> str:
        art = input_data.artifacts or {}
        if not isinstance(art, dict):
            art = {}
        focus = art.get("focus_node")
        if not isinstance(focus, dict) or not str(focus.get("id") or "").strip():
            return (
                "缺少父功能点 artifacts.focus_node（须含有效 id）。\n"
                "请由预处理生成根节点或由编排层传入待拆父节点。"
            )

        content = "【在下列父功能点下展开一层子功能】\n"
        content += f"父功能点（focus_node）:\n{json.dumps(focus, ensure_ascii=False, indent=2)}\n"
        if input_data.requirement_text:
            content += f"\n补充需求原文:\n{input_data.requirement_text}\n"
        if input_data.normalized_requirement:
            content += f"\n标准化需求（上下文）:\n{input_data.normalized_requirement}\n"

        nrm = art.get("normalizer_result") if isinstance(art, dict) else None
        constraint_list: list = []
        if isinstance(nrm, dict):
            cn = nrm.get("constraints")
            if isinstance(cn, list):
                constraint_list = list(cn)
            elif isinstance(cn, dict):
                inner_items = cn.get("items")
                if isinstance(inner_items, list):
                    constraint_list = list(inner_items)
        if isinstance(nrm, dict) and constraint_list:
            content += (
                "\nNormalizer 结构化字段（拆分必须与之一致；**constraints** 须分发到 function_list 各行）：\n"
                + json.dumps(
                    {"constraints": constraint_list},
                    ensure_ascii=False,
                    indent=2,
                )
                + "\n"
            )

        if input_data.context:
            content += f"\n上下文:\n{input_data.context}\n"

        if input_data.config:
            content += f"\n配置:\n{input_data.config}\n"

        content += (
            "\n【当前 ID 规则】子节点 parent_id 必须等于上述父功能点的 id；"
            "id/parent_id 为字符串形式的 F-* 路径；**不要**输出父节点本身（仅输出子节点）。"
            "\n请输出：function_list（扁平数组）+ core_flow。"
            "\n关键格式要求："
            "\n1) function_list 每项含 id/title/desc/node_type/granularity/acceptance_hint/parent_id/path/**constraints**（数组，必出现；无则 []）"
            "\n2) 仅在父节点下多一层，禁止 F-x.y.z 再向下拆第三层"
            "\n3) 禁止用 id/title 充当 schema 字段名（如纯 id、纯 title 作为业务名）"
        )
        return content

    def _extract_evidence(self, result: Dict[str, Any]) -> Optional[list]:
        ev = []
        if result.get("function_list"):
            ev.append(f"已输出功能列表条数: {len(result['function_list'])}")
        if result.get("core_flow"):
            ev.append(f"已输出主流程步骤数: {len(result['core_flow'])}")
        return ev or None

    def _extract_warnings(self, result: Dict[str, Any]) -> Optional[list]:
        warnings = []
        metrics = compute_function_list_metrics(result.get("function_list") or [])
        total_nodes = metrics.get("total_nodes")
        leaf_nodes = metrics.get("leaf_nodes")

        if isinstance(total_nodes, int) and total_nodes < 3:
            warnings.append("拆分条目偏少，可在后续评估驱动细化中扩展")
        if isinstance(leaf_nodes, int) and leaf_nodes < 3:
            warnings.append("叶子节点偏少，可能需要后续细化")

        return warnings or None

    @staticmethod
    def _list_too_shallow(metrics: Dict[str, Any], *, under_focus: bool = True) -> bool:
        try:
            total_nodes = int(metrics.get("total_nodes") or 0)
        except Exception:
            return True
        if total_nodes < 1:
            return True
        if under_focus and total_nodes < 2:
            return True
        return False

    def _build_retry_instruction(
        self,
        *,
        input_data: AgentInput,
        metrics: Dict[str, Any],
        hops: int,
        hop_limit: int,
        invalid_keyword_nodes: int = 0,
        too_shallow: bool,
        hop_bad: bool,
    ) -> str:
        parts: List[str] = []
        if too_shallow:
            parts.append(
                "上一轮覆盖偏少。请增加「挂在父功能点下的子节点」数量（子节点建议>=3），"
                "通过加并列域/模块来补，**不要**用增加树深度来凑。"
            )
        if hop_bad:
            parts.append(
                f"上一轮 parent 链过长（max_hops={hops}，允许<={hop_limit}）。"
                "请删除所有孙节点及以下，仅保留父下的直系子节点。"
            )
        if invalid_keyword_nodes > 0:
            parts.append(
                f"上一轮检测到 {invalid_keyword_nodes} 个“字段名污染”节点。"
                "\n请用真实业务动作命名 id/title。"
            )
        leaf_nodes = metrics.get("leaf_nodes")
        total_nodes = metrics.get("total_nodes")
        parts.append(
            f"（上一轮统计 total_nodes={total_nodes}, leaf_nodes={leaf_nodes}）\n"
            "请重新输出完整 function_list + core_flow；core_flow 仅引用存在的 function id。"
        )
        return "\n".join(parts)

    def _check_quality(
        self, result: Dict[str, Any], *, used_builtin_fallback: bool = False
    ) -> list:
        flags = super()._check_quality(result)
        if not result.get("function_list"):
            flags.append("missing_function_list")
        if used_builtin_fallback:
            flags.append("decomposer_schema_fallback_applied")

        metrics = compute_function_list_metrics(result.get("function_list") or [])
        hops = max_parent_hops_to_root(result.get("function_list") or [])
        leaf_nodes = metrics.get("leaf_nodes")

        if isinstance(leaf_nodes, int) and leaf_nodes < 2:
            flags.append("COARSE_LEAF")
        if hops > EXPAND_MAX_HOPS:
            flags.append("LAYER_POLICY_TOO_DEEP")
        fl = result.get("function_list")
        if isinstance(fl, list) and not self._list_has_resilience(fl):
            flags.append("MISSING_EXCEPTION_BRANCH")
        return flags

    def _list_has_resilience(self, fl: List[Dict[str, Any]]) -> bool:
        for it in fl:
            if not isinstance(it, dict):
                continue
            nt = str(it.get("node_type") or "").upper()
            if nt in ("EXCEPTION", "SUPPORT"):
                return True
        return False

    def _count_schema_keyword_in_list(self, fl: List[Dict[str, Any]]) -> int:
        n = 0
        for it in fl:
            if not isinstance(it, dict):
                continue
            rid = str(it.get("id") or "").strip()
            rtitle = str(it.get("title") or "").strip()
            if self._is_schema_keyword_label(rid) or self._is_schema_keyword_label(rtitle):
                n += 1
        return n

    def _remove_schema_keyword_items(self, fl: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        out: List[Dict[str, Any]] = []
        for it in fl:
            if not isinstance(it, dict):
                continue
            rid = str(it.get("id") or "").strip()
            rtitle = str(it.get("title") or "").strip()
            if self._is_schema_keyword_label(rid) or self._is_schema_keyword_label(rtitle):
                continue
            out.append(it)
        return out

    def _is_schema_keyword_label(self, text: str) -> bool:
        if not text:
            return False
        normalized = text.strip().lower()
        if normalized in SCHEMA_KEYWORDS:
            return True

        parts = [p for p in re.split(r"[:\-\s_]+", normalized) if p]
        if not parts:
            return False
        return parts[0] in SCHEMA_KEYWORDS
