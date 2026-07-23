// 将旧版 ground-truth（case/implementation/distractors）转换为样本模板结构
// （sample_id/query_ar_*/candidate_snippets），content 留空字符串。
import { readFileSync, writeFileSync, readdirSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const LOC = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const AR_DIR = resolve(LOC, '..', 'requirements', 'AR');
const SRC = resolve(LOC, '_gen', 'ground-truth.legacy.json');
const OUT = resolve(LOC, 'ground-truth.json');

// ar_id -> { title, text }（取 AR 文档的 [需求标题] 与 [需求描述]）
const arDocs = new Map();
for (const f of readdirSync(AR_DIR).filter(f => f.endsWith('.md'))) {
  const md = readFileSync(resolve(AR_DIR, f), 'utf8');
  const id = md.match(/^- AR-ID:\s*(\S+)/m)?.[1];
  const title = md.match(/\|\s*\[需求标题\]\s*\|\s*(.+?)\s*\|/)?.[1];
  const text = md.match(/\|\s*\[需求描述\]\s*\|\s*(.+?)\s*\|/)?.[1];
  if (!id || !title || !text) throw new Error(`AR 文档解析失败: ${f}`);
  arDocs.set(id, { title, text });
}

const legacy = JSON.parse(readFileSync(SRC, 'utf8'));
const samples = legacy.map(c => {
  const ar = arDocs.get(c.ar_id);
  if (!ar) throw new Error(`未找到 AR 文档: ${c.ar_id} (${c.case})`);
  // 正例 + 干扰合并后按文件内出现顺序（行号）排序，original_index 即该顺序
  const merged = [
    ...c.implementation.map(s => ({ ...s, label: 1 })),
    ...c.distractors.map(s => ({ ...s, label: 0 })),
  ].sort((a, b) => a.file.localeCompare(b.file) || a.start_line - b.start_line);
  let pos = 0, neg = 0;
  const candidate_snippets = merged.map((s, i) => ({
    candidate_id: `${c.case}_${s.label ? `pos_${pos++}` : `neg_${neg++}`}`,
    file_path: s.file,
    symbol: s.symbol,
    start_line: s.start_line,
    end_line: s.end_line,
    content: '',
    label: s.label,
    original_index: i,
  }));
  return {
    sample_id: c.case,
    project: 'saltplayer',
    commit: c.commit,
    query_ar_id: c.ar_id,
    query_ar_title: ar.title,
    query_ar_text: ar.text,
    raw_positive_count: c.implementation.length,
    raw_candidate_count: merged.length,
    candidate_snippets,
  };
});

writeFileSync(OUT, JSON.stringify(samples, null, 2) + '\n');
const pos = samples.reduce((n, s) => n + s.raw_positive_count, 0);
const cand = samples.reduce((n, s) => n + s.raw_candidate_count, 0);
console.log(`已生成 ${OUT}: ${samples.length} 个样本，正例 ${pos}，候选 ${cand}`);
