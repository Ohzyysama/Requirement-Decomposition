"""
智能体调用器（薄调用层）— 封装单个 LLM Agent 的调用接口。

职责：
  1. 单个 Agent 的输入构建（输入瘦身、AgentInput 组装）
  2. 调用单个 Agent 并写入单条 artifact
  3. 快照、episode、质量标记等共享辅助方法

多步骤管线编排由 PipelineRunner 负责；子 AR 递归由 SubARRefiner 负责。
"""
from typing import Dict, Any, Optional, Callable, Awaitable, List
import copy
import json
import logging
import uuid
from datetime import datetime
from app.core.config import settings

from app.schemas.agent import AgentInput, BaseAgentOutput
from app.services.coordinator.context import CoordinatorContext
from app.services.coordinator.agent_timeline import with_llm_agent_span

_OPENAI_ONLY_MODELS = frozenset({
    "gpt-4o-mini", "gpt-4o", "gpt-4", "gpt-4-turbo",
    "gpt-3.5-turbo", "gpt-3.5-turbo-16k", "gpt-3.5-turbo-0125",
})

from app.services.agents.M1.agents.m1_normalizer_agent import M1NormalizerAgent
from app.services.agents.M1.agents.m1_decomposer_agent import M1FunctionalDecomposerAgent
from app.services.agents.M1.agents.m1_dependency_agent import M1DependencyClassifierAgent
from app.services.agents.M2.agents.m2_consistency_agent import M2ConsistencyEvaluatorAgent
from app.services.agents.M2.agents.m2_feasibility_agent import M2FeasibilityEvaluatorAgent
from app.services.agents.M2.agents.m2_integrator_agent import M2EvaluationIntegratorAgent
from app.services.coordinator.tree_utils import (
    sub_requirement_list_stats,
)
from app.schemas.evaluation_episodes import (
    EpisodeM2Bundle,
    EvaluationEpisodeRecord,
    EvaluationScopeKind,
)

logger = logging.getLogger(__name__)

# M2 评估前从功能列表中排除的节点 id（如 Normalizer 派生的占位根，不参与细评）
_M2_EXCLUDED_FUNCTION_IDS = frozenset({"F-1"})


class AgentInvoker:
    """智能体调用器（薄调用层）"""

    def __init__(self):
        self._m1_normalizer = M1NormalizerAgent()
        self._m1_decomposer = M1FunctionalDecomposerAgent()
        self._m1_dependency = M1DependencyClassifierAgent()
        self._m2_consistency = M2ConsistencyEvaluatorAgent()
        self._m2_feasibility = M2FeasibilityEvaluatorAgent()
        self._m2_integrator = M2EvaluationIntegratorAgent()

    # ───────────── 辅助：Pydantic 安全序列化 ─────────────

    @staticmethod
    def _to_serializable(obj: Any) -> Any:
        """递归将对象转为可 JSON 序列化的格式"""
        if hasattr(obj, "model_dump"):
            return obj.model_dump()
        if hasattr(obj, "__dict__"):
            return {k: AgentInvoker._to_serializable(v) for k, v in obj.__dict__.items()}
        if isinstance(obj, dict):
            return {k: AgentInvoker._to_serializable(v) for k, v in obj.items()}
        if isinstance(obj, list):
            return [AgentInvoker._to_serializable(v) for v in obj]
        if callable(obj):
            return f"<function {obj.__name__ if hasattr(obj, '__name__') else 'anonymous'}>"
        return obj

    @staticmethod
    def _m2_standard_input_signature(std: Any) -> str:
        """用于 history 连续去重：同内容 m2_standard_input 不重复落条。"""
        try:
            return json.dumps(std, sort_keys=True, ensure_ascii=False, default=str)
        except TypeError:
            return repr(std)

    @staticmethod
    def _m2_snapshot_history_signature(snap: Any, pipeline_stage: str) -> str:
        """去重键：标准输入 + 可选 m2_scope + pipeline_stage。"""
        if not isinstance(snap, dict):
            snap = {}
        payload = {
            "m2_standard_input": snap.get("m2_standard_input"),
            "m2_scope": snap.get("m2_scope"),
            "pipeline_stage": pipeline_stage or "",
        }
        try:
            return json.dumps(payload, sort_keys=True, ensure_ascii=False, default=str)
        except TypeError:
            return repr(payload)

    @staticmethod
    def _prune_evaluation_episodes_for_append(
        eps: List[Any],
        *,
        new_scope: EvaluationScopeKind,
        new_root: Optional[str],
        new_tv: int,
    ) -> List[Dict[str, Any]]:
        """写入新 episode 前裁剪列表。"""
        out: List[Dict[str, Any]] = []
        nr = str(new_root).strip() if new_root else ""
        for ep in eps:
            if not isinstance(ep, dict):
                continue
            raw_sc = ep.get("scope")
            sc = (
                raw_sc.value
                if hasattr(raw_sc, "value")
                else str(raw_sc or "").strip().lower()
            )
            is_full = sc == EvaluationScopeKind.FULL_TREE.value
            if new_scope == EvaluationScopeKind.FULL_TREE:
                if is_full:
                    continue
                out.append(ep)
                continue
            if is_full:
                out.append(ep)
                continue
            sr = ep.get("scope_root_node_id") or ep.get("parent_node_id")
            sr = str(sr).strip() if sr else ""
            otv = int(ep.get("tree_version", 0) or 0)
            if nr and sr == nr and otv < int(new_tv):
                continue
            out.append(ep)
        return out

    def _append_evaluation_episode(
        self,
        context: CoordinatorContext,
        *,
        parent_node_id: Optional[str],
        scope_kind: str,
        scope_root_node_id: Optional[str],
    ) -> None:
        """将当前 artifacts 中的 M2 三联快照追加到 evaluation_episodes。"""
        eps = context.artifacts.get("evaluation_episodes")
        if not isinstance(eps, list):
            eps = []
        sk = (
            EvaluationScopeKind.SUBTREE
            if scope_kind == "subtree"
            else EvaluationScopeKind.FULL_TREE
        )
        new_tv = int(getattr(context, "tree_version", 0) or 0)
        eps = self._prune_evaluation_episodes_for_append(
            eps,
            new_scope=sk,
            new_root=scope_root_node_id,
            new_tv=new_tv,
        )
        seq = len(eps) + 1
        tid = str(context.conversation_id or "task")[:48]
        eid = f"ep_{tid}_tv{new_tv}_{seq}_{uuid.uuid4().hex[:8]}"

        def _safe_dict(key: str) -> Dict[str, Any]:
            raw = context.artifacts.get(key)
            return copy.deepcopy(raw) if isinstance(raw, dict) else {}

        bundle = EpisodeM2Bundle(evaluation=_safe_dict("evaluation"))
        rec = EvaluationEpisodeRecord(
            episode_id=eid,
            parent_node_id=parent_node_id,
            tree_version=new_tv,
            scope=sk,
            scope_root_node_id=scope_root_node_id,
            captured_at=datetime.now().isoformat(),
            bundle=bundle,
        )
        eps.append(rec.model_dump())
        context.add_artifact("evaluation_episodes", eps, agent="coordinator")

    def _append_evaluation_episode_after_m2_tail(
        self,
        context: CoordinatorContext,
    ) -> None:
        """根据 artifacts.m2_scope 判断全树或子树 episode。"""
        m2_scope = context.artifacts.get("m2_scope")
        if isinstance(m2_scope, dict) and m2_scope.get("scope_root_node_id"):
            sid = str(m2_scope.get("scope_root_node_id") or "").strip()
            if sid:
                self._append_evaluation_episode(
                    context,
                    parent_node_id=sid,
                    scope_kind="subtree",
                    scope_root_node_id=sid,
                )
                return
        self._append_evaluation_episode(
            context,
            parent_node_id=None,
            scope_kind="full_tree",
            scope_root_node_id=None,
        )

    @staticmethod
    def _extract_feasibility_failed_node_ids(feas: Dict[str, Any]) -> List[str]:
        """从可实现性评估 dict 收集未通过规则涉及的节点 id。"""
        out: List[str] = []
        seen: set = set()

        def _collect_from_rule(item: Any) -> None:
            if not isinstance(item, dict):
                return
            if item.get("passed") is True:
                return
            for n in item.get("affected_nodes") or []:
                s = str(n).strip()
                if s and s not in seen:
                    seen.add(s)
                    out.append(s)

        for item in feas.get("critical_issues") or []:
            _collect_from_rule(item)
        for item in feas.get("rule_results") or []:
            _collect_from_rule(item)
        return out

    @staticmethod
    def _input_phase_from_pipeline_stage(context: CoordinatorContext) -> str:
        raw = str(getattr(context, "pipeline_stage", "") or "").strip()
        mapping = {
            "consistency": "main_m2",
            "refine_sub_ar": "sub_ar",
            "feasibility": "feasibility_m2",
        }
        return mapping.get(raw, raw or "unknown")

    @staticmethod
    def _sub_ar_stack_tail_for_snapshot(
        context: CoordinatorContext,
    ) -> Optional[Dict[str, Any]]:
        stack = getattr(context, "sub_ar_refinement_stack", None) or []
        if not stack:
            return None
        top = stack[-1]
        if not isinstance(top, dict):
            return None
        out: Dict[str, Any] = {}
        if top.get("node_id") is not None:
            out["node_id"] = top.get("node_id")
        if top.get("wave_depth") is not None:
            out["wave_depth"] = top.get("wave_depth")
        return out or None

    # ───────────── 辅助：构建 AgentInput ─────────────

    _M1_CONFIG_ALLOW_KEYS = frozenset({
        "model",
        "instructor_mode",
        "max_tokens",
        "split_retry_hints",
    })
    _M1_CONTEXT_ALLOW_KEYS = frozenset({"user_feedback"})

    @staticmethod
    def _m1_slim_config(full_config: Dict[str, Any]) -> Dict[str, Any]:
        out: Dict[str, Any] = {}
        for k in AgentInvoker._M1_CONFIG_ALLOW_KEYS:
            if k in full_config and full_config[k] is not None:
                out[k] = full_config[k]
        if not out.get("model") or out.get("model") in _OPENAI_ONLY_MODELS:
            out["model"] = settings.LLM_MODEL
        return out

    @staticmethod
    def _slim_context_for_m1(ctx: Optional[Dict[str, Any]]) -> Dict[str, Any]:
        if not isinstance(ctx, dict) or not ctx:
            return {}
        slim: Dict[str, Any] = {}
        for k in AgentInvoker._M1_CONTEXT_ALLOW_KEYS:
            if k in ctx and ctx[k] is not None:
                slim[k] = ctx[k]
        return slim

    @staticmethod
    def _slim_norm_for_decomposer(norm: Dict[str, Any]) -> Dict[str, Any]:
        return {"constraints": norm.get("constraints") or []}

    @staticmethod
    def _slim_norm_for_dependency(norm: Dict[str, Any]) -> Dict[str, Any]:
        _SKIP = {"assumptions", "open_questions", "glossary_candidates"}
        return {k: v for k, v in norm.items() if k not in _SKIP}

    @staticmethod
    def _slim_norm_for_consistency(norm: Dict[str, Any]) -> Dict[str, Any]:
        return {
            "normalized_requirement": norm.get("normalized_requirement", ""),
            "constraints_copy": norm.get("constraints_copy") or [],
        }

    @staticmethod
    def _slim_norm_for_feasibility(norm: Dict[str, Any]) -> Dict[str, Any]:
        return {"normalized_requirement": norm.get("normalized_requirement", "")}

    @staticmethod
    def _slim_fl_for_consistency(fl: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        _KEEP = {"id", "title", "desc", "constraints"}
        return [
            {k: v for k, v in item.items() if k in _KEEP}
            for item in fl
            if isinstance(item, dict)
        ]

    @staticmethod
    def _slim_fl_for_feasibility(fl: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        _KEEP = {"id", "title", "desc"}
        return [
            {k: v for k, v in item.items() if k in _KEEP}
            for item in fl
            if isinstance(item, dict)
        ]

    @staticmethod
    def _filter_function_list_for_m2(fl: List[Any]) -> List[Dict[str, Any]]:
        if not isinstance(fl, list):
            return []
        out: List[Dict[str, Any]] = []
        for item in fl:
            if not isinstance(item, dict):
                continue
            nid = str(item.get("id") or "").strip()
            if nid in _M2_EXCLUDED_FUNCTION_IDS:
                continue
            out.append(item)
        return out

    @staticmethod
    def _filter_dependencies_for_m2(
        deps: List[Any],
        excluded_ids: frozenset[str],
    ) -> List[Dict[str, Any]]:
        if not isinstance(deps, list):
            return []
        out: List[Dict[str, Any]] = []
        for item in deps:
            if not isinstance(item, dict):
                continue
            fr = item.get("from")
            if fr is None:
                fr = item.get("from_")
            to = item.get("to")
            if to is None:
                to = item.get("to_id") or item.get("target_id")
            fid = str(fr or "").strip()
            tid = str(to or "").strip()
            if fid in excluded_ids or tid in excluded_ids:
                continue
            out.append(item)
        return out

    def _build_input(
        self,
        context: CoordinatorContext,
        *,
        normalized_requirement: Any = None,
        artifacts: Optional[Dict[str, Any]] = None,
    ) -> AgentInput:
        return AgentInput(
            task_id=context.conversation_id,
            requirement_text=context.requirement_text,
            normalized_requirement=normalized_requirement,
            artifacts=artifacts or {},
            context=self._slim_context_for_m1(context.context),
            config=self._m1_slim_config(context.config or {}),
        )

    _M2_CONFIG_ALLOW_KEYS = frozenset({"model", "temperature"})

    @staticmethod
    def _m2_slim_config(full_config: Dict[str, Any]) -> Dict[str, Any]:
        out: Dict[str, Any] = {}
        for k in AgentInvoker._M2_CONFIG_ALLOW_KEYS:
            if k in full_config and full_config[k] is not None:
                out[k] = full_config[k]
        if not out.get("model") or out.get("model") in _OPENAI_ONLY_MODELS:
            out["model"] = settings.LLM_MODEL
        return out

    def _build_m2_eval_input(
        self,
        context: CoordinatorContext,
        *,
        stage: str,
        integrator_extras: Optional[Dict[str, Any]] = None,
        function_list_override: Optional[List[Dict[str, Any]]] = None,
        dependencies_override: Optional[List[Dict[str, Any]]] = None,
    ) -> AgentInput:
        """
        M2 最小化输入。

        function_list_override / dependencies_override 用于子 AR 作用域评估，
        传入时不读取 context.artifacts（避免污染全树状态）。
        """
        fl = function_list_override if function_list_override is not None \
            else context.artifacts.get("function_list")
        deps = dependencies_override if dependencies_override is not None \
            else context.artifacts.get("dependencies")
        fl = self._filter_function_list_for_m2(fl if isinstance(fl, list) else [])
        deps = self._filter_dependencies_for_m2(
            deps if isinstance(deps, list) else [],
            _M2_EXCLUDED_FUNCTION_IDS,
        )
        norm = context.artifacts.get("normalized_requirement")
        norm_dict = norm if isinstance(norm, dict) else {}

        if stage == "consistency":
            arts: Dict[str, Any] = {
                "function_list": self._slim_fl_for_consistency(fl if isinstance(fl, list) else []),
                "dependencies": deps if isinstance(deps, list) else [],
                "normalizer_result": self._slim_norm_for_consistency(norm_dict),
            }
        elif stage == "feasibility":
            arts = {
                "function_list": self._slim_fl_for_feasibility(fl if isinstance(fl, list) else []),
                "normalizer_result": self._slim_norm_for_feasibility(norm_dict),
            }
        elif stage == "integrator":
            arts = {}
            if integrator_extras:
                arts.update(integrator_extras)
        else:
            norm_copy = copy.deepcopy(norm_dict) if norm_dict else {}
            arts = {
                "function_list": fl if isinstance(fl, list) else [],
                "dependencies": deps if isinstance(deps, list) else [],
                "normalizer_result": norm_copy,
            }
            if integrator_extras:
                arts.update(integrator_extras)

        return AgentInput(
            task_id=context.conversation_id,
            requirement_text=context.requirement_text or "",
            normalized_requirement=None,
            artifacts=arts,
            context={},
            config=self._m2_slim_config(context.config or {}),
        )

    @staticmethod
    def _warn_if_missing_m2_preprocess(context: CoordinatorContext) -> None:
        if context.artifacts.get("normalized_requirement") is None:
            logger.warning(
                f"[{context.conversation_id}] M2：缺少 normalized_requirement"
            )
            context.add_quality_flag("coordinator", "m2_missing_normalizer_preprocess")

    def build_m2_inputs_snapshot(
        self,
        context: CoordinatorContext,
        *,
        function_list_override: Optional[List[Dict[str, Any]]] = None,
        dependencies_override: Optional[List[Dict[str, Any]]] = None,
    ) -> Dict[str, Any]:
        """构建 M2 标准输入快照（从 artifacts 读取，包括 m2_scope 元数据）。

        function_list_override / dependencies_override：子 AR 作用域评估时传入，
        使快照中的 actual_m2_input 字段真实反映 M2 agent 实际接收到的数据；
        m2_standard_input 仍记录完整树状态，便于对比上下文。
        """
        fl_raw = context.artifacts.get("function_list")
        deps_raw = context.artifacts.get("dependencies")
        norm = context.artifacts.get("normalized_requirement")
        fl = self._filter_function_list_for_m2(fl_raw if isinstance(fl_raw, list) else [])
        deps = self._filter_dependencies_for_m2(
            deps_raw if isinstance(deps_raw, list) else [],
            _M2_EXCLUDED_FUNCTION_IDS,
        )

        snap: Dict[str, Any] = {
            "m2_standard_input": {
                "requirement_text": context.requirement_text or "",
                "function_list": self._to_serializable(fl),
                "dependencies": self._to_serializable(deps),
                "normalizer_result": self._to_serializable(norm),
            },
        }
        # m2_scope 现在存储在 artifacts（由 SubARRefiner 写入）
        m2_scope = context.artifacts.get("m2_scope")
        if isinstance(m2_scope, dict) and m2_scope:
            snap["m2_scope"] = copy.deepcopy(m2_scope)

        # 当使用了 scoped override 时，额外记录 M2 实际收到的输入，避免与全树快照混淆
        if function_list_override is not None:
            actual_fl = self._filter_function_list_for_m2(function_list_override)
            actual_deps = self._filter_dependencies_for_m2(
                dependencies_override if isinstance(dependencies_override, list) else [],
                _M2_EXCLUDED_FUNCTION_IDS,
            )
            snap["actual_m2_input"] = {
                "function_list": self._to_serializable(actual_fl),
                "dependencies": self._to_serializable(actual_deps),
            }
        return snap

    def refresh_m2_inputs_snapshot(
        self,
        context: CoordinatorContext,
        *,
        function_list_override: Optional[List[Dict[str, Any]]] = None,
        dependencies_override: Optional[List[Dict[str, Any]]] = None,
    ) -> Dict[str, Any]:
        """构建并写入快照 history（按签名去重）。

        function_list_override / dependencies_override 透传给 build_m2_inputs_snapshot，
        用于在 actual_m2_input 字段中准确记录子 AR 作用域评估的实际输入。
        """
        snap = self.build_m2_inputs_snapshot(
            context,
            function_list_override=function_list_override,
            dependencies_override=dependencies_override,
        )
        context.add_artifact("m2_inputs_snapshot", snap, agent="coordinator")
        hist = context.artifacts.get("m2_inputs_snapshot_history")
        if not isinstance(hist, list):
            hist = []
        stage = str(getattr(context, "pipeline_stage", "") or "")
        sig_full = self._m2_snapshot_history_signature(snap, stage)
        if hist:
            last = hist[-1]
            last_snap = last.get("snapshot") if isinstance(last, dict) else None
            last_stage = (last.get("pipeline_stage") if isinstance(last, dict) else "") or ""
            if isinstance(last_snap, dict):
                last_sig = self._m2_snapshot_history_signature(last_snap, str(last_stage))
            else:
                last_sig = ""
            if last_sig == sig_full:
                context.artifacts["m2_inputs_snapshot_history"] = hist
                return snap

        entry: Dict[str, Any] = {
            "seq": len(hist) + 1,
            "captured_at": datetime.now().isoformat(),
            "pipeline_stage": stage,
            "input_phase": self._input_phase_from_pipeline_stage(context),
            "tree_version": int(getattr(context, "tree_version", 0) or 0),
            "snapshot": copy.deepcopy(snap),
        }
        sub_tail = self._sub_ar_stack_tail_for_snapshot(context)
        if sub_tail:
            entry["sub_ar_stack_tail"] = sub_tail
        m2_scope = context.artifacts.get("m2_scope")
        if isinstance(m2_scope, dict) and m2_scope.get("scope_root_node_id"):
            entry["target_node_id"] = m2_scope.get("scope_root_node_id")
            if m2_scope.get("node_depth") is not None:
                entry["node_depth"] = m2_scope.get("node_depth")
            if m2_scope.get("refinement_root_id"):
                entry["refinement_root_id"] = m2_scope.get("refinement_root_id")
        hist.append(entry)
        context.artifacts["m2_inputs_snapshot_history"] = hist
        return snap

    # ───────────── 辅助：质量标记与产物 ─────────────

    @staticmethod
    def _record_quality_flags(
        context: CoordinatorContext,
        agent_name: str,
        output: BaseAgentOutput,
    ):
        for flag in (output.quality_flags or []):
            context.add_quality_flag(agent_name, flag)

    @staticmethod
    def _apply_decomposer_normalizer_patch(
        context: CoordinatorContext,
        decomp_output: BaseAgentOutput,
    ) -> None:
        meta = decomp_output.meta or {}
        nr = meta.get("normalizer_result")
        if isinstance(nr, dict):
            context.add_artifact("normalized_requirement", nr, agent="decomposer")

    @staticmethod
    def _artifacts_from_decomposer_result(decomp_result: Dict[str, Any]) -> Dict[str, Any]:
        raw_list = decomp_result.get("function_list")
        fl = AgentInvoker._to_serializable(raw_list) if isinstance(raw_list, list) else []
        raw_cf = decomp_result.get("core_flow")
        cf = (
            AgentInvoker._to_serializable(raw_cf)
            if isinstance(raw_cf, list)
            else []
        )
        return {"function_list": fl, "core_flow": cf}

    @staticmethod
    def _core_flow_from_context(context: CoordinatorContext) -> List[Any]:
        cf = context.artifacts.get("core_flow")
        if isinstance(cf, list):
            return AgentInvoker._to_serializable(cf)
        full = context.artifacts.get("decomposer_full")
        if isinstance(full, dict):
            raw = full.get("core_flow")
            if isinstance(raw, list):
                return AgentInvoker._to_serializable(raw)
        return []

    @staticmethod
    def sub_requirement_list_from_context(context: CoordinatorContext) -> List[Dict[str, Any]]:
        fl = context.artifacts.get("function_list")
        if not isinstance(fl, list) or len(fl) == 0:
            return []
        out: List[Dict[str, Any]] = []
        for row in fl:
            if not isinstance(row, dict):
                continue
            out.append({
                "id": row.get("id"),
                "title": row.get("title"),
                "desc": row.get("desc"),
                "node_type": row.get("node_type"),
                "granularity": row.get("granularity"),
                "path": row.get("path") or "",
            })
        return out

    # ───────────── M2 单 Agent 调用 ─────────────

    @staticmethod
    def _unwrap_consistency_eval_dict(consistency_output: BaseAgentOutput) -> Dict[str, Any]:
        raw = (consistency_output.result or {}) if consistency_output else {}
        inner = raw.get("result") if isinstance(raw, dict) else {}
        return inner if isinstance(inner, dict) else {}

    @staticmethod
    def consistency_evaluation_passes(
        eval_dict: Dict[str, Any],
        threshold: float,
    ) -> bool:
        if not eval_dict:
            return False
        try:
            score = float(eval_dict.get("score") or 0.0)
        except (TypeError, ValueError):
            score = 0.0
        crit = eval_dict.get("critical_issues") or []
        if isinstance(crit, list) and len(crit) > 0:
            return False
        return score >= threshold

    async def invoke_m2_consistency_only(
        self,
        context: CoordinatorContext,
        *,
        function_list_override: Optional[List[Dict[str, Any]]] = None,
        dependencies_override: Optional[List[Dict[str, Any]]] = None,
        on_m2_agent_complete: Optional[
            Callable[[str, CoordinatorContext, Optional[Dict[str, Any]]], Awaitable[None]]
        ] = None,
        write_to_artifacts: bool = True,
    ) -> BaseAgentOutput:
        """仅一致性评估。支持传入作用域数据覆盖，避免修改 context.artifacts。

        write_to_artifacts: 为 False 时不把评估结果写回 context.artifacts["consistency_evaluation"]，
        用于子 AR 作用域评估，防止局部结果覆盖根层全树的 consistency_evaluation。
        """
        if not function_list_override and not context.artifacts.get("function_list"):
            logger.warning("M2 一致性：缺少 function_list，将用空数据评估")

        self._warn_if_missing_m2_preprocess(context)
        consistency_input = self._build_m2_eval_input(
            context,
            stage="consistency",
            function_list_override=function_list_override,
            dependencies_override=dependencies_override,
        )
        emit = getattr(context, "agent_span_emit", None)
        consistency_output = await with_llm_agent_span(
            context,
            "consistency_evaluator",
            "M2-Consistency",
            emit,
            self._m2_consistency.execute(consistency_input),
        )
        ev = self._unwrap_consistency_eval_dict(consistency_output)
        if write_to_artifacts:
            context.add_artifact("consistency_evaluation", ev, agent="consistency_evaluator")
        if on_m2_agent_complete:
            await on_m2_agent_complete("consistency_evaluator", context, ev)
        return consistency_output

    async def invoke_m2_feasibility_integrator_only(
        self,
        context: CoordinatorContext,
        *,
        function_list_override: Optional[List[Dict[str, Any]]] = None,
        on_m2_agent_complete: Optional[
            Callable[[str, CoordinatorContext, Optional[Dict[str, Any]]], Awaitable[None]]
        ] = None,
        write_to_artifacts: bool = True,
        consistency_result_override: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, BaseAgentOutput]:
        """可实现性 + 综合集成。支持传入作用域数据覆盖。

        write_to_artifacts: 为 False 时不把评估结果写回 context.artifacts 的
        feasibility_evaluation / evaluation 主键，防止局部子树评估覆盖根层结果。

        consistency_result_override: 当 write_to_artifacts=False 时需传入 scoped 一致性结果
        供 integrator 使用（无法从 artifacts["consistency_evaluation"] 读取，因为子 AR
        调用 invoke_m2_consistency_only 时同样使用 write_to_artifacts=False）。
        """
        results: Dict[str, BaseAgentOutput] = {}
        if consistency_result_override is not None:
            consistency_result = consistency_result_override
        else:
            consistency_result = context.artifacts.get("consistency_evaluation") or {}

        logger.info(f"[{context.conversation_id}] M2-FeasibilityEvaluator 开始")
        self._warn_if_missing_m2_preprocess(context)
        feasibility_input = self._build_m2_eval_input(
            context,
            stage="feasibility",
            function_list_override=function_list_override,
        )
        emit = getattr(context, "agent_span_emit", None)
        feasibility_output = await with_llm_agent_span(
            context,
            "feasibility_evaluator",
            "M2-Feasibility",
            emit,
            self._m2_feasibility.execute(feasibility_input),
        )
        results["feasibility_evaluator"] = feasibility_output

        feasibility_result = self._to_serializable(feasibility_output.get_payload())
        if write_to_artifacts:
            context.add_artifact(
                "feasibility_evaluation", feasibility_result, agent="feasibility_evaluator"
            )
        logger.info(f"[{context.conversation_id}] M2-FeasibilityEvaluator 完成")
        if on_m2_agent_complete:
            await on_m2_agent_complete("feasibility_evaluator", context, feasibility_result)
        self.refresh_m2_inputs_snapshot(
            context,
            function_list_override=function_list_override,
        )

        logger.info(f"[{context.conversation_id}] M2-EvaluationIntegrator 开始")
        self._warn_if_missing_m2_preprocess(context)
        integrator_input = self._build_m2_eval_input(
            context,
            stage="integrator",
            integrator_extras={
                "consistency_result": consistency_result,
                "feasibility_result": feasibility_result,
            },
        )
        integrator_output = await with_llm_agent_span(
            context,
            "evaluation_integrator",
            "M2-Integrator",
            emit,
            self._m2_integrator.execute(integrator_input),
        )
        results["evaluation_integrator"] = integrator_output

        integrator_result = self._to_serializable(integrator_output.get_payload())
        if write_to_artifacts:
            context.add_artifact("evaluation", integrator_result, agent="evaluation_integrator")
            self._append_evaluation_episode_after_m2_tail(context)
        else:
            # 为 evaluation_episodes 记录临时写入，episode 记录完毕后恢复原值
            _prev_eval = context.artifacts.get("evaluation")
            context.artifacts["evaluation"] = integrator_result
            self._append_evaluation_episode_after_m2_tail(context)
            if _prev_eval is not None:
                context.artifacts["evaluation"] = _prev_eval
            else:
                context.artifacts.pop("evaluation", None)

        logger.info(f"[{context.conversation_id}] M2-EvaluationIntegrator 完成")
        if on_m2_agent_complete:
            await on_m2_agent_complete("evaluation_integrator", context, integrator_result)
        return results

    async def invoke_m2_integrator_skip_feasibility(
        self,
        context: CoordinatorContext,
        on_m2_agent_complete: Optional[
            Callable[[str, CoordinatorContext, Optional[Dict[str, Any]]], Awaitable[None]]
        ] = None,
    ) -> Dict[str, BaseAgentOutput]:
        """跳过可实现性评估，直接运行 Integrator。"""
        results: Dict[str, BaseAgentOutput] = {}
        consistency_result = context.artifacts.get("consistency_evaluation") or {}
        context.add_artifact("feasibility_evaluation", {}, agent="feasibility_evaluator")

        logger.info(f"[{context.conversation_id}] M2-EvaluationIntegrator 开始（跳过可实现性评估）")
        self._warn_if_missing_m2_preprocess(context)
        integrator_input = self._build_m2_eval_input(
            context,
            stage="integrator",
            integrator_extras={
                "consistency_result": consistency_result,
                "feasibility_result": {},
                "feasibility_evaluation_skipped": True,
            },
        )
        emit = getattr(context, "agent_span_emit", None)
        integrator_output = await with_llm_agent_span(
            context,
            "evaluation_integrator",
            "M2-Integrator(skip_feasibility)",
            emit,
            self._m2_integrator.execute(integrator_input),
        )
        results["evaluation_integrator"] = integrator_output

        integrator_result = self._to_serializable(integrator_output.get_payload())
        context.add_artifact("evaluation", integrator_result, agent="evaluation_integrator")

        logger.info(f"[{context.conversation_id}] M2-EvaluationIntegrator 完成（跳过可实现性评估）")
        if on_m2_agent_complete:
            await on_m2_agent_complete("evaluation_integrator", context, integrator_result)
        self._append_evaluation_episode_after_m2_tail(context)
        return results

    async def _invoke_dependency_classifier_only(
        self,
        context: CoordinatorContext,
        on_agent_complete: Optional[
            Callable[[str, CoordinatorContext], Awaitable[None]]
        ] = None,
    ) -> Dict[str, BaseAgentOutput]:
        """在已有 function_list 时仅重跑 DependencyClassifier。"""
        results: Dict[str, BaseAgentOutput] = {}
        task_id = context.conversation_id
        function_list = context.artifacts.get("function_list")
        norm_for_dep = context.artifacts.get("normalized_requirement") or {}
        core_flow = self._core_flow_from_context(context)
        logger.info(f"[{task_id}] M1-DependencyClassifier 开始 (only)")
        dep_input = self._build_input(
            context,
            artifacts={
                "function_list": function_list,
                "normalizer_result": self._slim_norm_for_dependency(
                    norm_for_dep if isinstance(norm_for_dep, dict) else {}
                ),
                "core_flow": core_flow,
            },
        )
        emit = getattr(context, "agent_span_emit", None)
        dep_output = await with_llm_agent_span(
            context,
            "dependency_classifier",
            "M1-DependencyClassifier(only)",
            emit,
            self._m1_dependency.execute(dep_input),
        )
        results["dependency_classifier"] = dep_output
        dep_result = self._to_serializable(dep_output.get_payload())
        dependencies = self._to_serializable(dep_result.get("dependencies"))
        if not isinstance(dependencies, list):
            dependencies = []
        context.add_artifact("dependencies", dependencies, agent="dependency_classifier")
        context.add_artifact("dependency_full", dep_result, agent="dependency_classifier")
        self._record_quality_flags(context, "dependency_classifier", dep_output)
        if on_agent_complete:
            await on_agent_complete("dependency_classifier", context)
        logger.info(f"[{task_id}] M1-DependencyClassifier 完成 (only)")
        return results
