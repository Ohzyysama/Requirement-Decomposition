# 椒盐音乐 HarmonyOS —— 需求拆分 & 需求代码定位 评测测试集

本目录是用于评测「需求工程系统」两项能力的**带标准答案（ground truth）测试集**：

1. **需求拆分（Requirement Decomposition）**：把总体需求 SR 拆为原子需求 AR。
2. **需求代码定位（Requirement-Code Localization）**：给定一个 commit + 一条 AR 需求描述，定位该 AR 关联了哪些代码（文件 / 符号 / 行号）。

## 目录结构

```
eval/
├── README.md                       # 本文件
├── requirements/                   # 【拆分测试集】标准答案
│   ├── SR-AR-mapping.md            # 主映射表：15 SR → 77 AR（标准答案核心）
│   ├── SR-AR-detail.md             # 77 AR 逐条功能说明
│   ├── decomposition-judgment-points.md  # 77 个 (SR→AR) 判定点 + 拆分评分口径
│   ├── SR/   SR-01..SR-15 *.md     # 15 份总体需求，完整字段表规格
│   └── AR/   AR-XX-YY *.md         # 77 份原子需求，完整字段表规格
└── localization/                   # 【定位测试集】标准答案
    ├── README.md                   # 数据集说明 + 评分口径
    ├── ground-truth.json           # 154 条 (commit+AR)→关联代码（简单 77 + 难例 77，机器可读）
    ├── ground-truth.md             # 人类可读版（含每条的实现/干扰位置）
    ├── score-template.md           # 文件/符号/行级 准确率统计模板
    └── _gen/                       # 生成器（snippets 代码规格 / commit.mjs 建提交 / docs.mjs 出文档，可复现）
```

## 数据来源与可信度

- SR/AR 清单经对当前仓库 `entry/src/main/ets/` 的代码理解逐项确认（15 SR / 77 AR，重排编号版）。
- 定位测试集在分支 `eval/requirement-testset` 上为**每个 AR 构造一个真实合成提交**（共 77 个，真实改动、真实 diff），每个提交追加该 AR 的**真实代码实现**与一段**无关干扰代码**，标准答案精确到 **文件 + 符号 + 行号**，不污染 `main`。

## 如何使用

### 评测「需求拆分」
1. 让系统对仓库 `entry/` 做需求拆分，产出它自己的 SR/AR 清单。
2. 与 `requirements/decomposition-judgment-points.md` 的 **77 个 (SR→AR) 判定点** 对照，逐点判命中/未命中；据此算拆分 召回率 / 准确率 / 粒度合理性。
3. 可逐 AR 比对完整字段表规格（`AR/` 下 77 份完整 15 字段表）。

### 评测「需求代码定位」
1. 切到分支 `eval/requirement-testset`。
2. 对其中 **154 个用例**逐个（简单层 L01–L77：1 实现 + 1 通用干扰；难例层 H01–H77：1 实现 + 5 干扰，其中 3 段是其它 AR 的真实代码）：把该用例的 `commit` 与 `requirement`（AR 需求描述）给系统，让它定位「该 AR 关联了哪些代码」（输出 文件/符号/行号）。
3. 用 `localization/score-template.md` 的口径，与 `ground-truth.json` 的 `implementation` 对照，计算 文件级 / 符号级 准确率与行级 IoU；若系统命中了同 commit 内的 `distractors`（无关或其它 AR 的代码）记为误报。难例层可分层报告。

详见 `localization/README.md`。
