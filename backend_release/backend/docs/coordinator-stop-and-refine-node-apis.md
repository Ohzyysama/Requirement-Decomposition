# 协调器：中止运行与节点重拆 API

本文档整理协调器中两个相关接口：**协作式停止当前编排**、**对功能树节点发起重拆（子需求列表 → 一致性 → 可实现性尾部）**。

- **路由前缀**（默认）：`{API_V1_PREFIX}/coordinator`，其中 `API_V1_PREFIX` 默认为 `/api/v1`（见 `app/core/config.py`）。
- **认证**：需 **HTTP Bearer** 登录态；`task_id` 对应对话主键，且须为当前用户所属的会话。

---

## 1. 中止对话 / 停止协调任务

### 请求

| 项 | 说明 |
|----|------|
| 方法 | `POST` |
| 路径 | `/api/v1/coordinator/stop/{task_id}` |
| 路径参数 | `task_id`：与 `conversation_id` 相同 |

无请求体。

### 行为说明

- **协作式取消**：在运行中的 `TaskManager` 上将 `stop_requested` 置为 `true`；编排会在**当前迭代边界**或 **LLM 调用返回后**结束，而非立即中断 HTTP 请求。
- **SSE**：结束后会通过 SSE 推送带 `stopped_by_user` 的完成类事件；前端应继续监听既有订阅。
- **注意**：不要从内存中提前移除 `TaskManager`；停止依赖当前进程内已注册的任务表（`task_registry`）。

### 响应

**成功请求停止**（`200`，JSON）：

```json
{
  "task_id": "<task_id>",
  "status": "stop_requested",
  "message": "已请求停止，智能体将在当前 LLM 调用返回后结束，并通过 SSE 推送 stopped_by_user 事件"
}
```

**当前进程内没有运行中的任务**（仍 `200`，JSON）：

```json
{
  "task_id": "<task_id>",
  "status": "idle_or_completed",
  "message": "当前进程内未找到运行中的任务，可能已结束或尚未启动"
}
```

**常见错误**

| HTTP 状态 | 条件 |
|-----------|------|
| `404` | 对话不存在 |
| `403` | 非本会话所属用户 |
| `400` | `request_stop` 失败（例如上下文中找不到活跃任务）；`detail`: `无法停止该任务` |

实现位置：`app/api/coordinator.py` 中 `stop_coordination`；停止标志：`app/services/coordinator/task_manager.py` 中 `request_stop`。

---

## 2. 重启某节点分析（节点重拆）

### 请求

| 项 | 说明 |
|----|------|
| 方法 | `POST` |
| 路径 | `/api/v1/coordinator/tasks/{task_id}/refine-node` |
| 路径参数 | `task_id`：与 `conversation_id` 相同 |
| 请求体 | JSON，见下表 |

**请求体字段**（`RefineNodeRequest`）

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `node_id` | string | 是 | `function_list` 中的节点 id，不能为空 |
| `user_instruction` | string | 否 | 用户补充说明，会写入协调上下文并作为拆分提示 |
| `config` | object | 否 | 覆盖会话级配置的片段；键语义与 `POST /coordinator/start` 的 `config` 一致（编排阈值与 LLM 参数等）。可单独传 `max_feasibility_refinement_depth` 控制本次以选中节点为根的可实现性细化深度；**`0` 表示禁止重拆** |

### 前置条件

- 会话元数据中已存在持久化的 **`final_result`**（主协调任务跑完）；否则返回 `400`：`尚无最终结果，请先完成主协调任务`。

### 行为说明

- 后台异步执行：接口立即返回 `CoordinationResponse`，实际重拆在 `BackgroundTasks` 中运行。
- **推荐**：在调用前对已建立的同 `task_id` 的 **SSE** 订阅保持不变，以便接收进度事件。
- 任务会再次注册到 `task_registry`，因此 **`POST .../stop/{task_id}` 同样可中止本次 refine-node 运行**。
- 若用户停止导致结果中含 `stopped_by_user`，会将会话状态更新为 `cancelled` 并写入部分 `final`；否则正常组装完整结果、更新 `final_result` 与 `done` 等状态。

### 响应

**成功受理**（`200`，`CoordinationResponse`）：

| 字段 | 说明 |
|------|------|
| `task_id` | 同路径 `task_id` |
| `conversation_id` | 与 `task_id` 相同 |
| `status` | 固定为 `started` |
| `message` | `节点重拆任务已启动` |

**常见错误**

| HTTP 状态 | 条件 |
|-----------|------|
| `404` | 对话不存在 |
| `403` | 非本会话所属用户 |
| `400` | 尚无 `final_result`，或 `node_id` 为空 |

实现位置：`app/api/coordinator.py` 中 `refine_node_coordination`；模式定义：`app/schemas/coordinator.py` 中 `RefineNodeRequest`。

---

## 3. 与主流程的配合顺序（简要）

1. 建议先 **`GET /api/v1/coordinator/tasks/{conversation_id}/stream`** 建立 SSE。
2. 主任务：**`POST /api/v1/coordinator/start`**。
3. 需要停止时：**`POST /api/v1/coordinator/stop/{task_id}`**（主任务或 refine-node 在跑时均可尝试）。
4. 主任务产出 `final_result` 后，可对某节点：**`POST /api/v1/coordinator/tasks/{task_id}/refine-node`**。

以上顺序说明与注释一致，见 `app/api/coordinator.py` 文件头与对应端点 docstring。
