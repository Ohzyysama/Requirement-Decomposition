
### 为什么拆 schema / agent？
- schema（Pydantic）用于 **约束 LLM 输出结构**，便于稳定接入与校验
- agent 负责 **调用 LLM + 组装 BaseAgentOutput**
- module3 后续如果做 schema 校验、版本升级、复用都会更轻松

---

## 3. 输入输出协议（模块三如何组装调用参数）

### 3.1 统一输入：`AgentInput`
模块三传入的 `AgentInput` 需要包含：

- `task_id`：本轮任务唯一标识
- `requirement_text`：用户原始自然语言输入
- `normalized_requirement`：标准化需求（Normalizer 输出后才有）
- `artifacts`：上游产物（功能树、依赖等）
- `context`：平台/角色/约束/术语等上下文
- `config`：运行配置（如模型、max_depth 等）

> 模块一智能体不会自行获取外部上下文，模块三需要显式传入。

---

## 4. 三个智能体的产物说明（模块三要存哪些关键字段）

### 4.1 M1-Normalizer 输出重点
模块三需保存：
- 标准化需求主句（供后续拆分使用）
- 约束与范围（供后续评估与展示使用）
- 待确认问题（半自动/手动模式可用）
- 假设项（用于解释与风险提示）

✅ 模块三要写回：
- `normalized_requirement`

---

### 4.2 M1-FunctionalDecomposer 输出重点
模块三需保存：
- **功能列表 `function_list`**（核心产物：扁平行，含 `parent_id`/`path` 等，与 `FunctionNode` 内核字段对齐）
- 编排层会 **派生 `function_tree`** 供 Dependency / M2 等仍吃树的模块使用
- 主流程骨架（用于覆盖检查）

**统一输入**（`AgentInput.artifacts`）：
- 必须提供 **`focus_node`**：一个父功能点对象（含有效 **`id`**）。首轮由编排层在 Normalizer 之后用 [`build_focus_node_from_normalizer`](app/services/agents/M1/focus_from_normalizer.py) 从预处理结果**确定性生成**根节点（默认 `id=F-1`）；子 AR 细化时传入待拆的已有节点快照。
- **`normalized_requirement`** 与 **`normalizer_result`** 仍作为上下文与约束来源传入；**不再**支持「仅整段标准化文本、无 `focus_node`」的拆分入口。

✅ 协调器在 Normalizer 完成后写入 **`decomposition_root`** 便于展示/追溯；Decomposer 输出在首轮会自动 **prepend** `F-1` 行，使 `function_list` 含需求根与一层子节点。

✅ 模块三要写回：
- `artifacts.function_list`（主）
- `artifacts.function_tree`（协调层由列表派生，兼容旧链路）

---

### 4.3 M1-DependencyClassifier 输出重点
模块三需保存：
- 依赖集合（顺序 / 数据 / 资源三类）
- 依赖指标（缺失项、分布统计）

✅ 模块三要写回：
- `artifacts.dependencies`

---

## 5. 模块三最小串联调用示例（一轮完整模块一）

下面是模块三一轮执行模块一的最小示例（伪代码 / 可直接照搬改造）：

```python
from schemas.agent import AgentInput
from agents.module1.m1_normalizer_agent import M1NormalizerAgent
from agents.module1.m1_decomposer_agent import M1FunctionalDecomposerAgent
from agents.module1.m1_dependency_agent import M1DependencyClassifierAgent


async def run_module1(task_id: str, requirement_text: str, context: dict, config: dict):
    # 1) Normalizer
    normalizer = M1NormalizerAgent()
    out_norm = await normalizer.execute(AgentInput(
        task_id=task_id,
        requirement_text=requirement_text,
        context=context,
        config=config
    ))
    norm_result = out_norm.result["result"]  # 或 model_dump
    normalized_requirement = norm_result.get("normalized_requirement", "")
    from services.agents.M1.focus_from_normalizer import build_focus_node_from_normalizer
    focus_node = build_focus_node_from_normalizer(norm_result if isinstance(norm_result, dict) else {})

    # 2) Decomposer
    decomposer = M1FunctionalDecomposerAgent()
    out_decomp = await decomposer.execute(AgentInput(
        task_id=task_id,
        requirement_text=requirement_text,
        normalized_requirement=normalized_requirement,
        context=context,
        config=config,
        artifacts={"focus_node": focus_node, "normalizer_result": norm_result},
    ))
    function_list = out_decomp.result["result"]["function_list"]
    from services.agents.M1.schemas.m1_decomposer import function_list_to_function_tree_dict
    function_tree = function_list_to_function_tree_dict(function_list)

    # 3) DependencyClassifier
    dep_agent = M1DependencyClassifierAgent()
    out_dep = await dep_agent.execute(AgentInput(
        task_id=task_id,
        requirement_text=requirement_text,
        artifacts={"function_tree": function_tree},
        context=context,
        config=config
    ))
    dependencies = out_dep.result["result"]["dependencies"]

    return {
        "normalized_requirement": normalized_requirement,
        "function_list": function_list,
        "function_tree": function_tree,
        "dependencies": dependencies,
    }
```
