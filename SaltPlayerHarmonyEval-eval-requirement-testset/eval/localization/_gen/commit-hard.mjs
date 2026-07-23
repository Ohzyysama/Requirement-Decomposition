// 定位测试集 —— 难例层（H01-H77）：每个 AR 的 commit 含其真实实现 + 5 段干扰
// （3 段为其它 AR 的真实代码，标注来源 AR；2 段通用无关代码）。目标实现位置打乱。
// 保留已有简单层 L01-L77，合并写回 ground-truth.json。
import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync, existsSync, readdirSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
const GEN = dirname(fileURLToPath(import.meta.url));
const SNIP = resolve(GEN, 'snippets');
const E = 'entry/src/main/ets';

// 读 snippets（含每个 AR 的实现代码 + 通用干扰代码）
let items = [];
for (const f of readdirSync(SNIP).filter(f => f.endsWith('.json')))
  items.push(...JSON.parse(readFileSync(resolve(SNIP, f), 'utf8')));
items.sort((a, b) => a.arId < b.arId ? -1 : a.arId > b.arId ? 1 : 0);
const byId = new Map(items.map(x => [x.arId, x]));

const pad = n => String(n).padStart(2, '0');
const rename = (code, from, to) => code.split(from).join(to);

// 选 3 个跨 AR 干扰：优先同 SR，再补其它；按 t 轮转增加多样性
function crossPicks(t) {
  const T = items[t];
  const sr = T.arId.slice(0, 5);
  const sameSR = items.filter(x => x.arId !== T.arId && x.arId.startsWith(sr));
  const others = items.filter(x => x.arId !== T.arId && !x.arId.startsWith(sr));
  const pool = sameSR.concat(others);
  const rot = t % pool.length;
  const rotated = pool.slice(rot).concat(pool.slice(0, rot));
  return rotated.slice(0, 3);
}

const hardOut = [];
let n = 0;
for (let t = 0; t < items.length; t++) {
  n++;
  const T = items[t];
  const caseNo = n;
  const anchorRel = `${E}/${T.anchor}`;
  const abs = resolve(ROOT, anchorRel);
  const sfx = `_H${caseNo}`;

  // 组装代码块
  const used = new Set();
  const uniq = base => { let s = base + sfx; let k = 1; while (used.has(s)) s = base + sfx + '_' + (k++); used.add(s); return s; };
  const blocks = [];
  // 目标实现
  {
    const sym = uniq(T.arSymbol);
    blocks.push({ kind: 'impl', comment: T.arComment, symbol: sym, code: rename(T.arCode, T.arSymbol, sym) });
  }
  // 3 跨 AR 干扰
  for (const D of crossPicks(t)) {
    const sym = uniq(D.arSymbol);
    blocks.push({ kind: 'cross', source: D.arId, comment: D.arComment, symbol: sym, code: rename(D.arCode, D.arSymbol, sym) });
  }
  // 2 通用干扰（取另两个条目的通用干扰函数）
  for (const off of [1, 2]) {
    const D = items[(t + off) % items.length];
    const sym = uniq(D.distractorSymbol);
    blocks.push({ kind: 'generic', source: 'generic', comment: D.distractorComment, symbol: sym, code: rename(D.distractorCode, D.distractorSymbol, sym) });
  }
  // 轮转打乱目标位置
  const rot = caseNo % blocks.length;
  const ordered = blocks.slice(rot).concat(blocks.slice(0, rot));

  // 追加并计算行号
  let base = readFileSync(abs, 'utf8');
  if (!base.endsWith('\n')) base += '\n';
  const beforeLines = base.split('\n').length - 1;
  const newLines = [];
  let cur = beforeLines;
  const push = s => { newLines.push(s); cur++; return cur; };
  for (const b of ordered) {
    push('');
    const start = push(b.comment);
    let end = start;
    for (const cl of b.code.split('\n')) end = push(cl);
    b.range = [start, end];
  }
  writeFileSync(abs, base + newLines.join('\n') + '\n');

  // 校验行号
  const lines = readFileSync(abs, 'utf8').split('\n');
  for (const b of ordered) {
    if (lines[b.range[0] - 1] !== b.comment) { console.error(`行号校验失败 H${caseNo} ${T.arId} 块 ${b.symbol}`); process.exit(1); }
  }

  execFileSync('git', ['add', '--', anchorRel], { cwd: ROOT, stdio: 'ignore' });
  execFileSync('git', ['commit', '-m', T.message], { cwd: ROOT, stdio: ['ignore', 'ignore', 'ignore'] });
  const sha = execFileSync('git', ['rev-parse', 'HEAD'], { cwd: ROOT, encoding: 'utf8' }).trim();

  const impl = ordered.find(b => b.kind === 'impl');
  const distractors = ordered.filter(b => b.kind !== 'impl').map(b => ({
    file: anchorRel, symbol: b.symbol, start_line: b.range[0], end_line: b.range[1],
    source: b.kind === 'cross' ? b.source : 'generic',
  }));
  hardOut.push({
    case: 'H' + pad(caseNo), tier: 'hard', commit: sha, ar_id: T.arId, requirement: T.title, message: T.message,
    implementation: [{ file: anchorRel, symbol: impl.symbol, start_line: impl.range[0], end_line: impl.range[1] }],
    distractors,
  });
  process.stdout.write(`H${pad(caseNo)} ${T.arId} ${sha.slice(0, 8)} impl ${impl.symbol}@${impl.range[0]}-${impl.range[1]} | 干扰 ${distractors.length}（跨AR ${distractors.filter(d => d.source !== 'generic').length}）\n`);
}

// 合并：把已有简单层 L01-L77 规整为统一 schema + 追加难例层
const gtPath = resolve(ROOT, 'eval/localization/ground-truth.json');
const prev = JSON.parse(readFileSync(gtPath, 'utf8'));
const simple = prev.map(e => ({
  case: e.case, tier: 'simple', commit: e.commit, ar_id: e.ar_id, requirement: e.requirement, message: e.message,
  implementation: e.implementation,
  distractors: (e.distractor || e.distractors || []).map(d => ({ ...d, source: d.source || 'generic' })),
}));
const merged = simple.concat(hardOut);
writeFileSync(gtPath, JSON.stringify(merged, null, 2) + '\n');
console.log(`\n难例 ${hardOut.length} 个已提交 | 合并后共 ${merged.length} 条（简单 ${simple.length} + 难例 ${hardOut.length}）`);
