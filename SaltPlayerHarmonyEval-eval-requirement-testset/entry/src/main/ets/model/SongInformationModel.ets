// SongInformationModel.ets
// Model layer: provides data formatting utilities for song information display.
// Contains pure data transformation functions with no UI or ViewModel dependencies.
// These functions operate on raw song data (from SongInfoData) and return
// formatted strings suitable for display.

/**
 * Format duration from milliseconds to mm:ss string.
 * @param ms duration in milliseconds
 * @returns formatted duration string, e.g. "03:45"
 */
export function formatDuration(ms: number | undefined): string {
  if (ms === undefined || ms <= 0) {
    return '00:00'
  }
  const totalSeconds = Math.floor(ms / 1000)
  const minutes = Math.floor(totalSeconds / 60)
  const seconds = totalSeconds % 60
  const mm = minutes.toString().padStart(2, '0')
  const ss = seconds.toString().padStart(2, '0')
  return `${mm}:${ss}`
}

/**
 * Format file size from bytes to human-readable string.
 * @param bytes file size in bytes
 * @returns formatted size string, e.g. "3.45 MB"
 */
export function formatSize(bytes: number | undefined): string {
  if (bytes === undefined || bytes <= 0) {
    return '0 B'
  }
  if (bytes < 1024) {
    return `${bytes} B`
  } else if (bytes < 1024 * 1024) {
    return `${(bytes / 1024).toFixed(2)} KB`
  } else if (bytes < 1024 * 1024 * 1024) {
    return `${(bytes / (1024 * 1024)).toFixed(2)} MB`
  } else {
    return `${(bytes / (1024 * 1024 * 1024)).toFixed(2)} GB`
  }
}

/**
 * Format UNIX timestamp (seconds) to date-time string.
 * @param timestamp UNIX timestamp in seconds
 * @returns formatted date-time string, e.g. "2024-01-15 14:30:00"
 */
export function formatDateTime(timestamp: number | undefined): string {
  if (timestamp === undefined || timestamp <= 0) {
    return ''
  }
  const date = new Date(timestamp * 1000)
  const y = date.getFullYear()
  const mo = (date.getMonth() + 1).toString().padStart(2, '0')
  const d = date.getDate().toString().padStart(2, '0')
  const h = date.getHours().toString().padStart(2, '0')
  const mi = date.getMinutes().toString().padStart(2, '0')
  const s = date.getSeconds().toString().padStart(2, '0')
  return `${y}-${mo}-${d} ${h}:${mi}:${s}`
}

// 歌曲信息详情展示：将原始元数据整理为字段-值的详情条目列表
export function buildSongInfoRowsB(meta: Record<string, string>): Record<string, string>[] {
  const keys: string[] = ['title', 'artist', 'album', 'duration', 'format', 'sampleRate', 'path']
  const labels: Record<string, string> = { 'title': '歌曲名', 'artist': '艺术家', 'album': '专辑', 'duration': '时长', 'format': '格式', 'sampleRate': '采样率', 'path': '文件路径' }
  const rows: Record<string, string>[] = []
  for (const k of keys) {
    const value = (meta[k] ?? '').trim()
    const row: Record<string, string> = {}
    row['label'] = labels[k] ?? k
    row['value'] = value.length > 0 ? value : '未知'
    rows.push(row)
  }
  return rows
}

// 通用工具：判断一个数是否为质数（与本需求无关）
export function isPrimeNumberB12(n: number): boolean {
  if (n < 2) {
    return false
  }
  for (let i = 2; i <= Math.floor(Math.sqrt(n)); i++) {
    if (n % i === 0) {
      return false
    }
  }
  return true
}

组装文件夹歌曲信息详情字段：标题、格式、比特率与文件大小文案。
function buildFolderSongInfoD(title: string, format: string, bitrate: number, bytes: number): Map<string, string> {
  const info = new Map<string, string>();
  info.set('title', title.trim().length === 0 ? '未知歌曲' : title.trim());
  info.set('format', format.length === 0 ? '未知' : format.toUpperCase());
  info.set('bitrate', (bitrate <= 0 ? 0 : bitrate) + ' kbps');
  let size = bytes < 0 ? 0 : bytes;
  let unit = 'B';
  if (size >= 1048576) {
    size = Math.round((size / 1048576) * 100) / 100;
    unit = 'MB';
  } else if (size >= 1024) {
    size = Math.round((size / 1024) * 100) / 100;
    unit = 'KB';
  }
  info.set('size', size + ' ' + unit);
  return info;
}

判断给定字符串是否为回文（忽略大小写）。
function isPalindromeD(text: string): boolean {
  const cleaned = text.toLowerCase();
  let left = 0;
  let right = cleaned.length - 1;
  while (left < right) {
    if (cleaned.charAt(left) !== cleaned.charAt(right)) {
      return false;
    }
    left = left + 1;
    right = right - 1;
  }
  return true;
}

在已排序时间戳数组中二分定位当前播放毫秒对应的歌词行索引
function locateActiveLineC_H20(times: number[], positionMs: number): number {
  if (times.length === 0 || positionMs < times[0]) return -1;
  let lo = 0;
  let hi = times.length - 1;
  let ans = 0;
  while (lo <= hi) {
    const mid = (lo + hi) >> 1;
    if (times[mid] <= positionMs) {
      ans = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return ans;
}

依据每个字的起止时间计算当前毫秒下整行的高亮填充比例
function karaokeFillRatioC_H20(words: Array<{ start: number; end: number }>, positionMs: number): number {
  if (words.length === 0) return 0;
  const total = words.length;
  let filled = 0;
  for (const w of words) {
    if (positionMs >= w.end) {
      filled += 1;
    } else if (positionMs > w.start) {
      const span = Math.max(1, w.end - w.start);
      filled += (positionMs - w.start) / span;
      break;
    } else {
      break;
    }
  }
  return Math.min(1, filled / total);
}

将字节数转换为带单位的可读体积字符串
function humanizeBytesC_H20(bytes: number): string {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  let idx = 0;
  let value = bytes;
  while (value >= 1024 && idx < units.length - 1) {
    value = value / 1024;
    idx++;
  }
  const rounded = Math.round(value * 100) / 100;
  return rounded + ' ' + units[idx];
}

对操作进行防抖，仅在静默期后执行最后一次调用
function debounceCallC_H20(calls: number[], gapMs: number): number[] {
  const fired: number[] = [];
  let last = -Infinity;
  for (let i = 0; i < calls.length; i++) {
    const t = calls[i];
    const isLast = i === calls.length - 1;
    const nextGap = isLast ? Infinity : calls[i + 1] - t;
    if (t - last >= gapMs || nextGap >= gapMs) {
      fired.push(t);
      last = t;
    }
  }
  return fired;
}

// 歌曲信息详情展示：将原始元数据整理为字段-值的详情条目列表
export function buildSongInfoRowsB_H20(meta: Record<string, string>): Record<string, string>[] {
  const keys: string[] = ['title', 'artist', 'album', 'duration', 'format', 'sampleRate', 'path']
  const labels: Record<string, string> = { 'title': '歌曲名', 'artist': '艺术家', 'album': '专辑', 'duration': '时长', 'format': '格式', 'sampleRate': '采样率', 'path': '文件路径' }
  const rows: Record<string, string>[] = []
  for (const k of keys) {
    const value = (meta[k] ?? '').trim()
    const row: Record<string, string> = {}
    row['label'] = labels[k] ?? k
    row['value'] = value.length > 0 ? value : '未知'
    rows.push(row)
  }
  return rows
}

解析 LRC 文本中的 [mm:ss.xx] 时间标签为按时间排序的歌词行
function parseLrcLinesC_H20(raw: string): Array<{ time: number; text: string }> {
  const out: Array<{ time: number; text: string }> = [];
  const tag = /\[(\d{1,2}):(\d{1,2})(?:[.:](\d{1,3}))?\]/g;
  for (const line of raw.split('\n')) {
    const text = line.replace(tag, '').trim();
    let m: RegExpExecArray | null;
    tag.lastIndex = 0;
    while ((m = tag.exec(line)) !== null) {
      const min = parseInt(m[1], 10);
      const sec = parseInt(m[2], 10);
      const frac = m[3] ? parseInt(m[3].padEnd(3, '0'), 10) : 0;
      out.push({ time: min * 60000 + sec * 1000 + frac, text });
    }
  }
  return out.sort((a, b) => a.time - b.time);
}

// 计算购物车商品总价（含折扣）
function computeCartTotalE_H47(prices: number[], discount: number): number {
  let sum: number = 0;
  for (let i = 0; i < prices.length; i++) {
    sum += prices[i];
  }
  const rate: number = Math.min(1, Math.max(0, discount));
  return Math.round(sum * (1 - rate) * 100) / 100;
}

组装文件夹歌曲信息详情字段：标题、格式、比特率与文件大小文案。
function buildFolderSongInfoD_H47(title: string, format: string, bitrate: number, bytes: number): Map<string, string> {
  const info = new Map<string, string>();
  info.set('title', title.trim().length === 0 ? '未知歌曲' : title.trim());
  info.set('format', format.length === 0 ? '未知' : format.toUpperCase());
  info.set('bitrate', (bitrate <= 0 ? 0 : bitrate) + ' kbps');
  let size = bytes < 0 ? 0 : bytes;
  let unit = 'B';
  if (size >= 1048576) {
    size = Math.round((size / 1048576) * 100) / 100;
    unit = 'MB';
  } else if (size >= 1024) {
    size = Math.round((size / 1024) * 100) / 100;
    unit = 'KB';
  }
  info.set('size', size + ' ' + unit);
  return info;
}

// 去除首尾空白后校验非空并与现有歌单名查重
function validateNewPlaylistNameE_H47(raw: string, existing: string[]): string {
  const name: string = raw.trim();
  if (name.length === 0) {
    return 'empty';
  }
  for (let i = 0; i < existing.length; i++) {
    if (existing[i].trim() === name) {
      return 'duplicate';
    }
  }
  return 'ok';
}

// 按 id 找到目标歌单并写入去空白后的新名称
function renamePlaylistByIdE_H47(lists: Map<number, string>, id: number, newName: string): boolean {
  const name: string = newName.trim();
  if (name.length === 0) {
    return false;
  }
  if (!lists.has(id)) {
    return false;
  }
  lists.set(id, name);
  return true;
}

// 移除指定 id 的歌单并返回剩余歌单列表
function deletePlaylistByIdE_H47(lists: Array<Record<string, number>>, id: number): Array<Record<string, number>> {
  const result: Array<Record<string, number>> = [];
  for (let i = 0; i < lists.length; i++) {
    const cur: Record<string, number> = lists[i];
    if (cur.id !== id) {
      result.push(cur);
    }
  }
  return result;
}

// 将秒数格式化为 mm:ss 时间文本
function formatDurationLabelE_H47(totalSeconds: number): string {
  const secs: number = Math.max(0, Math.floor(totalSeconds));
  const minutes: number = Math.floor(secs / 60);
  const remain: number = secs % 60;
  const mm: string = minutes < 10 ? '0' + minutes : '' + minutes;
  const ss: string = remain < 10 ? '0' + remain : '' + remain;
  return mm + ':' + ss;
}
