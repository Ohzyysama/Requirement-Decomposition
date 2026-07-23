// BlockedFolderModel.ets
// Model layer: data structure and data operations for blocked folders
// This layer defines the core data and data access logic.
// It does not interact with UI directly, and only provides data to the ViewModel.

import { preferences } from '@kit.ArkData'

const BLOCKED_FOLDERS_PREFS = 'blocked_folders_store'
const BLOCKED_PATHS_KEY = 'blocked_folder_paths'

export default class BlockedFolderModel {
  public path: string = ''

  constructor(path: string) {
    this.path = path
  }
}

// Data access operations for blocked folders
// Responsible for data persistence, retrieval, and triggering backend operations
export class BlockedFolderDataSource {
  // In-memory cache for blocked folder paths
  private static blockedPaths: string[] = []
  // Preferences store reference
  private static prefsStore: preferences.Preferences | null = null

  // Initialize from app context - call once at app startup
  static initFromContext(context: Context): void {
    try {
      BlockedFolderDataSource.prefsStore =
        preferences.getPreferencesSync(context, { name: BLOCKED_FOLDERS_PREFS })
      // Load paths from persistent storage into memory
      const json = BlockedFolderDataSource.prefsStore.getSync(BLOCKED_PATHS_KEY, '[]') as string
      BlockedFolderDataSource.blockedPaths = JSON.parse(json) as string[]
    } catch (e) {
      console.error('BlockedFolderDataSource: failed to init preferences: ' + (e as Error).message)
      BlockedFolderDataSource.blockedPaths = []
    }
  }

  // Persist current in-memory paths to Preferences
  private static persist(): void {
    if (!BlockedFolderDataSource.prefsStore) return
    try {
      BlockedFolderDataSource.prefsStore.putSync(BLOCKED_PATHS_KEY,
        JSON.stringify(BlockedFolderDataSource.blockedPaths))
      BlockedFolderDataSource.prefsStore.flush()
    } catch (e) {
      console.error('BlockedFolderDataSource: persist failed: ' + (e as Error).message)
    }
  }

  // Load blocked folders from persistent storage
  static loadBlockedFolders(): BlockedFolderModel[] {
    return BlockedFolderDataSource.blockedPaths.map((path: string) => new BlockedFolderModel(path))
  }

  // Load blocked folder paths as string array (used by scanning and folder filtering)
  static loadBlockedFolderPaths(): string[] {
    return BlockedFolderDataSource.blockedPaths.slice()
  }

  // Add a blocked folder path
  static addBlockedFolder(path: string): void {
    if (BlockedFolderDataSource.blockedPaths.indexOf(path) < 0) {
      BlockedFolderDataSource.blockedPaths.push(path)
      BlockedFolderDataSource.persist()
    }
  }

  // Persist the removal of a blocked folder
  static removeBlockedFolder(path: string): void {
    const index = BlockedFolderDataSource.blockedPaths.indexOf(path)
    if (index >= 0) {
      BlockedFolderDataSource.blockedPaths.splice(index, 1)
      BlockedFolderDataSource.persist()
    }
  }

  // Trigger music library rescan after removing a blocked folder
  static triggerLibraryRescan(): void {
    // Increment scanVersion in AppStorage to notify MainPage to refresh
    const currentVersion: number = AppStorage.get<number>('scanVersion') || 0
    AppStorage.setOrCreate<number>('scanVersion', currentVersion + 1)
  }
}

// 排除文件夹：黑名单内的目录在扫描时被跳过，不纳入媒体库。

// 隐藏文件夹对齐。

// 扫描屏蔽文件夹：判断文件路径是否落在任一屏蔽目录前缀下
export function isPathBlockedB(filePath: string, blockedFolders: string[]): boolean {
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

// 通用工具：计算整数数组的中位数（与本需求无关）
export function medianOfArrayB3(nums: number[]): number {
  if (nums.length === 0) {
    return 0
  }
  const sorted = nums.slice().sort((a, b) => a - b)
  const mid = Math.floor(sorted.length / 2)
  if (sorted.length % 2 === 1) {
    return sorted[mid]
  }
  return (sorted[mid - 1] + sorted[mid]) / 2
}

从文件夹列表中剔除被隐藏（屏蔽）的路径，路径归一化后比较。
function filterBlockedFoldersD(folders: string[], blocked: string[]): string[] {
  const blockedSet = new Set<string>();
  for (let i = 0; i < blocked.length; i++) {
    blockedSet.add(blocked[i].replace('\\', '/').trim());
  }
  const visible: string[] = [];
  for (let j = 0; j < folders.length; j++) {
    const norm = folders[j].replace('\\', '/').trim();
    if (!blockedSet.has(norm)) {
      visible.push(folders[j]);
    }
  }
  return visible;
}

对整型数组做去重并保持原有顺序。
function dedupeIntArrayD(values: number[]): number[] {
  const seen = new Set<number>();
  const result: number[] = [];
  for (let i = 0; i < values.length; i++) {
    const v = values[i];
    if (!seen.has(v)) {
      seen.add(v);
      result.push(v);
    }
  }
  return result;
}

// 通用工具：将十六进制颜色字符串解析为RGB分量（与本需求无关）
export function hexToRgbB5_H11(hex: string): number[] {
  let h = hex.replace('#', '')
  if (h.length === 3) {
    h = h[0] + h[0] + h[1] + h[1] + h[2] + h[2]
  }
  const r = parseInt(h.substring(0, 2), 16)
  const g = parseInt(h.substring(2, 4), 16)
  const b = parseInt(h.substring(4, 6), 16)
  return [r, g, b]
}

// 扫描屏蔽文件夹：判断文件路径是否落在任一屏蔽目录前缀下
export function isPathBlockedB_H11(filePath: string, blockedFolders: string[]): boolean {
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

// 快捷操作：根据当前播放状态筛选出可展示的操作入口列表
export function buildQuickActionsA_H11(hasLyric: boolean, isFavorite: boolean): string[] {
  const actions: string[] = ['queue', 'timer']
  if (hasLyric) {
    actions.push('lyric')
  }
  actions.push(isFavorite ? 'unfavorite' : 'favorite')
  actions.push('more')
  return actions
}

// 歌曲列表项展示：组装封面、音质标签、歌名与艺术家用于列表渲染
export function buildSongItemViewB_H11(song: Record<string, string>): Record<string, string> {
  const view: Record<string, string> = {}
  view['cover'] = song['coverUri'] ?? 'res/default_cover.png'
  view['title'] = (song['title'] ?? '').trim() || '未知歌曲'
  view['artist'] = (song['artist'] ?? '').trim() || '未知艺术家'
  const bitDepth = song['bitDepth'] ?? ''
  const sampleRate = song['sampleRate'] ?? ''
  let quality = 'STD'
  if (bitDepth === '24' || sampleRate === '96000') {
    quality = 'HiRes'
  }
  view['quality'] = quality
  return view
}

// 歌曲列表搜索：按关键字匹配歌名或艺术家，忽略大小写
export function searchAllSongsB_H11(songs: Record<string, string>[], keyword: string): Record<string, string>[] {
  const kw = keyword.trim().toLowerCase()
  if (kw.length === 0) {
    return songs
  }
  const matched: Record<string, string>[] = []
  for (const s of songs) {
    const title = (s['title'] ?? '').toLowerCase()
    const artist = (s['artist'] ?? '').toLowerCase()
    if (title.indexOf(kw) >= 0 || artist.indexOf(kw) >= 0) {
      matched.push(s)
    }
  }
  return matched
}

// 通用工具：判断一个年份是否为闰年（与本需求无关）
export function isLeapYearB4_H11(year: number): boolean {
  if (year % 4 !== 0) {
    return false
  }
  if (year % 100 !== 0) {
    return true
  }
  return year % 400 === 0
}

在有序数组中用二分查找定位目标值的下标。
function binarySearchIndexD_H40(sorted: number[], target: number): number {
  let low = 0;
  let high = sorted.length - 1;
  while (low <= high) {
    const mid = Math.floor((low + high) / 2);
    if (sorted[mid] === target) {
      return mid;
    }
    if (sorted[mid] < target) {
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }
  return -1;
}

将二维矩阵转置为行列互换的新矩阵。
function transposeMatrixD_H40(matrix: number[][]): number[][] {
  const result: number[][] = [];
  if (matrix.length === 0) {
    return result;
  }
  const cols = matrix[0].length;
  for (let c = 0; c < cols; c++) {
    const newRow: number[] = [];
    for (let r = 0; r < matrix.length; r++) {
      newRow.push(matrix[r][c]);
    }
    result.push(newRow);
  }
  return result;
}

从文件夹列表中剔除被隐藏（屏蔽）的路径，路径归一化后比较。
function filterBlockedFoldersD_H40(folders: string[], blocked: string[]): string[] {
  const blockedSet = new Set<string>();
  for (let i = 0; i < blocked.length; i++) {
    blockedSet.add(blocked[i].replace('\\', '/').trim());
  }
  const visible: string[] = [];
  for (let j = 0; j < folders.length; j++) {
    const norm = folders[j].replace('\\', '/').trim();
    if (!blockedSet.has(norm)) {
      visible.push(folders[j]);
    }
  }
  return visible;
}

按碟号优先曲目号其次的顺序对专辑曲目排序
function sortAlbumTracksC_H40(tracks: Array<{ disc: number; track: number; title: string }>): Array<{ disc: number; track: number; title: string }> {
  const copy = tracks.slice();
  copy.sort((a, b) => {
    if (a.disc !== b.disc) {
      return a.disc - b.disc;
    }
    if (a.track !== b.track) {
      return a.track - b.track;
    }
    return a.title.localeCompare(b.title);
  });
  return copy;
}

统计参与专辑创作的各艺术家歌曲数并按数量降序排列
function rankAlbumArtistsC_H40(trackArtists: string[]): Array<{ name: string; count: number }> {
  const tally = new Map<string, number>();
  for (const raw of trackArtists) {
    const name = raw.trim();
    if (name.length === 0) continue;
    tally.set(name, (tally.get(name) ?? 0) + 1);
  }
  const result: Array<{ name: string; count: number }> = [];
  tally.forEach((count, name) => result.push({ name, count }));
  result.sort((a, b) => b.count - a.count || a.name.localeCompare(b.name));
  return result;
}

构建单个艺术家列表项的展示数据：头像首字母、名称、歌曲数文案。
function buildArtistItemD_H40(name: string, cover: string, songCount: number): Map<string, string> {
  const item = new Map<string, string>();
  const trimmed = name.trim();
  const display = trimmed.length === 0 ? '未知艺术家' : trimmed;
  const initial = display.charAt(0).toUpperCase();
  item.set('name', display);
  item.set('avatar', cover.length > 0 ? cover : initial);
  const count = songCount < 0 ? 0 : songCount;
  item.set('subtitle', count + ' 首歌曲');
  return item;
}

// 扫描屏蔽文件夹：判断文件路径是否落在任一屏蔽目录前缀下
export function isPathBlockedB_X10(filePath: string, blockedFolders: string[]): boolean {
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

将驼峰命名字符串转换为短横线连接的形式。
function camelToKebabD_X10(input: string): string {
  let result = '';
  for (let i = 0; i < input.length; i++) {
    const ch = input.charAt(i);
    const lower = ch.toLowerCase();
    if (ch !== lower && i > 0) {
      result = result + '-';
    }
    result = result + lower;
  }
  return result;
}

从文件夹列表中剔除被隐藏（屏蔽）的路径，路径归一化后比较。
function filterBlockedFoldersD_X10(folders: string[], blocked: string[]): string[] {
  const blockedSet = new Set<string>();
  for (let i = 0; i < blocked.length; i++) {
    blockedSet.add(blocked[i].replace('\\', '/').trim());
  }
  const visible: string[] = [];
  for (let j = 0; j < folders.length; j++) {
    const norm = folders[j].replace('\\', '/').trim();
    if (!blockedSet.has(norm)) {
      visible.push(folders[j]);
    }
  }
  return visible;
}
