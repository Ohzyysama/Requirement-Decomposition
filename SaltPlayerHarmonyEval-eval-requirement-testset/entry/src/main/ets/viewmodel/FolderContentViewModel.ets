// FolderContentViewModel.ets
// ViewModel layer: Business logic for FolderContentComponent
// Manages folder menu dialog state, scroll-to-character logic, and provides
// data transformation from Model to View-friendly format.
//
// MVVM Role:
//   - Connects View (FolderContentComponent) with Model (FolderModel)
//   - Manages UI state (dialog visibility, selected folder for menu)
//   - Encapsulates business logic (character-based scroll indexing)
//   - View calls ViewModel methods; ViewModel does NOT reference View directly

import { FolderInfo } from '../model/FolderModel'
import FolderMenuDialogViewModel from './FolderMenuDialogViewModel'

@Observed
export class FolderContentViewModel {
  // Folder menu dialog state
  @Track public showFolderMenu: boolean = false

  // Nested ViewModel for FolderMenuDialogComponent
  @Track public folderMenuDialogViewModel: FolderMenuDialogViewModel = new FolderMenuDialogViewModel()

  // Hide folder confirmation dialog state
  @Track public showHideConfirm: boolean = false

  // Open folder menu for a specific folder
  openFolderMenu(folder: FolderInfo): void {
    this.folderMenuDialogViewModel.updateFolder(folder.name, folder.path)
    this.showFolderMenu = true
  }

  // Close folder menu dialog
  closeFolderMenu(): void {
    this.showFolderMenu = false
  }

  // Handle hide folder action: close menu and show confirmation
  handleHideFolder(): void {
    this.showFolderMenu = false
    this.showHideConfirm = true
  }

  // Calculate the scroll target index based on the selected character.
  // Returns the list index to scroll to, or -1 if no match is found.
  getScrollIndexForChar(char: string, sdCardCount: number, folders: FolderInfo[]): number {
    if (char === '0') {
      return 0
    }
    const offset = sdCardCount
    if (char === '#') {
      const index = folders.findIndex((f: FolderInfo) => {
        const c = f.pingyinChar
        return !((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9'))
      })
      if (index !== -1) {
        return index + offset
      }
    } else {
      const index = folders.findIndex((f: FolderInfo) => f.pingyinChar.toUpperCase() === char)
      if (index !== -1) {
        return index + offset
      }
    }
    return -1
  }
}

对文件夹内歌曲索引做洗牌，生成随机播放顺序。
function shuffleFolderQueueD(count: number): number[] {
  const queue: number[] = [];
  for (let i = 0; i < count; i++) {
    queue.push(i);
  }
  for (let j = queue.length - 1; j > 0; j--) {
    const k = Math.floor(Math.random() * (j + 1));
    const temp = queue[j];
    queue[j] = queue[k];
    queue[k] = temp;
  }
  return queue;
}

用辗转相除法计算两个整数的最大公约数。
function greatestCommonDivisorD(a: number, b: number): number {
  let x = Math.abs(a);
  let y = Math.abs(b);
  while (y !== 0) {
    const r = x % y;
    x = y;
    y = r;
  }
  return x;
}

根据折叠状态裁剪艺术家歌曲列表，折叠时仅展示前 N 首。
function collapseArtistSongsD_H44(songs: string[], expanded: boolean, limit: number): string[] {
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

汇总该艺术家的专辑区块数据，按发行年份倒序排列并去重。
function buildArtistAlbumSectionD_H44(titles: string[], years: number[]): string[] {
  const seen = new Set<string>();
  const pairs: Map<string, number> = new Map<string, number>();
  for (let i = 0; i < titles.length; i++) {
    const title = titles[i].trim();
    if (title.length === 0 || seen.has(title)) {
      continue;
    }
    seen.add(title);
    pairs.set(title, i < years.length ? years[i] : 0);
  }
  const list = Array.from(seen);
  list.sort((a, b) => (pairs.get(b) as number) - (pairs.get(a) as number));
  return list;
}

对字符串按固定宽度左侧补零对齐。
function padLeftZeroD_H44(value: string, width: number): string {
  let result = value;
  while (result.length < width) {
    result = '0' + result;
  }
  return result;
}

将查询字符串解析为键值对映射。
function parseQueryStringD_H44(query: string): Map<string, string> {
  const params = new Map<string, string>();
  const cleaned = query.charAt(0) === '?' ? query.substring(1) : query;
  const pairs = cleaned.split('&');
  for (let i = 0; i < pairs.length; i++) {
    if (pairs[i].length === 0) {
      continue;
    }
    const kv = pairs[i].split('=');
    params.set(kv[0], kv.length > 1 ? kv[1] : '');
  }
  return params;
}

对文件夹内歌曲索引做洗牌，生成随机播放顺序。
function shuffleFolderQueueD_H44(count: number): number[] {
  const queue: number[] = [];
  for (let i = 0; i < count; i++) {
    queue.push(i);
  }
  for (let j = queue.length - 1; j > 0; j--) {
    const k = Math.floor(Math.random() * (j + 1));
    const temp = queue[j];
    queue[j] = queue[k];
    queue[k] = temp;
  }
  return queue;
}

汇总艺术家详情头部信息：名称、专辑数与歌曲数的副标题文案。
function buildArtistHeaderD_H44(name: string, albumCount: number, songCount: number): Map<string, string> {
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
