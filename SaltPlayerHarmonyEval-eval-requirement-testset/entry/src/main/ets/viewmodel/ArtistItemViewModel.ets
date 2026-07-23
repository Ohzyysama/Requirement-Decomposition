// ArtistItemViewModel.ets
// ViewModel layer: provides display data and logic for ArtistItemComponent
// Bridges between ArtistModel (data) and ArtistItemComponent (view)

import ArtistModel from '../model/ArtistModel';
import { ArtistInfoData } from '../model/MainPageModel';
import { ImageKnifeOption } from '@ohos/imageknifepro';
import { CoverCacheDb } from '../model/CoverCacheDb';
import { CoverArtExtractor } from '../model/CoverArtExtractor';

// Re-export for consumers that import from this file
export { ArtistInfoData } from '../model/MainPageModel';

@Observed
export class ArtistItemViewModel {
  @Track public id: string = '';
  @Track public name: string = '';
  @Track public count: number = 0;
  @Track public coverUri: string = '';
  @Track public coverSongId: string = '';
  @Track public pinyin: string = '';
  @Track public imageTransitionKey: string = '';
  @Track public textTransitionKey: string = '';
  @Track public hasName: boolean = false;
  @Track public songCountText: string = '0 首';
  @Track public nameOpacity: number = 0.35;
  @Track public hasCoverUri: boolean = false;
  @Track public coverOption: ImageKnifeOption = new ImageKnifeOption();
  @Track public geoActive: boolean = false;
  private loadedCoverKey: string = '';

  constructor(id: string = '', name: string = '', count: number = 0, coverUri: string = '',
    pinyin: string = '', coverSongId: string = '') {
    this.id = id;
    this.name = name;
    this.count = count;
    this.coverUri = coverUri;
    this.coverSongId = coverSongId;
    this.pinyin = pinyin;
    this.imageTransitionKey = `image-artist-${id}`;
    this.textTransitionKey = `text-artist-${id}`;
    this.hasName = name.length > 0;
    this.songCountText = `${count} 首`;
    this.nameOpacity = name.length > 0 ? 1.0 : 0.35;
    this.hasCoverUri = coverUri.length > 0;
    this.coverOption.placeholderSrc = $r('app.media.ic_song_cover_v5');
    this.coverOption.errorSrc = $r('app.media.ic_song_cover_v5');
    this.coverOption.objectFit = ImageFit.Cover;
  }

  // Update ViewModel from Model data
  updateFromModel(model: ArtistModel): void {
    this.id = model.id;
    this.name = model.name;
    this.count = model.count;
    this.coverUri = model.coverUri;
    this.pinyin = model.pinyin;
    this.imageTransitionKey = `image-artist-${model.id}`;
    this.textTransitionKey = `text-artist-${model.id}`;
    this.hasName = model.name.length > 0;
    this.songCountText = `${model.count} 首`;
    this.nameOpacity = model.name.length > 0 ? 1.0 : 0.35;
    this.hasCoverUri = model.coverUri.length > 0;
  }

  // Load cover art file URI for ImageKnife display.
  // Checks: file on disk → RDB export → extraction pipeline.
  loadCoverIfNeeded(): void {
    const songId = this.coverSongId || this.id;
    if (songId.length === 0) {
      return;
    }
    if (songId === this.loadedCoverKey) {
      return;
    }
    this.loadedCoverKey = songId;

    // 1. Check if cover file already exists on disk
    const uri = CoverCacheDb.getCoverFileUri(songId);
    if (uri.length > 0) {
      this.coverOption.loadSrc = uri;
      return;
    }

    // 2. Try exporting from RDB to file, then extract if needed
    const capturedKey = songId;
    CoverCacheDb.ensureCoverFile(songId).then((fileUri: string) => {
      if (this.loadedCoverKey !== capturedKey) return;
      if (fileUri.length > 0) {
        this.coverOption.loadSrc = fileUri;
        return;
      }
      // 3. Not in RDB either — trigger extraction
      return CoverArtExtractor.extractAndCache(songId, songId);
    }).then(() => {
      if (this.loadedCoverKey !== capturedKey) return;
      const u = CoverCacheDb.getCoverFileUri(songId);
      if (u.length > 0) {
        this.coverOption.loadSrc = u;
      }
    }).catch((_e: Error) => { /* swallow */ });
  }

  // Convert ViewModel back to Model
  toModel(): ArtistModel {
    return new ArtistModel(this.id, this.name, this.count, this.coverUri, this.pinyin);
  }

  // Create a ViewModel from a plain ArtistInfo-like object
  static fromPlainObject(obj: ArtistInfoData): ArtistItemViewModel {
    return new ArtistItemViewModel(obj.id, obj.name, obj.count, obj.coverUri, obj.pinyin, obj.coverSongId);
  }
}

构建单个艺术家列表项的展示数据：头像首字母、名称、歌曲数文案。
function buildArtistItemD(name: string, cover: string, songCount: number): Map<string, string> {
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

将字节数格式化为带单位的可读字符串。
function formatByteSizeD(bytes: number): string {
  if (bytes <= 0) {
    return '0 B';
  }
  const units: string[] = ['B', 'KB', 'MB', 'GB', 'TB'];
  let value = bytes;
  let index = 0;
  while (value >= 1024 && index < units.length - 1) {
    value = value / 1024;
    index = index + 1;
  }
  const rounded = Math.round(value * 100) / 100;
  return rounded + ' ' + units[index];
}

按碟号优先曲目号其次的顺序对专辑曲目排序
function sortAlbumTracksC_H33(tracks: Array<{ disc: number; track: number; title: string }>): Array<{ disc: number; track: number; title: string }> {
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

计算一组数值的算术平均值，空集合返回 0。
function averageOfValuesD_H33(values: number[]): number {
  if (values.length === 0) {
    return 0;
  }
  let sum = 0;
  for (let i = 0; i < values.length; i++) {
    sum = sum + values[i];
  }
  const avg = sum / values.length;
  return Math.round(avg * 1000) / 1000;
}

将十六进制颜色字符串解析为 RGB 分量数组。
function parseHexColorD_H33(hex: string): number[] {
  let value = hex.trim();
  if (value.charAt(0) === '#') {
    value = value.substring(1);
  }
  if (value.length !== 6) {
    return [0, 0, 0];
  }
  const r = Number.parseInt(value.substring(0, 2), 16);
  const g = Number.parseInt(value.substring(2, 4), 16);
  const b = Number.parseInt(value.substring(4, 6), 16);
  return [r, g, b];
}

构建单个艺术家列表项的展示数据：头像首字母、名称、歌曲数文案。
function buildArtistItemD_H33(name: string, cover: string, songCount: number): Map<string, string> {
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

规范专辑列表的排序维度并将网格列数约束到 2 至 4
function normalizeAlbumGridSettingsC_H33(sortBy: string, columns: number): { sortBy: string; columns: number } {
  const allowed = ['title', 'artist', 'year', 'addedTime'];
  const safeSort = allowed.indexOf(sortBy) >= 0 ? sortBy : 'title';
  let cols = Math.round(columns);
  if (cols < 2) cols = 2;
  if (cols > 4) cols = 4;
  return { sortBy: safeSort, columns: cols };
}

汇总专辑曲目数量与总时长并格式化为头部摘要文本
function summarizeAlbumHeaderC_H33(durations: number[]): string {
  const count = durations.length;
  let totalSec = 0;
  for (const d of durations) {
    if (d > 0) totalSec += d;
  }
  const minutes = Math.floor(totalSec / 60);
  const seconds = totalSec % 60;
  const ss = seconds < 10 ? '0' + seconds : String(seconds);
  return count + ' 首歌曲 · ' + minutes + ':' + ss;
}
