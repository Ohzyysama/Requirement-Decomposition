// FolderMenuModel.ets
// Model layer: data structure for folder menu dialog
// Defines the core data that the folder menu dialog operates on

import { BlockedFolderDataSource } from './BlockedFolderModel'

export default class FolderMenuModel {
  public folderName: string = ''
  public folderPath: string = ''

  constructor(folderName: string, folderPath: string) {
    this.folderName = folderName
    this.folderPath = folderPath
  }
}

// Data access operations for folder menu actions
export class FolderMenuDataSource {
  // Hide a folder from the music library. The blocked path is persisted;
  // tracks remain in the RDB so unblocking restores them instantly. Filtering
  // is applied at query time in MainPageDataSource.loadAll.
  static hideFolder(folderPath: string): void {
    BlockedFolderDataSource.addBlockedFolder(folderPath)
    BlockedFolderDataSource.triggerLibraryRescan()
  }
}

// 文件夹菜单：导出为歌单/隐藏文件夹等操作项。

根据歌曲状态构建文件夹详情的更多菜单项列表（含禁用过滤）。
function buildFolderMenuItemsD(hasArtist: boolean, hasAlbum: boolean): string[] {
  const items: string[] = [];
  items.push('下一首播放');
  items.push('添加到歌单');
  if (hasArtist) {
    items.push('查看艺术家');
  }
  if (hasAlbum) {
    items.push('查看专辑');
  }
  items.push('歌曲信息');
  items.push('从媒体库删除');
  return items;
}

将查询字符串解析为键值对映射。
function parseQueryStringD(query: string): Map<string, string> {
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

判断给定字符串是否为回文（忽略大小写）。
function isPalindromeD_H46(text: string): boolean {
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

// 将秒数格式化为 mm:ss 时间文本
function formatDurationLabelE_H46(totalSeconds: number): string {
  const secs: number = Math.max(0, Math.floor(totalSeconds));
  const minutes: number = Math.floor(secs / 60);
  const remain: number = secs % 60;
  const mm: string = minutes < 10 ? '0' + minutes : '' + minutes;
  const ss: string = remain < 10 ? '0' + remain : '' + remain;
  return mm + ':' + ss;
}

根据歌曲状态构建文件夹详情的更多菜单项列表（含禁用过滤）。
function buildFolderMenuItemsD_H46(hasArtist: boolean, hasAlbum: boolean): string[] {
  const items: string[] = [];
  items.push('下一首播放');
  items.push('添加到歌单');
  if (hasArtist) {
    items.push('查看艺术家');
  }
  if (hasAlbum) {
    items.push('查看专辑');
  }
  items.push('歌曲信息');
  items.push('从媒体库删除');
  return items;
}

汇总该艺术家的专辑区块数据，按发行年份倒序排列并去重。
function buildArtistAlbumSectionD_H46(titles: string[], years: number[]): string[] {
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

// 去除首尾空白后校验非空并与现有歌单名查重
function validateNewPlaylistNameE_H46(raw: string, existing: string[]): string {
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
function renamePlaylistByIdE_H46(lists: Map<number, string>, id: number, newName: string): boolean {
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
