from typing import Any, Dict, List, Optional
from collections import defaultdict, deque

from app.services.agents.base_agent import BaseAgent
from app.schemas.agent import AgentInput, BaseAgentOutput
from app.services.agents.function_list_bridge import function_tree_from_artifacts
from app.services.agents.M1.schemas.m1_dependency import (
    M1DependencyLLMResult,
    migrate_dependency_edge_dict,
)
from app.services.agents.M1.dependency_trigger_zh import dependency_trigger_to_zh
from app.core.config import settings
import json


DEFAULT_SYSTEM_PROMPT = """
你是「依赖识别与分类（DependencyClassifier）」智能体：在功能树与标准化需求之上输出依赖边与 metrics。

若用户消息中附带 **core_flow**（功能拆分产出的主流程骨架），请用作 **EXEC_ORDER** 与主链覆盖的参考；若与 function_list 节点或 id 不一致，以 **function_list** 为准。

## dependency_type（每条依赖必填，仅三选一）
- **DATA**：数据/契约传递（谁产出字段、谁消费；筛选入参、查询结果、导出载荷等）。
- **EXEC_ORDER**：执行顺序/拓扑（必须先完成 A 再执行 B；用于排序的主干边）。
- **RESOURCE**：资源与外部约束（权限、SDK、文件 IO 等；须填 resources_required）。

强弱与异常路径用字段 **severity**、**degradation_mode** / **degradation_note** 表达，不要另造 HARD/SOFT 或第二套「维度」字段。

## 核心原则
1. **筛选/过滤**：筛选条件是查询入参，用 **dependency_type=DATA**，不要用 EXEC_ORDER 表达「列表→筛选」。
2. **导出**：用 DATA 表达 `export_payload` / `order_list` 等，避免用 EXEC_ORDER 强行串「筛选→导出」的唯一顺序。
3. **异常**：不要用 EXEC_ORDER 把「正常步骤→异常处理」连成主序；用 DATA 传错误上下文，或用 degradation 表达旁路。
4. **语义化 IO**：requires/provides 用业务字段名；避免整条线只有 flow_context/step_output。
5. **trigger**：必须是**短字符串**（禁止 `{condition: ...}` 对象），使用**中文**短语描述触发时机（如「筛选参数变更」「导出请求」「详情加载完成」）；勿使用英文 snake_case。
6. **去冗余**：若已有 A→B→C 的 EXEC_ORDER 链，不要重复加 A→C 直达 EXEC_ORDER。
7. **自环**：禁止 from==to。**RESOURCE** 须填 resources_required。

## 输出规模
- 总依赖 8～15 条（最多 18）；DATA 与 EXEC_ORDER 混合，避免全部为 EXEC_ORDER。

## 每条依赖
- trigger、description、direction_explain、degradation_note 保持短句；每条至少 1 个 requires 与 1 个 provides（业务字段优先）。

## 输出格式
- 仅输出 dependencies + metrics；每条 **dependency_type** 只能是 DATA、EXEC_ORDER、RESOURCE 之一；dep_id 连续 D-001…；不要额外解释文字。
"""


class M1DependencyClassifierAgent(BaseAgent):

    def __init__(
        self,
        name: str = "M1-DependencyClassifier",
        description: str = (
            "依赖识别：dependency_type 为 DATA | EXEC_ORDER | RESOURCE；"
            "强弱用 severity，缺失时用 degradation_mode/degradation_note；补齐 trigger 与 IO"
        ),
        system_prompt: str = DEFAULT_SYSTEM_PROMPT
    ):
        super().__init__(name=name, description=description, system_prompt=system_prompt)

    async def execute(self, input_data: AgentInput) -> BaseAgentOutput:
        messages = self._build_messages(input_data)
        cfg = input_data.config or {}
        llm_model = cfg.get("model") or settings.LLM_MODEL

        llm_result: M1DependencyLLMResult = await self._call_llm_with_schema(
            llm_model=llm_model,
            messages=messages,
            response_model=M1DependencyLLMResult,
            temperature=0.2,
            max_tokens=cfg.get("max_tokens", settings.LLM_MAX_TOKENS),
            instructor_mode=cfg.get("instructor_mode"),
        )

        result_dict = llm_result.model_dump(by_alias=True)
        result_dict = self._finalize_dependencies(result_dict, input_data)
        result_dict = M1DependencyLLMResult.model_validate(result_dict).model_dump(by_alias=True)

        return BaseAgentOutput(
            agent_name=self.name,
            result={"result": result_dict},
            evidence=self._extract_evidence(result_dict),
            warnings=self._extract_warnings(result_dict),
            quality_flags=self._check_quality(result_dict),
            metadata={"version": "m1_dependency_v4", "model": llm_model}
        )

    def _count_tree_leaves(self, tree: Any) -> int:
        if not isinstance(tree, dict):
            return 1

        def walk(node: Dict[str, Any]) -> int:
            ch = node.get("children") or []
            if not ch:
                return 1
            n = 0
            for c in ch:
                if isinstance(c, dict):
                    n += walk(c)
            return max(n, 1)

        return walk(tree)

    def _finalize_dependencies(self, result_dict: Dict[str, Any], input_data: AgentInput) -> Dict[str, Any]:
        """补齐 dep_id / IO / 降级说明，并重算 metrics，保证与 schema 及统计一致。"""
        deps: List[Dict[str, Any]] = []
        raw = result_dict.get("dependencies") or []
        for dep in raw:
            if not isinstance(dep, dict):
                continue
            d = migrate_dependency_edge_dict(dict(dep))
            fid0 = (d.get("from") or "").strip()
            tid0 = (d.get("to") or "").strip()
            if fid0 and tid0 and fid0 == tid0:
                continue
            did = (d.get("dep_id") or "").strip()
            if not did:
                d["dep_id"] = f"D-{len(deps) + 1:03d}"
            d["trigger"] = dependency_trigger_to_zh(d.get("trigger") or "")
            req = d.get("requires") or []
            prov = d.get("provides") or []
            if not req and not prov:
                d["requires"] = [
                    {"field": "flow_context", "data_type": "object", "source": "SYSTEM", "required": True}
                ]
                d["provides"] = [
                    {"field": "step_output", "data_type": "object", "source": "SYSTEM", "required": True}
                ]
            if d.get("requires") is None:
                d["requires"] = []
            if d.get("provides") is None:
                d["provides"] = []
            if d.get("resources_required") is None:
                d["resources_required"] = []
            if d.get("dependency_type") == "RESOURCE" and not (d.get("resources_required") or []):
                d["resources_required"] = [
                    {
                        "kind": "sdk",
                        "name": "EXPORT_OR_FILE_IO",
                        "notes": "导出/表格生成所需运行时或库（按技术栈选型）",
                    }
                ]
            note = (d.get("degradation_note") or "").strip()
            if not note:
                mode = d.get("degradation_mode") or "PROMPT"
                d["degradation_note"] = f"按{mode}策略处理依赖缺失场景"
            deps.append(d)
        deps = self._dedupe_redundant_exec_edges(deps)
        for j, dep in enumerate(deps):
            dep["dep_id"] = f"D-{j + 1:03d}"
        result_dict["dependencies"] = deps
        art = input_data.artifacts or {}
        tree_for_leaf = function_tree_from_artifacts(art if isinstance(art, dict) else {})
        leaf_n = self._count_tree_leaves(tree_for_leaf)
        result_dict["metrics"] = self._compute_dependency_metrics(deps, leaf_n)
        return result_dict

    def _compute_dependency_metrics(self, deps: List[Dict[str, Any]], leaf_count: int) -> Dict[str, Any]:
        n = len(deps)
        missing_trigger = 0
        missing_io = 0
        data_dep = 0
        control_dep = 0
        resource_dep = 0
        lc = max(leaf_count, 1)
        for d in deps:
            if not (d.get("trigger") or "").strip():
                missing_trigger += 1
            req = d.get("requires") or []
            prov = d.get("provides") or []
            if not req and not prov:
                missing_io += 1
            dt0 = d.get("dependency_type") or ""
            if dt0 == "DATA":
                data_dep += 1
            elif dt0 == "EXEC_ORDER":
                control_dep += 1
            elif dt0 == "RESOURCE":
                resource_dep += 1
        avg = n / lc
        return {
            "total_dependencies": n,
            "avg_deps_per_leaf": round(float(avg), 2),
            "missing_trigger_count": missing_trigger,
            "missing_io_count": missing_io,
            "resource_dep_count": resource_dep,
            "data_dep_count": data_dep,
            "exec_dep_count": control_dep,
        }

    def _exec_path_exists_excluding(
        self, deps: List[Dict[str, Any]], exclude_idx: int, start: str, end: str
    ) -> bool:
        """在去掉第 exclude_idx 条 EXEC_ORDER 边后，start 是否仍能到达 end（用于检测冗余直达边）。"""
        g: Dict[str, List[str]] = defaultdict(list)
        for j, d in enumerate(deps):
            if j == exclude_idx:
                continue
            if d.get("dependency_type") != "EXEC_ORDER":
                continue
            a = (d.get("from") or "").strip()
            b = (d.get("to") or "").strip()
            if a and b:
                g[a].append(b)
        q = deque([start])
        seen = {start}
        while q:
            u = q.popleft()
            if u == end:
                return True
            for v in g.get(u, []):
                if v not in seen:
                    seen.add(v)
                    q.append(v)
        return False

    def _dedupe_redundant_exec_edges(self, deps: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        removable: set[int] = set()
        for i, d in enumerate(deps):
            if d.get("dependency_type") != "EXEC_ORDER":
                continue
            a = (d.get("from") or "").strip()
            b = (d.get("to") or "").strip()
            if not a or not b or a == b:
                continue
            if self._exec_path_exists_excluding(deps, i, a, b):
                removable.add(i)
        return [d for k, d in enumerate(deps) if k not in removable]

    def _build_user_content(self, input_data: AgentInput) -> str:
        art = input_data.artifacts or {}
        fl = art.get("function_list") if isinstance(art, dict) else None
        function_tree = function_tree_from_artifacts(art if isinstance(art, dict) else {})

        if isinstance(fl, list) and len(fl) > 0:
            content = "功能点列表（function_list，扁平行）:\n"
            content += json.dumps(fl, ensure_ascii=False, separators=(",", ":")) + "\n"
        elif function_tree:
            content = "功能树（由 function_list 组装或兼容 artifacts.function_tree）:\n"
            content += json.dumps(function_tree, ensure_ascii=False, separators=(",", ":")) + "\n"
        else:
            return (
                "缺少功能点列表（artifacts.function_list）。\n"
                "请先运行 FunctionalDecomposer，再运行本智能体。"
            )

        norm = (input_data.artifacts or {}).get("normalizer_result")
        if isinstance(norm, dict) and norm:
            content += "\n标准化需求摘要（normalizer_result，含性能/外部依赖列表时请在依赖分类中纳入）:\n"
            content += json.dumps(norm, ensure_ascii=False, separators=(",", ":")) + "\n"

        cf = art.get("core_flow") if isinstance(art, dict) else None
        if isinstance(cf, list) and len(cf) > 0:
            content += (
                "\n主流程骨架（core_flow，来自功能拆分；作顺序与主链参考，function_id 须与功能点 id 一致；"
                "若与 function_list 矛盾以 function_list 为准）:\n"
            )
            content += json.dumps(cf, ensure_ascii=False, separators=(",", ":")) + "\n"

        if input_data.context:
            content += f"\n上下文:\n{input_data.context}\n"

        if input_data.config:
            content += f"\n配置:\n{input_data.config}\n"

        content += "\n请输出：依赖集合 + 指标（依赖类型分布、缺失项统计）。"
        return content

    def _extract_evidence(self, result: Dict[str, Any]) -> Optional[list]:
        deps = result.get("dependencies") or []
        return [f"已输出依赖数量: {len(deps)}"] if deps else None

    def _extract_warnings(self, result: Dict[str, Any]) -> Optional[list]:
        warnings = []
        metrics = result.get("metrics") or {}
        if metrics.get("missing_trigger_count", 0) > 0:
            warnings.append("存在缺失触发条件的依赖")
        if metrics.get("missing_io_count", 0) > 0:
            warnings.append("存在缺失字段化IO的依赖")
        return warnings or None

    def _check_quality(self, result: Dict[str, Any]) -> list:
        flags = super()._check_quality(result)
        if not result.get("dependencies"):
            flags.append("empty_dependencies")
        if not result.get("metrics"):
            flags.append("missing_dependency_metrics")
        return flags
