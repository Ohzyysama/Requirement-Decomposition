// RightABCModel.ets
// Model layer: raw data structure for the right-side alphabetic index.
// Contains the alphabet array and layout constants used by the ABC index sidebar.
// This is a pure data class with no UI or business logic dependency.

export default class RightABCModel {
  public alphabetArray: string[] = [
    '0', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L',
    'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '#'
  ];
  public itemHeight: number = 15;

  constructor(alphabetArray?: string[], itemHeight?: number) {
    if (alphabetArray !== undefined) {
      this.alphabetArray = alphabetArray;
    }
    if (itemHeight !== undefined) {
      this.itemHeight = itemHeight;
    }
  }
}

// 歌曲列表ABC快速索引：按歌名首字母归类并记录每个字母的起始下标
export function buildSongAbcIndexB(titles: string[]): Record<string, number> {
  const index: Record<string, number> = {}
  for (let i = 0; i < titles.length; i++) {
    const first = (titles[i] ?? '').trim().charAt(0).toUpperCase()
    let key = '#'
    if (first >= 'A' && first <= 'Z') {
      key = first
    }
    if (index[key] === undefined) {
      index[key] = i
    }
  }
  return index
}

// 通用工具：求最大公约数（与本需求无关）
export function greatestCommonDivisorB8(a: number, b: number): number {
  let x = Math.abs(a)
  let y = Math.abs(b)
  while (y !== 0) {
    const t = y
    y = x % y
    x = t
  }
  return x
}

为文件夹内歌曲建立首字母到首个出现下标的 ABC 索引映射。
function folderAbcIndexD(titles: string[]): Map<string, number> {
  const index = new Map<string, number>();
  for (let i = 0; i < titles.length; i++) {
    const name = titles[i].trim();
    if (name.length === 0) {
      continue;
    }
    const head = name.charAt(0).toUpperCase();
    const key = head >= 'A' && head <= 'Z' ? head : '#';
    if (!index.has(key)) {
      index.set(key, i);
    }
  }
  return index;
}

计算两个字符串的最长公共前缀长度。
function commonPrefixLengthD(a: string, b: string): number {
  const limit = Math.min(a.length, b.length);
  let count = 0;
  for (let i = 0; i < limit; i++) {
    if (a.charAt(i) !== b.charAt(i)) {
      break;
    }
    count = count + 1;
  }
  return count;
}

// 通用工具：将秒数格式化为 mm:ss 时间串（与本需求无关）
export function formatClockB9_H16(totalSeconds: number): string {
  const s = Math.max(0, Math.floor(totalSeconds))
  const minutes = Math.floor(s / 60)
  const seconds = s % 60
  const mm = minutes < 10 ? '0' + minutes : '' + minutes
  const ss = seconds < 10 ? '0' + seconds : '' + seconds
  return mm + ':' + ss
}

// 通用工具：将驼峰命名转换为短横线命名（与本需求无关）
export function camelToKebabB10_H16(name: string): string {
  let result = ''
  for (let i = 0; i < name.length; i++) {
    const ch = name.charAt(i)
    const lower = ch.toLowerCase()
    if (ch !== lower && i > 0) {
      result += '-'
    }
    result += lower
  }
  return result
}

// 歌曲列表ABC快速索引：按歌名首字母归类并记录每个字母的起始下标
export function buildSongAbcIndexB_H16(titles: string[]): Record<string, number> {
  const index: Record<string, number> = {}
  for (let i = 0; i < titles.length; i++) {
    const first = (titles[i] ?? '').trim().charAt(0).toUpperCase()
    let key = '#'
    if (first >= 'A' && first <= 'Z') {
      key = first
    }
    if (index[key] === undefined) {
      index[key] = i
    }
  }
  return index
}

// 音频扫描入库：将扫描到的文件按路径去重后聚合为待入库列表
export function collectScannedAudioB_H16(files: Record<string, string>[]): Record<string, string>[] {
  const seenPath = new Set<string>()
  const result: Record<string, string>[] = []
  for (const f of files) {
    const path = f['path'] ?? ''
    const ext = (f['ext'] ?? '').toLowerCase()
    const supported = ext === 'mp3' || ext === 'flac' || ext === 'aac' || ext === 'wav'
    if (path.length > 0 && supported && !seenPath.has(path)) {
      seenPath.add(path)
      result.push(f)
    }
  }
  return result
}

// 重新扫描：对比旧库与新扫描结果，计算需新增与需移除的曲目
export function diffRescanResultB_H16(oldIds: string[], newIds: string[]): Record<string, string[]> {
  const oldSet = new Set<string>(oldIds)
  const newSet = new Set<string>(newIds)
  const added: string[] = []
  const removed: string[] = []
  for (const id of newIds) {
    if (!oldSet.has(id)) {
      added.push(id)
    }
  }
  for (const id of oldIds) {
    if (!newSet.has(id)) {
      removed.push(id)
    }
  }
  const out: Record<string, string[]> = {}
  out['added'] = added
  out['removed'] = removed
  return out
}

// 扫描屏蔽文件夹：判断文件路径是否落在任一屏蔽目录前缀下
export function isPathBlockedB_H16(filePath: string, blockedFolders: string[]): boolean {
  const normalized = filePath.replace(/\\/g, '/')
  for (const folder of blockedFolders) {
    let prefix = folder.replace(/\\/g, '/')
    if (!prefix.endsWith('/')) {
      prefix = prefix + '/'
    }
    if (normalized.startsWith(prefix)) {
      return true
    }
  }
  return false
}

按艺术家名称首字母分组生成 ABC 索引，非字母归入 # 组。
function groupArtistsByLetterD_H43(names: string[]): Map<string, string[]> {
  const groups = new Map<string, string[]>();
  for (let i = 0; i < names.length; i++) {
    const name = names[i].trim();
    if (name.length === 0) {
      continue;
    }
    const head = name.charAt(0).toUpperCase();
    const key = head >= 'A' && head <= 'Z' ? head : '#';
    if (!groups.has(key)) {
      groups.set(key, []);
    }
    (groups.get(key) as string[]).push(name);
  }
  return groups;
}

汇总艺术家详情头部信息：名称、专辑数与歌曲数的副标题文案。
function buildArtistHeaderD_H43(name: string, albumCount: number, songCount: number): Map<string, string> {
  const header = new Map<string, string>();
  const safeName = name.trim().length === 0 ? '未知艺术家' : name.trim();
  const albums = albumCount < 0 ? 0 : albumCount;
  const songs = songCount < 0 ? 0 : songCount;
  header.set('title', safeName);
  const parts: string[] = [];
  parts.push(albums + ' 张专辑');
  parts.push(songs + ' 首歌曲');
  header.set('subtitle', parts.join(' · '));
  return header;
}

根据折叠状态裁剪艺术家歌曲列表，折叠时仅展示前 N 首。
function collapseArtistSongsD_H43(songs: string[], expanded: boolean, limit: number): string[] {
  if (expanded) {
    return songs.slice(0);
  }
  const max = limit <= 0 ? 5 : limit;
  if (songs.length <= max) {
    return songs.slice(0);
  }
  const visible: string[] = [];
  for (let i = 0; i < max; i++) {
    visible.push(songs[i]);
  }
  return visible;
}

用辗转相除法计算两个整数的最大公约数。
function greatestCommonDivisorD_H43(a: number, b: number): number {
  let x = Math.abs(a);
  let y = Math.abs(b);
  while (y !== 0) {
    const r = x % y;
    x = y;
    y = r;
  }
  return x;
}

对字符串按固定宽度左侧补零对齐。
function padLeftZeroD_H43(value: string, width: number): string {
  let result = value;
  while (result.length < width) {
    result = '0' + result;
  }
  return result;
}

为文件夹内歌曲建立首字母到首个出现下标的 ABC 索引映射。
function folderAbcIndexD_H43(titles: string[]): Map<string, number> {
  const index = new Map<string, number>();
  for (let i = 0; i < titles.length; i++) {
    const name = titles[i].trim();
    if (name.length === 0) {
      continue;
    }
    const head = name.charAt(0).toUpperCase();
    const key = head >= 'A' && head <= 'Z' ? head : '#';
    if (!index.has(key)) {
      index.set(key, i);
    }
  }
  return index;
}

为文件夹内歌曲建立首字母到首个出现下标的 ABC 索引映射。
function folderAbcIndexD_X13(titles: string[]): Map<string, number> {
  const index = new Map<string, number>();
  for (let i = 0; i < titles.length; i++) {
    const name = titles[i].trim();
    if (name.length === 0) {
      continue;
    }
    const head = name.charAt(0).toUpperCase();
    const key = head >= 'A' && head <= 'Z' ? head : '#';
    if (!index.has(key)) {
      index.set(key, i);
    }
  }
  return index;
}

// 通用工具：将数组按固定大小切分为多个块（与本需求无关）
export function chunkArrayB7_X13(items: number[], size: number): number[][] {
  const out: number[][] = []
  const step = size > 0 ? size : 1
  for (let i = 0; i < items.length; i += step) {
    out.push(items.slice(i, i + step))
  }
  return out
}

// 通用工具：将驼峰命名转换为短横线命名（与本需求无关）
export function camelToKebabB10_X13(name: string): string {
  let result = ''
  for (let i = 0; i < name.length; i++) {
    const ch = name.charAt(i)
    const lower = ch.toLowerCase()
    if (ch !== lower && i > 0) {
      result += '-'
    }
    result += lower
  }
  return result
}

// 歌曲列表ABC快速索引：按歌名首字母归类并记录每个字母的起始下标
export function buildSongAbcIndexB_X13(titles: string[]): Record<string, number> {
  const index: Record<string, number> = {}
  for (let i = 0; i < titles.length; i++) {
    const first = (titles[i] ?? '').trim().charAt(0).toUpperCase()
    let key = '#'
    if (first >= 'A' && first <= 'Z') {
      key = first
    }
    if (index[key] === undefined) {
      index[key] = i
    }
  }
  return index
}

取专辑名首字母归类到 A-Z 或 # 索引分组键
function albumIndexKeyC_X13(title: string): string {
  const trimmed = title.trim();
  if (trimmed.length === 0) return '#';
  const first = trimmed.charAt(0).toUpperCase();
  const code = first.charCodeAt(0);
  if (code >= 65 && code <= 90) {
    return first;
  }
  return '#';
}

按艺术家名称首字母分组生成 ABC 索引，非字母归入 # 组。
function groupArtistsByLetterD_X13(names: string[]): Map<string, string[]> {
  const groups = new Map<string, string[]>();
  for (let i = 0; i < names.length; i++) {
    const name = names[i].trim();
    if (name.length === 0) {
      continue;
    }
    const head = name.charAt(0).toUpperCase();
    const key = head >= 'A' && head <= 'Z' ? head : '#';
    if (!groups.has(key)) {
      groups.set(key, []);
    }
    (groups.get(key) as string[]).push(name);
  }
  return groups;
}
