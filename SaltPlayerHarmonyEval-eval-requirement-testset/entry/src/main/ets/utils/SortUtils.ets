// SortUtils.ets
// Utility functions for sorting: natural sort, pinyin transliteration, and string comparison.

import { SongInfoData } from '../model/SongItemModel'
import { i18n } from '@kit.LocalizationKit'

export const collator: Intl.Collator = new Intl.Collator('zh-Hans-CN-u-co-pinyin')

let transliterator: i18n.Transliterator | null = null

export function getTransliterator(): i18n.Transliterator {
  if (!transliterator) {
    try {
      transliterator = i18n.Transliterator.getInstance('Han-Latin; Latin-ASCII')
    } catch (e) {
      transliterator = i18n.Transliterator.getInstance('Any-Latin')
    }
  }
  return transliterator
}

// Determine the pinyin initial letter for a string's first character.
// For ASCII letters returns uppercase directly; for Chinese characters
// uses i18n.Transliterator to convert to Latin and extract the initial.
//
// Memoized on the first character: the song-list / artist-list refresh path
// calls this once per song (rebuildSongAlphabetIndex on 2000+ songs) plus
// once per album / artist / folder (loadAll). Transliterator.transform is a
// native-boundary call; without this cache a 2000-song scan triggers ~2000+
// transliterations of overlapping first characters and the resulting UI
// stall is what users feel as scan-completion lag once the library grows.
const pinyinInitialCache: Map<string, string> = new Map<string, string>()

export function getPinyinInitial(text: string): string {
  if (text.length === 0) return '#'
  const firstChar = text.charAt(0)
  const upper = firstChar.toUpperCase()
  if (upper >= 'A' && upper <= 'Z') return upper
  if (upper >= '0' && upper <= '9') return '0'
  const cached = pinyinInitialCache.get(firstChar)
  if (cached !== undefined) return cached
  // For Chinese characters: transliterate to Latin and get the first letter
  let result = '#'
  const latin = getTransliterator().transform(firstChar)
  if (latin.length > 0) {
    const initial = latin.charAt(0).toUpperCase()
    if (initial >= 'A' && initial <= 'Z') result = initial
  }
  pinyinInitialCache.set(firstChar, result)
  return result
}

function normalizeForSort(text: string): string {
  if (text.length === 0) return ''
  // Transliterate to Latin (converts Chinese to pinyin, keeps ASCII).
  // Strip spaces so pinyin syllables concatenate
  const transliterated = getTransliterator().transform(text)
  return transliterated.toLowerCase().replace(/ /g, '')
}

// Look up or compute the pinyin sort key for a string.
// Uses the provided cache so each unique string is transliterated only once per sort pass.
export function getPinyin(text: string, cache: Map<string, string>): string {
  if (text.length === 0) return ''
  let cached = cache.get(text)
  if (cached !== undefined) return cached
  cached = normalizeForSort(text)
  cache.set(text, cached)
  return cached
}

// Compare two strings by their pinyin representations using natural sort.
// Matches Android: all text is first normalized to pinyin/ASCII, so Latin
// letters and Chinese characters interleave correctly (e.g. "Hello" mixes
// with "你好"→"nihao" by pinyin order).
export function compareStr(a: string, b: string, cache: Map<string, string>): number {
  if (a.length === 0 && b.length === 0) return 0
  if (a.length === 0) return 1
  if (b.length === 0) return -1
  const aNorm = getPinyin(a, cache)
  const bNorm = getPinyin(b, cache)
  return naturalSort(aNorm, bNorm)
}

// Compare non-digit characters with special handling for first character
function compareNotDigit(c1: number, c2: number): number {
  const isLetter1 = (c1 >= 65 && c1 <= 90) || (c1 >= 97 && c1 <= 122) // A-Z, a-z
  const isLetter2 = (c2 >= 65 && c2 <= 90) || (c2 >= 97 && c2 <= 122)

  if (isLetter1 && isLetter2) return c1 - c2
  if (isLetter1 && !isLetter2) return -1
  if (!isLetter1 && isLetter2) return 1
  return c1 - c2
}

// Natural sort implementation based on NaturalComparator from SPC
// Handles numeric sequences and mixed alphanumeric strings naturally
export function naturalSort(a: string, b: string): number {
  const length1 = a.length
  const length2 = b.length
  let index1 = 0
  let index2 = 0

  while (index1 < length1 && index2 < length2) {
    const c1 = a.charCodeAt(index1++)
    const c2 = b.charCodeAt(index2++)

    const isDigit1 = c1 >= 48 && c1 <= 57 // '0' to '9'
    const isDigit2 = c2 >= 48 && c2 <= 57

    if (isDigit1 && !isDigit2) return -1
    if (!isDigit1 && isDigit2) return 1

    if (isDigit1 && isDigit2) {
      // Parse full numbers
      let number1 = c1 - 48
      while (index1 < length1) {
        const digit = a.charCodeAt(index1)
        if (digit >= 48 && digit <= 57) {
          number1 = number1 * 10 + (digit - 48)
          index1++
        } else {
          break
        }
      }

      let number2 = c2 - 48
      while (index2 < length2) {
        const digit = b.charCodeAt(index2)
        if (digit >= 48 && digit <= 57) {
          number2 = number2 * 10 + (digit - 48)
          index2++
        } else {
          break
        }
      }

      if (number1 !== number2) {
        return number1 - number2
      }
    } else {
      // Compare non-digit characters
      // For first character, apply special comparison logic
      let cmp = 0
      if (index1 === 1 && index2 === 1) {
        cmp = compareNotDigit(c1, c2)
      } else {
        cmp = c1 - c2
      }

      if (cmp !== 0) {
        return cmp
      }
    }
  }

  if (index1 < length1) return 1
  if (index2 < length2) return -1
  return 0
}

export function getFileName(song: SongInfoData): string {
  const uri = song.path ?? song.fileUri ?? ''
  if (uri.length === 0) return song.title
  const idx = uri.lastIndexOf('/')
  const raw = idx >= 0 ? uri.substring(idx + 1) : uri
  try {
    return decodeURIComponent(raw)
  } catch (_) {
    return raw
  }
}

export function getFolderPath(song: SongInfoData): string {
  const uri = song.fileUri ?? song.path ?? ''
  if (uri.length === 0) return ''
  const idx = uri.lastIndexOf('/')
  const raw = idx >= 0 ? uri.substring(0, idx) : ''
  try {
    return decodeURIComponent(raw)
  } catch (_) {
    return raw
  }
}

// 排序工具：拼音首字母归一化，用于 ABC 索引与按名称排序。

// ABC 快速索引：按拼音首字母分组，右侧 A-Z 索引快速定位。
