// SongInformationViewModel.ets
// ViewModel layer: provides formatted display data for SongInformationComponent (View).
// Bridges the Model layer (SongItemModel + SongInformationModel) with the View layer.
// Exposes observable state variables for song metadata and pre-formatted display strings.
// The View binds to this ViewModel and does not perform any data formatting itself.

import { SongInfoData } from '../model/SongItemModel'
import { formatDuration, formatSize, formatDateTime } from '../model/SongInformationModel'

@Observed
export class SongInformationViewModel {
  // ---------- Raw song data (from Model) ----------
  @Track public title: string = ''
  @Track public artist: string = ''
  @Track public album: string = ''
  @Track public albumArtist: string | undefined = undefined
  @Track public duration: number | undefined = undefined
  @Track public bitrate: number | undefined = undefined
  @Track public sampleRate: number | undefined = undefined
  @Track public channels: number | undefined = undefined
  @Track public bits: number | undefined = undefined
  @Track public size: number | undefined = undefined
  @Track public format: string | undefined = undefined
  @Track public path: string | undefined = undefined
  @Track public codec: string | undefined = undefined
  @Track public copyright: string | undefined = undefined
  @Track public dateAdded: number | undefined = undefined
  @Track public dateModified: number | undefined = undefined
  @Track public playedTimes: number | undefined = undefined

  // ---------- Callback for album artwork action ----------
  @Track public onAlbumArtworkClick: () => void = () => {
    console.info('TODO: open AlbumArtworkDialog')
  }

  /**
   * Load data from a SongInfoData model object into this ViewModel.
   * This is the bridge between Model and ViewModel.
   * @param model the raw song data from Model layer
   */
  updateFromModel(model: SongInfoData): void {
    this.title = model.title
    this.artist = model.artist
    this.album = model.album
    this.albumArtist = model.albumArtist
    this.duration = model.duration
    this.bitrate = model.bitrate
    this.sampleRate = model.sampleRate
    this.channels = model.channels
    this.bits = model.bits
    this.size = model.size
    this.format = model.format
    this.path = model.path
    this.codec = model.codec
    this.copyright = model.copyright
    this.dateAdded = model.dateAdded
    this.dateModified = model.dateModified
    this.playedTimes = model.playedTimes
  }

  // ---------- Formatted display getters (ViewModel logic) ----------

  /**
   * Get the display value for title field.
   */
  getDisplayTitle(): string {
    return this.title || ''
  }

  /**
   * Get the display value for artist field.
   */
  getDisplayArtist(): string {
    return this.artist || ''
  }

  /**
   * Get the display value for album field.
   */
  getDisplayAlbum(): string {
    return this.album || ''
  }

  /**
   * Get the display value for album artist.
   * Falls back to 'unknown' resource string (caller provides the fallback).
   */
  getDisplayAlbumArtist(unknownText: string): string {
    return this.albumArtist ? this.albumArtist : unknownText
  }

  /**
   * Get the display value for media source.
   * Currently always returns the provided unknown text.
   */
  getDisplayMediaSource(unknownText: string): string {
    return unknownText
  }

  /**
   * Get the display value for played times.
   */
  getDisplayPlayedTimes(): string {
    return this.playedTimes !== undefined ? this.playedTimes.toString() : '0'
  }

  /**
   * Get the formatted duration string.
   * Delegates to Model layer formatting utility.
   */
  getDisplayDuration(): string {
    return formatDuration(this.duration)
  }

  /**
   * Get the display value for bitrate.
   */
  getDisplayBitrate(unknownText: string): string {
    return (this.bitrate !== undefined && this.bitrate > 0)
      ? `${Math.round(this.bitrate / 1000)} kbps` : unknownText
  }

  /**
   * Whether sample rate should be displayed.
   */
  hasChannels(): boolean {
    return this.channels !== undefined && this.channels > 0
  }

  getDisplayChannels(): string {
    return `${this.channels} Channels`
  }

  hasSampleRate(): boolean {
    return this.sampleRate !== undefined && this.sampleRate > 0
  }

  getDisplaySampleRate(): string {
    return `${this.sampleRate} Hz`
  }

  /**
   * Whether bit depth should be displayed.
   */
  hasBitDepth(): boolean {
    return this.bits !== undefined && this.bits > 0
  }

  /**
   * Get the display value for bit depth.
   */
  getDisplayBitDepth(): string {
    return this.bits !== undefined ? this.bits.toString() : ''
  }

  /**
   * Get the formatted file size string.
   * Delegates to Model layer formatting utility.
   */
  getDisplaySize(): string {
    return formatSize(this.size)
  }

  /**
   * Get the display value for format.
   */
  getDisplayFormat(unknownText: string): string {
    return this.format ? this.format : unknownText
  }

  /**
   * Get the display value for file path.
   * Decodes URI-encoded path for display (same fix as FolderMenuDialogViewModel).
   */
  getDisplayPath(unknownText: string): string {
    if (!this.path) {
      return unknownText
    }
    try {
      return decodeURIComponent(this.path)
    } catch (e) {
      return this.path
    }
  }

  /**
   * Get the display value for codec.
   */
  getDisplayCodec(unknownText: string): string {
    return this.codec ? this.codec : (this.format ? this.format : unknownText)
  }

  /**
   * Get the display value for copyright.
   */
  getDisplayCopyright(unknownText: string): string {
    return this.copyright ? this.copyright : unknownText
  }

  /**
   * Get the formatted add time string.
   * Delegates to Model layer formatting utility.
   */
  getDisplayAddTime(): string {
    return formatDateTime(this.dateAdded)
  }

  /**
   * Get the formatted date modified string.
   * Delegates to Model layer formatting utility.
   */
  getDisplayDateModified(): string {
    return formatDateTime(this.dateModified)
  }

  // ---------- User interaction handlers ----------

  /**
   * Handle album artwork section click.
   */
  handleAlbumArtworkClick(): void {
    this.onAlbumArtworkClick()
  }

  // ---------- Static factory ----------

  /**
   * Create a SongInformationViewModel from a SongInfoData model object.
   * @param songInfo the raw song data
   * @returns a new SongInformationViewModel instance populated with the data
   */
  static createFromModel(songInfo: SongInfoData): SongInformationViewModel {
    const vm = new SongInformationViewModel()
    vm.updateFromModel(songInfo)
    return vm
  }
}
