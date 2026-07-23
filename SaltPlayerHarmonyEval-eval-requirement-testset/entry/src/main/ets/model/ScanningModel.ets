// ScanningModel.ets
// Model layer: scanning audio files
// Uses DocumentViewPicker with authMode to let user select audio files
// Then uses AVMetadataExtractor to read metadata from selected files
// Stores results in MusicDatabase (RDB) with incremental dedup by path

import { picker } from '@kit.CoreFileKit'
import { fileIo, fileShare } from '@kit.CoreFileKit'
import { media } from '@kit.MediaKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import {
  MusicDatabase,
  TrackRow,
  TrackMetadataUpdate,
  TrackQualityMissing,
  TrackQualityUpdate
} from './MusicDatabase'
import { CoverCacheDb } from './CoverCacheDb'
import { preferences, relationalStore } from '@kit.ArkData'
import { Guqin } from './Guqin'
import { computeSongQuality, extractExtension } from '../utils/SongQualityUtil'
import { ReplayGainExtractor } from './ReplayGainTagExtractor'

// Sentinel error: thrown by the pause checker when the user cancels mid-scan
// (dialog dismissed by tapping outside, or app closing). performScan and the
// surrounding viewmodel let it propagate so cancellation cleanup can revoke
// any URI permissions granted during this scan.
export class ScanCanceledError extends Error {
  constructor(message: string = 'Scan canceled by user') {
    super(message)
    this.name = 'ScanCanceledError'
  }
}

// Recovery storage: pending URI grants written here just after persistPermission.
// If the app is killed before the scan completes, the next launch revokes them
// to satisfy "已获取授权歌曲都要恢复未授权状态" (all songs authorized this scan
// must be restored to unauthorized state when the scan does not finish).
const SCAN_RECOVERY_PREFS = 'scan_recovery'
const PENDING_GRANTS_KEY = 'pending_grants_json'

const SUPPORTED_AUDIO_EXTENSIONS: string[] = [
  '.mp3', '.aac', '.flac', '.wav', '.opus', '.wv', '.ape',
  '.ogg', '.m4a', '.alac', '.aiff', '.aif', '.dsf', '.dff'
]

export class ScannedSongData {
  public id: string = ''
  public title: string = ''
  public artist: string = ''
  public albumArtist: string = ''
  public album: string = ''
  public trackNumber: number = 0
  public bitrate: number = 0
  public duration: number = 0
  public year: number = 0
  public sampleRate: number = 0
  public channels: number = 0
  public bitsPerSample: number = 0
  public composer: string = ''
  public genre: string = ''
  public path: string = ''
  public fileUri: string = ''
  public size: number = 0
  public dateModified: number = 0
  public dateAdded: number = 0
  public songType: number = 0
  public displayName: string = ''
  public mimeType: string = ''
  public coverUri: string = ''
  public quality: number = 0
  // spec14: ReplayGain tag value (e.g. "-3.5 dB"), empty if not present
  public replayGainDb: string = ''
  constructor() {}
}

export class ScanningState {
  public scanning: boolean = false
  public scanningLog: string = ''
  public scanProgress: number = 0
}

export class ScanLogEntry {
  public progress: number
  public message: string
  constructor(progress: number, message: string) {
    this.progress = progress
    this.message = message
  }
}

export class ScanResult {
  public songs: ScannedSongData[] = []
  public totalScanned: number = 0
  public totalAfterFilter: number = 0
  public skippedDuplicate: number = 0
}

export class RefreshResult {
  public updated: number = 0
  public removed: number = 0
  public total: number = 0
}

export class RescanResult {
  public total: number = 0
  public updated: number = 0
  public failed: number = 0
  public removed: number = 0
}

export type ScanLogCallback = (message: string) => void

// Cooperative pause checker — performScan awaits this between batches.
// Resolves immediately when not paused; blocks (resolves later) while paused.
// Rejects with ScanCanceledError when the caller has canceled the scan
// (e.g. user dismissed the dialog or app is closing).
export type ScanPauseChecker = () => Promise<void>

// Reports the URIs newly authorized by this scan (i.e. not already in the
// library) so the caller can revoke them if the scan is later canceled.
export type ScanGrantCallback = (newUris: string[]) => void

// Revoke persistent URI permissions for removed songs (batch by 500)
// Uses revokePermission (not deactivatePermission) to fully remove the persisted
// authorization so DocumentViewPicker can re-select these files on next scan.
export async function revokeFilePermissions(fileUris: string[]): Promise<void> {
  const validUris = fileUris.filter((uri: string): boolean => uri.length > 0)
  if (validUris.length === 0) return
  const policies: fileShare.PolicyInfo[] = validUris.map((uri: string): fileShare.PolicyInfo => {
    return { uri: uri, operationMode: fileShare.OperationMode.READ_MODE } as fileShare.PolicyInfo
  })
  const BATCH = 500
  for (let i = 0; i < policies.length; i += BATCH) {
    const batch = policies.slice(i, Math.min(i + BATCH, policies.length))
    try {
      await fileShare.revokePermission(batch)
    } catch (batchErr) {
      hilog.warn(0, 'ScanRevoke', 'revokePermission batch %{public}d failed: %{public}s',
        Math.floor(i / BATCH) + 1, (batchErr as BusinessError).message ?? '')
    }
  }
}

export class ScanningDataSource {
  static formatDate(date: Date): string {
    const y = date.getFullYear()
    const mo = String(date.getMonth() + 1).padStart(2, '0')
    const d = String(date.getDate()).padStart(2, '0')
    const h = String(date.getHours()).padStart(2, '0')
    const mi = String(date.getMinutes()).padStart(2, '0')
    const s = String(date.getSeconds()).padStart(2, '0')
    return `${y}-${mo}-${d} ${h}:${mi}:${s}`
  }

  static getParentFolderName(path: string): string {
    if (!path || path.length === 0) return ''
    const lastSlash = path.lastIndexOf('/')
    if (lastSlash <= 0) return ''
    const parentPath = path.substring(0, lastSlash)
    const secondLastSlash = parentPath.lastIndexOf('/')
    const name = secondLastSlash < 0 ? parentPath : parentPath.substring(secondLastSlash + 1)
    try {
      return decodeURIComponent(name)
    } catch (_e) {
      return name
    }
  }

  static getFileName(filePath: string): string {
    const lastSlash = filePath.lastIndexOf('/')
    return lastSlash >= 0 ? filePath.substring(lastSlash + 1) : filePath
  }

  static getFileNameWithoutExtension(displayName: string): string {
    const dotIndex = displayName.lastIndexOf('.')
    return dotIndex > 0 ? displayName.substring(0, dotIndex) : displayName
  }

  
  // Open DocumentViewPicker in audio merge mode for user to select audio files
  static async pickAudioFiles(context: Context): Promise<string[]> {
    const documentViewPicker = new picker.DocumentViewPicker(context)
    const options = new picker.DocumentSelectOptions()
    options.maxSelectNumber = 1000
    options.multiAuthMode = true
    options.mergeMode = picker.MergeTypeMode.AUDIO
    const result: Array<string> = await documentViewPicker.select(options)
    return result
  }

  // Main scan: open picker, get selected files, read metadata (incremental)
  static async performScan(
    context: Context,
    allowCache: boolean,
    skipBelow60s: boolean,
    blockedFolders: string[],
    scanDirs: string[],
    logCallback: ScanLogCallback,
    pauseChecker?: ScanPauseChecker,
    onGrant?: ScanGrantCallback
  ): Promise<ScanResult> {
    const result = new ScanResult()

    try {
      // Load existing paths from DB for dedup
      logCallback('Loading existing library for dedup...')
      const existingPaths: Set<string> = await MusicDatabase.getAllTrackPaths()
      logCallback('Existing tracks in library: ' + existingPaths.size)

      // Use DocumentViewPicker (authMode) to let user select audio files
      logCallback('Opening audio file picker...')
      let fileUris: string[]
      try {
        fileUris = await ScanningDataSource.pickAudioFiles(context)
      } catch (pickErr) {
        logCallback('Picker cancelled or failed: ' + (pickErr as BusinessError).message)
        return result
      }

      if (fileUris.length === 0) {
        logCallback('No files selected')
        return result
      }

      logCallback('Selected ' + fileUris.length + ' files')

      // Persist URI permissions so file access survives app restart (batch by 500)
      try {
        const policies: fileShare.PolicyInfo[] = fileUris.map((uri: string): fileShare.PolicyInfo => {
          return { uri: uri, operationMode: fileShare.OperationMode.READ_MODE } as fileShare.PolicyInfo
        })
        const PERSIST_BATCH = 500
        for (let i = 0; i < policies.length; i += PERSIST_BATCH) {
          const batch = policies.slice(i, Math.min(i + PERSIST_BATCH, policies.length))
          try {
            await fileShare.persistPermission(batch)
          } catch (batchErr) {
            hilog.warn(0, 'ScanPersist', 'persistPermission batch %{public}d failed: %{public}s',
              Math.floor(i / PERSIST_BATCH) + 1, (batchErr as BusinessError).message ?? '')
          }
        }
        logCallback('Persisted URI permissions for ' + fileUris.length + ' files')
      } catch (persistErr) {
        hilog.warn(0, 'ScanPersist', 'persistPermission failed: %{public}s',
          (persistErr as BusinessError).message ?? '')
        logCallback('Warning: persistPermission failed - files may not be accessible after restart')
      }

      // Deduplicate: skip files already in DB
      const newUris: string[] = []
      let skipped = 0
      for (const uri of fileUris) {
        if (existingPaths.has(uri)) {
          skipped++
        } else {
          newUris.push(uri)
        }
      }
      result.skippedDuplicate = skipped
      if (skipped > 0) {
        logCallback('Skipped ' + skipped + ' already existing tracks')
      }
      logCallback('New files to scan: ' + newUris.length)

      // Report newly-authorized URIs so the caller can track them for revoke
      // if the scan is canceled. Only the genuinely new URIs are reported —
      // pre-existing ones were already authorized by a previous scan and must
      // not be revoked.
      if (onGrant && newUris.length > 0) {
        onGrant(newUris)
      }

      if (newUris.length === 0) {
        logCallback('No new files to import')
        return result
      }

      // Process each new file (batch concurrent extraction, batch size = 3)
      const allSongs: ScannedSongData[] = []
      const BATCH_SIZE = 30

      for (let i = 0; i < newUris.length; i += BATCH_SIZE) {
        // Cooperative cancel checkpoint: the caller's pauseChecker throws
        // ScanCanceledError when the user dismissed the scan dialog or the
        // app is closing. The error propagates so the caller can revoke any
        // URI permissions persisted earlier in this scan.
        if (pauseChecker) {
          await pauseChecker()
        }

        const batch: string[] = newUris.slice(i, Math.min(i + BATCH_SIZE, newUris.length))
        const promises: Promise<ScannedSongData | null>[] = batch.map(
          (uri: string): Promise<ScannedSongData | null> =>
            ScanningDataSource.readAudioFromUri(uri, logCallback, context)
        )
        const results: (ScannedSongData | null)[] = await Promise.all(promises)
        for (const song of results) {
          if (song) {
            allSongs.push(song)
          }
        }

        const processed = Math.min(i + BATCH_SIZE, newUris.length)
        if (processed % 10 < BATCH_SIZE) {
          logCallback('Processing... ' + processed + '/' + newUris.length)
          // Yield to UI thread to prevent UI freeze
          await new Promise<void>((resolve) => setTimeout(resolve, 0))
        }
      }

      result.totalScanned = allSongs.length
      logCallback('Scanned ' + allSongs.length + ' new songs')

      // Blocked folders filter
      logCallback('Applying blocked folders filter...')
      let filteredSongs: ScannedSongData[]
      if (blockedFolders.length > 0) {
        filteredSongs = allSongs.filter((song: ScannedSongData) => {
          for (const blocked of blockedFolders) {
            if (blocked.length > 0 && song.fileUri.startsWith(blocked + '/')) return false
          }
          return true
        })
      } else {
        filteredSongs = allSongs
      }

      // Duration filter
      if (skipBelow60s) {
        logCallback('Filtering audio below 60 seconds...')
        filteredSongs = filteredSongs.filter((song: ScannedSongData) => song.duration >= 60000)
      }

      result.songs = filteredSongs
      result.totalAfterFilter = filteredSongs.length
      logCallback('After filters: ' + filteredSongs.length + ' songs')

    } catch (err) {
      // Cancellation is not an error — let it propagate so the caller can
      // run its revoke-and-reset cleanup.
      if (err instanceof ScanCanceledError) {
        throw err
      }
      const error = err as BusinessError
      logCallback('Scan error: ' + error.code + ' - ' + error.message)
    }

    return result
  }

  // Read metadata from an audio file URI (no cover extraction during scan per spec)
  static async readAudioFromUri(uri: string, logCallback: ScanLogCallback, context?: Context): Promise<ScannedSongData | null> {
    let file: fileIo.File | null = null
    try {
      file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY)

      const stat: fileIo.Stat = await fileIo.stat(file.fd)

      const song = new ScannedSongData()
      song.fileUri = uri
      song.path = uri
      const uriName: string = ScanningDataSource.getFileName(uri)
      song.displayName = decodeURIComponent(uriName)
      song.size = stat.size
      song.dateModified = stat.mtime
      song.dateAdded = stat.ctime
      song.id = uri

      // Extract metadata using AVMetadataExtractor
      try {
        const extractor: media.AVMetadataExtractor = await media.createAVMetadataExtractor()
        extractor.fdSrc = { fd: file.fd, offset: 0, length: stat.size }
        const metadata: media.AVMetadata = await extractor.fetchMetadata()

        if (metadata.title && metadata.title.length > 0) song.title = metadata.title
        if (metadata.artist) song.artist = metadata.artist
        if (metadata.album) song.album = metadata.album
        if (metadata.albumArtist) song.albumArtist = metadata.albumArtist
        if (metadata.genre) song.genre = metadata.genre
        if (metadata.composer) song.composer = metadata.composer
        else if (metadata.author) song.composer = metadata.author
        if (metadata.duration) {
          const dur: number = parseInt(metadata.duration)
          if (!isNaN(dur) && dur > 0) song.duration = dur
        }
        if (metadata.sampleRate) song.sampleRate = parseInt(metadata.sampleRate) || 0
        if (metadata.tracks && metadata.tracks.length > 0) {
          for (const track of metadata.tracks) {
            const chRaw = track[media.MediaDescriptionKey.MD_KEY_AUD_CHANNEL_COUNT]
            const ch = typeof chRaw === 'number' ? chRaw : parseInt(`${chRaw}`) || 0
            if (ch > 0) {
              song.channels = ch
              break
            }
          }
        }
        if (metadata.mimeType) song.mimeType = metadata.mimeType
        if (metadata.dateTime) song.year = ScanningDataSource.parseYear(metadata.dateTime)
        if (song.duration > 0 && song.size > 0) {
          song.bitrate = Math.round((song.size * 8) / (song.duration / 1000))
        }

        // Classify audio quality once per scan — persisted on Track row and
        // read back into SongInfoData so the list/detail UI can display the
        // HR/SQ/HQ badge.
        {
          let ext = extractExtension(song.displayName)
          if (ext.length === 0) ext = extractExtension(song.path)
          song.quality = computeSongQuality(ext, song.sampleRate, song.bitsPerSample, song.bitrate)
        }

        // NOTE: Cover art is NOT extracted during scan per spec.
        // Cover thumbnails are generated on-demand during playback.

        await extractor.release()
      } catch (_metaErr) {
        // metadata extraction failed
      }

      // spec14: extract ReplayGain tags from raw file bytes
      try {
        song.replayGainDb = ReplayGainExtractor.extract(file.fd, stat.size, song.mimeType)
      } catch (_rgErr) {
        song.replayGainDb = ''
      }

      await fileIo.close(file)
      file = null

      // --- Tag cleaning (Guqin) ---
      song.title = Guqin.formatTitle(song.title, song.displayName)
      song.artist = Guqin.formatArtist(song.artist)
      song.album = Guqin.formatAlbum(song.album, ScanningDataSource.getParentFolderName(uri))
      song.albumArtist = Guqin.formatArtist(song.albumArtist)
      song.genre = Guqin.formatGenre(song.genre)
      if (song.composer) {
        song.composer = song.composer.trim()
      }

      return song
    } catch (err) {
      logCallback('Failed to read: ' + uri + ' (' + (err as BusinessError).message + ')')
      if (file) {
        try { await fileIo.close(file) } catch (_e) { /* ignore */ }
      }
      return null
    }
  }

  static parseYear(dateStr: string): number {
    if (!dateStr || dateStr.length === 0) return 0
    const yearMatch = dateStr.match(/(\d{4})/)
    return yearMatch ? parseInt(yearMatch[1]) : 0
  }

  static parseTrackNumber(trackStr: string): number {
    if (!trackStr || trackStr.length === 0) return 0
    const slashIndex = trackStr.indexOf('/')
    const numStr = slashIndex > 0 ? trackStr.substring(0, slashIndex) : trackStr
    const parsed = parseInt(numStr)
    return isNaN(parsed) ? 0 : parsed
  }

  // Convert ScannedSongData to TrackRow for DB insertion
  private static toTrackRow(song: ScannedSongData): TrackRow {
    return {
      id: song.id,
      title: song.title,
      artist: song.artist,
      album: song.album,
      albumArtist: song.albumArtist,
      genre: song.genre,
      year: song.year,
      number: song.trackNumber,
      isFavorite: false,
      playCount: 0,
      trackOrder: 0,
      path: song.path,
      readable: true,
      size: song.size,
      addedTime: song.dateAdded,
      modifiedTime: song.dateModified,
      duration: song.duration,
      bitsPerSample: song.bitsPerSample,
      sampleRate: song.sampleRate,
      channels: song.channels,
      bitrate: song.bitrate,
      fileUri: song.fileUri,
      coverUri: song.coverUri,
      displayName: song.displayName,
      mimeType: song.mimeType,
      composer: song.composer,
      quality: song.quality,
      // Scanning runs computeSongQuality() above (line ~356), so the value
      // is authoritative — let the music-library backfill skip this row.
      qualityClassified: true,
      // spec14: ReplayGain volume balance tag
      replayGainDb: song.replayGainDb
    }
  }

  // Persist scan results to RDB and update AppStorage counts
  static async persistScanResults(scanResult: ScanResult, _context: Context,
    logCallback?: ScanLogCallback): Promise<void> {
    // Convert and insert into RDB
    const trackRows: TrackRow[] = scanResult.songs.map(
      (song: ScannedSongData): TrackRow => ScanningDataSource.toTrackRow(song))
    const inserted = await MusicDatabase.insertTracks(trackRows)
    hilog.info(0, 'ScanPersist', 'Inserted %{public}d tracks into RDB', inserted)

    // Rebuild Album/Artist/Folder tables from Track data
    await MusicDatabase.refreshAlbumsAndArtists()
    await MusicDatabase.refreshFolders()

    // NOTE: Cover art is no longer pre-extracted here. Covers are loaded lazily
    // as list items scroll into view (see SongItemComponent.loadCover), which
    // avoids a long blocking tail on scan completion and mirrors the Android
    // behaviour where the disk cache is populated on first display.

    // Update AppStorage counts
    const totalSongs = await MusicDatabase.getTrackCount()
    const totalAlbums = await MusicDatabase.getAlbumCount()
    const totalArtists = await MusicDatabase.getArtistCount()
    const totalFolders = await MusicDatabase.getFolderCount()

    AppStorage.setOrCreate<number>('totalSongCount', totalSongs)
    AppStorage.setOrCreate<string>('lastScanTime', ScanningDataSource.formatDate(new Date()))
    AppStorage.setOrCreate<number>('totalAlbumCount', totalAlbums)
    AppStorage.setOrCreate<number>('totalArtistCount', totalArtists)
    AppStorage.setOrCreate<number>('totalFolderCount', totalFolders)

    // Refresh in-memory cache BEFORE notifying UI, so getScannedSongs() returns fresh data
    await ScanningDataSource.refreshCache()

    // Increment scan version to notify MainPage to refresh
    const currentVersion: number = AppStorage.get<number>('scanVersion') || 0
    AppStorage.setOrCreate<number>('scanVersion', currentVersion + 1)
  }

  // Get all scanned songs from RDB (replaces static array)
  static async getScannedSongsAsync(): Promise<ScannedSongData[]> {
    const tracks = await MusicDatabase.getAllTracks()
    return tracks.map((t: TrackRow): ScannedSongData => {
      const song = new ScannedSongData()
      song.id = t.id
      song.title = t.title
      song.artist = t.artist
      song.albumArtist = t.albumArtist
      song.album = t.album
      song.trackNumber = t.number
      song.bitrate = t.bitrate
      song.duration = t.duration
      song.year = t.year
      song.sampleRate = t.sampleRate
      song.channels = t.channels
      song.bitsPerSample = t.bitsPerSample
      song.composer = t.composer
      song.genre = t.genre
      song.path = t.path
      song.fileUri = t.fileUri
      song.size = t.size
      song.dateModified = t.modifiedTime
      song.dateAdded = t.addedTime
      song.displayName = t.displayName
      song.mimeType = t.mimeType
      song.coverUri = t.coverUri
      song.quality = t.quality
      song.replayGainDb = t.replayGainDb
      return song
    })
  }

  // Synchronous wrapper - returns cached data (kept for backward compat with MainPageDataSource)
  // The cache is populated on app startup and after each scan
  private static cachedSongs: ScannedSongData[] = []

  // Tracks whether URI permissions have been activated (resolves when done).
  // Public so callers that need to read files outside the scan path
  // (e.g. MusicLibraryModel's size-fallback) can wait for activation to
  // complete before invoking fileIo.open on persisted URIs.
  static permissionActivationPromise: Promise<void> = Promise.resolve()

  static getScannedSongs(): ScannedSongData[] {
    return ScanningDataSource.cachedSongs
  }

  // Load songs from RDB into cache (called at app startup)
  static async loadFromDatabase(): Promise<void> {
    ScanningDataSource.cachedSongs = await ScanningDataSource.getScannedSongsAsync()
    hilog.info(0, 'ScanLoad', 'Loaded %{public}d songs from RDB', ScanningDataSource.cachedSongs.length)
  }

  // Migrate data from old Preferences storage to RDB (one-time migration)
  static async migrateFromPreferences(context: Context): Promise<void> {
    try {
      const preferencesModule = await import('@kit.ArkData')
      const store = preferencesModule.preferences.getPreferencesSync(context, { name: 'scanned_songs' })
      const jsonStr = store.getSync('songs_json', '') as string
      if (jsonStr.length === 0) return // nothing to migrate

      const arr: object[] = JSON.parse(jsonStr) as object[]
      if (arr.length === 0) return

      hilog.info(0, 'ScanMigrate', 'Migrating %{public}d songs from Preferences to RDB', arr.length)
      const trackRows: TrackRow[] = arr.map((obj: object): TrackRow => {
        const rec = obj as Record<string, string | number>
        return {
          id: (rec['id'] as string) ?? '',
          title: (rec['title'] as string) ?? '',
          artist: (rec['artist'] as string) ?? '',
          album: (rec['album'] as string) ?? '',
          albumArtist: (rec['albumArtist'] as string) ?? '',
          genre: (rec['genre'] as string) ?? '',
          year: (rec['year'] as number) ?? 0,
          number: (rec['trackNumber'] as number) ?? 0,
          isFavorite: false,
          playCount: 0,
          trackOrder: 0,
          path: (rec['path'] as string) ?? '',
          readable: true,
          size: (rec['size'] as number) ?? 0,
          addedTime: (rec['dateAdded'] as number) ?? 0,
          modifiedTime: (rec['dateModified'] as number) ?? 0,
          duration: (rec['duration'] as number) ?? 0,
          bitsPerSample: (rec['bitsPerSample'] as number) ?? 0,
          sampleRate: (rec['sampleRate'] as number) ?? 0,
          channels: (rec['channels'] as number) ?? 0,
          bitrate: (rec['bitrate'] as number) ?? 0,
          fileUri: (rec['fileUri'] as string) ?? '',
          coverUri: (rec['coverUri'] as string) ?? '',
          displayName: (rec['displayName'] as string) ?? '',
          mimeType: (rec['mimeType'] as string) ?? '',
          composer: (rec['composer'] as string) ?? '',
          quality: 0,
          // Migrated rows haven't been classified — let the music-library
          // backfill recompute their quality from existing metadata.
          qualityClassified: false,
          // spec14: migrated rows have no ReplayGain data
          replayGainDb: ''
        }
      })

      await MusicDatabase.insertTracks(trackRows)
      await MusicDatabase.refreshAlbumsAndArtists()
      await MusicDatabase.refreshFolders()

      // Clear old preferences data after successful migration
      store.deleteSync('songs_json')
      await store.flush()
      hilog.info(0, 'ScanMigrate', 'Migration complete, cleared old Preferences data')
    } catch (e) {
      hilog.warn(0, 'ScanMigrate', 'Migration failed: %{public}s', (e as Error).message)
    }
  }

  // Refresh the in-memory cache from RDB (called after scan completes)
  static async refreshCache(): Promise<void> {
    ScanningDataSource.cachedSongs = await ScanningDataSource.getScannedSongsAsync()
  }

  // Eager in-memory invalidation. Strips the given ids from `cachedSongs` in
  // a single pass so subsequent sync reads (loadDefaultAlbums / loadDefaultArtists
  // / album-detail / artist-detail — all of which read `getScannedSongs()`)
  // see the post-deletion state IMMEDIATELY, before the slow RDB-side
  // refreshCache() round-trips finish. Without this, navigating to the
  // Album or Artist page right after a multi-select removal still shows the
  // removed songs until refreshCache() completes seconds later.
  static removeSongsFromCache(songIds: string[]): void {
    if (songIds.length === 0 || ScanningDataSource.cachedSongs.length === 0) return
    const removeSet = new Set<string>(songIds)
    const filtered: ScannedSongData[] = []
    for (const s of ScanningDataSource.cachedSongs) {
      if (!removeSet.has(s.id)) filtered.push(s)
    }
    if (filtered.length !== ScanningDataSource.cachedSongs.length) {
      ScanningDataSource.cachedSongs = filtered
    }
  }

  // Re-check all existing tracks: skip unchanged files, re-read metadata for changed files,
  // remove tracks whose source file no longer exists.
  static async refreshExistingTracks(context: Context): Promise<RefreshResult> {
    // Wait for URI permissions to be fully activated before checking file accessibility,
    // otherwise fileIo.open() fails and tracks get incorrectly deleted.
    await ScanningDataSource.permissionActivationPromise

    const logCallback: ScanLogCallback = (msg: string) => { console.info('[Refresh] ' + msg) }
    const allTracks: TrackRow[] = await MusicDatabase.getAllTracks()
    logCallback('Checking ' + allTracks.length + ' tracks for changes...')

    const batchUpdates: TrackMetadataUpdate[] = []
    const toRemovePaths: string[] = []
    const toRemoveIds: string[] = []
    const toRemoveFileUris: string[] = []
    const coverInvalidations: string[] = []
    let skipped = 0

    for (let i = 0; i < allTracks.length; i++) {
      const track = allTracks[i]

      // Try to open file and stat it
      let file: fileIo.File | null = null
      let stat: fileIo.Stat | null = null
      try {
        file = await fileIo.open(track.fileUri, fileIo.OpenMode.READ_ONLY)
        stat = await fileIo.stat(file.fd)
        await fileIo.close(file)
        file = null
      } catch (_e) {
        // File no longer exists or permission revoked
        if (file) {
          try { await fileIo.close(file) } catch (_closeErr) { /* ignore */ }
        }
        toRemovePaths.push(track.path)
        toRemoveIds.push(track.id)
        toRemoveFileUris.push(track.fileUri)
        continue
      }

      // Compare mtime and size — skip if unchanged
      if (stat.mtime === track.modifiedTime && stat.size === track.size) {
        skipped++
        continue
      }

      // File changed — re-read metadata
      const song: ScannedSongData | null =
        await ScanningDataSource.readAudioFromUri(track.fileUri, logCallback, context)
      if (!song) {
        // Could not read — mark unreadable
        const unreadableBucket: relationalStore.ValuesBucket = { 'readable': 0 }
        const unreadableUpdate: TrackMetadataUpdate = { id: track.id, bucket: unreadableBucket }
        batchUpdates.push(unreadableUpdate)
        continue
      }

      // Build update bucket (metadata only, preserving user fields)
      const bucket: relationalStore.ValuesBucket = {
        'title': song.title,
        'artist': song.artist,
        'album': song.album,
        'albumArtist': song.albumArtist,
        'genre': song.genre,
        'year': song.year,
        'number': song.trackNumber,
        'size': song.size,
        'modifiedTime': song.dateModified,
        'duration': song.duration,
        'bitsPerSample': song.bitsPerSample,
        'sampleRate': song.sampleRate,
        'channels': song.channels,
        'bitrate': song.bitrate,
        'displayName': song.displayName,
        'mimeType': song.mimeType,
        'composer': song.composer,
        'coverUri': song.coverUri,
        'readable': 1,
        'quality': song.quality,
        'qualityClassified': 1,
        // spec14: update ReplayGain on refresh
        'replayGainDb': song.replayGainDb
      }
      const metadataUpdate: TrackMetadataUpdate = { id: track.id, bucket: bucket }
      batchUpdates.push(metadataUpdate)
      coverInvalidations.push(track.id)

      // Yield to UI thread every 10 tracks
      if ((i + 1) % 10 === 0) {
        await new Promise<void>((resolve) => setTimeout(resolve, 0))
      }
    }

    // Batch persist updates
    const updatedCount = await MusicDatabase.updateTracksMetadata(batchUpdates)
    logCallback('Updated ' + updatedCount + ' tracks')

    // Remove tracks whose files no longer exist
    let removedCount = 0
    for (const path of toRemovePaths) {
      const deleted = await MusicDatabase.deleteTrackByPath(path)
      if (deleted) removedCount++
    }
    if (removedCount > 0) {
      logCallback('Removed ' + removedCount + ' missing tracks')
      // Revoke persistent URI permissions for removed tracks
      await revokeFilePermissions(toRemoveFileUris)
    }

    // Invalidate cover caches for changed tracks
    for (const songId of coverInvalidations) {
      await CoverCacheDb.deleteCover(songId)
    }

    // Clean up cover caches for removed tracks
    for (const songId of toRemoveIds) {
      await CoverCacheDb.deleteCover(songId)
    }

    // Pull-to-refresh must also recover any per-track state the new version
    // computes that the old DB never persisted — first and foremost the
    // HQ/SQ/HR quality tag. Rows whose mtime/size are unchanged take the
    // "skipped" branch above and never enter batchUpdates, so legacy rows
    // upgraded from a build without the quality column would otherwise
    // remain qualityClassified=0 and render with no tag in the song list
    // until the user opens the Music Library page.
    const reclassifiedCount = await ScanningDataSource.backfillQualitiesAcrossLibrary()
    if (reclassifiedCount > 0) {
      logCallback('Reclassified ' + reclassifiedCount + ' legacy tracks')
    }

    // Aggregation tables only need rebuilding when the track set itself
    // actually moved — track count, album list, etc. don't change for a
    // pure quality-only backfill, so we keep this expensive path gated.
    if (batchUpdates.length > 0 || removedCount > 0) {
      await MusicDatabase.refreshAlbumsAndArtists()
      await MusicDatabase.refreshFolders()

      const totalSongs = await MusicDatabase.getTrackCount()
      const totalAlbums = await MusicDatabase.getAlbumCount()
      const totalArtists = await MusicDatabase.getArtistCount()
      const totalFolders = await MusicDatabase.getFolderCount()
      AppStorage.setOrCreate<number>('totalSongCount', totalSongs)
      AppStorage.setOrCreate<number>('totalAlbumCount', totalAlbums)
      AppStorage.setOrCreate<number>('totalArtistCount', totalArtists)
      AppStorage.setOrCreate<number>('totalFolderCount', totalFolders)
    }

    // Always reload the in-memory song cache and bump scanVersion so the
    // song list re-renders with the latest DB state. The previous build
    // gated this on whether THIS refresh wrote rows, but quality may have
    // been written to the DB by an earlier visit to the Music Library
    // page (which calls backfillQualitiesAcrossLibrary too) while the
    // cache populated at app start still holds quality=0 for those rows.
    // In that case THIS refresh has nothing to backfill yet the song list
    // is the screen the user is looking at — they need it to pick up the
    // already-classified rows from disk now, not on the next app launch.
    // This is also a single SQL query plus an AppStorage write, so the
    // cost of running it unconditionally on a user-triggered pull is
    // negligible compared to any of the file-stat work above.
    await ScanningDataSource.refreshCache()
    const currentVersion: number = AppStorage.get<number>('scanVersion') || 0
    AppStorage.setOrCreate<number>('scanVersion', currentVersion + 1)

    logCallback('Refresh complete: ' + skipped + ' unchanged, ' +
      coverInvalidations.length + ' updated, ' + removedCount + ' removed, ' +
      reclassifiedCount + ' reclassified')
    const refreshResult = new RefreshResult()
    refreshResult.updated = coverInvalidations.length + reclassifiedCount
    refreshResult.removed = removedCount
    refreshResult.total = allTracks.length
    return refreshResult
  }

  // Full rescan: re-read metadata for ALL existing tracks.
  // Unlike refreshExistingTracks (which skips unchanged files), this re-reads
  // every track's metadata — useful when new fields are added (e.g. replayGainDb)
  // or when the extraction logic changes.
  static async rescanAllTracks(
    context: Context,
    logCallback: ScanLogCallback,
    pauseChecker?: ScanPauseChecker
  ): Promise<RescanResult> {
    await ScanningDataSource.permissionActivationPromise

    const result = new RescanResult()
    const allTracks: TrackRow[] = await MusicDatabase.getAllTracks()
    result.total = allTracks.length
    logCallback('Rescanning ' + allTracks.length + ' tracks...')

    const batchUpdates: TrackMetadataUpdate[] = []
    const toRemovePaths: string[] = []
    const toRemoveFileUris: string[] = []
    const toRemoveIds: string[] = []
    const coverInvalidations: string[] = []

    const BATCH_SIZE = 30

    for (let i = 0; i < allTracks.length; i += BATCH_SIZE) {
      if (pauseChecker) {
        await pauseChecker()
      }

      const batch = allTracks.slice(i, Math.min(i + BATCH_SIZE, allTracks.length))
      const promises = batch.map(async (track: TrackRow) => {
        const song: ScannedSongData | null =
          await ScanningDataSource.readAudioFromUri(track.fileUri, logCallback, context)

        if (!song) {
          toRemovePaths.push(track.path)
          toRemoveFileUris.push(track.fileUri)
          toRemoveIds.push(track.id)
          result.failed++
          return
        }

        const bucket: relationalStore.ValuesBucket = {
          'title': song.title,
          'artist': song.artist,
          'album': song.album,
          'albumArtist': song.albumArtist,
          'genre': song.genre,
          'year': song.year,
          'number': song.trackNumber,
          'size': song.size,
          'modifiedTime': song.dateModified,
          'duration': song.duration,
          'bitsPerSample': song.bitsPerSample,
          'sampleRate': song.sampleRate,
          'channels': song.channels,
          'bitrate': song.bitrate,
          'displayName': song.displayName,
          'mimeType': song.mimeType,
          'composer': song.composer,
          'coverUri': song.coverUri,
          'readable': 1,
          'quality': song.quality,
          'qualityClassified': 1,
          'replayGainDb': song.replayGainDb
        }
        batchUpdates.push({ id: track.id, bucket })
        coverInvalidations.push(track.id)
        result.updated++
      })

      await Promise.all(promises)
      logCallback('Progress: ' + Math.min(i + BATCH_SIZE, allTracks.length) + '/' + allTracks.length)
    }

    // Batch persist updates
    const updatedCount = await MusicDatabase.updateTracksMetadata(batchUpdates)
    logCallback('Updated ' + updatedCount + ' tracks')

    // Remove tracks whose files no longer exist
    let removedCount = 0
    for (const path of toRemovePaths) {
      const deleted = await MusicDatabase.deleteTrackByPath(path)
      if (deleted) removedCount++
    }
    if (removedCount > 0) {
      logCallback('Removed ' + removedCount + ' missing tracks')
      await revokeFilePermissions(toRemoveFileUris)
    }

    // Invalidate cover caches
    for (const songId of coverInvalidations) {
      await CoverCacheDb.deleteCover(songId)
    }
    for (const songId of toRemoveIds) {
      await CoverCacheDb.deleteCover(songId)
    }

    // Rebuild aggregation tables when data changed
    if (batchUpdates.length > 0 || removedCount > 0) {
      await MusicDatabase.refreshAlbumsAndArtists()
      await MusicDatabase.refreshFolders()

      const totalSongs = await MusicDatabase.getTrackCount()
      const totalAlbums = await MusicDatabase.getAlbumCount()
      const totalArtists = await MusicDatabase.getArtistCount()
      const totalFolders = await MusicDatabase.getFolderCount()
      AppStorage.setOrCreate<number>('totalSongCount', totalSongs)
      AppStorage.setOrCreate<number>('totalAlbumCount', totalAlbums)
      AppStorage.setOrCreate<number>('totalArtistCount', totalArtists)
      AppStorage.setOrCreate<number>('totalFolderCount', totalFolders)
    }

    // Refresh cache and bump version
    await ScanningDataSource.refreshCache()
    const currentVersion: number = AppStorage.get<number>('scanVersion') || 0
    AppStorage.setOrCreate<number>('scanVersion', currentVersion + 1)

    result.removed = removedCount
    logCallback('Rescan complete: ' + result.updated + ' updated, ' + result.failed + ' failed, ' + result.removed + ' removed')
    return result
  }

  // Re-run computeSongQuality on every Track row whose qualityClassified flag
  // is still 0 — i.e. rows persisted before the quality columns existed, or
  // rows imported via the Preferences migration. Uses metadata already on the
  // row so it does no file I/O and is cheap to invoke from any refresh path.
  // Returns the number of rows whose quality was rewritten so callers can
  // decide whether to bump scan version / reload caches.
  static async backfillQualitiesAcrossLibrary(): Promise<number> {
    const missing: TrackQualityMissing[] = await MusicDatabase.getTracksMissingQuality()
    if (missing.length === 0) return 0
    const updates: TrackQualityUpdate[] = []
    for (const t of missing) {
      let ext = extractExtension(t.displayName)
      if (ext.length === 0) ext = extractExtension(t.path)
      const q = computeSongQuality(ext, t.sampleRate, t.bitsPerSample, t.bitrate)
      updates.push({ id: t.id, quality: q })
    }
    try {
      await MusicDatabase.updateTrackQualities(updates)
    } catch (e) {
      hilog.warn(0, 'ScanRefresh', 'backfillQualitiesAcrossLibrary failed: %{public}s',
        (e as Error).message)
      return 0
    }
    return updates.length
  }

  static getScanSteps(): ScanLogEntry[] { return [] }

  // ----- Crash-recovery for interrupted scans -----
  // The viewmodel calls writePendingGrants right after persistPermission so that
  // a process kill mid-scan still leaves a record of which URIs need revoking.
  // On clean cancel or successful completion the viewmodel calls clearPendingGrants;
  // on next launch EntryAbility calls recoverInterruptedScan which revokes any
  // leftover grants.
  static async writePendingGrants(context: Context, uris: string[]): Promise<void> {
    if (!context) return
    try {
      const store = preferences.getPreferencesSync(context, { name: SCAN_RECOVERY_PREFS })
      store.putSync(PENDING_GRANTS_KEY, JSON.stringify(uris))
      await store.flush()
    } catch (e) {
      hilog.warn(0, 'ScanRecover', 'writePendingGrants failed: %{public}s',
        (e as BusinessError).message ?? '')
    }
  }

  static async clearPendingGrants(context: Context): Promise<void> {
    if (!context) return
    try {
      const store = preferences.getPreferencesSync(context, { name: SCAN_RECOVERY_PREFS })
      store.deleteSync(PENDING_GRANTS_KEY)
      await store.flush()
    } catch (e) {
      hilog.warn(0, 'ScanRecover', 'clearPendingGrants failed: %{public}s',
        (e as BusinessError).message ?? '')
    }
  }

  static async readPendingGrants(context: Context): Promise<string[]> {
    if (!context) return []
    try {
      const store = preferences.getPreferencesSync(context, { name: SCAN_RECOVERY_PREFS })
      const json = store.getSync(PENDING_GRANTS_KEY, '') as string
      if (!json || json.length === 0) return []
      const parsed: object = JSON.parse(json) as object
      if (!Array.isArray(parsed)) return []
      const arr = parsed as string[]
      return arr.filter((u: string): boolean => typeof u === 'string' && u.length > 0)
    } catch (e) {
      hilog.warn(0, 'ScanRecover', 'readPendingGrants failed: %{public}s',
        (e as BusinessError).message ?? '')
      return []
    }
  }

  // Called once at app startup. If the previous run was interrupted while a
  // scan was in flight, the persisted URI list is revoked here so those songs
  // are restored to the unauthorized state.
  static async recoverInterruptedScan(context: Context): Promise<void> {
    const uris = await ScanningDataSource.readPendingGrants(context)
    if (uris.length === 0) return
    hilog.info(0, 'ScanRecover', 'Revoking %{public}d grants from interrupted scan', uris.length)
    try {
      await revokeFilePermissions(uris)
    } catch (e) {
      hilog.warn(0, 'ScanRecover', 'revoke during recovery failed: %{public}s',
        (e as BusinessError).message ?? '')
    }
    await ScanningDataSource.clearPendingGrants(context)
  }

  // Activate persisted URI permissions for all stored songs (call at app startup)
  // Uses the in-memory cache (populated by loadFromDatabase()) instead of re-querying RDB.
  // Stores the activation promise so refreshExistingTracks can await it.
  // Batches in groups of 500 due to fileShare.activatePermission API limit.
  static activateStoredPermissions(): void {
    const songs = ScanningDataSource.getScannedSongs()
    if (songs.length === 0) {
      return
    }
    try {
      const policies: fileShare.PolicyInfo[] = songs
        .filter((s: ScannedSongData): boolean => s.fileUri.length > 0)
        .map((s: ScannedSongData): fileShare.PolicyInfo => {
          return { uri: s.fileUri, operationMode: fileShare.OperationMode.READ_MODE } as fileShare.PolicyInfo
        })
      if (policies.length > 0) {
        const BATCH_SIZE = 500
        const batches: fileShare.PolicyInfo[][] = []
        for (let i = 0; i < policies.length; i += BATCH_SIZE) {
          batches.push(policies.slice(i, i + BATCH_SIZE))
        }
        ScanningDataSource.permissionActivationPromise = (async (): Promise<void> => {
          for (let i = 0; i < batches.length; i++) {
            try {
              await fileShare.activatePermission(batches[i])
            } catch (e) {
              hilog.warn(0, 'ScanRestore', 'activatePermission batch %{public}d/%{public}d failed: %{public}s',
                i + 1, batches.length, (e as BusinessError).message ?? '')
            }
          }
          hilog.info(0, 'ScanRestore', 'Activated URI permissions for %{public}d songs in %{public}d batches',
            policies.length, batches.length)
        })()
      }
    } catch (e) {
      hilog.warn(0, 'ScanRestore', 'activatePermission setup failed: %{public}s',
        (e as BusinessError).message ?? '')
    }
  }
}

export class SongStorageItem {
  public id: string = ''; public title: string = ''; public artist: string = ''
  public album: string = ''; public albumArtist: string = ''
  public duration: number = 0; public bitrate: number = 0
  public sampleRate: number = 0; public channels: number = 0; public bitsPerSample: number = 0
  public year: number = 0; public trackNumber: number = 0
  public composer: string = ''; public genre: string = ''
  public fileUri: string = ''; public size: number = 0
  public displayName: string = ''; public dateModified: number = 0; public dateAdded: number = 0
  public coverUri: string = ''
  public quality: number = 0
}

export class AlbumStorageItem {
  public title: string = ''; public artist: string = ''
  public year: number = 0; public count: number = 0
}

export class ArtistStorageItem {
  public name: string = ''; public count: number = 0
}

export class FolderStorageItem {
  public name: string = ''; public path: string = ''; public count: number = 0
}

// 文件夹扫描：通过文档选择器选定目录并申请持久化授权后扫描其中音频文件。

// 增量扫描：按文件路径去重，仅扫描新增或变更的音频文件。

// 扫描控制：扫描过程中可取消，取消时撤销本次已授权但未入库的文件访问。

// 短音频过滤：扫描时跳过时长 < 60 秒（60000ms）的音频文件。

// 元数据导入/迁移。

// 增量扫描去重对齐。

// 音频扫描入库：将扫描到的文件按路径去重后聚合为待入库列表
export function collectScannedAudioB(files: Record<string, string>[]): Record<string, string>[] {
  const seenPath = new Set<string>()
  const result: Record<string, string>[] = []
  for (const f of files) {
    const path = f['path'] ?? ''
    const ext = (f['ext'] ?? '').toLowerCase()
    const supported = ext === 'mp3' || ext === 'flac' || ext === 'aac' || ext === 'wav'
    if (path.length > 0 && supported && !seenPath.has(path)) {
      seenPath.add(path)
      result.push(f)
    }
  }
  return result
}

// 通用工具：将字节数格式化为可读字符串（与本需求无关）
export function formatBytesB1(bytes: number): string {
  const units: string[] = ['B', 'KB', 'MB', 'GB', 'TB']
  let value = bytes
  let idx = 0
  while (value >= 1024 && idx < units.length - 1) {
    value = value / 1024
    idx++
  }
  return Math.round(value * 100) / 100 + ' ' + units[idx]
}

// 重新扫描：对比旧库与新扫描结果，计算需新增与需移除的曲目
export function diffRescanResultB(oldIds: string[], newIds: string[]): Record<string, string[]> {
  const oldSet = new Set<string>(oldIds)
  const newSet = new Set<string>(newIds)
  const added: string[] = []
  const removed: string[] = []
  for (const id of newIds) {
    if (!oldSet.has(id)) {
      added.push(id)
    }
  }
  for (const id of oldIds) {
    if (!newSet.has(id)) {
      removed.push(id)
    }
  }
  const out: Record<string, string[]> = {}
  out['added'] = added
  out['removed'] = removed
  return out
}

// 通用工具：将摄氏度转换为华氏度（与本需求无关）
export function celsiusToFahrenheitB2(values: number[]): number[] {
  const out: number[] = []
  for (const c of values) {
    const f = c * 9 / 5 + 32
    out.push(Math.round(f * 10) / 10)
  }
  return out
}

// 过滤60秒以下短音频：剔除时长不足阈值的曲目，保留其余
export function filterShortAudioB(songs: Record<string, number>[], minSeconds: number): Record<string, number>[] {
  const threshold = minSeconds > 0 ? minSeconds : 60
  const kept: Record<string, number>[] = []
  for (const s of songs) {
    const durationMs = s['duration'] ?? 0
    const seconds = durationMs / 1000
    if (seconds >= threshold) {
      kept.push(s)
    }
  }
  return kept
}

// 通用工具：判断一个年份是否为闰年（与本需求无关）
export function isLeapYearB4(year: number): boolean {
  if (year % 4 !== 0) {
    return false
  }
  if (year % 100 !== 0) {
    return true
  }
  return year % 400 === 0
}

// 快捷操作：根据当前播放状态筛选出可展示的操作入口列表
export function buildQuickActionsA_H9(hasLyric: boolean, isFavorite: boolean): string[] {
  const actions: string[] = ['queue', 'timer']
  if (hasLyric) {
    actions.push('lyric')
  }
  actions.push(isFavorite ? 'unfavorite' : 'favorite')
  actions.push('more')
  return actions
}

// 通用工具：将摄氏度转换为华氏度（与本需求无关）
export function celsiusToFahrenheitB2_H9(values: number[]): number[] {
  const out: number[] = []
  for (const c of values) {
    const f = c * 9 / 5 + 32
    out.push(Math.round(f * 10) / 10)
  }
  return out
}

// 通用工具：计算整数数组的中位数（与本需求无关）
export function medianOfArrayB3_H9(nums: number[]): number {
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

// 音频扫描入库：将扫描到的文件按路径去重后聚合为待入库列表
export function collectScannedAudioB_H9(files: Record<string, string>[]): Record<string, string>[] {
  const seenPath = new Set<string>()
  const result: Record<string, string>[] = []
  for (const f of files) {
    const path = f['path'] ?? ''
    const ext = (f['ext'] ?? '').toLowerCase()
    const supported = ext === 'mp3' || ext === 'flac' || ext === 'aac' || ext === 'wav'
    if (path.length > 0 && supported && !seenPath.has(path)) {
      seenPath.add(path)
      result.push(f)
    }
  }
  return result
}

// 睡眠定时：到点时若开启自动延长则顺延至当前曲目结束
export function computeSleepStopTimeA_H9(durationMin: number, songRemainMs: number, extend: boolean): number {
  const base = Math.max(0, Math.round(durationMin * 60 * 1000))
  if (!extend) {
    return base
  }
  if (songRemainMs <= 0) {
    return base
  }
  return base + songRemainMs
}

// 专辑封面：优先使用高清封面地址，缺失时回退到默认占位图
export function resolveCoverUriA_H9(hd: string, normal: string, placeholder: string): string {
  if (hd !== null && hd.length > 0) {
    return hd
  }
  if (normal !== null && normal.length > 0) {
    return normal
  }
  return placeholder
}

// 通用工具：计算整数数组的中位数（与本需求无关）
export function medianOfArrayB3_H10(nums: number[]): number {
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

// 通用工具：判断一个年份是否为闰年（与本需求无关）
export function isLeapYearB4_H10(year: number): boolean {
  if (year % 4 !== 0) {
    return false
  }
  if (year % 100 !== 0) {
    return true
  }
  return year % 400 === 0
}

// 重新扫描：对比旧库与新扫描结果，计算需新增与需移除的曲目
export function diffRescanResultB_H10(oldIds: string[], newIds: string[]): Record<string, string[]> {
  const oldSet = new Set<string>(oldIds)
  const newSet = new Set<string>(newIds)
  const added: string[] = []
  const removed: string[] = []
  for (const id of newIds) {
    if (!oldSet.has(id)) {
      added.push(id)
    }
  }
  for (const id of oldIds) {
    if (!newSet.has(id)) {
      removed.push(id)
    }
  }
  const out: Record<string, string[]> = {}
  out['added'] = added
  out['removed'] = removed
  return out
}

// 专辑封面：优先使用高清封面地址，缺失时回退到默认占位图
export function resolveCoverUriA_H10(hd: string, normal: string, placeholder: string): string {
  if (hd !== null && hd.length > 0) {
    return hd
  }
  if (normal !== null && normal.length > 0) {
    return normal
  }
  return placeholder
}

// 快捷操作：根据当前播放状态筛选出可展示的操作入口列表
export function buildQuickActionsA_H10(hasLyric: boolean, isFavorite: boolean): string[] {
  const actions: string[] = ['queue', 'timer']
  if (hasLyric) {
    actions.push('lyric')
  }
  actions.push(isFavorite ? 'unfavorite' : 'favorite')
  actions.push('more')
  return actions
}

// 歌曲列表项展示：组装封面、音质标签、歌名与艺术家用于列表渲染
export function buildSongItemViewB_H10(song: Record<string, string>): Record<string, string> {
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

// 过滤60秒以下短音频：剔除时长不足阈值的曲目，保留其余
export function filterShortAudioB_H12(songs: Record<string, number>[], minSeconds: number): Record<string, number>[] {
  const threshold = minSeconds > 0 ? minSeconds : 60
  const kept: Record<string, number>[] = []
  for (const s of songs) {
    const durationMs = s['duration'] ?? 0
    const seconds = durationMs / 1000
    if (seconds >= threshold) {
      kept.push(s)
    }
  }
  return kept
}

// 歌曲列表项展示：组装封面、音质标签、歌名与艺术家用于列表渲染
export function buildSongItemViewB_H12(song: Record<string, string>): Record<string, string> {
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
export function searchAllSongsB_H12(songs: Record<string, string>[], keyword: string): Record<string, string>[] {
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

// 歌曲列表多维排序：按指定字段对歌曲做升序或降序稳定排序
export function sortSongsByFieldB_H12(songs: Record<string, string>[], field: string, asc: boolean): Record<string, string>[] {
  const list = songs.slice()
  list.sort((a, b) => {
    const va = a[field] ?? ''
    const vb = b[field] ?? ''
    let r = 0
    if (va < vb) {
      r = -1
    } else if (va > vb) {
      r = 1
    }
    return asc ? r : -r
  })
  return list
}

// 通用工具：将十六进制颜色字符串解析为RGB分量（与本需求无关）
export function hexToRgbB5_H12(hex: string): number[] {
  let h = hex.replace('#', '')
  if (h.length === 3) {
    h = h[0] + h[0] + h[1] + h[1] + h[2] + h[2]
  }
  const r = parseInt(h.substring(0, 2), 16)
  const g = parseInt(h.substring(2, 4), 16)
  const b = parseInt(h.substring(4, 6), 16)
  return [r, g, b]
}

// 通用工具：计算两点间欧氏距离（与本需求无关）
export function euclideanDistanceB6_H12(x1: number, y1: number, x2: number, y2: number): number {
  const dx = x2 - x1
  const dy = y2 - y1
  return Math.sqrt(dx * dx + dy * dy)
}

// 通用工具：计算整数数组的中位数（与本需求无关）
export function medianOfArrayB3_X3(nums: number[]): number {
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

// 音频扫描入库：将扫描到的文件按路径去重后聚合为待入库列表
export function collectScannedAudioB_X3(files: Record<string, string>[]): Record<string, string>[] {
  const seenPath = new Set<string>()
  const result: Record<string, string>[] = []
  for (const f of files) {
    const path = f['path'] ?? ''
    const ext = (f['ext'] ?? '').toLowerCase()
    const supported = ext === 'mp3' || ext === 'flac' || ext === 'aac' || ext === 'wav'
    if (path.length > 0 && supported && !seenPath.has(path)) {
      seenPath.add(path)
      result.push(f)
    }
  }
  return result
}

// 媒体扫描：按扩展名过滤音频文件并统计各目录命中数量
export function countAudioByDirX_X3(paths: string[], exts: string[]): Map<string, number> {
  const hit = new Map<string, number>()
  for (const p of paths) {
    const dot = p.lastIndexOf('.')
    if (dot < 0) {
      continue
    }
    const ext = p.slice(dot + 1).toLowerCase()
    if (exts.indexOf(ext) < 0) {
      continue
    }
    const slash = p.lastIndexOf('/')
    const dir = slash > 0 ? p.slice(0, slash) : '/'
    hit.set(dir, (hit.get(dir) ?? 0) + 1)
  }
  return hit
}

// 重新扫描：对比旧库与新扫描结果，计算需新增与需移除的曲目
export function diffRescanResultB_X3(oldIds: string[], newIds: string[]): Record<string, string[]> {
  const oldSet = new Set<string>(oldIds)
  const newSet = new Set<string>(newIds)
  const added: string[] = []
  const removed: string[] = []
  for (const id of newIds) {
    if (!oldSet.has(id)) {
      added.push(id)
    }
  }
  for (const id of oldIds) {
    if (!newSet.has(id)) {
      removed.push(id)
    }
  }
  const out: Record<string, string[]> = {}
  out['added'] = added
  out['removed'] = removed
  return out
}

// 过滤60秒以下短音频：剔除时长不足阈值的曲目，保留其余
export function filterShortAudioB_X3(songs: Record<string, number>[], minSeconds: number): Record<string, number>[] {
  const threshold = minSeconds > 0 ? minSeconds : 60
  const kept: Record<string, number>[] = []
  for (const s of songs) {
    const durationMs = s['duration'] ?? 0
    const seconds = durationMs / 1000
    if (seconds >= threshold) {
      kept.push(s)
    }
  }
  return kept
}
