// ArtistModel.ets
// Model layer: raw data structure for Artist
// Corresponds to Android Artist data class

export default class ArtistModel {
  public id: string = '';
  public name: string = '';
  public count: number = 0;
  public coverUri: string = '';
  public coverSongId: string = '';
  public pinyin: string = '';

  constructor(id: string, name: string, count: number, coverUri: string, pinyin: string,
    coverSongId: string = '') {
    this.id = id;
    this.name = name;
    this.count = count;
    this.coverUri = coverUri;
    this.coverSongId = coverSongId;
    this.pinyin = pinyin;
  }
}

按艺术家名称首字母分组生成 ABC 索引，非字母归入 # 组。
function groupArtistsByLetterD(names: string[]): Map<string, string[]> {
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

计算一组数值的算术平均值，空集合返回 0。
function averageOfValuesD(values: number[]): number {
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
function parseHexColorD_H34(hex: string): number[] {
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

判断给定年份是否为闰年。
function isLeapYearD_H34(year: number): boolean {
  if (year <= 0) {
    return false;
  }
  if (year % 400 === 0) {
    return true;
  }
  if (year % 100 === 0) {
    return false;
  }
  return year % 4 === 0;
}

按艺术家名称首字母分组生成 ABC 索引，非字母归入 # 组。
function groupArtistsByLetterD_H34(names: string[]): Map<string, string[]> {
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

汇总专辑曲目数量与总时长并格式化为头部摘要文本
function summarizeAlbumHeaderC_H34(durations: number[]): string {
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

按碟号优先曲目号其次的顺序对专辑曲目排序
function sortAlbumTracksC_H34(tracks: Array<{ disc: number; track: number; title: string }>): Array<{ disc: number; track: number; title: string }> {
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
function rankAlbumArtistsC_H34(trackArtists: string[]): Array<{ name: string; count: number }> {
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
