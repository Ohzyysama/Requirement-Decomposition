// 定位测试集 v2 提交器：把每个 AR 的真实实现 + 干扰函数追加到锚点文件，逐个提交，
// 计算 file+symbol+行号 标准答案，回填真实 SHA。
import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync, existsSync, readdirSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
const SNIP = resolve(dirname(fileURLToPath(import.meta.url)), 'snippets');
const E = 'entry/src/main/ets';

// 读取全部 snippets
let items = [];
for (const f of readdirSync(SNIP).filter(f => f.endsWith('.json'))) {
  const arr = JSON.parse(readFileSync(resolve(SNIP, f), 'utf8'));
  arr.forEach(x => x.__src = f);
  items.push(...arr);
}
items.sort((a, b) => a.arId < b.arId ? -1 : a.arId > b.arId ? 1 : 0);

// ---- 校验 ----
const errs = [];
if (items.length !== 77) errs.push(`期望 77 条，实际 ${items.length}`);
const syms = new Map();
const arSeen = new Set();
for (const it of items) {
  const anchorRel = `${E}/${it.anchor}`;
  if (!existsSync(resolve(ROOT, anchorRel))) errs.push(`${it.arId} 锚点缺失: ${it.anchor}`);
  for (const f of ['arId', 'title', 'anchor', 'message', 'arComment', 'arSymbol', 'arCode', 'distractorComment', 'distractorSymbol', 'distractorCode'])
    if (!it[f]) errs.push(`${it.arId} 缺字段 ${f}`);
  if (arSeen.has(it.arId)) errs.push(`重复 AR ${it.arId}`); arSeen.add(it.arId);
  for (const s of [it.arSymbol, it.distractorSymbol]) {
    if (syms.has(s)) errs.push(`符号重名 ${s} (${it.arId} 与 ${syms.get(s)})`);
    else syms.set(s, it.arId);
  }
  if (it.arCode && !it.arCode.includes(it.arSymbol)) errs.push(`${it.arId} arCode 不含 arSymbol ${it.arSymbol}`);
  if (it.distractorCode && !it.distractorCode.includes(it.distractorSymbol)) errs.push(`${it.arId} distractorCode 不含 distractorSymbol`);
  for (const [k, code] of [['arCode', it.arCode], ['distractorCode', it.distractorCode]]) {
    if (code && /(^|\n)\s*import\s/.test(code)) errs.push(`${it.arId} ${k} 含 import`);
    if (code && /\bAR-\d{2}-\d{2}\b/.test(code)) errs.push(`${it.arId} ${k} 泄露 AR 编号`);
  }
}
if (errs.length) { console.error('校验失败:\n' + errs.join('\n')); process.exit(1); }
console.log(`校验通过：77 条，${syms.size} 个唯一符号。开始提交...\n`);

// ---- 提交 ----
const pad = n => String(n).padStart(2, '0');
const out = [];
let i = 0;
for (const it of items) {
  i++;
  const anchorRel = `${E}/${it.anchor}`;
  const abs = resolve(ROOT, anchorRel);
  let base = readFileSync(abs, 'utf8');
  if (!base.endsWith('\n')) base += '\n';
  const beforeLines = base.split('\n').length - 1;
  const N = it.arCode.split('\n').length;
  const M = it.distractorCode.split('\n').length;
  const arStart = beforeLines + 2;
  const arEnd = beforeLines + 2 + N;
  const dStart = beforeLines + 4 + N;
  const dEnd = beforeLines + 4 + N + M;
  const appendText = `\n${it.arComment}\n${it.arCode}\n\n${it.distractorComment}\n${it.distractorCode}\n`;
  writeFileSync(abs, base + appendText);

  // 校验行号
  const lines = readFileSync(abs, 'utf8').split('\n');
  const assert = (cond, msg) => { if (!cond) { console.error(`行号校验失败 ${it.arId}: ${msg}`); process.exit(1); } };
  assert(lines[arStart - 1] === it.arComment, `arComment@${arStart} 实为「${lines[arStart - 1]}」`);
  assert(lines[arEnd - 1] === it.arCode.split('\n').pop(), `arCode 末行@${arEnd}`);
  assert(lines[dStart - 1] === it.distractorComment, `distractorComment@${dStart}`);

  execFileSync('git', ['add', '--', anchorRel], { cwd: ROOT, stdio: 'ignore' });
  execFileSync('git', ['commit', '-m', it.message], { cwd: ROOT, stdio: ['ignore', 'ignore', 'ignore'] });
  const sha = execFileSync('git', ['rev-parse', 'HEAD'], { cwd: ROOT, encoding: 'utf8' }).trim();

  out.push({
    case: 'L' + pad(i),
    commit: sha,
    ar_id: it.arId,
    requirement: it.title,
    message: it.message,
    implementation: [{ file: anchorRel, symbol: it.arSymbol, start_line: arStart, end_line: arEnd }],
    distractor: [{ file: anchorRel, symbol: it.distractorSymbol, start_line: dStart, end_line: dEnd }],
  });
  process.stdout.write(`L${pad(i)} ${it.arId} ${sha.slice(0, 8)} ${it.anchor}:${arStart}-${arEnd} (${it.arSymbol}) | 干扰 ${it.distractorSymbol}:${dStart}-${dEnd}\n`);
}

writeFileSync(resolve(ROOT, 'eval/localization/ground-truth.json'), JSON.stringify(out, null, 2) + '\n');
const arCovered = new Set(out.map(o => o.ar_id));
console.log(`\n提交 ${out.length} 个 | 覆盖 AR ${arCovered.size}/77 | 已写 ground-truth.json`);
