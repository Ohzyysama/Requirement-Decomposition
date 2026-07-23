// 定位测试集 —— 复杂层（X01-X20）：四类更复杂的场景
//   multi      同文件多段实现：2 段正例 + 3 段干扰（考查"找全"）
//   xfile      跨文件实现：2 段正例分布在 2 个文件 + 4 段干扰跨文件分布
//   xsr        跨 SR 同语义强干扰：1 正例 + 5 干扰（3 段为其它 SR 同语义 AR 的真实代码）
//   large      大候选集：1 正例 + 9 干扰（7 跨 AR + 2 通用），位置打乱
// 逐用例 git 提交（追加式，不破坏既有代码），把标准答案以旧 schema 追加进
// _gen/ground-truth.legacy.json；之后由 samples.mjs 重新生成样本模板结构的
// ground-truth.json，由 docs.mjs 重新生成文档。
import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync, readdirSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
const GEN = dirname(fileURLToPath(import.meta.url));
const SNIP = resolve(GEN, 'snippets');
const E = 'entry/src/main/ets';

let items = [];
for (const f of readdirSync(SNIP).filter(f => f.endsWith('.json')))
  items.push(...JSON.parse(readFileSync(resolve(SNIP, f), 'utf8')));
const byId = new Map(items.map(x => [x.arId, x]));

const pad = n => String(n).padStart(2, '0');
const rename = (code, from, to) => code.split(from).join(to);

// ---- 第二实现段（multi/xfile 用例的额外正例代码） ----
// file 省略 = 目标 AR 锚点文件；指定 = 跨文件实现
const EXTRA = {
  1: { comment: '// 播放控制：未加载曲目时点击播放，从记忆位置恢复并串行化命令',
    symbol: 'resolveResumeIndexX',
    code: `export function resolveResumeIndexX(loaded: boolean, rememberedIndex: number, total: number, pending: string[]): number {
  if (loaded || total <= 0) {
    return -1
  }
  if (pending.length > 0 && pending[pending.length - 1] === 'play') {
    return -1
  }
  pending.push('play')
  if (rememberedIndex >= 0 && rememberedIndex < total) {
    return rememberedIndex
  }
  return 0
}` },
  2: { comment: '// 睡眠定时：剩余毫秒格式化为 mm:ss，"播完本曲"时对齐到歌曲结束',
    symbol: 'formatSleepRemainX',
    code: `export function formatSleepRemainX(remainMs: number, finishCurrent: boolean, songRemainMs: number): string {
  let ms = remainMs > 0 ? remainMs : 0
  if (finishCurrent && songRemainMs > ms) {
    ms = songRemainMs
  }
  const sec = Math.floor(ms / 1000)
  const m = Math.floor(sec / 60)
  const s = sec % 60
  const mm = m < 10 ? '0' + m : String(m)
  const ss = s < 10 ? '0' + s : String(s)
  return mm + ':' + ss
}` },
  3: { comment: '// 媒体扫描：按扩展名过滤音频文件并统计各目录命中数量',
    symbol: 'countAudioByDirX',
    code: `export function countAudioByDirX(paths: string[], exts: string[]): Map<string, number> {
  const hit = new Map<string, number>()
  for (const p of paths) {
    const dot = p.lastIndexOf('.')
    if (dot < 0) {
      continue
    }
    const ext = p.slice(dot + 1).toLowerCase()
    if (exts.indexOf(ext) < 0) {
      continue
    }
    const slash = p.lastIndexOf('/')
    const dir = slash > 0 ? p.slice(0, slash) : '/'
    hit.set(dir, (hit.get(dir) ?? 0) + 1)
  }
  return hit
}` },
  4: { comment: '// 歌词滚动：计算当前行垂直居中所需的滚动偏移并夹取上下边界',
    symbol: 'lyricScrollOffsetX',
    code: `export function lyricScrollOffsetX(lineTops: number[], active: number, viewportH: number, contentH: number): number {
  if (active < 0 || active >= lineTops.length) {
    return 0
  }
  let offset = lineTops[active] - viewportH / 2
  const max = contentH - viewportH
  if (offset > max) {
    offset = max
  }
  if (offset < 0) {
    offset = 0
  }
  return Math.round(offset)
}` },
  5: { comment: '// 新建歌单：名称去首尾空白、空名回退默认名、与既有歌单重名时追加序号',
    symbol: 'normalizePlaylistNameX',
    code: `export function normalizePlaylistNameX(name: string, existing: string[], fallback: string): string {
  let n = name.trim()
  if (n.length === 0) {
    n = fallback
  }
  if (existing.indexOf(n) < 0) {
    return n
  }
  let i = 2
  while (existing.indexOf(n + ' (' + i + ')') >= 0) {
    i++
  }
  return n + ' (' + i + ')'
}` },
  6: { comment: '// 播放暂停渐变：按渐变时长生成等间隔音量步序列',
    symbol: 'buildFadeStepsX',
    code: `export function buildFadeStepsX(from: number, to: number, durationMs: number, stepMs: number): number[] {
  const steps: number[] = []
  const n = Math.max(1, Math.floor(durationMs / Math.max(1, stepMs)))
  for (let i = 1; i <= n; i++) {
    const v = from + (to - from) * (i / n)
    steps.push(Math.round(v * 100) / 100)
  }
  return steps
}` },
  7: { file: 'viewmodel/PlayerPageViewModel.ets',
    comment: '// 进度拖拽：把滑块百分比换算为目标毫秒位置并夹取边界',
    symbol: 'dragPercentToMsX',
    code: `export function dragPercentToMsX(percent: number, durationMs: number): number {
  if (durationMs <= 0) {
    return 0
  }
  let p = percent
  if (p < 0) {
    p = 0
  }
  if (p > 100) {
    p = 100
  }
  return Math.round(durationMs * p / 100)
}` },
  8: { file: 'viewmodel/MainPageViewModel.ets',
    comment: '// 歌曲搜索：计算关键字在标题中的高亮区间（[start,end) 列表）',
    symbol: 'searchHighlightRangesX',
    code: `export function searchHighlightRangesX(text: string, keyword: string): number[][] {
  const out: number[][] = []
  if (keyword.length === 0) {
    return out
  }
  const lower = text.toLowerCase()
  const k = keyword.toLowerCase()
  let from = 0
  while (true) {
    const at = lower.indexOf(k, from)
    if (at < 0) {
      break
    }
    out.push([at, at + k.length])
    from = at + k.length
  }
  return out
}` },
  9: { file: 'viewmodel/AlbumTabViewModel.ets',
    comment: '// 专辑列表设置：根据列数与封面开关计算网格模板描述',
    symbol: 'albumGridTemplateX',
    code: `export function albumGridTemplateX(columns: number, showCover: boolean): string {
  let c = columns
  if (c < 1) {
    c = 1
  }
  if (c > 4) {
    c = 4
  }
  const parts: string[] = []
  for (let i = 0; i < c; i++) {
    parts.push('1fr')
  }
  return (showCover ? 'cover:' : 'plain:') + parts.join(' ')
}` },
  10: { file: 'model/FolderModel.ets',
    comment: '// 隐藏文件夹：应用黑名单过滤可见文件夹（含子目录前缀匹配），保持原排序',
    symbol: 'applyHiddenFoldersX',
    code: `export function applyHiddenFoldersX(folders: string[], hidden: string[]): string[] {
  const out: string[] = []
  for (const f of folders) {
    let masked = false
    for (const h of hidden) {
      if (f === h || f.startsWith(h + '/')) {
        masked = true
        break
      }
    }
    if (!masked) {
      out.push(f)
    }
  }
  return out
}` },
  11: { file: 'viewmodel/UserInterfaceViewModel.ets',
    comment: '// 主题模式：跟随系统/手动深浅色的最终生效值计算',
    symbol: 'resolveColorModeX',
    code: `export function resolveColorModeX(mode: string, systemDark: boolean, fallback: string): string {
  if (mode === 'dark' || mode === 'light') {
    return mode
  }
  if (mode === 'system') {
    return systemDark ? 'dark' : 'light'
  }
  return fallback === 'dark' ? 'dark' : 'light'
}` },
  12: { file: 'viewmodel/LyricsViewModel.ets',
    comment: '// 桌面歌词开关：由开关状态、会话可用性与歌词有无求最终展示态',
    symbol: 'desktopLyricsStateX',
    code: `export function desktopLyricsStateX(enabled: boolean, sessionReady: boolean, hasLyric: boolean): string {
  if (!enabled) {
    return 'off'
  }
  if (!sessionReady) {
    return 'pending'
  }
  return hasLyric ? 'showing' : 'empty'
}` },
};

// ---- 用例定义 ----
// cross: 干扰取这些 AR 的真实实现代码（标注来源）；generic: 干扰取这些 AR 的通用干扰函数。
// xfile 的 cross/generic 各 2 个：[0] 放锚点文件，[1] 放第二文件。
const CASES = [
  // A 同文件多段实现（2 正例 + 3 干扰）
  { no: 1, type: 'multi', ar: 'AR-01-01', cross: ['AR-01-02', 'AR-01-03'], generic: ['AR-01-04'] },
  { no: 2, type: 'multi', ar: 'AR-01-06', cross: ['AR-01-05', 'AR-01-07'], generic: ['AR-01-08'] },
  { no: 3, type: 'multi', ar: 'AR-02-01', cross: ['AR-02-02', 'AR-02-04'], generic: ['AR-02-03'] },
  { no: 4, type: 'multi', ar: 'AR-04-02', cross: ['AR-04-01', 'AR-04-03'], generic: ['AR-04-04'] },
  { no: 5, type: 'multi', ar: 'AR-08-01', cross: ['AR-08-02', 'AR-08-04'], generic: ['AR-08-03'] },
  { no: 6, type: 'multi', ar: 'AR-13-03', cross: ['AR-13-01', 'AR-13-04'], generic: ['AR-13-02'] },
  // B 跨文件实现（2 正例分布 2 文件 + 4 干扰跨文件）
  { no: 7, type: 'xfile', ar: 'AR-01-05', cross: ['AR-01-01', 'AR-01-07'], generic: ['AR-01-02', 'AR-01-06'] },
  { no: 8, type: 'xfile', ar: 'AR-03-02', cross: ['AR-03-03', 'AR-09-02'], generic: ['AR-03-01', 'AR-03-05'] },
  { no: 9, type: 'xfile', ar: 'AR-05-03', cross: ['AR-12-02', 'AR-05-01'], generic: ['AR-05-02', 'AR-05-04'] },
  { no: 10, type: 'xfile', ar: 'AR-07-03', cross: ['AR-02-03', 'AR-07-01'], generic: ['AR-07-02', 'AR-07-04'] },
  { no: 11, type: 'xfile', ar: 'AR-12-01', cross: ['AR-12-06', 'AR-12-03'], generic: ['AR-12-04', 'AR-12-05'] },
  { no: 12, type: 'xfile', ar: 'AR-11-01', cross: ['AR-11-02', 'AR-04-05'], generic: ['AR-11-03', 'AR-11-04'] },
  // C 跨 SR 同语义强干扰（1 正例 + 5 干扰，3 段为同语义家族真实代码）
  { no: 13, type: 'xsr', ar: 'AR-03-04', cross: ['AR-05-02', 'AR-06-02', 'AR-07-06'], generic: ['AR-03-03', 'AR-03-06'] },
  { no: 14, type: 'xsr', ar: 'AR-09-02', cross: ['AR-03-02', 'AR-07-02', 'AR-09-01'], generic: ['AR-02-01', 'AR-08-05'] },
  { no: 15, type: 'xsr', ar: 'AR-07-05', cross: ['AR-03-03', 'AR-08-06', 'AR-07-06'], generic: ['AR-07-07', 'AR-07-01'] },
  { no: 16, type: 'xsr', ar: 'AR-07-08', cross: ['AR-03-06', 'AR-07-09', 'AR-03-07'], generic: ['AR-07-02', 'AR-07-04'] },
  // D 大候选集（1 正例 + 9 干扰）
  { no: 17, type: 'large', ar: 'AR-01-02', cross: ['AR-01-01', 'AR-01-03', 'AR-01-04', 'AR-01-05', 'AR-01-06', 'AR-03-05', 'AR-07-07'], generic: ['AR-01-07', 'AR-01-08'] },
  { no: 18, type: 'large', ar: 'AR-04-03', cross: ['AR-04-01', 'AR-04-02', 'AR-04-04', 'AR-04-05', 'AR-04-06', 'AR-11-03', 'AR-11-04'], generic: ['AR-11-01', 'AR-11-02'] },
  { no: 19, type: 'large', ar: 'AR-08-04', cross: ['AR-08-01', 'AR-08-02', 'AR-08-03', 'AR-08-05', 'AR-08-06', 'AR-03-07', 'AR-10-01'], generic: ['AR-09-01', 'AR-09-02'] },
  { no: 20, type: 'large', ar: 'AR-12-05', cross: ['AR-12-01', 'AR-12-02', 'AR-12-03', 'AR-12-04', 'AR-12-06', 'AR-12-07', 'AR-14-02'], generic: ['AR-14-01', 'AR-15-01'] },
];

// ---- 校验 ----
const errs = [];
for (const c of CASES) {
  if (!byId.has(c.ar)) errs.push(`X${pad(c.no)} 目标 AR 不存在: ${c.ar}`);
  for (const id of c.cross.concat(c.generic)) if (!byId.has(id)) errs.push(`X${pad(c.no)} 干扰 AR 不存在: ${id}`);
  if ((c.type === 'multi' || c.type === 'xfile') && !EXTRA[c.no]) errs.push(`X${pad(c.no)} 缺第二实现段`);
  if (c.type === 'xfile') {
    const ex = EXTRA[c.no];
    if (!ex.file) errs.push(`X${pad(c.no)} xfile 第二实现段缺 file`);
    else if (ex.file === byId.get(c.ar).anchor) errs.push(`X${pad(c.no)} 第二文件与锚点相同`);
    if (c.cross.length !== 2 || c.generic.length !== 2) errs.push(`X${pad(c.no)} xfile 需 cross/generic 各 2 个`);
  }
  const ex = EXTRA[c.no];
  if (ex && !ex.code.includes(ex.symbol)) errs.push(`X${pad(c.no)} 第二实现段代码不含符号名`);
}
if (errs.length) { console.error('校验失败:\n' + errs.join('\n')); process.exit(1); }
console.log(`校验通过：${CASES.length} 个复杂用例。开始提交...\n`);

// 把若干代码块追加到一个文件末尾，返回各块行号区间
function appendBlocks(relPath, blocks) {
  const abs = resolve(ROOT, relPath);
  let base = readFileSync(abs, 'utf8');
  if (!base.endsWith('\n')) base += '\n';
  let cur = base.split('\n').length - 1;
  const newLines = [];
  const push = s => { newLines.push(s); cur++; return cur; };
  for (const b of blocks) {
    push('');
    const start = push(b.comment);
    let end = start;
    for (const cl of b.code.split('\n')) end = push(cl);
    b.range = [start, end];
    b.file = relPath;
  }
  writeFileSync(abs, base + newLines.join('\n') + '\n');
  const lines = readFileSync(abs, 'utf8').split('\n');
  for (const b of blocks)
    if (lines[b.range[0] - 1] !== b.comment) { console.error(`行号校验失败 ${relPath} 块 ${b.symbol}`); process.exit(1); }
}

const complexOut = [];
for (const c of CASES) {
  const T = byId.get(c.ar);
  const sfx = `_X${c.no}`;
  const used = new Set();
  const uniq = base => { let s = base + sfx; let k = 1; while (used.has(s)) s = base + sfx + '_' + (k++); used.add(s); return s; };
  const implBlock = () => {
    const sym = uniq(T.arSymbol);
    return { kind: 'impl', comment: T.arComment, symbol: sym, code: rename(T.arCode, T.arSymbol, sym) };
  };
  const extraBlock = () => {
    const ex = EXTRA[c.no];
    const sym = uniq(ex.symbol);
    return { kind: 'impl', comment: ex.comment, symbol: sym, code: rename(ex.code, ex.symbol, sym) };
  };
  const crossBlock = id => {
    const D = byId.get(id);
    const sym = uniq(D.arSymbol);
    return { kind: 'cross', source: D.arId, comment: D.arComment, symbol: sym, code: rename(D.arCode, D.arSymbol, sym) };
  };
  const genericBlock = id => {
    const D = byId.get(id);
    const sym = uniq(D.distractorSymbol);
    return { kind: 'generic', source: 'generic', comment: D.distractorComment, symbol: sym, code: rename(D.distractorCode, D.distractorSymbol, sym) };
  };
  const rot = (arr, k) => { const r = k % arr.length; return arr.slice(r).concat(arr.slice(0, r)); };

  const anchorRel = `${E}/${T.anchor}`;
  const files = [];
  if (c.type === 'xfile') {
    const file2Rel = `${E}/${EXTRA[c.no].file}`;
    files.push({ rel: anchorRel, blocks: rot([implBlock(), crossBlock(c.cross[0]), genericBlock(c.generic[0])], c.no) });
    files.push({ rel: file2Rel, blocks: rot([extraBlock(), crossBlock(c.cross[1]), genericBlock(c.generic[1])], c.no + 1) });
  } else {
    const blocks = [implBlock()];
    if (c.type === 'multi') blocks.push(extraBlock());
    for (const id of c.cross) blocks.push(crossBlock(id));
    for (const id of c.generic) blocks.push(genericBlock(id));
    files.push({ rel: anchorRel, blocks: rot(blocks, c.no * 3) });
  }

  for (const f of files) appendBlocks(f.rel, f.blocks);
  execFileSync('git', ['add', '--', ...files.map(f => f.rel)], { cwd: ROOT, stdio: 'ignore' });
  execFileSync('git', ['commit', '-m', T.message], { cwd: ROOT, stdio: ['ignore', 'ignore', 'ignore'] });
  const sha = execFileSync('git', ['rev-parse', 'HEAD'], { cwd: ROOT, encoding: 'utf8' }).trim();

  const all = files.flatMap(f => f.blocks);
  const impls = all.filter(b => b.kind === 'impl').map(b => ({ file: b.file, symbol: b.symbol, start_line: b.range[0], end_line: b.range[1] }));
  const distractors = all.filter(b => b.kind !== 'impl').map(b => ({ file: b.file, symbol: b.symbol, start_line: b.range[0], end_line: b.range[1], source: b.source }));
  complexOut.push({
    case: 'X' + pad(c.no), tier: 'complex', scenario: c.type, commit: sha, ar_id: c.ar, requirement: T.title, message: T.message,
    implementation: impls, distractors,
  });
  process.stdout.write(`X${pad(c.no)} [${c.type}] ${c.ar} ${sha.slice(0, 8)} 正例 ${impls.length} | 干扰 ${distractors.length}（跨AR ${distractors.filter(d => d.source !== 'generic').length}）| 文件 ${files.length}\n`);
}

// 追加进 legacy 标准答案（samples.mjs / docs.mjs 的数据源）
const legacyPath = resolve(GEN, 'ground-truth.legacy.json');
const prev = JSON.parse(readFileSync(legacyPath, 'utf8')).filter(e => e.tier !== 'complex');
const merged = prev.concat(complexOut);
writeFileSync(legacyPath, JSON.stringify(merged, null, 2) + '\n');
console.log(`\n复杂用例 ${complexOut.length} 个已提交 | legacy 合并后共 ${merged.length} 条。请依次运行 samples.mjs 与 docs.mjs。`);
