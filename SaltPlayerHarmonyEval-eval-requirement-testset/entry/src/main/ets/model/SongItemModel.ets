// SongItemModel.ets
// Model layer: pure data structure for a song item.
// Contains no UI or business logic dependency.

// 歌曲音质等级，对齐安卓端 SongExtensions.kt
export const SONG_QUALITY_NORMAL: number = 0
export const SONG_QUALITY_HQ: number = 1
export const SONG_QUALITY_SQ: number = 2
export const SONG_QUALITY_HI_RES: number = 3

export interface SongInfoData {
  id: string
  title: string
  artist: string
  album: string
  subTitle: string
  coverUri: string
  valid: boolean
  quality: number
  format?: string
  fileUri?: string
  duration?: number
  bitrate?: number
  sampleRate?: number
  channels?: number
  bits?: number
  size?: number
  path?: string
  albumArtist?: string
  copyright?: string
  dateAdded?: number
  playlistAddedTime?: number
  dateModified?: number
  year?: number
  trackNumber?: number
  playedTimes?: number
  codec?: string
  // spec14: ReplayGain volume balance tag value (e.g. "-3.5 dB")
  replayGainDb?: string
}

// Default empty SongInfoData for initialization
export function createDefaultSongInfoData(): SongInfoData {
  return {
    id: '',
    title: '',
    artist: '',
    album: '',
    subTitle: '',
    coverUri: '',
    valid: true,
    quality: 0
  }
}

// spec21 — Extract the last path segment (file name with extension) from a
// storage path / URI. The persisted Track.path values land here in URI form
// (`file:///…`) and may contain URL-encoded byte sequences for non-ASCII names.
// Decoding is best-effort: a malformed sequence (e.g. dangling %) returns the
// raw segment so the UI never blanks out. Returns '' only when the caller has
// passed nothing useful — callers should fall back to the title in that case.
export function fileNameFromPath(path?: string | undefined | null): string {
  if (path === undefined || path === null) return ''
  const raw: string = path
  if (raw.length === 0) return ''
  const slash = raw.lastIndexOf('/')
  const segment = slash >= 0 ? raw.substring(slash + 1) : raw
  if (segment.length === 0) return ''
  try {
    return decodeURIComponent(segment)
  } catch (_e) {
    return segment
  }
}
