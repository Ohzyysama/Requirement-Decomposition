# 编排管线顺序与 Gate 说明

本文档与 **`PipelineRunner.invoke_consistency_first_pipeline`**（经 **`_cf_list_consistency_m2_tail`**）及 **`Orchestrator.run`**（**单次主运行**，无外层 `max_iterations` 循环）中的实际调用一致，便于对照源码。

> **架构说明**：原 `agent_invoker.py` 的编排职责已按单一职责原则拆分为三个独立类：
> - **`AgentInvoker`**（`agent_invoker.py`）：纯单 Agent 调用层，每个方法只调用一个 LLM Agent（输入构建 + execute + 写单条 artifact）。
> - **`PipelineRunner`**（`pipeline_runner.py`）：多步骤管线编排（M1 全线、M2 尾部、一致性优先主线、节点重拆）。
> - **`SubARRefiner`**（`sub_ar_refiner.py`）：子 AR 递归细化（`_feasibility_failed_walk`、`_refine_one_sub_ar_node` 及栈管理）。
>
> 状态管理统一由 `PipelineStage` 枚举（`app/core/enums.py`）驱动，通过 `CoordinatorContext.update_stage()` 更新；`conversations.status`、SSE、`final_result.pipeline_stage` 均使用管线阶段字符串（`idle` / `split` / `consistency` / `refine_sub_ar` / `feasibility` / `done` / `error`）。`transitions` FSM 已删除。

---

## 1. 一致性优先主路径：`invoke_consistency_first_pipeline`

实现上分两段：

1. **`invoke_module1_pipeline_without_gate`**（`PipelineRunner`）：M1 无 Gate 管线。
2. **`_cf_list_consistency_m2_tail`**（`PipelineRunner`）：在已有 M1 产物上完成「列表化 → 一致性闭环 → M2 可实现性+集成 → 可选可实现性驱动子 AR 递归细化」。

### 1.1 M1

顺序固定为：

**Normalizer → FunctionalDecomposer → DependencyClassifier**

- Decomposer / Dependency 完成后会触发编排器注册的 `on_agent_complete`（用于 SSE 功能树、依赖预览）。

### 1.2 列表化（协调层）

- 子需求列表来自 **`AgentInvoker.sub_requirement_list_from_context`**：按 `artifacts.function_list` 行拍平为 `sub_requirement_list`，并写入 **`sub_requirement_list_stats`**。
- 调用 **`on_list_ready`** 回调（SSE 子需求列表推送），阶段维持 `split`，随后进入一致性评估循环。

### 1.3 整层一致性 + 内层重拆

在 **`_cf_list_consistency_m2_tail`**（`PipelineRunner`）中：

1. **`pipeline_stage = PipelineStage.CONSISTENCY`**，调用 **`AgentInvoker.invoke_m2_consistency_only`**（仅 M2 ConsistencyEvaluator）。
2. **通过条件**（**`consistency_evaluation_passes`**）：`score >= consistency_pass_threshold`，且 **`critical_issues` 为空列表**（任一为否则视为未通过）。
3. 未通过时：
   - 递增内层计数，将 **`remediation_instruction`** 写入 **`retry_context`**，并可选合并到 **`config.split_retry_hints`**；
   - 若 **`inner_attempt > consistency_inner_max_retries`**：打上质量标记 **`consistency_not_passed_after_inner_retries`**，**跳出内层循环**（不再重拆）；
   - 否则保持 **`pipeline_stage = PipelineStage.CONSISTENCY`**，调用 **`PipelineRunner.invoke_m1_decomposer_and_dependency_no_gate`**（保留已有标准化结果，整树重拆 + 全量依赖），刷新列表化产物后 **回到步骤 1**。

**代码默认值**（`context.config.get(...)`）：`consistency_pass_threshold` 默认 **`0.7`**；**`consistency_inner_max_retries` 默认 `1`**（即首次一致性不通过时，**最多再执行一轮**内层 Decomposer+Dependency 重试后再评一致性；仍不通过则打上上述 quality flag）。若需更多轮内层重试，须在配置中显式增大该值。

### 1.4 M2 尾部：可实现性 + 综合集成

- 若根层一致性内层已耗尽且仍存在 **`consistency_not_passed_after_inner_retries`**，且 **`continue_pipeline_after_consistency_exhausted`** 为 **`false`**（默认）：**跳过**可实现性+后续细化，直接调用 **`invoke_m2_integrator_skip_feasibility`** 完成集成，管线阶段保持 `consistency`，由 Orchestrator 设为 `done`。
- 否则：**`pipeline_stage = PipelineStage.FEASIBILITY`**，执行 **`AgentInvoker.invoke_m2_feasibility_integrator_only`**（FeasibilityEvaluator → EvaluationIntegrator）。

### 1.6 可实现性驱动子 AR 递归细化（可选）

在 **根层** 可实现性+集成完成后，若 **`enable_feasibility_refinement`** 不为 **`false`**（默认开启），由 **`SubARRefiner._run_feasibility_refinement_after_root`** 驱动：

1. 从 **`feasibility_evaluation`** 中解析未通过规则涉及的 **`affected_nodes`**（**`_extract_feasibility_failed_node_ids`**），得到待处理节点列表。
2. 对列表中**每一个**可实现性未通过节点（递归深度受 **`max_feasibility_refinement_depth`** 约束）：**`SubARRefiner._refine_one_sub_ar_node`** 子范围重拆 → 将 **`function_list` / `dependencies` 收窄为该子树根下闭包**（以局部变量传参，**不写入 `context.artifacts`**，避免并发读取污染）→ 在该作用域上调用 **`AgentInvoker.invoke_m2_consistency_only`**（通过 `function_list_override` / `dependencies_override` 传入收窄数据）；若一致性未通过，则按 **`consistency_inner_max_retries`** 对**当前子树**再次 **`_refine_one_sub_ar_node`**（提示来自 **`remediation_instruction`**）并重复收窄后的一致性，直至通过或次数耗尽；**仅当一致性通过**后再调用 **`AgentInvoker.invoke_m2_feasibility_integrator_only`**（同样通过 override 参数传入收窄数据）。次数耗尽或内层 M1 重拆失败时打上 **`feasibility_refinement_scoped_consistency_failed`** 等标记并**跳过**该节点上的可实现性调用。
3. 若收窄作用域下仍有未通过节点，**深度优先递归**同一逻辑（`SubARRefiner._feasibility_failed_walk`），直至通过或触达上限；根层 **`evaluation` / consistency / feasibility** 结果在整段递归结束后写回为 **根层首轮** 快照（**`feasibility_refinement_log`** 写入 `context.artifacts`）。
4. **`context.artifacts["m2_scope"]`** 在子树评估期间临时存放当前作用域信息（评估完毕后由 `SubARRefiner` pop），**`m2_inputs_snapshot_history`** 中的 **`target_node_id` / `feasibility_refinement_depth`** 用于区分子树轮次。

达到深度上限时可能产生 **`feasibility_refinement_depth_exceeded`** 等 quality flag。

子 AR 递归细化全部完成后，`pipeline_stage` 仍为 `feasibility`，由 Orchestrator 统一推进至 `done`。

---

## 2. 分段续跑与独立 M2（与当前代码一致）

以下 **`AgentInvoker` 方法已从代码库删除**，本文档不再描述其调用语义，以免与源码不一致：

- **`resolve_cf_resume_entry`**、**`invoke_cf_resume_from`**（原：从中间档续跑一致性优先管线）
- **`resolve_target_agent`**、**`invoke_module1_partial`**（原：按 Gate 建议从某一 M1 档部分重跑）
- **`invoke_module2_pipeline`**、**`_stub_execute`**（原：M2 整段封装 / 占位评估）

**替代做法：**

| 需求 | 推荐做法 |
|------|----------|
| 全量重跑 M1 + M2 | 对会话再次 **`POST .../coordinator/start`**；编排侧仍为 **`Orchestrator.run`** → **`PipelineRunner.invoke_consistency_first_pipeline`**（单次主运行） |
| 仅对功能树某节点补充拆分并重跑「列表 → 一致性 → 可实现性」尾部 | **`POST .../coordinator/tasks/{conversation_id}/refine-node`**（**`PipelineRunner.refine_node_and_run_m2_tail`**） |
| 本地/实验：在已有 M1 产物上只跑 M2 | **`scripts/run_m2_evaluation.py`**：依次 **`AgentInvoker.invoke_m2_consistency_only`**、**`AgentInvoker.invoke_m2_feasibility_integrator_only`**（不再提供 `invoke_module2_pipeline` 封装） |

---

## 3. 与 `Orchestrator.run` 的关系

- **`Orchestrator.run`** 仅执行 **一次** **`PipelineRunner.invoke_consistency_first_pipeline`**，然后 **`DecisionEngine.make_iteration_decision`** 生成质量摘要（**不触发外层自动重试**）。
- **子 AR**（由 `SubARRefiner` 完成）、**一致性内层重拆**均发生在 **该次运行内部**。
- 若根层一致性内层耗尽仍未通过，由 **`continue_pipeline_after_consistency_exhausted`** 决定是否仍跑可实现性；否则依赖 **`quality_flags`** 与结果中的说明，用户可通过 **`refine-node`** 对指定节点再拆。

---

## 4. SSE 与 `pipeline_stage`

编排器进度与中间结果会带上 **`pipeline_stage`**（见 **`SsePayloadFactory`**，位于 `sse_payload_factory.py`）。`pipeline_stage` 现为 **`PipelineStage` 枚举**（`app/core/enums.py`），共 7 个取值：

`idle` → `split`（M1 拆分中）→ `consistency`（一致性评估/内层重拆中）→ `refine_sub_ar`（可实现性驱动子 AR 递归细化中）→ `feasibility`（可实现性+集成评估中）→ `done` / `error`

可实现性递归细化时，功能树预览的 **`intermediate_result`** 可带 **`tree_version`** 与当前 **`pipeline_stage`**。

---

## 5. 配置键（`CoordinatorContext.config`）

| 键 | 含义（与代码一致） |
|----|---------------------|
| `consistency_pass_threshold` | 一致性分数阈值，默认 **`0.7`** |
| `consistency_inner_max_retries` | 根层内层「未通过则整树 Decomposer+Dependency 重试」与可实现性细化**收窄作用域**下「未通过则子树 M1 重拆」共用次数上限；**代码默认 `1`** |
| `enable_feasibility_refinement` | 为 **`false`** 时跳过可实现性驱动子 AR 递归；默认开启（未设置则执行） |
| `max_feasibility_refinement_depth` | **当前拆分根**下的最大非根深度，默认 **`3`**（不含根）。正常拆分以原始需求根 `F-1` 为当前根；`refine-node` 以用户选择的节点为当前根，该节点相对深度为 0。设为 **`0`** 时完全禁止自动细化与 `refine-node` 重拆。 |
| `continue_pipeline_after_consistency_exhausted` | 根层一致性内层耗尽后是否仍跑可实现性；默认 **`false`** |
| （内部）`split_retry_hints` | 非用户配置；一致性未通过时写入 **`remediation_instruction`** 供 M1 重拆参考 |

**说明**：`max_feasibility_refinement_depth = n` 表示当前根下可以细化相对深度 `0..n-1` 的节点，最多生成到相对第 `n` 层。`refine-node` 时可通过 `request.config.max_feasibility_refinement_depth` 单独覆盖会话配置。`__ROOT__` 多根兼容包装节点不参与深度计算。

---

## 6. 用户介入：`refine-node`

- **API**：`POST /api/v1/coordinator/tasks/{conversation_id}/refine-node`（见 **`app/api/coordinator.py`**）。
- **行为**：从 **`conversation_metadata.final_result`** 通过 **`ContextHydrator.from_db_result()`**（`context_hydrator.py`）恢复 **`CoordinatorContext`**，调用 **`PipelineRunner.refine_node_and_run_m2_tail`**，再经 **`Orchestrator.run_refine_node`** 完成 SSE 与 **`DecisionEngine`** 摘要，落库 **`final_result`**。
- **深度配置**：`request.config.max_feasibility_refinement_depth` 可覆盖会话配置，语义与正常拆分相同，但当前根变为用户选择的节点。传 `0` 表示禁止本次重拆。

---

## 7. 源码入口（便于跳转）

| 职责 | 文件 | 关键方法 |
|------|------|----------|
| 一致性优先管线编排 | `app/services/coordinator/pipeline_runner.py` | `invoke_consistency_first_pipeline`、`_cf_list_consistency_m2_tail`、`invoke_module1_pipeline_without_gate`、`invoke_m1_decomposer_and_dependency_no_gate`、`refine_node_and_run_m2_tail` |
| 子 AR 递归细化 | `app/services/coordinator/sub_ar_refiner.py` | `_run_feasibility_refinement_after_root`、`_feasibility_failed_walk`、`_refine_one_sub_ar_node` |
| 单 Agent 调用层 | `app/services/coordinator/agent_invoker.py` | `invoke_m2_consistency_only`、`invoke_m2_feasibility_integrator_only`、`invoke_m2_integrator_skip_feasibility`、`sub_requirement_list_from_context` |
| 主编排入口 | `app/services/coordinator/orchestrator.py` | `run`（单次主运行）、`run_refine_node` |
| 迭代决策摘要 | `app/services/coordinator/decision_engine.py` | `make_iteration_decision`（汇总 `quality_flags`，无外层自动重试） |
| 管线阶段枚举 | `app/core/enums.py` | `PipelineStage` |
| 上下文状态管理 | `app/services/coordinator/context.py` | `CoordinatorContext.update_stage()`（权威状态更新） |
| 上下文恢复 | `app/services/coordinator/context_hydrator.py` | `ContextHydrator.from_db_result()` |
| 最终结果组装 | `app/services/coordinator/final_result_assembler.py` | `FinalResultAssembler.assemble_final_result()` |
| SSE 载荷工厂 | `app/services/coordinator/sse_payload_factory.py` | `SsePayloadFactory.assemble_*` |
| 树操作与统计 | `app/services/coordinator/tree_utils.py` | `splice_subtree_into_function_list`、`count_tree_nodes`、`build_tree_preview_str` 等 |
| 全局状态封装 | `app/services/coordinator/task_registry.py` | `TaskRegistry`、`SSEManager` |
