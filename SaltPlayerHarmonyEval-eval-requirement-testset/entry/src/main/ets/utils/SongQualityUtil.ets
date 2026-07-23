// SongQualityUtil.ets
// Pure helpers for classifying a track's audio quality tier from its
// container + technical metadata. Mirrors the Android SongExtensions quality
// rules (see spec19 plan). Placed under utils/ so it can be reused by the
// scan pipeline (ScanningModel) and any future caller.

import {
  SONG_QUALITY_NORMAL,
  SONG_QUALITY_HQ,
  SONG_QUALITY_SQ,
  SONG_QUALITY_HI_RES
} from '../model/SongItemModel'

// Extract lowercase extension (without dot) from a filename or path.
// Returns '' when no extension is present.
export function extractExtension(displayNameOrPath: string): string {
  if (!displayNameOrPath || displayNameOrPath.length === 0) return ''
  // Strip any query string / fragment to avoid confusing dot detection.
  let name = displayNameOrPath
  const qIdx = name.indexOf('?')
  if (qIdx >= 0) name = name.substring(0, qIdx)
  const lastSlash = name.lastIndexOf('/')
  if (lastSlash >= 0) name = name.substring(lastSlash + 1)
  const dot = name.lastIndexOf('.')
  if (dot <= 0 || dot === name.length - 1) return ''
  return name.substring(dot + 1).toLowerCase()
}

// Classify a song's quality tier. Inputs:
//   ext          — lowercase extension without dot (e.g. 'flac', 'mp3')
//   sampleRate   — Hz (0 if unknown)
//   bits         — bit depth (0 if unknown)
//   bitrate      — bps (0 if unknown)
// Returns one of SONG_QUALITY_* constants.
export function computeSongQuality(ext: string, sampleRate: number, bits: number, bitrate: number): number {
  // Scene 1: DSD native formats → HR unconditionally.
  if (ext === 'dsf' || ext === 'dff') {
    return SONG_QUALITY_HI_RES
  }

  // Scene 2: both sampleRate and bit depth known.
  if (sampleRate > 0 && bits > 0) {
    if (sampleRate >= 44100 && bits >= 24) {
      return SONG_QUALITY_HI_RES
    }
    if (ext === 'flac') {
      if (sampleRate >= 44100 && bits >= 16) {
        return SONG_QUALITY_SQ
      }
      return SONG_QUALITY_HQ
    }
    // Non-flac with sampleRate/bits known — fall through to bitrate rules.
    if (bitrate >= 800_000) return SONG_QUALITY_SQ
    if (bitrate >= 320_000) return SONG_QUALITY_HQ
    return SONG_QUALITY_NORMAL
  }

  // Scene 3: sampleRate or bits unknown — classify by bitrate alone.
  if (bitrate >= 1_600_000 && ext !== 'mp3') return SONG_QUALITY_HI_RES
  if (bitrate >= 800_000) return SONG_QUALITY_SQ
  if (bitrate >= 320_000) return SONG_QUALITY_HQ
  return SONG_QUALITY_NORMAL
}

// 统一缩进与 import 顺序，无功能变更。

// 音质分级：依据采样率/位深/比特率判定无损/Hi-Res/高码率。
