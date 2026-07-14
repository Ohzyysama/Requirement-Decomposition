# API：对话详情、协调结果（result）、SSE 进度流

本文档单独描述三条常用接口的**路径、认证、输入（路径/查询/请求头）与输出（响应体 / SSE 事件）**。  

- **前缀**：`/api/v1`（见 `app/core/config.py` 中 `API_V1_PREFIX`）  
- **认证**：三条接口均需 **`Authorization: Bearer <access_token>`**  
- **task_id**：协调器中 **`task_id` 与对话 `conversation_id`（UUID）相同**  

完整接口一览见项目根目录 [`API.md`](API.md)。

---

## 1. 根据 ID 获取对话详情

**`GET /api/v1/conversations/{conversation_id}`**

### 路径参数

| 参数 | 类型 | 说明 |
|------|------|------|
| `conversation_id` | string (UUID) | 对话主键 |

### 查询参数

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `include_messages` | boolean | `false` | `true` 时在响应体中内嵌 `messages`；否则 `messages` 为空数组。完整聊天时间线建议 **`GET .../conversations/{id}/messages`**。 |

### 响应 `200`

JSON 对象，与 `ConversationResponse` / `Conversation.to_dict()` 一致。典型字段：

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | string | 对话 ID |
| `user_id` | string | 所有者用户 ID |
| `title` | string | 标题 |
| `description` | string \| null | 描述 |
| `original_requirement` | string | 原始需求正文 |
| `current_iteration` | number | 当前迭代轮次 |
| `status` | string | 对话/管线状态（可能与 `PipelineStage` 字符串并存，以实际落库为准） |
| `decomposed_requirements` | array | 分解结果占位（JSON 列，默认 `[]`） |
| `validation_results` | object | 校验摘要（默认 `{}`） |
| `quality_flags` | object | 质量标记（默认 `{}`） |
| `conversation_metadata` | object | 扩展元数据；协调完成后常含 **`final_result`**、`progress`、`config` 等 |
| `created_at` / `updated_at` / `completed_at` | string \| null | ISO8601；未完成时 `completed_at` 可为 `null` |
| `messages` | array | `include_messages=false` 时为 `[]`；为 `true` 时为消息列表（见下表） |

**`messages` 单项（`include_messages=true`）**

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | string | 消息 ID |
| `conversation_id` | string | 对话 ID |
| `role` | string | `user` / `assistant` / `system` 等 |
| `content` | string | 文本 |
| `message_type` | string | 如 `text`、`iteration_feedback`、`assistant_summary`、`system_event` |
| `message_metadata` | object | 轻量结构；完整功能树等大 JSON 见 **`conversation_metadata.final_result`** 或 `detail_ref` |
| `created_at` | string \| null | ISO8601 |

### 错误

| HTTP | 条件 |
|------|------|
| `404` | 对话不存在 |
| `403` | 非该对话所有者 |

### 请求示例

```http
GET /api/v1/conversations/18f26695-af59-4a49-84c6-90428ac04d0e?include_messages=false HTTP/1.1
Host: example.com
Authorization: Bearer <access_token>
```

---

## 2. 获取协调任务最终结果（`result`）

**`GET /api/v1/coordinator/tasks/{task_id}/result`**

### 路径参数

| 参数 | 类型 | 说明 |
|------|------|------|
| `task_id` | string (UUID) | 与 `conversation_id` 相同 |

### 查询参数

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `version` | string | 省略 | **省略且库中已有 `final_result`**：直接返回 **`conversation_metadata.final_result` 的已持久化 JSON**（不经实时拼装）。传入非空策略名（如 `latest`、`best_by_score`、`specified`）时走 **`FinalResultAssembler.assemble_final_result`**，按迭代与上下文重新组装。 |
| `iteration_number` | integer | 省略 | 与 `version=specified` 配合时，选用指定迭代号的快照；具体逻辑见组装器 `version_strategy`。 |

### 响应 `200`

- **快捷路径**（有 `final_result` 且未传 `version`）：响应体即数据库中的 **`final_result` 对象**（形状与成功跑完管线后落库的一致，字段随版本演进可能略有增减）。
- **拼装路径**：由 `FinalResultAssembler` 生成的 **dict**，核心字段包括（非穷举）：

| 字段 | 说明 |
|------|------|
| `conversation_id` | 会话 ID |
| `requirement_text` | 需求原文 |
| `mode` | 任务模式 |
| `pipeline_stage` | 管线阶段字符串 |
| `iteration_count` / `progress` | 迭代次数与进度 |
| `quality_summary` | 质量汇总（含 rollup 相关统计） |
| `timeline` | 任务时间线事件 |
| `generated_at` | 生成时间 ISO8601 |
| `function_list` / `dependencies` / `io_contract` / `sub_requirement_list` | M1/M2 产物 |
| `function_tree_with_evaluation_meta` / `function_tree_with_episode_meta` | 带评估元数据的功能树视图 |
| `normalized_requirement` / `decomposition_root` / `normalizer_meta` | 标准化与拆分根 |
| `evaluation_episodes` / `evaluation_rollup` / `evaluation_summary_text` | 评估 episode 与 rollup |
| `node_evaluations` / `tree_version` | 节点评估与树版本 |
| `selected_iteration` | 当前选用的迭代号 |
| `iteration_history` / `key_improvements` / `execution_summary` | 历史与摘要 |
| `m2_inputs_snapshot` / `m2_inputs_snapshot_history` | M2 输入快照 |
| `retry_context` / `sub_ar_refinement_stack` / `coordinator_workspace` | 编排上下文 |

失败或停止时可能出现 **`error`** 字段或 **`stopped_by_user`** 等，以实际 JSON 为准。

### 错误

| HTTP | 条件 |
|------|------|
| `404` | 对话不存在；或既无 `final_result` 又无可用迭代 |
| `403` | 非该对话所有者 |

### 请求示例

```http
GET /api/v1/coordinator/tasks/18f26695-af59-4a49-84c6-90428ac04d0e/result HTTP/1.1
Authorization: Bearer <access_token>
```

```http
GET /api/v1/coordinator/tasks/18f26695-af59-4a49-84c6-90428ac04d0e/result?version=best_by_score HTTP/1.1
Authorization: Bearer <access_token>
```

---

## 3. 协调任务进度 SSE（`stream`）

**`GET /api/v1/coordinator/tasks/{task_id}/stream`**

### 路径参数

| 参数 | 类型 | 说明 |
|------|------|------|
| `task_id` | string (UUID) | 与 `conversation_id` 相同；**对话须已存在且属于当前用户** |

### 请求头建议

| 头 | 值 | 说明 |
|----|-----|------|
| `Authorization` | `Bearer <access_token>` | 必填 |
| `Accept` | `text/event-stream` | 建议 |

### 响应 `200`

- **Content-Type**：`text/event-stream`
- **Body**：符合 [SSE](https://html.spec.whatwg.org/multipage/server-sent-events.html) 的文本流，每条事件形如：

```text
event: <事件类型>
data: <JSON 字符串>

```

（空行分隔事件；JSON 使用 UTF-8，`ensure_ascii=False`，便于中文。）

### 事件类型与 `data` 载荷概要

| `event` | 触发时机 | `data`（JSON）概要 |
|-----------|----------|-------------------|
| `intermediate_result` | 管线关键步骤（标准化预览、功能树预览、M2 单步完成等） | 来自 `SsePayloadFactory`，常见顶层：`type`（如 `INTERMEDIATE_RESULT`）、`stage`、`content_type`、`data`；并常含 **`sse_sequence`**、`completed_at`；部分载荷含 **`artifact_family`**、`supersedes_sse_sequence`、`user_visible_stability` |
| `completed` | 编排正常结束，或用户停止后的结束推送 | **完整或部分最终结果对象**（与落库的 `final_result` 同类）；合成结束场景可能为 `{"message": "任务已结束"}` |
| `error` | 管线异常；或长时间未等到 **`POST /coordinator/start`** | 如 `{"message": "...", "code": "PENDING_SSE_TIMEOUT"}` 或编排错误信息 |
| `heartbeat` | 约 **30 秒**无新事件 | `{"server_time": "<ISO8601>", "last_sse_sequence": <number \| null>}` |

编排器侧主要推送 **`intermediate_result` / `completed` / `error`**；连接层补充 **`heartbeat`**，以及连接收尾时的 **`completed`** / **`error`**（例如任务已结束或等待启动超时）。

### 行为说明

1. **推荐顺序**：先 **`GET .../stream`** 建立 SSE，再 **`POST /api/v1/coordinator/start`**，避免错过早期 `intermediate_result`。  
2. **仅挂起 SSE、迟迟不 start**：在任务从未进入内存注册表的情况下，最长等待约 **`PENDING_SSE_MAX_SECONDS`（代码中为 30×60 秒）** 后会收到 **`error`**（`PENDING_SSE_TIMEOUT`）。  
3. 客户端断开连接时，服务端从该 `task_id` 的广播队列中移除对应队列。

### 错误（连接建立前）

| HTTP | 条件 |
|------|------|
| `404` | 对话不存在 |
| `403` | 权限不足 |

### `curl` 示例（须 `-N` 禁用缓冲）

```bash
curl -N \
  -H "Authorization: Bearer $TOKEN" \
  -H "Accept: text/event-stream" \
  "http://127.0.0.1:8000/api/v1/coordinator/tasks/<CONVERSATION_UUID>/stream"
```

---

## 4. 前端对接要点（精简）

### 建议数据流

1. 先 **`GET .../conversations/{id}`**：拿 `status`、`conversation_metadata`；若已有 **`conversation_metadata.final_result`**，可与 **`GET .../coordinator/tasks/{id}/result`**（不传 `version`）视为**同一份 JSON**，用于详情页主数据。  
2. 任务**进行中**：订阅 **`GET .../stream`**，用 `intermediate_result` 增量刷新 UI；**结束或需与后端完全一致**时再拉 **`GET .../result`**（或依赖 `completed` 事件里的最终结果对象）。  
3. **SSE 断线**：已推送的中间事件不会重放，需用 **`result` / `final_result`** 补齐。

### 结构不必统一，但要认两套入口

| 能力 | `final_result` / `result`（完成后） | SSE `intermediate_result`（进行中） |
|------|-------------------------------------|-------------------------------------|
| 功能点 | `function_list`、`function_tree_*`、`decomposition_root` 等 | `content_type=function_tree_preview` → **`data.function_tree`**；`sub_requirement_list_preview` → **`data.sub_requirement_list`**。中间阶段**不**保证有顶层 `function_list`。 |
| 依赖 | `dependencies` | `dependencies_preview` → **`data.dependencies`**（全量列表，语义对齐）。 |
| 一致性 / 可实现性评估 | 根上**无**独立 `consistency_evaluation` 字段；看 **`evaluation_episodes[].bundle.evaluation`** 内的 **`consistency_result` / `feasibility_result`**（以实际 JSON 为准） | `content_type=m2_agent_complete`，按 **`data.agent`**：`consistency_evaluator` → **`data.consistency_evaluation`**，`feasibility_evaluator` → **`data.feasibility_evaluation`**，`evaluation_integrator` → **`data.evaluation`**。 |
| 汇总文案 | `evaluation_summary_text`、`evaluation_rollup` 等 | 一般以 **`completed` / `result`** 为准；中间 SSE 多为分步原始评估对象。 |

解析 SSE 时：**先读 `content_type`，再读内层 `data`**；勿与 `final_result` 顶层键混为一谈。

### 注意点

- **`decomposed_requirements`**（对话根字段）与 **`function_list`** 不是同一数据源，不要互代。  
- **`io_contract`** 等通常只在 **`final_result` / `result`** 出现，中间 SSE 不保证推送。  
- **`completed`** 的 `data` 在少数场景可能仅为 **`{"message": "任务已结束"}`**，此时须 **`GET .../result`** 或读库内 **`final_result`**。  
- 新建任务：**先连 SSE 再 `POST .../coordinator/start`**，避免丢早期事件（见上文 §3 行为说明）。
