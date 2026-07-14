# Requirement-Decomposition

2026 大创项目 ——「需求拆分助手」

复杂功能需求自动化拆分系统：输入自然语言需求描述，通过多智能体协作管线自动完成需求标准化、功能拆分、依赖识别与质量评估，输出结构化的功能树和评估报告。

---

## 项目结构

```
Requirement-Decomposition/
├── backend_release/          # 后端服务（Python / FastAPI）
│   └── backend/
│       ├── app/
│       │   ├── api/          # REST API 接口（auth、conversation、coordinator）
│       │   ├── core/         # 核心配置、数据库连接、安全、枚举
│       │   ├── models/       # SQLAlchemy 数据模型
│       │   ├── repositories/ # 数据访问层
│       │   ├── schemas/      # Pydantic 请求/响应模型
│       │   └── services/
│       │       ├── agents/   # AI Agent 实现
│       │       │   ├── M1/   # 模块一：需求标准化、功能拆分、依赖分类
│       │       │   └── M2/   # 模块二：一致性评估、可实现性评估、综合集成
│       │       └── coordinator/  # 编排器：管线调度、SSE 推送、上下文管理
│       ├── docs/             # 技术文档（API、前端对接说明）
│       ├── scripts/          # 调试/测试脚本
│       ├── tests/            # 单元测试
│       ├── .env      # 环境变量
│       └── requirements.txt  # Python 依赖
│
└── frontend_release/         # 前端界面（Vue 3 + Vite）
    └── frontend/
        └── src/
            ├── api/          # API 请求封装（auth、chat、SSE）
            ├── components/   # 组件（功能树、评估报告、协调器配置、聊天）
            ├── router/       # 路由配置
            ├── stores/       # Pinia 状态管理
            ├── utils/        # 工具函数（SSE 客户端、Mock 数据）
            └── views/        # 页面（首页、登录、注册）
```

---

## 系统架构

### 智能体管线

```
用户需求 → [M1-Normalizer] → [M1-FunctionalDecomposer] → [M1-DependencyClassifier]
                                    ↓
                            [列表化 / 功能树构建]
                                    ↓
              ┌─────────────────────────────────────────┐
              │         M2 一致性评估 + 内层重拆          │
              │  (ConsistencyEvaluator → 未通过则重拆)   │
              └─────────────────────────────────────────┘
                                    ↓
              ┌─────────────────────────────────────────┐
              │       M2 可实现性评估 + 综合集成          │
              │  (FeasibilityEvaluator → Integrator)    │
              └─────────────────────────────────────────┘
                                    ↓
                    最终结果（功能树 + 评估报告）
```

### 模块说明

| 模块 | 智能体 | 职责 |
|------|--------|------|
| **M1** | Normalizer | 需求标准化，提取约束与范围 |
| **M1** | FunctionalDecomposer | 功能拆分，生成扁平功能列表与功能树 |
| **M1** | DependencyClassifier | 依赖关系分类（顺序/数据/资源） |
| **M2** | ConsistencyEvaluator | 一致性检查（依赖有效性、循环检测、重复检测、覆盖完整性等） |
| **M2** | FeasibilityEvaluator | 可实现性评估（FPA 功能点分析、粒度评估、资源约束匹配等） |
| **M2** | EvaluationIntegrator | 综合评分与决策建议（继续/修订/终止） |

### 管线阶段

`idle` → `split`（拆分中）→ `consistency`（一致性评估）→ `refine_sub_ar`（子 AR 细化）→ `feasibility`（可实现性评估）→ `done` / `error`

---

## 技术栈

### 后端

| 类别 | 技术 |
|------|------|
| 框架 | FastAPI 0.104 + Uvicorn |
| 数据库 | MySQL + SQLAlchemy 2.0（异步 aiomysql） |
| 认证 | JWT（python-jose + passlib/bcrypt） |
| AI/LLM | OpenAI 兼容接口（通义千问 qwen-coder-plus） |
| 数据校验 | Pydantic 2.5 + instructor |
| 状态机 | transitions |
| 实时推送 | SSE（Server-Sent Events） |

### 前端

| 类别 | 技术 |
|------|------|
| 框架 | Vue 3.5（Composition API） |
| 构建 | Vite 7 |
| UI 组件库 | Element Plus |
| 状态管理 | Pinia |
| 路由 | Vue Router 4 |
| 图表 | ECharts 5 |
| HTTP | Axios |

---

## 快速开始

### 环境要求

- **后端**：Python 3.10.7、pip 25.3、MySQL
- **前端**：Node.js 20.19+ 或 22.12+

### 1. 后端部署

```bash
cd backend_release/backend

# 创建并激活虚拟环境
python -m venv venv
source venv/bin/activate   # Linux/Mac
# venv\Scripts\activate    # Windows

# 安装依赖
pip install -r requirements.txt

# 配置环境变量
cp .env.example .env
# 编辑 .env：填写 MySQL 密码、LLM API Key 等
```

关键配置项（`.env`）：

```ini
DB_HOST=localhost
DB_PORT=3306
DB_USER=root
DB_PASSWORD=<你的MySQL密码>
DB_NAME=agent_system

LLM_API_KEY=<你的 API Key>
LLM_BASE_URL=https://api.deepseek.com/v1
LLM_MODEL=deepseek-chat

SECRET_KEY=<随机密钥>
```

```bash
# 启动服务
uvicorn app.main:app --reload
```

### 2. 前端部署

```bash
cd frontend_release/frontend

# 安装依赖
npm install

# 启动开发服务器
npm run dev
```

### 3. 初始化数据库

1. 登录 MySQL，创建数据库 `agent_system`
2. 浏览器访问 `http://localhost:8000/init-db` 自动建表

### 4. 验证

| 地址 | 说明 |
|------|------|
| `http://localhost:8000/docs` | Swagger API 文档 |
| `http://localhost:8000/health` | 健康检查 |
| `http://localhost:5173` | 前端开发页面（Vite 默认端口） |

### 5. 调试流程

1. 在 Swagger（`/docs`）注册用户 → 登录 → 获取 Token
2. 右上角 **Authorize** 填入 Token
3. 创建对话（`POST /api/v1/conversations`）：

```json
{
  "title": "在线课程平台需求分析",
  "description": "测试统一编排能力",
  "original_requirement": "实现一个在线课程平台，支持学生注册登录、浏览课程列表、购买课程、观看视频，并提供作业提交和老师评分功能。"
}
```

4. 用对话 ID 创建并启动协调任务（`POST /api/v1/coordinator/start`）：

```json
{
  "conversation_id": "<上一步返回的 id>",
  "config": {
    "model": "qwen-coder-plus",
    "consistency_inner_max_retries": 1,
    "continue_pipeline_after_consistency_exhausted": false
  }
}
```

5. 实时进度通过 SSE 订阅：`GET /api/v1/coordinator/tasks/{conversation_id}/stream`
6. 完成后通过 `GET /api/v1/coordinator/tasks/{conversation_id}/result` 获取最终结果

> **对某节点补充拆分**：`POST /api/v1/coordinator/tasks/{conversation_id}/refine-node`，传入 `node_id` 和可选的 `user_instruction` 与 `config` 覆盖。

---

## 管线配置参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `consistency_pass_threshold` | `0.7` | 一致性通过分数阈值 |
| `consistency_inner_max_retries` | `1` | 一致性未通过时内层重拆最大次数 |
| `enable_feasibility_refinement` | `true` | 是否启用可实现性驱动的子 AR 递归细化 |
| `max_feasibility_refinement_depth` | `3` | 最大递归细化深度 |
| `continue_pipeline_after_consistency_exhausted` | `false` | 根层一致性耗尽后是否继续可实现性评估 |

---

## API 概览

| 方法 | 路径 | 说明 |
|------|------|------|
| `POST` | `/api/v1/auth/register` | 用户注册 |
| `POST` | `/api/v1/auth/login` | 用户登录 |
| `POST` | `/api/v1/conversations` | 创建对话 |
| `GET` | `/api/v1/conversations/{id}` | 获取对话详情 |
| `POST` | `/api/v1/coordinator/start` | 启动协调器管线 |
| `GET` | `/api/v1/coordinator/tasks/{id}/stream` | SSE 实时进度流 |
| `GET` | `/api/v1/coordinator/tasks/{id}/result` | 获取最终结果 |
| `POST` | `/api/v1/coordinator/tasks/{id}/refine-node` | 对指定节点补充拆分 |

所有 API 接口（除注册/登录外）需 `Authorization: Bearer <token>` 认证。

---

## 前端页面

| 路由 | 页面 | 说明 |
|------|------|------|
| `/login` | 登录 | 用户登录 |
| `/register` | 注册 | 用户注册 |
| `/home` | 首页 | 对话列表、需求输入、功能树展示、评估报告、实时进度 |

核心组件：
- **FunctionTree** — 功能树可视化展示
- **EvaluationReport** — M2 评估报告展示（评分、风险、建议）
- **CoordinatorTaskConfigDialog** — 协调器任务配置面板
- **chat** — 聊天对话界面
- **coordinatorSse** — SSE 流式数据解析与状态同步
