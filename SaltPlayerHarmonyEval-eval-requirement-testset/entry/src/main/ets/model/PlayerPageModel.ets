// PlayerPageModel.ets
// Model layer: pure data structures for the PlayerPage.
// Defines playback state, song metadata, audio info, and play mode constants.
// No UI or ViewModel logic - only data definitions and raw data operations.

import { QueueSongModel, PlayModeConstants } from './PlayQueueModel'

// Re-export PlayModeConstants for convenience
export { PlayModeConstants } from './PlayQueueModel'

// Represents the currently playing song's metadata
export class CurrentSongModel {
  public id: string = ''
  public title: string = ''
  public artist: string = ''
  public album: string = ''
  public coverUri: string = ''

  constructor(id: string = '', title: string = '', artist: string = '',
    album: string = '', coverUri: string = '') {
    this.id = id
    this.title = title
    this.artist = artist
    this.album = album
    this.coverUri = coverUri
  }
}

// Represents playback progress state
export class PlaybackProgressModel {
  public currentProgress: number = 0 // in milliseconds
  public duration: number = 0 // in milliseconds
  public isSeeking: boolean = false
  public seekProgress: number = 0

  constructor(currentProgress: number = 0, duration: number = 0) {
    this.currentProgress = currentProgress
    this.duration = duration
  }
}

// Represents audio information metadata
export class AudioInfoModel {
  public format: string = ''
  public channels: number = 0
  public sampleRate: number = 0
  public bitrate: number = 0 // raw bits/sec from metadata
  public fileExtension: string = ''

  constructor(format: string = '', channels: number = 0, sampleRate: number = 0,
    bitrate: number = 0, fileExtension: string = '') {
    this.format = format
    this.channels = channels
    this.sampleRate = sampleRate
    this.bitrate = bitrate
    this.fileExtension = fileExtension
  }

  hasChannels(): boolean {
    return this.channels > 0
  }

  hasSampleRate(): boolean {
    return this.sampleRate > 0
  }

  // Format display: song.format if present; else uppercased file extension; else blank.
  getDisplayFormat(): string {
    if (this.format.length > 0) {
      return this.format
    }
    if (this.fileExtension.length > 0) {
      let ext = this.fileExtension
      if (ext.startsWith('.')) {
        ext = ext.substring(1)
      }
      return ext.toUpperCase()
    }
    return ''
  }

  getDisplayChannels(): string {
    if (this.channels <= 0) return ''
    return `${this.channels} Channels`
  }

  // Display sample rate as kHz, e.g. "44.1 kHz". Strip trailing ".0" for whole numbers.
  getDisplaySampleRate(): string {
    if (this.sampleRate <= 0) return ''
    const khz = this.sampleRate / 1000
    let text = khz.toFixed(1)
    if (text.endsWith('.0')) {
      text = text.substring(0, text.length - 2)
    }
    return `${text} kHz`
  }

  // Bitrate is always displayed. If <= 0, show "0 Kbps".
  // Metadata bitrate is in bits/sec; divide by 1000 for kbps and round.
  getDisplayBitrate(): string {
    if (this.bitrate <= 0) return '0 Kbps'
    return `${Math.round(this.bitrate / 1000)} Kbps`
  }

  // Join only the present fields (channels if any, sampleRate if any) followed by
  // the always-present bitrate, separated by 4 spaces to match the existing visual.
  getDisplayText(): string {
    const parts: string[] = []
    if (this.hasChannels()) {
      parts.push(this.getDisplayChannels())
    }
    if (this.hasSampleRate()) {
      parts.push(this.getDisplaySampleRate())
    }
    parts.push(this.getDisplayBitrate())
    return parts.join('    ')
  }
}

// Pure helper: extract a lowercase file extension (no leading dot) from a
// path or file URI. Returns '' if neither provides a usable extension.
export function extractFileExtension(path: string | undefined, fileUri: string | undefined): string {
  const src: string = (path && path.length > 0) ? path : (fileUri ?? '')
  if (src.length === 0) return ''
  const dot: number = src.lastIndexOf('.')
  const slashF: number = src.lastIndexOf('/')
  const slashB: number = src.lastIndexOf('\\')
  const slash: number = slashF > slashB ? slashF : slashB
  if (dot > slash && dot < src.length - 1) {
    return src.substring(dot + 1).toLowerCase()
  }
  return ''
}

// Represents the dual queue data (normal + shuffled)
export class PlayQueueDataModel {
  public normalQueueSongs: QueueSongModel[] = []
  public randomQueueSongs: QueueSongModel[] = []

  constructor() {
    this.normalQueueSongs = []
  }

  // Fisher-Yates shuffle to generate randomQueueSongs from normalQueueSongs
  shuffleQueue(): void {
    const shuffled = this.normalQueueSongs.slice()
    for (let i = shuffled.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1))
      const temp = shuffled[i]
      shuffled[i] = shuffled[j]
      shuffled[j] = temp
    }
    this.randomQueueSongs = shuffled
  }

  // Get the display queue based on current play mode
  getDisplayQueue(playMode: string): QueueSongModel[] {
    return playMode === PlayModeConstants.RANDOM ? this.randomQueueSongs : this.normalQueueSongs
  }

  // Remove a song from both queues. Returns [normalIndex, randomIndex].
  removeSong(songId: string): [number, number] {
    let normalIndex = -1
    let randomIndex = -1
    const ni = this.normalQueueSongs.findIndex((song: QueueSongModel) => song.id === songId)
    if (ni !== -1) {
      normalIndex = ni
      this.normalQueueSongs.splice(ni, 1)
    }
    const ri = this.randomQueueSongs.findIndex((song: QueueSongModel) => song.id === songId)
    if (ri !== -1) {
      randomIndex = ri
      this.randomQueueSongs.splice(ri, 1)
    }
    return [normalIndex, randomIndex]
  }

  // Clear both queues
  clearAll(): void {
    this.normalQueueSongs = []
    this.randomQueueSongs = []
  }
}

// Bottom sheet type enumeration
export class BottomSheetType {
  static readonly NONE: string = ''
  static readonly AUDIO_EFFECT: string = 'audioEffect'
  static readonly SLEEP_TIMER: string = 'sleepTimer'
  static readonly LYRICS_INTERFACE: string = 'lyricsInterface'
  static readonly AUDIO_OUTPUT_INFO: string = 'audioOutputInfo'
}
