# 解析任务编排配置：前端使用说明

本文说明如何拉取「一致性重试 / 可实现性细化深度 / 一致性耗尽后是否继续」三组可选配置，并在启动解析任务时使用。

---

## 1. 拉取可选配置列表

### 请求

| 项目 | 说明 |
|------|------|
| 方法 | `GET` |
| 路径 | `{API_PREFIX}/coordinator/config/task-choice-groups` |
| 认证 | `Authorization: Bearer <access_token>`（与其它需登录接口一致） |

`API_PREFIX` 与后端一致，默认为 **`/api/v1`**（见环境变量或 `settings.API_V1_PREFIX`）。完整示例：

```http
GET /api/v1/coordinator/config/task-choice-groups
Authorization: Bearer <token>
```

### 响应体（概要）

顶层字段：

| 字段 | 类型 | 含义 |
|------|------|------|
| `groups` | 数组 | 三项配置分组，顺序固定 |
| `usage_hint` | 字符串 | 与启动接口配合使用的简短说明 |

每个 **`groups[]`** 元素：

| 字段 | 类型 | 含义 |
|------|------|------|
| `key` | string | 写入 `POST .../coordinator/start` 里 `config` 的键名 |
| `title` | string | 表单标题 |
| `summary` | string | 该项的业务语义、默认值行为说明 |
| `value_type` | `"integer"` \| `"boolean"` | 控件类型提示 |
| `default_value` | number \| boolean | 与后端 **`cfg.get(key, default)`** 一致；用户不改时可不传键 |
| `omit_means_default` | boolean | 为 `true` 时表示：**请求里省略该键即等于使用 `default_value`** |
| `options` | 数组 | 推荐枚举项，用于下拉框 / 单选 |

每个 **`options[]`** 元素：

| 字段 | 类型 | 含义 |
|------|------|------|
| `value` | number \| boolean | 选中后写入 `config[key]` 的值 |
| `label` | string | 展示用短文案；**整数类**一般为「数字（备注）」，**提交值以 `value` 为准** |
| `description` | string | 补充说明，多作备注/副文案 |
| `is_default` | boolean | 是否与「不传键时的后端默认」一致 |

### 三组 `key`（便于联调核对）

1. **`consistency_inner_max_retries`** — 一致性内层重试上限（整数）  
2. **`max_feasibility_refinement_depth`** — 可实现性细化最大相对深度（整数，`0` 表示关闭自动细化且禁止 refine-node）  
3. **`continue_pipeline_after_consistency_exhausted`** — 根层一致性耗尽后是否仍跑可实现性（布尔）

---

## 2. 在启动解析任务时写入配置

启动接口：**`POST {API_PREFIX}/coordinator/start`**（请求体字段见 OpenAPI / `CoordinationRequest`）。

**要点**：这些编排项都放在请求体的 **`config` 对象**里；与 GET 目录里的 **`groups[].key`** 一一对应。可选字段还有 **`user_feedback`**（聊天式反馈，不是 `config` 里的键）。

完整 HTTP 示例（含认证头）：

```http
POST /api/v1/coordinator/start
Authorization: Bearer <token>
Content-Type: application/json

{
  "conversation_id": "<会话 ID>",
  "config": {
    "consistency_inner_max_retries": 1,
    "max_feasibility_refinement_depth": 3,
    "continue_pipeline_after_consistency_exhausted": false
  },
  "user_feedback": null
}
```

### 方式 A：使用后端默认值（推荐「不改就用默认」）

**不要在 `config` 里携带对应键**。后端对每个键使用内置默认值（与各组里的 `default_value` 一致）。

### 方式 B：用户从列表中选择

用户在某组中选了一项后，将该项的 **`value`** 写入 **`config[group.key]`**。

示例（用户选了「一致性内层重试 = 2」「细化深度 = 3」「耗尽后继续 = false」）：

```json
{
  "conversation_id": "<会话 ID>",
  "config": {
    "consistency_inner_max_retries": 2,
    "max_feasibility_refinement_depth": 3,
    "continue_pipeline_after_consistency_exhausted": false
  }
}
```

若用户只希望改其中一项，**只传需要覆盖的键即可**，其余省略仍走默认。

### 方式 C：整数项自定义输入（进阶）

对 **`consistency_inner_max_retries`** 与 **`max_feasibility_refinement_depth`**，后端接受 **任意合法整数**（不限于 `options` 列表）。前端可提供「自定义输入」：`options` 用于预设，`summary` / `description` 用于约束说明（例如深度 `0` 的语义）。

---

## 3. 前端表单建议

1. **首次进入创建任务页**：调用一次 `GET .../task-choice-groups`，缓存结果（可按会话或全局缓存，配置文案较少变动）。  
2. **每组渲染**：用 `title` + `summary` 作为区块标题与说明；用 `options` 渲染单选或下拉，`label` 作主显、`description` 作副标题或 Tooltip。  
3. **默认选中**：每组中 **`is_default === true`** 的选项应对应「不传该键」的行为；可在 UI 上增加「恢复默认」= 从待提交的 `config` 中 **删除该键**。  
4. **类型**：`value_type === "integer"` 用数字控件；`"boolean"` 用开关或两个单选项（以 `options` 为准）。  
5. **与 `conversation` 合并**：若会话的 `conversation_metadata.config` 里已有键，后端在 `start` 时会与本次请求 `config` **合并**（请求层覆盖会话层）。前端若展示「当前会话默认」，需与会话详情接口的数据源对齐。

---

## 4. 与其它接口的关系（简述）

- **`refine-node`** 也可传 `config` 片段；其中 **`max_feasibility_refinement_depth`** 可单独覆盖会话配置（详见接口文档）。  
- 本文档三组键仅为编排侧常用项；完整 `config` 能力（模型、阈值等）仍以 OpenAPI / 后端 `CoordinationRequest.config` 说明为准。

---

## 5. 相关代码位置（供后端对照）

| 说明 | 路径 |
|------|------|
| GET 路由 | `app/api/coordinator.py` |
| 目录与文案 | `app/services/coordinator/config_task_choice_catalog.py` |
| 响应模型 | `app/schemas/coordinator_task_config_choices.py` |
