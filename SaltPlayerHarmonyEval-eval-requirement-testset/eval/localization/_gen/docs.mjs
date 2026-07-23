// 由 _gen/ground-truth.legacy.json（旧结构）生成 ground-truth.md 与 score-template.md（AR→代码，双层）
// 注：ground-truth.json 已改为样本模板结构（见 _gen/samples.mjs），文档仍由旧结构生成。
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
const LOC = resolve(ROOT, 'eval/localization');
const g = JSON.parse(readFileSync(resolve(LOC, '_gen', 'ground-truth.legacy.json'), 'utf8'));
const simple = g.filter(x => x.tier === 'simple');
const hard = g.filter(x => x.tier === 'hard');
const complex = g.filter(x => x.tier === 'complex');
const short = f => f.replace('entry/src/main/ets/', '');
const loc = x => `\`${short(x.file)}\`·\`${x.symbol}\`·L${x.start_line}-${x.end_line}`;
const locs = arr => arr.map(loc).join('<br>');
const SCEN = { multi: '同文件多段实现', xfile: '跨文件实现', xsr: '跨SR同语义干扰', large: '大候选集' };

// ground-truth.md
let md = `# 需求代码定位测试集 —— 标准答案（人类可读版）

> 机器可读版见 \`ground-truth.json\`。任务方向：**给定一个 commit + 一条 AR 需求描述 → 定位该 AR 关联的真实代码**（文件 + 符号 + 行号）。
> 标准答案对齐 **15-SR / 77-AR 方案**（见 \`../requirements/SR-AR-mapping.md\`）。

## 统计
- 用例数：**${g.length}**（简单层 ${simple.length} + 难例层 ${hard.length} + 复杂层 ${complex.length}）
- **简单层 L01-L77**：每个 commit = 1 段 AR 真实实现 + 1 段通用干扰。
- **难例层 H01-H77**：每个 commit = 1 段 AR 真实实现 + **5 段干扰**（其中 **3 段是其它 AR 的真实代码**，已标注来源 AR；2 段通用无关代码），目标实现位置打乱。
- **复杂层 X01-X${String(complex.length).padStart(2, '0')}**：四类复杂场景 —— 同文件多段实现（2 正例）/ 跨文件实现（2 正例分布 2 个文件）/ 跨 SR 同语义强干扰 / 大候选集（1 正例 + 9 干扰）。
- 粒度：文件 + 符号 + 行号区间。每个干扰标 \`source\`：\`generic\` 或来源 AR 编号（如 \`AR-03-04\`）。

## 简单层 L01-L77

| 用例 | AR | 需求描述 | commit | 标准答案（AR 关联代码） | 干扰（通用） |
|------|----|----------|--------|--------------------------|--------------|
`;
for (const c of simple)
  md += `| ${c.case} | ${c.ar_id} | ${c.requirement} | \`${c.commit.slice(0, 8)}\` | ${loc(c.implementation[0])} | ${loc(c.distractors[0])} |\n`;

md += `
## 难例层 H01-H77（多干扰 + 跨 AR 干扰）

| 用例 | AR | commit | 标准答案（AR 关联代码） | 干扰数 | 跨 AR 干扰来源 |
|------|----|--------|--------------------------|--------|----------------|
`;
for (const c of hard) {
  const cross = c.distractors.filter(d => d.source !== 'generic').map(d => d.source).join(', ');
  md += `| ${c.case} | ${c.ar_id} | \`${c.commit.slice(0, 8)}\` | ${loc(c.implementation[0])} | ${c.distractors.length} | ${cross} |\n`;
}
md += `
## 复杂层 X01-X${String(complex.length).padStart(2, '0')}（多段实现 / 跨文件 / 跨SR干扰 / 大候选集）

| 用例 | 场景 | AR | commit | 标准答案（可能多段） | 干扰数 | 跨 AR 干扰来源 |
|------|------|----|--------|----------------------|--------|----------------|
`;
for (const c of complex) {
  const cross = c.distractors.filter(d => d.source !== 'generic').map(d => d.source).join(', ');
  md += `| ${c.case} | ${SCEN[c.scenario] || c.scenario} | ${c.ar_id} | \`${c.commit.slice(0, 8)}\` | ${locs(c.implementation)} | ${c.distractors.length} | ${cross} |\n`;
}
md += `
> 难例/复杂层每个干扰的精确位置与来源见标准答案的 \`distractors[].{symbol,start_line,end_line,source}\`。
> \`source\` 为 \`generic\`（通用无关代码）或某 AR 编号（该段是那个 AR 的真实代码，作为强干扰）。
> 复杂层 \`multi\`/\`xfile\` 场景有 **2 段正例**，须全部找到才算找全（按召回计）。
`;
writeFileSync(resolve(LOC, 'ground-truth.md'), md);

// score-template.md
let st = `# 需求代码定位 —— 评分模板（AR→代码，双层）

输入 \`commit + AR 需求描述\`，系统输出「该 AR 关联代码位置（文件/符号/行号）」，填入「系统输出」。
判定（口径见 \`README.md\`）：文件级 / 符号级 / 行级 IoU；命中任一 \`distractors\` 记为误报（难例层干扰更多、且含其它 AR 真实代码）。

| 用例 | 层 | AR | commit | 标准答案 | 干扰数 | 系统输出 | 文件✓ | 符号✓ | 行级IoU | 命中干扰? |
|------|----|----|--------|----------|--------|----------|-------|-------|---------|-----------|
`;
for (const c of g) {
  st += `| ${c.case} | ${c.tier} | ${c.ar_id} | \`${c.commit.slice(0, 8)}\` | ${locs(c.implementation)} | ${c.distractors.length} | | | | | |\n`;
}
st += `
## 汇总（分层报告）

| 指标 | 简单层(${simple.length}) | 难例层(${hard.length}) | 复杂层(${complex.length}) | 全部(${g.length}) |
|------|-----------|-----------|-----------|-----------|
| 文件级准确率 | | | | |
| 符号级准确率 | | | | |
| 行级平均 IoU | | | | |
| 干扰命中率（理想 0） | | | | |
| 跨 AR 干扰被误判为目标 AR 的次数 | — | | | |
| 多段正例召回率（找全 2 段的比例） | — | — | | |
| 综合命中（符号正确且未命中干扰） | | | | |

> 难例层重点考查：在同一 commit/文件中混入其它 AR 的真实代码时，系统能否只挑出目标 AR 的实现而不被同域相似代码带偏。
> 复杂层另考查：多段/跨文件实现的"找全"能力（multi/xfile 场景每用例 2 段正例，全部命中才算找全）、
> 跨 SR 同语义家族（ABC 索引/搜索/排序/多选等）的区分能力、以及大候选集（1 正例 + 9 干扰）下的精确率。
> 标准答案以 \`ground-truth.json\` 为准。
`;
writeFileSync(resolve(LOC, 'score-template.md'), st);
console.log(`已生成 ground-truth.md 与 score-template.md（简单 ${simple.length} + 难例 ${hard.length} + 复杂 ${complex.length} = ${g.length}）`);
