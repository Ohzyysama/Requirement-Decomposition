// MusicDatabase.ets
// Model layer: RDB-based persistence for music library data.
// Tables: Track, Album, Artist, TrackArtist, Folder, Playlist, PlaylistTrack
// Follows the same init/ensureReady pattern as CoverCacheDb.

import { relationalStore } from '@kit.ArkData'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { Guqin } from './Guqin'
import AudioPlayerService from './AudioPlayerService'
import { ScanningDataSource, revokeFilePermissions } from './ScanningModel'
import { CoverCacheDb } from './CoverCacheDb'
import { MiniLyricsController } from './MiniLyricsController'
import { canonicalizePath } from './PathCodec'
import { SongInfoData } from './SongItemModel'

interface ArtistAggInfo {
  count: number
  coverSongId: string
  coverUri: string
}

const TAG = 'MusicDatabase'
const DB_NAME = 'music_library.db'

const SQL_CREATE_TRACK = `CREATE TABLE IF NOT EXISTS Track (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL DEFAULT '',
  artist TEXT NOT NULL DEFAULT '',
  album TEXT NOT NULL DEFAULT '',
  albumArtist TEXT NOT NULL DEFAULT '',
  genre TEXT NOT NULL DEFAULT '',
  year INTEGER NOT NULL DEFAULT 0,
  number INTEGER NOT NULL DEFAULT 0,
  isFavorite INTEGER NOT NULL DEFAULT 0,
  playCount INTEGER NOT NULL DEFAULT 0,
  trackOrder INTEGER NOT NULL DEFAULT 0,
  path TEXT NOT NULL DEFAULT '' UNIQUE,
  readable INTEGER NOT NULL DEFAULT 1,
  size INTEGER NOT NULL DEFAULT 0,
  addedTime INTEGER NOT NULL DEFAULT 0,
  modifiedTime INTEGER NOT NULL DEFAULT 0,
  duration INTEGER NOT NULL DEFAULT 0,
  bitsPerSample INTEGER NOT NULL DEFAULT 0,
  sampleRate INTEGER NOT NULL DEFAULT 0,
  channels INTEGER NOT NULL DEFAULT 0,
  bitrate REAL NOT NULL DEFAULT 0,
  fileUri TEXT NOT NULL DEFAULT '',
  coverUri TEXT NOT NULL DEFAULT '',
  displayName TEXT NOT NULL DEFAULT '',
  mimeType TEXT NOT NULL DEFAULT '',
  composer TEXT NOT NULL DEFAULT '',
  quality INTEGER NOT NULL DEFAULT 0,
  qualityClassified INTEGER NOT NULL DEFAULT 0,
  replayGainDb TEXT NOT NULL DEFAULT ''
)`

const SQL_CREATE_ALBUM = `CREATE TABLE IF NOT EXISTS Album (
  title TEXT NOT NULL DEFAULT '',
  artist TEXT NOT NULL DEFAULT '',
  cover TEXT NOT NULL DEFAULT '',
  coverModifiedTime INTEGER NOT NULL DEFAULT 0,
  year INTEGER NOT NULL DEFAULT 0,
  about TEXT NOT NULL DEFAULT '',
  isFavorite INTEGER NOT NULL DEFAULT 0,
  trackCount INTEGER NOT NULL DEFAULT 0,
  coverSongId TEXT NOT NULL DEFAULT '',
  PRIMARY KEY (title, artist)
)`

const SQL_CREATE_ARTIST = `CREATE TABLE IF NOT EXISTS Artist (
  name TEXT PRIMARY KEY,
  isAlbumArtist INTEGER NOT NULL DEFAULT 0,
  cover TEXT NOT NULL DEFAULT '',
  coverModifiedTime INTEGER NOT NULL DEFAULT 0,
  about TEXT NOT NULL DEFAULT '',
  website TEXT NOT NULL DEFAULT '',
  isFavorite INTEGER NOT NULL DEFAULT 0,
  isUserEdited INTEGER NOT NULL DEFAULT 0,
  coverSongId TEXT NOT NULL DEFAULT ''
)`

const SQL_CREATE_TRACK_ARTIST = `CREATE TABLE IF NOT EXISTS TrackArtist (
  trackId TEXT NOT NULL,
  artist TEXT NOT NULL,
  isAlbumArtist INTEGER NOT NULL DEFAULT 0,
  isPerformingArtist INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (trackId, artist)
)`

const SQL_CREATE_FOLDER = `CREATE TABLE IF NOT EXISTS Folder (
  vri TEXT PRIMARY KEY,
  addedTime INTEGER NOT NULL DEFAULT 0,
  isActive INTEGER NOT NULL DEFAULT 1
)`

const SQL_CREATE_PLAYLIST = `CREATE TABLE IF NOT EXISTS Playlist (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL DEFAULT '',
  coverModifiedTime INTEGER NOT NULL DEFAULT 0,
  isUserEditedCover INTEGER NOT NULL DEFAULT 0,
  description TEXT NOT NULL DEFAULT '',
  createdTime INTEGER NOT NULL DEFAULT 0,
  playlistOrder INTEGER NOT NULL DEFAULT 0,
  trackSort INTEGER NOT NULL DEFAULT 0,
  trackSortDescending INTEGER NOT NULL DEFAULT 0
)`

const SQL_CREATE_PLAYLIST_TRACK = `CREATE TABLE IF NOT EXISTS PlaylistTrack (
  playlistId TEXT NOT NULL,
  trackId TEXT NOT NULL,
  addedTime INTEGER NOT NULL DEFAULT 0,
  trackOrder INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (playlistId, trackId)
)`

// Index for faster lookups
const SQL_CREATE_INDICES: string[] = [
  'CREATE INDEX IF NOT EXISTS idx_track_album ON Track(album, albumArtist)',
  'CREATE INDEX IF NOT EXISTS idx_track_artist ON Track(artist)',
  'CREATE INDEX IF NOT EXISTS idx_track_path ON Track(path)',
  'CREATE INDEX IF NOT EXISTS idx_trackartist_track ON TrackArtist(trackId)',
  'CREATE INDEX IF NOT EXISTS idx_trackartist_artist ON TrackArtist(artist)',
  'CREATE INDEX IF NOT EXISTS idx_playlisttrack_playlist ON PlaylistTrack(playlistId)',
  'CREATE INDEX IF NOT EXISTS idx_playlisttrack_track ON PlaylistTrack(trackId)'
]

// Used by updateTracksMetadata for batch metadata updates
export interface TrackMetadataUpdate {
  id: string
  bucket: relationalStore.ValuesBucket
}

// TrackRow used for insert/query results
export interface TrackRow {
  id: string
  title: string
  artist: string
  album: string
  albumArtist: string
  genre: string
  year: number
  number: number
  isFavorite: boolean
  playCount: number
  trackOrder: number
  path: string
  readable: boolean
  size: number
  addedTime: number
  modifiedTime: number
  duration: number
  bitsPerSample: number
  sampleRate: number
  channels: number
  bitrate: number
  fileUri: string
  coverUri: string
  displayName: string
  mimeType: string
  composer: string
  quality: number
  // Whether `quality` is the result of computeSongQuality() (true) or still
  // the schema-default 0 (false). Lets the music-library backfill tell
  // legitimate NORMAL tracks apart from tracks scanned before the column
  // existed, so it only re-classifies the latter.
  qualityClassified: boolean
  // spec14: ReplayGain volume balance tag value (e.g. "-3.5 dB"), empty if not present
  replayGainDb: string
}

export interface AlbumRow {
  title: string
  artist: string
  cover: string
  coverModifiedTime: number
  year: number
  about: string
  isFavorite: boolean
  trackCount: number
  coverSongId: string
}

export interface ArtistRow {
  name: string
  isAlbumArtist: boolean
  cover: string
  coverModifiedTime: number
  about: string
  website: string
  isFavorite: boolean
  isUserEdited: boolean
  coverSongId: string
}

// Aggregate statistics returned by MusicDatabase.getMusicLibraryAggregate().
// Pulled in a single SQL roundtrip so the Music Library page renders the
// authoritative DB numbers without a JS-side iteration.
export interface MusicLibraryAggregate {
  totalSize: number
  totalCount: number
  hq: number
  sq: number
  hr: number
  others: number
}

// Minimal Track projection used by getTracksMissingSize() — just the two
// columns the size-recovery path needs (avoid pulling 25 unused columns).
export interface TrackSizeMissing {
  id: string
  fileUri: string
}

// Minimal projection used by getTracksMissingQuality() — only the columns
// computeSongQuality() needs to classify a track from already-persisted
// metadata. Avoids round-tripping every Track field for the backfill.
export interface TrackQualityMissing {
  id: string
  displayName: string
  path: string
  sampleRate: number
  bitsPerSample: number
  bitrate: number
}

// Per-id quality update payload used by updateTrackQualities().
export interface TrackQualityUpdate {
  id: string
  quality: number
}

// PlaylistTrackRow extends TrackRow with the per-playlist PlaylistTrack.addedTime
// (distinct from Track.addedTime which is the library import time). Only set by
// getPlaylistSongs — other TrackRow callers don't need this field.
export interface PlaylistTrackRow extends TrackRow {
  playlistAddedTime: number
}

// PlaylistRow used for insert/query against the Playlist table
export interface PlaylistRow {
  id: string
  title: string
  coverModifiedTime: number
  isUserEditedCover: boolean
  description: string
  createdTime: number
  playlistOrder: number
  trackSort: number
  trackSortDescending: boolean
}

// Used by updatePlaylistOrders to normalise order indexes
export interface PlaylistOrderUpdate {
  id: string
  order: number
}

// Return payload of insertPlaylistTracks. `lastCoverSongId` is the trackId that
// received the largest per-playlist addedTime in the batch — its cover becomes
// the playlist cover per spec5 S1.5/S2.5/...
export interface InsertPlaylistTracksResult {
  insertedCount: number
  lastCoverSongId: string
}

// Return payload of getPlaylistSort — kept as an interface (not a tuple) so the
// ArkTS 1.2 compiler can infer the shape across async boundaries.
export interface PlaylistSortState {
  sortType: number
  descending: boolean
}

export class MusicDatabase {
  private static rdbStore: relationalStore.RdbStore | null = null
  private static initPromise: Promise<void> | null = null

  static init(context: Context): void {
    if (MusicDatabase.initPromise) return
    MusicDatabase.initPromise = MusicDatabase.doInit(context)
  }

  private static async doInit(context: Context): Promise<void> {
    try {
      const config: relationalStore.StoreConfig = {
        name: DB_NAME,
        securityLevel: relationalStore.SecurityLevel.S1
      }
      MusicDatabase.rdbStore = await relationalStore.getRdbStore(context, config)
      await MusicDatabase.rdbStore.executeSql(SQL_CREATE_TRACK)
      await MusicDatabase.rdbStore.executeSql(SQL_CREATE_ALBUM)
      await MusicDatabase.rdbStore.executeSql(SQL_CREATE_ARTIST)
      await MusicDatabase.rdbStore.executeSql(SQL_CREATE_TRACK_ARTIST)
      await MusicDatabase.rdbStore.executeSql(SQL_CREATE_FOLDER)
      await MusicDatabase.rdbStore.executeSql(SQL_CREATE_PLAYLIST)
      await MusicDatabase.rdbStore.executeSql(SQL_CREATE_PLAYLIST_TRACK)
      for (const sql of SQL_CREATE_INDICES) {
        await MusicDatabase.rdbStore.executeSql(sql)
      }
      try {
        await MusicDatabase.rdbStore.executeSql(
          "ALTER TABLE Track ADD COLUMN channels INTEGER NOT NULL DEFAULT 0"
        )
      } catch (_ignored) {
      }
      try {
        await MusicDatabase.rdbStore.executeSql(
          "ALTER TABLE Track ADD COLUMN quality INTEGER NOT NULL DEFAULT 0"
        )
      } catch (_ignored) {
      }
      try {
        await MusicDatabase.rdbStore.executeSql(
          "ALTER TABLE Track ADD COLUMN qualityClassified INTEGER NOT NULL DEFAULT 0"
        )
      } catch (_ignored) {
      }
      try {
        await MusicDatabase.rdbStore.executeSql(
          "ALTER TABLE Track ADD COLUMN replayGainDb TEXT NOT NULL DEFAULT ''"
        )
      } catch (_ignored) {
      }
      hilog.info(0, TAG, 'Music database initialized')
    } catch (e) {
      hilog.error(0, TAG, 'init failed: %{public}s', (e as Error).message)
    }
  }

  static async ensureReady(): Promise<boolean> {
    if (MusicDatabase.initPromise) {
      await MusicDatabase.initPromise
    }
    return MusicDatabase.rdbStore !== null
  }

  // --- Track CRUD ---

  // Get all existing fileUri and path values (for dedup during incremental scan)
  static async getAllTrackPaths(): Promise<Set<string>> {
    if (!(await MusicDatabase.ensureReady())) return new Set()
    try {
      const predicates = new relationalStore.RdbPredicates('Track')
      const resultSet = await MusicDatabase.rdbStore!.query(predicates, ['path', 'fileUri'])
      const paths = new Set<string>()
      while (resultSet.goToNextRow()) {
        paths.add(resultSet.getString(resultSet.getColumnIndex('path')))
        const fileUri = resultSet.getString(resultSet.getColumnIndex('fileUri'))
        if (fileUri.length > 0) {
          paths.add(fileUri)
        }
      }
      resultSet.close()
      return paths
    } catch (e) {
      hilog.error(0, TAG, 'getAllTrackPaths failed: %{public}s', (e as Error).message)
      return new Set()
    }
  }

  // Insert multiple tracks, skip duplicates by path (INSERT OR IGNORE)
  static async insertTracks(tracks: TrackRow[]): Promise<number> {
    if (!(await MusicDatabase.ensureReady())) return 0
    let inserted = 0
    try {
      MusicDatabase.rdbStore!.beginTransaction()
      for (const t of tracks) {
        const bucket: relationalStore.ValuesBucket = {
          'id': t.id,
          'title': t.title,
          'artist': t.artist,
          'album': t.album,
          'albumArtist': t.albumArtist,
          'genre': t.genre,
          'year': t.year,
          'number': t.number,
          'isFavorite': t.isFavorite ? 1 : 0,
          'playCount': t.playCount,
          'trackOrder': t.trackOrder,
          'path': t.path,
          'readable': t.readable ? 1 : 0,
          'size': t.size,
          'addedTime': t.addedTime,
          'modifiedTime': t.modifiedTime,
          'duration': t.duration,
          'bitsPerSample': t.bitsPerSample,
          'sampleRate': t.sampleRate,
          'channels': t.channels,
          'bitrate': t.bitrate,
          'fileUri': t.fileUri,
          'coverUri': t.coverUri,
          'displayName': t.displayName,
          'mimeType': t.mimeType,
          'composer': t.composer,
          'quality': t.quality,
          'qualityClassified': t.qualityClassified ? 1 : 0,
          'replayGainDb': t.replayGainDb ?? ''
        }
        try {
          await MusicDatabase.rdbStore!.insert('Track', bucket,
            relationalStore.ConflictResolution.ON_CONFLICT_IGNORE)
          inserted++
        } catch (_dupErr) {
          // duplicate path, skip
        }
      }
      MusicDatabase.rdbStore!.commit()
    } catch (e) {
      try { MusicDatabase.rdbStore!.rollBack() } catch (_rb) { /* ignore */ }
      hilog.error(0, TAG, 'insertTracks failed: %{public}s', (e as Error).message)
    }
    hilog.info(0, TAG, 'insertTracks: %{public}d of %{public}d inserted', inserted, tracks.length)
    return inserted
  }

  // Aggregated Music Library statistics for the Music Library page.
  // Replaces the per-row TS iteration with a single SQL aggregate so we
  // pull the authoritative numbers directly out of the Track table — no
  // JS-side accumulation that can hide a column-read bug behind 0.
  // Returns zeroes (not null) on failure so the caller can still render.
  static async getMusicLibraryAggregate(): Promise<MusicLibraryAggregate> {
    const empty: MusicLibraryAggregate = {
      totalSize: 0, totalCount: 0, hq: 0, sq: 0, hr: 0, others: 0
    }
    if (!(await MusicDatabase.ensureReady())) return empty
    let resultSet: relationalStore.ResultSet | null = null
    try {
      const sql = `SELECT
        COALESCE(SUM(size), 0) AS totalSize,
        COUNT(*) AS totalCount,
        SUM(CASE WHEN quality = 1 THEN 1 ELSE 0 END) AS hq,
        SUM(CASE WHEN quality = 2 THEN 1 ELSE 0 END) AS sq,
        SUM(CASE WHEN quality = 3 THEN 1 ELSE 0 END) AS hr,
        SUM(CASE WHEN quality NOT IN (1, 2, 3) THEN 1 ELSE 0 END) AS others
        FROM Track`
      resultSet = await MusicDatabase.rdbStore!.querySql(sql)
      if (!resultSet.goToFirstRow()) return empty
      const out: MusicLibraryAggregate = {
        totalSize: resultSet.getLong(resultSet.getColumnIndex('totalSize')),
        totalCount: resultSet.getLong(resultSet.getColumnIndex('totalCount')),
        hq: resultSet.getLong(resultSet.getColumnIndex('hq')),
        sq: resultSet.getLong(resultSet.getColumnIndex('sq')),
        hr: resultSet.getLong(resultSet.getColumnIndex('hr')),
        others: resultSet.getLong(resultSet.getColumnIndex('others'))
      }
      hilog.info(0, TAG,
        'getMusicLibraryAggregate: count=%{public}d totalSize=%{public}d hq=%{public}d sq=%{public}d hr=%{public}d others=%{public}d',
        out.totalCount, out.totalSize, out.hq, out.sq, out.hr, out.others)
      return out
    } catch (e) {
      hilog.error(0, TAG, 'getMusicLibraryAggregate failed: %{public}s', (e as Error).message)
      return empty
    } finally {
      if (resultSet !== null) {
        try { resultSet.close() } catch (_e) { /* ignore */ }
      }
    }
  }

  // Read every track that has size <= 0, so the Music Library page can
  // recover real sizes via fileIo.stat. Cheaper than getAllTracks because
  // we only project the two columns the recovery path actually needs.
  static async getTracksMissingSize(): Promise<TrackSizeMissing[]> {
    if (!(await MusicDatabase.ensureReady())) return []
    let resultSet: relationalStore.ResultSet | null = null
    try {
      resultSet = await MusicDatabase.rdbStore!.querySql(
        "SELECT id, fileUri FROM Track WHERE size <= 0 AND fileUri != ''")
      const out: TrackSizeMissing[] = []
      while (resultSet.goToNextRow()) {
        out.push({
          id: resultSet.getString(resultSet.getColumnIndex('id')),
          fileUri: resultSet.getString(resultSet.getColumnIndex('fileUri'))
        })
      }
      return out
    } catch (e) {
      hilog.error(0, TAG, 'getTracksMissingSize failed: %{public}s', (e as Error).message)
      return []
    } finally {
      if (resultSet !== null) {
        try { resultSet.close() } catch (_e) { /* ignore */ }
      }
    }
  }

  // Best-effort batch write of recovered file sizes. Used by the music
  // library page when the persisted Track.size is 0 and we had to stat the
  // file to recover a real value — writing back here means subsequent loads
  // take the fast DB path. Skips zero entries; transaction-wrapped; failures
  // are logged and swallowed so a write error never blocks the UI.
  static async updateTrackSizes(ids: string[], sizes: number[]): Promise<void> {
    if (ids.length === 0 || ids.length !== sizes.length) return
    if (!(await MusicDatabase.ensureReady())) return
    try {
      MusicDatabase.rdbStore!.beginTransaction()
      for (let i = 0; i < ids.length; i++) {
        if (sizes[i] <= 0) continue
        const pred = new relationalStore.RdbPredicates('Track')
        pred.equalTo('id', ids[i])
        const bucket: relationalStore.ValuesBucket = { 'size': sizes[i] }
        await MusicDatabase.rdbStore!.update(bucket, pred)
      }
      MusicDatabase.rdbStore!.commit()
    } catch (e) {
      try { MusicDatabase.rdbStore!.rollBack() } catch (_rb) { /* ignore */ }
      hilog.warn(0, TAG, 'updateTrackSizes failed: %{public}s', (e as Error).message)
    }
  }

  // Tracks whose `quality` column is still the schema default — i.e. they
  // were inserted before computeSongQuality() ran on them (either before
  // the column was added, or via the Preferences migration). The Music
  // Library page reclassifies these from existing metadata so HQ/SQ/HR/Others
  // counts no longer hide behind a column of zeros.
  static async getTracksMissingQuality(): Promise<TrackQualityMissing[]> {
    if (!(await MusicDatabase.ensureReady())) return []
    let resultSet: relationalStore.ResultSet | null = null
    try {
      resultSet = await MusicDatabase.rdbStore!.querySql(
        "SELECT id, displayName, path, sampleRate, bitsPerSample, bitrate " +
        "FROM Track WHERE qualityClassified = 0")
      const out: TrackQualityMissing[] = []
      while (resultSet.goToNextRow()) {
        out.push({
          id: resultSet.getString(resultSet.getColumnIndex('id')),
          displayName: resultSet.getString(resultSet.getColumnIndex('displayName')),
          path: resultSet.getString(resultSet.getColumnIndex('path')),
          sampleRate: resultSet.getLong(resultSet.getColumnIndex('sampleRate')),
          bitsPerSample: resultSet.getLong(resultSet.getColumnIndex('bitsPerSample')),
          bitrate: resultSet.getDouble(resultSet.getColumnIndex('bitrate'))
        })
      }
      return out
    } catch (e) {
      hilog.error(0, TAG, 'getTracksMissingQuality failed: %{public}s', (e as Error).message)
      return []
    } finally {
      if (resultSet !== null) {
        try { resultSet.close() } catch (_e) { /* ignore */ }
      }
    }
  }

  // Batch persist computed quality values and flip qualityClassified=1 so
  // the next page load skips these rows. Transaction-wrapped; failures are
  // logged and swallowed so a write hiccup never blocks the UI.
  static async updateTrackQualities(updates: TrackQualityUpdate[]): Promise<void> {
    if (updates.length === 0) return
    if (!(await MusicDatabase.ensureReady())) return
    try {
      MusicDatabase.rdbStore!.beginTransaction()
      for (const u of updates) {
        const pred = new relationalStore.RdbPredicates('Track')
        pred.equalTo('id', u.id)
        const bucket: relationalStore.ValuesBucket = {
          'quality': u.quality,
          'qualityClassified': 1
        }
        await MusicDatabase.rdbStore!.update(bucket, pred)
      }
      MusicDatabase.rdbStore!.commit()
    } catch (e) {
      try { MusicDatabase.rdbStore!.rollBack() } catch (_rb) { /* ignore */ }
      hilog.warn(0, TAG, 'updateTrackQualities failed: %{public}s', (e as Error).message)
    }
  }

  // Get all tracks
  static async getAllTracks(): Promise<TrackRow[]> {
    if (!(await MusicDatabase.ensureReady())) return []
    try {
      const predicates = new relationalStore.RdbPredicates('Track')
      const resultSet = await MusicDatabase.rdbStore!.query(predicates)
      const tracks: TrackRow[] = []
      while (resultSet.goToNextRow()) {
        tracks.push(MusicDatabase.readTrackRow(resultSet))
      }
      resultSet.close()
      return tracks
    } catch (e) {
      hilog.error(0, TAG, 'getAllTracks failed: %{public}s', (e as Error).message)
      return []
    }
  }

  // spec14 — Get the replayGainDb value for a single song id.
  // Fail-soft: returns empty string on any error.
  static async getReplayGainDb(songId: string): Promise<string> {
    if (!(await MusicDatabase.ensureReady())) return ''
    if (!songId || songId.length === 0) return ''
    let resultSet: relationalStore.ResultSet | null = null
    try {
      const sql = 'SELECT replayGainDb FROM Track WHERE id = ?'
      resultSet = await MusicDatabase.rdbStore!.querySql(sql, [songId])
      if (resultSet.goToNextRow()) {
        return MusicDatabase.safeGetString(resultSet, 'replayGainDb')
      }
      return ''
    } catch (e) {
      hilog.error(0, TAG, 'getReplayGainDb failed: %{public}s', (e as Error).message)
      return ''
    } finally {
      if (resultSet !== null) {
        try { resultSet.close() } catch (_e) { /* ignore */ }
      }
    }
  }

  // spec21 — Increment Track.playCount for a single song id. Used by the
  // AudioPlayerService play-count gate (60s / 90% of duration threshold).
  // Fail-soft: errors are logged and swallowed so playback is not disrupted.
  static async incrementTrackPlayCount(songId: string): Promise<void> {
    if (!(await MusicDatabase.ensureReady())) return
    if (!songId || songId.length === 0) return
    try {
      MusicDatabase.rdbStore!.beginTransaction()
      await MusicDatabase.rdbStore!.executeSql(
        'UPDATE Track SET playCount = playCount + 1 WHERE id = ?', [songId])
      MusicDatabase.rdbStore!.commit()
    } catch (e) {
      try { MusicDatabase.rdbStore!.rollBack() } catch (_rb) { /* ignore */ }
      hilog.error(0, TAG, 'incrementTrackPlayCount failed: %{public}s', (e as Error).message)
    }
  }

  // spec21 — Top 100 most-played tracks, playCount >= 1, DESC. Ties broken by
  // most-recently-added. Fail-soft: on error returns [].
  static async getListenMusicRankTop100(): Promise<TrackRow[]> {
    if (!(await MusicDatabase.ensureReady())) return []
    try {
      const sql = `SELECT id, title, artist, album, albumArtist, genre, year, number,
        isFavorite, playCount, trackOrder, path, readable, size, addedTime, modifiedTime,
        duration, bitsPerSample, sampleRate, channels, bitrate, fileUri, coverUri,
        displayName, mimeType, composer, quality, qualityClassified
        FROM Track WHERE playCount >= 1
        ORDER BY playCount DESC, addedTime DESC LIMIT 100`
      const rs = await MusicDatabase.rdbStore!.querySql(sql)
      const tracks: TrackRow[] = []
      while (rs.goToNextRow()) {
        tracks.push(MusicDatabase.readTrackRow(rs))
      }
      rs.close()
      return tracks
    } catch (e) {
      hilog.error(0, TAG, 'getListenMusicRankTop100 failed: %{public}s', (e as Error).message)
      return []
    }
  }

  // Get track count
  static async getTrackCount(): Promise<number> {
    if (!(await MusicDatabase.ensureReady())) return 0
    try {
      const predicates = new relationalStore.RdbPredicates('Track')
      const resultSet = await MusicDatabase.rdbStore!.query(predicates, ['id'])
      const count = resultSet.rowCount
      resultSet.close()
      return count
    } catch (_e) {
      return 0
    }
  }

  // Delete a track by path
  static async deleteTrackByPath(path: string): Promise<boolean> {
    if (!(await MusicDatabase.ensureReady())) return false
    try {
      const predicates = new relationalStore.RdbPredicates('Track')
      predicates.equalTo('path', path)
      const deleted = await MusicDatabase.rdbStore!.delete(predicates)
      return deleted > 0
    } catch (_e) {
      return false
    }
  }

  // Return trackIds for the given paths, preserving input order and dropping
  // entries with no matching Track row. Duplicate input paths are emitted
  // multiple times (each lookup is independent). Used by spec15 import-playlist
  // flow to resolve txt lines → track ids.
  //
  // Matching is done in CANONICAL form: both DB-stored paths and import-side
  // input lines are run through `canonicalizePath` (decodeURIComponent of all
  // percent-escapes) before comparison. This makes the lookup tolerant of
  // any percent-encoding variant the .txt happens to use — '&' as '&' or as
  // '%26', Chinese as literal or as '%E5%XX...', etc. The exact OS-side URI
  // encoding produced by DocumentViewPicker varies between HarmonyOS
  // versions, so reproducing it on the import side is fragile (this was the
  // root cause of the "%26 leak" import-failure bug). Matching on the
  // canonical form sidesteps that entirely.
  //
  // Performs a single full-table scan of Track.path. For typical libraries
  // (a few thousand rows) this is faster than chunked IN(...) lookups and
  // simpler. Fail-soft: on any error returns an empty array.
  static async getTrackIdsByPaths(paths: string[]): Promise<string[]> {
    if (!(await MusicDatabase.ensureReady())) return []
    if (paths.length === 0) return []
    try {
      const canonicalToId = new Map<string, string>()
      const pred = new relationalStore.RdbPredicates('Track')
      const rs = await MusicDatabase.rdbStore!.query(pred, ['id', 'path'])
      while (rs.goToNextRow()) {
        const dbPath = rs.getString(rs.getColumnIndex('path'))
        const id = rs.getString(rs.getColumnIndex('id'))
        if (dbPath.length > 0 && id.length > 0) {
          canonicalToId.set(canonicalizePath(dbPath), id)
        }
      }
      rs.close()
      const out: string[] = []
      for (const p of paths) {
        const key = canonicalizePath(p)
        const id = canonicalToId.get(key)
        if (id !== undefined && id.length > 0) {
          out.push(id)
        }
      }
      return out
    } catch (e) {
      hilog.error(0, TAG, 'getTrackIdsByPaths failed: %{public}s', (e as Error).message)
      return []
    }
  }

  // Batch-delete tracks by paths.
  // Uses chunked `WHERE path IN (...)` so a 2000-track multi-select removal
  // is one round-trip per CHUNK rather than one round-trip per row — the
  // per-row variant was the dominant cost behind the post-confirm UI stall.
  // CHUNK is 500 (well under SQLite's default 999 parameter limit).
  static async deleteTracksByPaths(paths: string[]): Promise<number> {
    if (!(await MusicDatabase.ensureReady())) return 0
    if (paths.length === 0) return 0
    let totalDeleted = 0
    try {
      const CHUNK = 500
      for (let i = 0; i < paths.length; i += CHUNK) {
        const slice = paths.slice(i, i + CHUNK)
        const predicates = new relationalStore.RdbPredicates('Track')
        predicates.in('path', slice)
        totalDeleted += await MusicDatabase.rdbStore!.delete(predicates)
      }
    } catch (e) {
      hilog.error(0, TAG, 'deleteTracksByPaths failed: %{public}s', (e as Error).message)
    }
    return totalDeleted
  }

  // Batch-update metadata fields for existing tracks (preserves isFavorite, playCount, trackOrder, addedTime)
  static async updateTracksMetadata(updates: TrackMetadataUpdate[]): Promise<number> {
    if (!(await MusicDatabase.ensureReady())) return 0
    if (updates.length === 0) return 0
    let updated = 0
    try {
      MusicDatabase.rdbStore!.beginTransaction()
      for (const entry of updates) {
        const predicates = new relationalStore.RdbPredicates('Track')
        predicates.equalTo('id', entry.id)
        const rows = await MusicDatabase.rdbStore!.update(entry.bucket, predicates)
        if (rows > 0) updated++
      }
      MusicDatabase.rdbStore!.commit()
    } catch (e) {
      try { MusicDatabase.rdbStore!.rollBack() } catch (_rb) { /* ignore */ }
      hilog.error(0, TAG, 'updateTracksMetadata failed: %{public}s', (e as Error).message)
    }
    hilog.info(0, TAG, 'updateTracksMetadata: %{public}d of %{public}d updated', updated, updates.length)
    return updated
  }

  // Defensive accessors used by readTrackRow so a Track row can still be
  // mapped to TrackRow when the on-disk schema is shaped slightly differently
  // from what the current code expects — e.g. an upgrade where doInit() hasn't
  // yet ALTERed in a newly added column, or a downgrade rolling back a column
  // the previous build added. Missing columns fall through to the schema's
  // CREATE TABLE default ('' for text, 0 for numerics) so the row reads as if
  // the column were present with its default value.
  private static safeGetString(rs: relationalStore.ResultSet, col: string): string {
    const idx = rs.getColumnIndex(col)
    if (idx < 0) return ''
    try { return rs.getString(idx) } catch (_e) { return '' }
  }

  private static safeGetLong(rs: relationalStore.ResultSet, col: string): number {
    const idx = rs.getColumnIndex(col)
    if (idx < 0) return 0
    try { return rs.getLong(idx) } catch (_e) { return 0 }
  }

  private static safeGetDouble(rs: relationalStore.ResultSet, col: string): number {
    const idx = rs.getColumnIndex(col)
    if (idx < 0) return 0
    try { return rs.getDouble(idx) } catch (_e) { return 0 }
  }

  private static readTrackRow(rs: relationalStore.ResultSet): TrackRow {
    return {
      id: MusicDatabase.safeGetString(rs, 'id'),
      title: MusicDatabase.safeGetString(rs, 'title'),
      artist: MusicDatabase.safeGetString(rs, 'artist'),
      album: MusicDatabase.safeGetString(rs, 'album'),
      albumArtist: MusicDatabase.safeGetString(rs, 'albumArtist'),
      genre: MusicDatabase.safeGetString(rs, 'genre'),
      year: MusicDatabase.safeGetLong(rs, 'year'),
      number: MusicDatabase.safeGetLong(rs, 'number'),
      isFavorite: MusicDatabase.safeGetLong(rs, 'isFavorite') !== 0,
      playCount: MusicDatabase.safeGetLong(rs, 'playCount'),
      trackOrder: MusicDatabase.safeGetLong(rs, 'trackOrder'),
      path: MusicDatabase.safeGetString(rs, 'path'),
      // readable defaults to true (schema default DEFAULT 1) when the column
      // is absent — otherwise an upgrade with no readable column would hide
      // every track from the UI as "unreadable".
      readable: rs.getColumnIndex('readable') < 0
        ? true
        : MusicDatabase.safeGetLong(rs, 'readable') !== 0,
      size: MusicDatabase.safeGetLong(rs, 'size'),
      addedTime: MusicDatabase.safeGetLong(rs, 'addedTime'),
      modifiedTime: MusicDatabase.safeGetLong(rs, 'modifiedTime'),
      duration: MusicDatabase.safeGetLong(rs, 'duration'),
      bitsPerSample: MusicDatabase.safeGetLong(rs, 'bitsPerSample'),
      sampleRate: MusicDatabase.safeGetLong(rs, 'sampleRate'),
      channels: MusicDatabase.safeGetLong(rs, 'channels'),
      bitrate: MusicDatabase.safeGetDouble(rs, 'bitrate'),
      fileUri: MusicDatabase.safeGetString(rs, 'fileUri'),
      coverUri: MusicDatabase.safeGetString(rs, 'coverUri'),
      displayName: MusicDatabase.safeGetString(rs, 'displayName'),
      mimeType: MusicDatabase.safeGetString(rs, 'mimeType'),
      composer: MusicDatabase.safeGetString(rs, 'composer'),
      quality: MusicDatabase.safeGetLong(rs, 'quality'),
      qualityClassified: MusicDatabase.safeGetLong(rs, 'qualityClassified') !== 0,
      replayGainDb: MusicDatabase.safeGetString(rs, 'replayGainDb')
    }
  }

  // --- Album/Artist aggregation from Track table ---

  // Rebuild Album and Artist tables from Track data
  static async refreshAlbumsAndArtists(): Promise<void> {
    if (!(await MusicDatabase.ensureReady())) return
    try {
      // --- Album rebuild (in transaction) ---
      const albumPred = new relationalStore.RdbPredicates('Album')
      await MusicDatabase.rdbStore!.delete(albumPred)

      const albumSql = `SELECT album, albumArtist, MIN(year) as year, COUNT(*) as cnt,
        MIN(id) as coverSongId, MIN(coverUri) as coverUri
        FROM Track WHERE album != '' GROUP BY album, albumArtist`
      const albumRs = await MusicDatabase.rdbStore!.querySql(albumSql)

      MusicDatabase.rdbStore!.beginTransaction()
      while (albumRs.goToNextRow()) {
        const bucket: relationalStore.ValuesBucket = {
          'title': albumRs.getString(albumRs.getColumnIndex('album')),
          'artist': albumRs.getString(albumRs.getColumnIndex('albumArtist')),
          'year': albumRs.getLong(albumRs.getColumnIndex('year')),
          'trackCount': albumRs.getLong(albumRs.getColumnIndex('cnt')),
          'coverSongId': albumRs.getString(albumRs.getColumnIndex('coverSongId')),
          'cover': albumRs.getString(albumRs.getColumnIndex('coverUri'))
        }
        await MusicDatabase.rdbStore!.insert('Album', bucket,
          relationalStore.ConflictResolution.ON_CONFLICT_REPLACE)
      }
      MusicDatabase.rdbStore!.commit()
      albumRs.close()

      // --- Artist rebuild (pre-load user-edited set to eliminate N+1) ---
      // One-shot query: collect all user-edited artist names
      const userEditedSet = new Set<string>()
      const editedRs = await MusicDatabase.rdbStore!.querySql(
        `SELECT name FROM Artist WHERE isUserEdited = 1`)
      while (editedRs.goToNextRow()) {
        userEditedSet.add(editedRs.getString(editedRs.getColumnIndex('name')))
      }
      editedRs.close()

      // Aggregate from Track table, split multi-artist strings via Guqin
      const artistSql = `SELECT artist, COUNT(*) as cnt, MIN(id) as coverSongId,
        MIN(coverUri) as coverUri
        FROM Track WHERE artist != '' GROUP BY artist`
      const artistRs = await MusicDatabase.rdbStore!.querySql(artistSql)

      const artistAggMap = new Map<string, ArtistAggInfo>()
      while (artistRs.goToNextRow()) {
        const rawName = artistRs.getString(artistRs.getColumnIndex('artist'))
        const cnt = artistRs.getLong(artistRs.getColumnIndex('cnt'))
        const coverSongId = artistRs.getString(artistRs.getColumnIndex('coverSongId'))
        const coverUri = artistRs.getString(artistRs.getColumnIndex('coverUri'))

        const splitNames: string[] = Guqin.getArtists(rawName)
        for (const artistName of splitNames) {
          if (artistName.length === 0) continue
          const existing = artistAggMap.get(artistName)
          if (existing) {
            existing.count += cnt
            if (existing.coverSongId.length === 0 && coverSongId.length > 0) {
              existing.coverSongId = coverSongId
            }
            if (existing.coverUri.length === 0 && coverUri.length > 0) {
              existing.coverUri = coverUri
              existing.coverSongId = coverSongId
            }
          } else {
            artistAggMap.set(artistName, { count: cnt, coverSongId: coverSongId, coverUri: coverUri } as ArtistAggInfo)
          }
        }
      }
      artistRs.close()

      // Batch insert/update artists in a single transaction
      const artistEntries: [string, ArtistAggInfo][] = Array.from(artistAggMap.entries())
      MusicDatabase.rdbStore!.beginTransaction()
      for (const entry of artistEntries) {
        const name = entry[0]
        const data = entry[1]

        if (userEditedSet.has(name)) {
          // Only update cover for user-edited artists (parameterized to avoid SQL injection)
          const updatePred = new relationalStore.RdbPredicates('Artist')
          updatePred.equalTo('name', name)
          const updateBucket: relationalStore.ValuesBucket = {
            'coverSongId': data.coverSongId
          }
          await MusicDatabase.rdbStore!.update(updateBucket, updatePred)
        } else {
          const bucket: relationalStore.ValuesBucket = {
            'name': name,
            'cover': data.coverUri,
            'coverSongId': data.coverSongId,
            'isFavorite': 0,
            'isUserEdited': 0
          }
          await MusicDatabase.rdbStore!.insert('Artist', bucket,
            relationalStore.ConflictResolution.ON_CONFLICT_REPLACE)
        }
      }
      MusicDatabase.rdbStore!.commit()

      hilog.info(0, TAG, 'refreshAlbumsAndArtists completed')
    } catch (e) {
      try { MusicDatabase.rdbStore!.rollBack() } catch (_rb) { /* ignore */ }
      hilog.error(0, TAG, 'refreshAlbumsAndArtists failed: %{public}s', (e as Error).message)
    }
  }

  // Get all albums
  static async getAllAlbums(): Promise<AlbumRow[]> {
    if (!(await MusicDatabase.ensureReady())) return []
    try {
      const predicates = new relationalStore.RdbPredicates('Album')
      const resultSet = await MusicDatabase.rdbStore!.query(predicates)
      const albums: AlbumRow[] = []
      while (resultSet.goToNextRow()) {
        albums.push({
          title: resultSet.getString(resultSet.getColumnIndex('title')),
          artist: resultSet.getString(resultSet.getColumnIndex('artist')),
          cover: resultSet.getString(resultSet.getColumnIndex('cover')),
          coverModifiedTime: resultSet.getLong(resultSet.getColumnIndex('coverModifiedTime')),
          year: resultSet.getLong(resultSet.getColumnIndex('year')),
          about: resultSet.getString(resultSet.getColumnIndex('about')),
          isFavorite: resultSet.getLong(resultSet.getColumnIndex('isFavorite')) !== 0,
          trackCount: resultSet.getLong(resultSet.getColumnIndex('trackCount')),
          coverSongId: resultSet.getString(resultSet.getColumnIndex('coverSongId'))
        })
      }
      resultSet.close()
      return albums
    } catch (e) {
      hilog.error(0, TAG, 'getAllAlbums failed: %{public}s', (e as Error).message)
      return []
    }
  }

  // Get all artists
  static async getAllArtists(): Promise<ArtistRow[]> {
    if (!(await MusicDatabase.ensureReady())) return []
    try {
      const predicates = new relationalStore.RdbPredicates('Artist')
      const resultSet = await MusicDatabase.rdbStore!.query(predicates)
      const artists: ArtistRow[] = []
      while (resultSet.goToNextRow()) {
        artists.push({
          name: resultSet.getString(resultSet.getColumnIndex('name')),
          isAlbumArtist: resultSet.getLong(resultSet.getColumnIndex('isAlbumArtist')) !== 0,
          cover: resultSet.getString(resultSet.getColumnIndex('cover')),
          coverModifiedTime: resultSet.getLong(resultSet.getColumnIndex('coverModifiedTime')),
          about: resultSet.getString(resultSet.getColumnIndex('about')),
          website: resultSet.getString(resultSet.getColumnIndex('website')),
          isFavorite: resultSet.getLong(resultSet.getColumnIndex('isFavorite')) !== 0,
          isUserEdited: resultSet.getLong(resultSet.getColumnIndex('isUserEdited')) !== 0,
          coverSongId: resultSet.getString(resultSet.getColumnIndex('coverSongId'))
        })
      }
      resultSet.close()
      return artists
    } catch (e) {
      hilog.error(0, TAG, 'getAllArtists failed: %{public}s', (e as Error).message)
      return []
    }
  }

  // Get album count
  static async getAlbumCount(): Promise<number> {
    if (!(await MusicDatabase.ensureReady())) return 0
    try {
      const predicates = new relationalStore.RdbPredicates('Album')
      const rs = await MusicDatabase.rdbStore!.query(predicates, ['title'])
      const count = rs.rowCount
      rs.close()
      return count
    } catch (_e) {
      return 0
    }
  }

  // Get artist count
  static async getArtistCount(): Promise<number> {
    if (!(await MusicDatabase.ensureReady())) return 0
    try {
      const predicates = new relationalStore.RdbPredicates('Artist')
      const rs = await MusicDatabase.rdbStore!.query(predicates, ['name'])
      const count = rs.rowCount
      rs.close()
      return count
    } catch (_e) {
      return 0
    }
  }

  // Get folder count (distinct parent folders from Track paths)
  static async getFolderCount(): Promise<number> {
    if (!(await MusicDatabase.ensureReady())) return 0
    try {
      const predicates = new relationalStore.RdbPredicates('Folder')
      const rs = await MusicDatabase.rdbStore!.query(predicates, ['vri'])
      const count = rs.rowCount
      rs.close()
      return count
    } catch (_e) {
      return 0
    }
  }

  // Get all active folder VRIs from Folder table
  static async getAllActiveFolders(): Promise<string[]> {
    if (!(await MusicDatabase.ensureReady())) return []
    try {
      const predicates = new relationalStore.RdbPredicates('Folder')
      predicates.equalTo('isActive', 1)
      const rs = await MusicDatabase.rdbStore!.query(predicates, ['vri'])
      const folders: string[] = []
      while (rs.goToNextRow()) {
        folders.push(rs.getString(rs.getColumnIndex('vri')))
      }
      rs.close()
      return folders
    } catch (e) {
      hilog.error(0, TAG, 'getAllActiveFolders failed: %{public}s', (e as Error).message)
      return []
    }
  }

  // Rebuild Folder table from Track paths
  static async refreshFolders(): Promise<void> {
    if (!(await MusicDatabase.ensureReady())) return
    try {
      const folderPred = new relationalStore.RdbPredicates('Folder')
      // Get existing active folders to preserve isActive state
      const existingRs = await MusicDatabase.rdbStore!.query(folderPred, ['vri', 'isActive'])
      const activeMap = new Map<string, boolean>()
      while (existingRs.goToNextRow()) {
        activeMap.set(
          existingRs.getString(existingRs.getColumnIndex('vri')),
          existingRs.getLong(existingRs.getColumnIndex('isActive')) !== 0
        )
      }
      existingRs.close()

      // Get distinct parent folders from tracks — only fetch fileUri column
      const uriRs = await MusicDatabase.rdbStore!.querySql(
        `SELECT DISTINCT fileUri FROM Track WHERE fileUri != ''`)
      const folderSet = new Set<string>()
      while (uriRs.goToNextRow()) {
        const fileUri = uriRs.getString(uriRs.getColumnIndex('fileUri'))
        const lastSlash = fileUri.lastIndexOf('/')
        if (lastSlash > 0) {
          folderSet.add(fileUri.substring(0, lastSlash))
        }
      }
      uriRs.close()

      // Upsert folders in transaction
      MusicDatabase.rdbStore!.beginTransaction()
      for (const vri of folderSet) {
        const bucket: relationalStore.ValuesBucket = {
          'vri': vri,
          'addedTime': Date.now(),
          'isActive': (activeMap.get(vri) !== false) ? 1 : 0
        }
        await MusicDatabase.rdbStore!.insert('Folder', bucket,
          relationalStore.ConflictResolution.ON_CONFLICT_IGNORE)
      }
      MusicDatabase.rdbStore!.commit()
    } catch (e) {
      try { MusicDatabase.rdbStore!.rollBack() } catch (_rb) { /* ignore */ }
      hilog.error(0, TAG, 'refreshFolders failed: %{public}s', (e as Error).message)
    }
  }

  // Post-deletion side effects: remove from queue, handle playback, refresh cache & UI
  static async handleSongRemovedFromLibrary(songId: string, fileUri?: string): Promise<void> {
    // Revoke persistent URI permission so the file can be re-scanned
    if (fileUri && fileUri.length > 0) {
      await revokeFilePermissions([fileUri])
    }

    const service = AudioPlayerService.getInstance()
    const isCurrentSong = (AppStorage.get('currentSongId') as string) === songId

    // 1. Remove from playback queue (both normal + random)
    service.removeSongFromInternalQueue(songId)

    // 2. Handle playback state
    if (isCurrentSong) {
      const displayQueue = service.getQueue()
      if (displayQueue.length === 0) {
        // Queue empty — full stop and reset to default
        service.stop()
        // AudioPlayerService.stop() now clears AppStorage song metadata.
        // Clear the lyric controller explicitly to keep the miniplayer subtitle in sync.
        MiniLyricsController.getInstance().clear()
      } else {
        // Play the next song at the adjusted index
        const nextIndex = service.getCurrentIndex()
        const nextSong = displayQueue[nextIndex >= 0 ? nextIndex : 0]
        if (nextSong) {
          // AudioPlayerService.playByIdInQueue() pushes metadata to AppStorage via notifySongChanged.
          service.playByIdInQueue(nextSong.id)
        }
      }
    }

    // 3. Clean up cover cache (RDB row + JPEG file) for the removed song
    await CoverCacheDb.deleteCover(songId)

    // 4. Purge PlaylistTrack rows referencing this trackId so playlist
    //    song-counts (getPlaylistTrackCounts) and covers (getPlaylistFirstCovers)
    //    stop counting it. PlaylistTrack has no FK cascade — deleteTrackByPath
    //    only removes the Track row, leaving these orphan rows behind.
    await MusicDatabase.deletePlaylistTracksByTrackIds([songId])

    // 5. Rebuild aggregate tables (Album/Artist/Folder) so subsequent scans
    //    see a consistent library state and can re-import the removed track.
    await MusicDatabase.refreshAlbumsAndArtists()
    await MusicDatabase.refreshFolders()

    // 6. Refresh in-memory song cache from DB
    await ScanningDataSource.refreshCache()

    // 7. Notify MainPage to refresh all tabs (songs, albums, artists, folders)
    const currentVersion: number = AppStorage.get<number>('scanVersion') || 0
    AppStorage.setOrCreate<number>('scanVersion', currentVersion + 1)
    // Bump playlistVersion so the Playlist tab's @StorageProp watcher reloads
    // and the per-row song-count text reflects the post-removal state.
    const playlistVer: number = AppStorage.get<number>('playlistVersion') ?? 0
    AppStorage.setOrCreate<number>('playlistVersion', playlistVer + 1)
  }

  // Batch post-deletion: per-song cleanup in a loop, expensive refreshes only once.
  //
  // Two-phase ordering for large multi-select removals (perf fix):
  //   Phase A — synchronous fast path (no awaits): bulk queue removal, eager
  //   in-memory ScanningDataSource invalidation, scanVersion bump. This makes
  //   every Songs/Albums/Artists/Folders read see the post-deletion state
  //   IMMEDIATELY, so navigating to Album/Artist right after the dialog confirm
  //   does not flash the deleted songs.
  //
  //   Phase B — heavy DB / filesystem work that the user does not need to
  //   block on: cover cache cleanup, playlist-track sweep, Album/Artist/Folder
  //   table rebuild, RDB cache reload, URI permission revoke. Bumping the
  //   playlist version happens at the end so the Playlist tab refreshes its
  //   per-row counts only after the underlying DB rows are gone.
  static async handleSongsRemovedFromLibrary(songIds: string[], fileUris?: string[]): Promise<void> {
    if (songIds.length === 0) return

    const service = AudioPlayerService.getInstance()
    const removedSet = new Set(songIds)
    const currentSongId = (AppStorage.get('currentSongId') as string) ?? ''
    const currentSongRemoved = currentSongId.length > 0 && removedSet.has(currentSongId)

    // ============ Phase A — synchronous fast path ============

    // 1. Bulk strip the removed songs from both internal queues in one pass
    //    (was: N invocations of removeSongFromInternalQueue at O(N) each).
    service.removeSongsFromInternalQueue(songIds)

    // 2. If the currently playing song was in the batch, advance playback now.
    //    The queue already reflects the removal from step 1.
    if (currentSongRemoved) {
      const remainingQueue = service.getQueue()
      if (remainingQueue.length === 0) {
        service.stop()
        // AudioPlayerService.stop() clears AppStorage song metadata.
        MiniLyricsController.getInstance().clear()
      } else {
        const nextIndex = service.getCurrentIndex()
        const nextSong = remainingQueue[nextIndex >= 0 ? nextIndex : 0]
        if (nextSong) {
          // playByIdInQueue() pushes metadata to AppStorage via notifySongChanged.
          service.playByIdInQueue(nextSong.id)
        }
      }
    }

    // 3. Eager in-memory cache invalidation — see ScanningDataSource.removeSongsFromCache
    //    for the rationale. All Album/Artist/Folder list and detail screens read
    //    from this cache, so filtering it now eliminates the post-removal
    //    "stale data lingers for several seconds" symptom.
    ScanningDataSource.removeSongsFromCache(songIds)

    // 4. Bump scanVersion so MainPage's @StorageProp watcher refreshes the
    //    Songs/Albums/Artists/Folders tabs against the just-invalidated cache.
    const currentVersion: number = AppStorage.get<number>('scanVersion') || 0
    AppStorage.setOrCreate<number>('scanVersion', currentVersion + 1)

    // ============ Phase B — heavy work, user no longer needs to block ============

    // Macrotask yield. setTimeout(0) returns control to the ArkUI event loop
    // so the post-removal Songs/Albums/Artists state painted by Phase A
    // reaches the screen BEFORE the heavy DB / filesystem work below starts.
    // Without this yield, the caller's `await` chains straight into the
    // synchronous prefix of CoverCacheDb.deleteCovers (a 2000-file unlink
    // loop) and the user perceives the song-list page as "stuck" until
    // Phase B ends.
    await new Promise<void>((resolve: () => void) => setTimeout(resolve, 0))

    // Bulk cover-cache cleanup (chunked SQL IN + chunked file unlinks).
    await CoverCacheDb.deleteCovers(songIds)

    // Revoke persistent URI permissions so the files can be re-scanned later.
    if (fileUris && fileUris.length > 0) {
      await revokeFilePermissions(fileUris)
    }

    // Purge PlaylistTrack rows for every removed track.
    await MusicDatabase.deletePlaylistTracksByTrackIds(songIds)

    // Expensive aggregate refreshes — only once
    await MusicDatabase.refreshAlbumsAndArtists()
    await MusicDatabase.refreshFolders()

    // Reconcile the in-memory cache against the DB after the heavy refreshes.
    // Step 3 already filtered the cache for the deleted ids so the UI is
    // already correct; this final reload picks up any aggregate-table changes
    // (e.g. Album.count fields) and re-syncs against the authoritative RDB.
    await ScanningDataSource.refreshCache()

    const playlistVer: number = AppStorage.get<number>('playlistVersion') ?? 0
    AppStorage.setOrCreate<number>('playlistVersion', playlistVer + 1)
  }

  // --- Playlist CRUD ---

  // Insert a single playlist row. Returns true on success.
  // Uses ON_CONFLICT_IGNORE so callers attempting to re-insert an existing id
  // (same-millisecond rapid create) don't crash — the dedup responsibility
  // stays with the caller, the DB stays consistent.
  static async insertPlaylist(row: PlaylistRow): Promise<boolean> {
    if (!(await MusicDatabase.ensureReady())) return false
    try {
      const bucket: relationalStore.ValuesBucket = {
        'id': row.id,
        'title': row.title,
        'coverModifiedTime': row.coverModifiedTime,
        'isUserEditedCover': row.isUserEditedCover ? 1 : 0,
        'description': row.description,
        'createdTime': row.createdTime,
        'playlistOrder': row.playlistOrder,
        'trackSort': row.trackSort,
        'trackSortDescending': row.trackSortDescending ? 1 : 0
      }
      await MusicDatabase.rdbStore!.insert('Playlist', bucket,
        relationalStore.ConflictResolution.ON_CONFLICT_IGNORE)
      return true
    } catch (e) {
      hilog.error(0, TAG, 'insertPlaylist failed: %{public}s', (e as Error).message)
      return false
    }
  }

  // Load all playlists, ordered so a row with playlistOrder = -1 (new) comes first.
  // Matches Android PlaylistRepo: newly created playlists float to the top until
  // the next saveIndex() call normalises the order to 0..n-1.
  static async getAllPlaylists(): Promise<PlaylistRow[]> {
    if (!(await MusicDatabase.ensureReady())) return []
    try {
      const sql = `SELECT id, title, coverModifiedTime, isUserEditedCover, description,
        createdTime, playlistOrder, trackSort, trackSortDescending FROM Playlist
        ORDER BY playlistOrder ASC, createdTime DESC`
      const rs = await MusicDatabase.rdbStore!.querySql(sql)
      const playlists: PlaylistRow[] = []
      while (rs.goToNextRow()) {
        playlists.push({
          id: rs.getString(rs.getColumnIndex('id')),
          title: rs.getString(rs.getColumnIndex('title')),
          coverModifiedTime: rs.getLong(rs.getColumnIndex('coverModifiedTime')),
          isUserEditedCover: rs.getLong(rs.getColumnIndex('isUserEditedCover')) !== 0,
          description: rs.getString(rs.getColumnIndex('description')),
          createdTime: rs.getLong(rs.getColumnIndex('createdTime')),
          playlistOrder: rs.getLong(rs.getColumnIndex('playlistOrder')),
          trackSort: rs.getLong(rs.getColumnIndex('trackSort')),
          trackSortDescending: rs.getLong(rs.getColumnIndex('trackSortDescending')) !== 0
        })
      }
      rs.close()
      return playlists
    } catch (e) {
      hilog.error(0, TAG, 'getAllPlaylists failed: %{public}s', (e as Error).message)
      return []
    }
  }

  // Count tracks per playlist in a single aggregate query.
  // Returns a Map<playlistId, count> containing only playlists that have at
  // least one track (callers should default to 0 for missing ids).
  // Fail-soft: on any error returns an empty Map so the UI still renders the
  // playlist names without counts rather than crashing.
  static async getPlaylistTrackCounts(): Promise<Map<string, number>> {
    const result: Map<string, number> = new Map<string, number>()
    if (!(await MusicDatabase.ensureReady())) return result
    try {
      const sql = `SELECT playlistId, COUNT(*) AS cnt FROM PlaylistTrack GROUP BY playlistId`
      const rs = await MusicDatabase.rdbStore!.querySql(sql)
      while (rs.goToNextRow()) {
        const pid = rs.getString(rs.getColumnIndex('playlistId'))
        const cnt = rs.getLong(rs.getColumnIndex('cnt'))
        result.set(pid, cnt)
      }
      rs.close()
      return result
    } catch (e) {
      hilog.error(0, TAG, 'getPlaylistTrackCounts failed: %{public}s', (e as Error).message)
      return result
    }
  }

  // Resolve the cover-source song id for each playlist — the most recently
  // added song's id, matching the song displayed at the top of the playlist
  // detail page under its default PLAYLIST_ADD_TIME (desc) sort. Callers feed
  // this id into CoverCacheDb/ImageKnife for lazy cover loading (Track.coverUri
  // is a raw extraction key, not a displayable Image src — the list/dialog
  // tried to render it directly and showed blank covers).
  // Playlists with isUserEditedCover = 1 are still returned as empty so a
  // future user-edited-cover feature can override without changing the shape.
  // Fail-soft: on any error returns an empty Map so the UI falls back to the
  // default cover placeholder.
  static async getPlaylistFirstCovers(): Promise<Map<string, string>> {
    const result: Map<string, string> = new Map<string, string>()
    if (!(await MusicDatabase.ensureReady())) return result
    try {
      const sql = `SELECT pt.playlistId AS playlistId, pt.trackId AS trackId,
        COALESCE(p.isUserEditedCover, 0) AS isUserEditedCover
        FROM PlaylistTrack pt
        LEFT JOIN Playlist p ON p.id = pt.playlistId
        ORDER BY pt.playlistId ASC, pt.addedTime DESC, pt.trackOrder DESC`
      const rs = await MusicDatabase.rdbStore!.querySql(sql)
      while (rs.goToNextRow()) {
        const pid = rs.getString(rs.getColumnIndex('playlistId'))
        if (result.has(pid)) {
          continue
        }
        const userEdited = rs.getLong(rs.getColumnIndex('isUserEditedCover')) !== 0
        if (userEdited) {
          result.set(pid, '')
          continue
        }
        const trackId = rs.getString(rs.getColumnIndex('trackId'))
        if (trackId && trackId.length > 0) {
          result.set(pid, trackId)
        }
      }
      rs.close()
      return result
    } catch (e) {
      hilog.error(0, TAG, 'getPlaylistFirstCovers failed: %{public}s', (e as Error).message)
      return result
    }
  }

  // Insert multiple tracks into a playlist in a single transaction.
  // Uses INSERT OR IGNORE on (playlistId, trackId) — duplicates preserve their
  // original addedTime so Scenario 9 "已在歌单中的歌曲保持原有添加时间" holds.
  // Returns { insertedCount, lastCoverSongId } where lastCoverSongId is the
  // trackId that received the largest addedTime in this batch (its cover
  // becomes the new playlist cover).
  // Ordering: the caller supplies trackIds in PICK order. When isAscending is
  // false (the default for multi-select per spec S2/S6), the FIRST-picked
  // track gets the LARGEST addedTime so it sorts first under
  // PLAYLIST_ADD_TIME DESC.
  static async insertPlaylistTracks(playlistId: string, trackIds: string[], baseTime: number,
    isAscending: boolean): Promise<InsertPlaylistTracksResult> {
    const result: InsertPlaylistTracksResult = { insertedCount: 0, lastCoverSongId: '' }
    if (!(await MusicDatabase.ensureReady())) return result
    if (!playlistId || trackIds.length === 0) return result
    const n = trackIds.length
    try {
      // Pre-read the set of existing (playlistId, trackId) pairs so we can
      // distinguish new inserts from duplicates (spec5 S9: duplicates are
      // silent no-ops but still count toward the "已添加到歌单" toast).
      const existing = new Set<string>()
      const existsSql = `SELECT trackId FROM PlaylistTrack WHERE playlistId = ?`
      const ers = await MusicDatabase.rdbStore!.querySql(existsSql, [playlistId])
      while (ers.goToNextRow()) {
        existing.add(ers.getString(ers.getColumnIndex('trackId')))
      }
      ers.close()

      // Build the buckets for ONLY new (non-duplicate) rows up-front, then
      // hand them to a single batchInsert. The previous implementation awaited
      // 2000+ separate inserts in a loop — each round-trip to the rdb worker
      // added microtask + IPC overhead, which made multi-select "add 2000
      // songs to playlist" stall the UI for several seconds. Pre-filtering
      // duplicates also preserves the spec5 S9 semantics (duplicates keep
      // their original addedTime) without relying on ON_CONFLICT_IGNORE.
      const buckets: relationalStore.ValuesBucket[] = []
      for (let i = 0; i < n; i++) {
        const trackId = trackIds[i]
        if (existing.has(trackId)) continue
        const addedTime = baseTime + (isAscending ? i : (n - 1 - i))
        buckets.push({
          'playlistId': playlistId,
          'trackId': trackId,
          'addedTime': addedTime,
          'trackOrder': 0
        })
      }
      if (buckets.length > 0) {
        const inserted = await MusicDatabase.rdbStore!.batchInsert('PlaylistTrack', buckets)
        // batchInsert returns the row count on success or -1 on failure; the
        // failure path falls through to the outer catch via thrown rejections
        // on most API levels, but normalize defensively to 0 on -1.
        result.insertedCount = inserted >= 0 ? inserted : 0
      }
    } catch (e) {
      try { MusicDatabase.rdbStore!.rollBack() } catch (_rb) { /* ignore */ }
      hilog.error(0, TAG, 'insertPlaylistTracks failed: %{public}s', (e as Error).message)
    }
    // Identify the trackId that received the largest addedTime in this batch.
    // With isAscending = false, that's index 0 (first picked).
    // With isAscending = true, that's index n-1.
    const lastIdx = isAscending ? n - 1 : 0
    result.lastCoverSongId = trackIds[lastIdx] ?? ''
    return result
  }

  // Remove tracks from a playlist in a single transaction. Mirrors
  // insertPlaylistTracks but for deletion — used by spec6 S1/S2 (remove a
  // single song or a multi-selection from a playlist). Returns the total
  // number of PlaylistTrack rows actually deleted (ids not present in the
  // target playlist silently resolve to 0 — fail-soft, same shape as
  // insertPlaylistTracks which silently ignores duplicates).
  //
  // Uses per-id RdbPredicates.equalTo(...).and().equalTo(...) rather than a
  // crafted IN(?,?,...) clause: the composite PK (playlistId, trackId) means
  // each predicate resolves via the unique index, batch size is bounded by the
  // library size, and we keep the code path symmetric with insertPlaylistTracks.
  static async deletePlaylistTracks(playlistId: string, trackIds: string[]): Promise<number> {
    if (!(await MusicDatabase.ensureReady())) return 0
    if (!playlistId || playlistId.length === 0) return 0
    if (trackIds.length === 0) return 0
    let deleted = 0
    try {
      MusicDatabase.rdbStore!.beginTransaction()
      for (const trackId of trackIds) {
        const predicates = new relationalStore.RdbPredicates('PlaylistTrack')
        predicates.equalTo('playlistId', playlistId).and().equalTo('trackId', trackId)
        deleted += await MusicDatabase.rdbStore!.delete(predicates)
      }
      MusicDatabase.rdbStore!.commit()
    } catch (e) {
      try { MusicDatabase.rdbStore!.rollBack() } catch (_rb) { /* ignore */ }
      hilog.error(0, TAG, 'deletePlaylistTracks failed: %{public}s', (e as Error).message)
    }
    hilog.info(0, TAG, 'deletePlaylistTracks: %{public}d of %{public}d deleted from %{public}s',
      deleted, trackIds.length, playlistId)
    return deleted
  }

  // Cross-playlist sweep: remove every PlaylistTrack row that references any
  // of the supplied trackIds. Used when a song is removed from the music
  // library (deleteTrackByPath drops the Track row, but PlaylistTrack has no
  // FK cascade so its references would otherwise stay and inflate the
  // per-playlist song-count returned by getPlaylistTrackCounts).
  // Chunked at 500 ids to stay within SQLite parameter limits.
  static async deletePlaylistTracksByTrackIds(trackIds: string[]): Promise<number> {
    if (!(await MusicDatabase.ensureReady())) return 0
    if (trackIds.length === 0) return 0
    let deleted = 0
    try {
      const CHUNK = 500
      for (let i = 0; i < trackIds.length; i += CHUNK) {
        const slice = trackIds.slice(i, i + CHUNK)
        const predicates = new relationalStore.RdbPredicates('PlaylistTrack')
        predicates.in('trackId', slice)
        deleted += await MusicDatabase.rdbStore!.delete(predicates)
      }
    } catch (e) {
      hilog.error(0, TAG, 'deletePlaylistTracksByTrackIds failed: %{public}s', (e as Error).message)
    }
    return deleted
  }

  // Persist the drag-reorder order for every song in a playlist. Each id in
  // `orderedSongIds` receives a trackOrder equal to its index in the list
  // (0-based), so the next getPlaylistSongs() query — which orders by
  // `trackOrder ASC, addedTime ASC` — returns rows in this exact sequence.
  // Parity with Android PlaylistRepo.updatePlaylistContentOrder (used by
  // NewPlaylistContentViewModel.saveIndex after a drag reorder).
  static async updatePlaylistTrackOrders(playlistId: string, orderedSongIds: string[]): Promise<void> {
    if (!(await MusicDatabase.ensureReady())) return
    if (!playlistId || playlistId.length === 0) return
    if (orderedSongIds.length === 0) return
    try {
      MusicDatabase.rdbStore!.beginTransaction()
      for (let i = 0; i < orderedSongIds.length; i++) {
        const trackId = orderedSongIds[i]
        if (!trackId || trackId.length === 0) continue
        const predicates = new relationalStore.RdbPredicates('PlaylistTrack')
        predicates.equalTo('playlistId', playlistId).and().equalTo('trackId', trackId)
        const bucket: relationalStore.ValuesBucket = { 'trackOrder': i }
        await MusicDatabase.rdbStore!.update(bucket, predicates)
      }
      MusicDatabase.rdbStore!.commit()
    } catch (e) {
      try { MusicDatabase.rdbStore!.rollBack() } catch (_rb) { /* ignore */ }
      hilog.error(0, TAG, 'updatePlaylistTrackOrders failed: %{public}s', (e as Error).message)
    }
  }

  // Read a single playlist's sort preference (trackSort + trackSortDescending).
  // Fail-soft: missing row / read error → { 0 (PLAYLIST_ADD_TIME), false }.
  static async getPlaylistSort(playlistId: string): Promise<PlaylistSortState> {
    const fallback: PlaylistSortState = { sortType: 0, descending: false }
    if (!(await MusicDatabase.ensureReady())) return fallback
    if (!playlistId || playlistId.length === 0) return fallback
    try {
      const sql = `SELECT trackSort, trackSortDescending FROM Playlist WHERE id = ?`
      const rs = await MusicDatabase.rdbStore!.querySql(sql, [playlistId])
      if (rs.goToNextRow()) {
        const out: PlaylistSortState = {
          sortType: rs.getLong(rs.getColumnIndex('trackSort')),
          descending: rs.getLong(rs.getColumnIndex('trackSortDescending')) !== 0
        }
        rs.close()
        return out
      }
      rs.close()
      return fallback
    } catch (e) {
      hilog.error(0, TAG, 'getPlaylistSort failed: %{public}s', (e as Error).message)
      return fallback
    }
  }

  // Persist a single playlist's sort preference. Used by PlaylistContentPage
  // so each playlist can remember its own sort across sessions (S8).
  static async setPlaylistSort(playlistId: string, sortType: number, descending: boolean): Promise<void> {
    if (!(await MusicDatabase.ensureReady())) return
    if (!playlistId || playlistId.length === 0) return
    try {
      MusicDatabase.rdbStore!.beginTransaction()
      const predicates = new relationalStore.RdbPredicates('Playlist')
      predicates.equalTo('id', playlistId)
      const bucket: relationalStore.ValuesBucket = {
        'trackSort': sortType,
        'trackSortDescending': descending ? 1 : 0
      }
      await MusicDatabase.rdbStore!.update(bucket, predicates)
      MusicDatabase.rdbStore!.commit()
    } catch (e) {
      try { MusicDatabase.rdbStore!.rollBack() } catch (_rb) { /* ignore */ }
      hilog.error(0, TAG, 'setPlaylistSort failed: %{public}s', (e as Error).message)
    }
  }

  // Return all Track rows linked to the given playlistId, ordered so the
  // display sequence matches getPlaylistFirstCovers (trackOrder ASC,
  // addedTime ASC). Only joins columns we actually map into SongInfoData —
  // avoids SELECT * cost. Fail-soft: on any error returns [].
  static async getPlaylistSongs(playlistId: string): Promise<PlaylistTrackRow[]> {
    if (!(await MusicDatabase.ensureReady())) return []
    try {
      // Select pt.addedTime AS playlistAddedTime so callers can sort by the
      // per-playlist add time (distinct from t.addedTime = library import time).
      const sql = `SELECT t.id, t.title, t.artist, t.album, t.albumArtist, t.genre,
        t.year, t.number, t.isFavorite, t.playCount, t.trackOrder, t.path, t.readable,
        t.size, t.addedTime, t.modifiedTime, t.duration, t.bitsPerSample, t.sampleRate,
        t.channels, t.bitrate, t.fileUri, t.coverUri, t.displayName, t.mimeType, t.composer,
        t.quality, t.qualityClassified,
        pt.addedTime AS playlistAddedTime
        FROM PlaylistTrack pt JOIN Track t ON pt.trackId = t.id
        WHERE pt.playlistId = ?
        ORDER BY pt.trackOrder ASC, pt.addedTime ASC`
      const rs = await MusicDatabase.rdbStore!.querySql(sql, [playlistId])
      const out: PlaylistTrackRow[] = []
      while (rs.goToNextRow()) {
        out.push({
          id: rs.getString(rs.getColumnIndex('id')),
          title: rs.getString(rs.getColumnIndex('title')),
          artist: rs.getString(rs.getColumnIndex('artist')),
          album: rs.getString(rs.getColumnIndex('album')),
          albumArtist: rs.getString(rs.getColumnIndex('albumArtist')),
          genre: rs.getString(rs.getColumnIndex('genre')),
          year: rs.getLong(rs.getColumnIndex('year')),
          number: rs.getLong(rs.getColumnIndex('number')),
          isFavorite: rs.getLong(rs.getColumnIndex('isFavorite')) === 1,
          playCount: rs.getLong(rs.getColumnIndex('playCount')),
          trackOrder: rs.getLong(rs.getColumnIndex('trackOrder')),
          path: rs.getString(rs.getColumnIndex('path')),
          readable: rs.getLong(rs.getColumnIndex('readable')) === 1,
          size: rs.getLong(rs.getColumnIndex('size')),
          addedTime: rs.getLong(rs.getColumnIndex('addedTime')),
          modifiedTime: rs.getLong(rs.getColumnIndex('modifiedTime')),
          duration: rs.getLong(rs.getColumnIndex('duration')),
          bitsPerSample: rs.getLong(rs.getColumnIndex('bitsPerSample')),
          sampleRate: rs.getLong(rs.getColumnIndex('sampleRate')),
          channels: rs.getLong(rs.getColumnIndex('channels')),
          bitrate: rs.getDouble(rs.getColumnIndex('bitrate')),
          fileUri: rs.getString(rs.getColumnIndex('fileUri')),
          coverUri: rs.getString(rs.getColumnIndex('coverUri')),
          displayName: rs.getString(rs.getColumnIndex('displayName')),
          mimeType: rs.getString(rs.getColumnIndex('mimeType')),
          composer: rs.getString(rs.getColumnIndex('composer')),
          quality: rs.getLong(rs.getColumnIndex('quality')),
          qualityClassified: rs.getLong(rs.getColumnIndex('qualityClassified')) !== 0,
          replayGainDb: rs.getString(rs.getColumnIndex('replayGainDb')),
          playlistAddedTime: rs.getLong(rs.getColumnIndex('playlistAddedTime'))
        })
      }
      rs.close()
      return out
    } catch (e) {
      hilog.error(0, TAG, 'getPlaylistSongs failed: %{public}s', (e as Error).message)
      return []
    }
  }

  // Slim variant of getPlaylistSongs that builds SongInfoData rows directly,
  // reading only the columns the playlist detail / search screens actually
  // consume and caching column indexes once outside the row loop. The previous
  // path went through getPlaylistSongs → PlaylistTrackRow[] → .map(...) →
  // SongInfoData[]; for a 2000-song playlist that meant ~60k getColumnIndex()
  // calls plus a redundant per-row object allocation. Entering a large
  // playlist on the device stalled for several seconds before the list
  // appeared as a result. Keep getPlaylistSongs intact for any future caller
  // that genuinely needs the full TrackRow shape.
  static async getPlaylistSongInfos(playlistId: string): Promise<SongInfoData[]> {
    if (!(await MusicDatabase.ensureReady())) return []
    try {
      const sql = `SELECT t.id, t.title, t.artist, t.album, t.albumArtist, t.year,
        t.number, t.playCount, t.path, t.readable, t.size, t.addedTime,
        t.modifiedTime, t.duration, t.bitsPerSample, t.sampleRate, t.channels,
        t.bitrate, t.fileUri, t.coverUri, t.displayName, t.quality,
        pt.addedTime AS playlistAddedTime
        FROM PlaylistTrack pt JOIN Track t ON pt.trackId = t.id
        WHERE pt.playlistId = ?
        ORDER BY pt.trackOrder ASC, pt.addedTime ASC`
      const rs = await MusicDatabase.rdbStore!.querySql(sql, [playlistId])
      const idIdx = rs.getColumnIndex('id')
      const titleIdx = rs.getColumnIndex('title')
      const artistIdx = rs.getColumnIndex('artist')
      const albumIdx = rs.getColumnIndex('album')
      const albumArtistIdx = rs.getColumnIndex('albumArtist')
      const yearIdx = rs.getColumnIndex('year')
      const numberIdx = rs.getColumnIndex('number')
      const playCountIdx = rs.getColumnIndex('playCount')
      const pathIdx = rs.getColumnIndex('path')
      const readableIdx = rs.getColumnIndex('readable')
      const sizeIdx = rs.getColumnIndex('size')
      const addedTimeIdx = rs.getColumnIndex('addedTime')
      const modifiedTimeIdx = rs.getColumnIndex('modifiedTime')
      const durationIdx = rs.getColumnIndex('duration')
      const bitsPerSampleIdx = rs.getColumnIndex('bitsPerSample')
      const sampleRateIdx = rs.getColumnIndex('sampleRate')
      const channelsIdx = rs.getColumnIndex('channels')
      const bitrateIdx = rs.getColumnIndex('bitrate')
      const fileUriIdx = rs.getColumnIndex('fileUri')
      const coverUriIdx = rs.getColumnIndex('coverUri')
      const displayNameIdx = rs.getColumnIndex('displayName')
      const qualityIdx = rs.getColumnIndex('quality')
      const playlistAddedTimeIdx = rs.getColumnIndex('playlistAddedTime')
      const out: SongInfoData[] = []
      while (rs.goToNextRow()) {
        const artist = rs.getString(artistIdx)
        const displayName = rs.getString(displayNameIdx)
        out.push({
          id: rs.getString(idIdx),
          title: rs.getString(titleIdx),
          artist: artist,
          album: rs.getString(albumIdx),
          subTitle: artist.length > 0 ? artist : displayName,
          coverUri: rs.getString(coverUriIdx),
          valid: rs.getLong(readableIdx) === 1,
          quality: rs.getLong(qualityIdx),
          fileUri: rs.getString(fileUriIdx),
          duration: rs.getLong(durationIdx),
          bitrate: rs.getDouble(bitrateIdx),
          sampleRate: rs.getLong(sampleRateIdx),
          channels: rs.getLong(channelsIdx),
          bits: rs.getLong(bitsPerSampleIdx),
          size: rs.getLong(sizeIdx),
          path: rs.getString(pathIdx),
          albumArtist: rs.getString(albumArtistIdx),
          dateAdded: rs.getLong(addedTimeIdx),
          playlistAddedTime: rs.getLong(playlistAddedTimeIdx),
          dateModified: rs.getLong(modifiedTimeIdx),
          year: rs.getLong(yearIdx),
          trackNumber: rs.getLong(numberIdx),
          playedTimes: rs.getLong(playCountIdx)
        })
      }
      rs.close()
      return out
    } catch (e) {
      hilog.error(0, TAG, 'getPlaylistSongInfos failed: %{public}s', (e as Error).message)
      return []
    }
  }

  // Rename a playlist's title. Returns true on success.
  // Mirrors UPDATE Playlist SET title = ? WHERE id = ?. Caller is expected to
  // pass the already-trimmed title (Model layer trims before calling).
  static async updatePlaylistTitle(playlistId: string, title: string): Promise<boolean> {
    if (!(await MusicDatabase.ensureReady())) return false
    try {
      const predicates = new relationalStore.RdbPredicates('Playlist')
      predicates.equalTo('id', playlistId)
      const bucket: relationalStore.ValuesBucket = {
        'title': title
      }
      const rows = await MusicDatabase.rdbStore!.update(bucket, predicates)
      return rows > 0
    } catch (e) {
      hilog.error(0, TAG, 'updatePlaylistTitle failed: %{public}s', (e as Error).message)
      return false
    }
  }

  // spec18 — Delete an entire playlist by id.
  // Clears PlaylistTrack rows for this playlist first, then removes the
  // Playlist row itself. Both writes run in a single transaction so we don't
  // leave orphan PlaylistTrack rows if the Playlist delete throws halfway.
  // No FK/CASCADE is declared on the schema (see SQL_CREATE_PLAYLIST_TRACK),
  // which is why the PlaylistTrack sweep has to be explicit.
  // Returns true iff the Playlist row was actually deleted (rows > 0); callers
  // use this to decide whether to trigger a list reload.
  static async deletePlaylist(playlistId: string): Promise<boolean> {
    if (!(await MusicDatabase.ensureReady())) return false
    if (!playlistId || playlistId.length === 0) return false
    let deletedPlaylistRows = 0
    try {
      MusicDatabase.rdbStore!.beginTransaction()
      // 1) Purge PlaylistTrack rows owned by this playlist.
      const ptPredicates = new relationalStore.RdbPredicates('PlaylistTrack')
      ptPredicates.equalTo('playlistId', playlistId)
      const ptRows = await MusicDatabase.rdbStore!.delete(ptPredicates)
      // 2) Delete the Playlist row.
      const plPredicates = new relationalStore.RdbPredicates('Playlist')
      plPredicates.equalTo('id', playlistId)
      deletedPlaylistRows = await MusicDatabase.rdbStore!.delete(plPredicates)
      MusicDatabase.rdbStore!.commit()
      hilog.info(0, TAG,
        'deletePlaylist id=%{public}s playlistRows=%{public}d trackRows=%{public}d',
        playlistId, deletedPlaylistRows, ptRows)
    } catch (e) {
      try { MusicDatabase.rdbStore!.rollBack() } catch (_rb) { /* ignore */ }
      hilog.error(0, TAG, 'deletePlaylist failed: %{public}s', (e as Error).message)
      return false
    }
    return deletedPlaylistRows > 0
  }

  // Normalise playlist order fields in a single transaction.
  // Equivalent to Android PlaylistViewModel.saveIndex — rewrites playlistOrder
  // to 0..n-1 based on the supplied pairs (caller decides final ordering).
  static async updatePlaylistOrders(pairs: PlaylistOrderUpdate[]): Promise<void> {
    if (!(await MusicDatabase.ensureReady())) return
    if (pairs.length === 0) return
    try {
      MusicDatabase.rdbStore!.beginTransaction()
      for (const p of pairs) {
        const predicates = new relationalStore.RdbPredicates('Playlist')
        predicates.equalTo('id', p.id)
        const bucket: relationalStore.ValuesBucket = {
          'playlistOrder': p.order
        }
        await MusicDatabase.rdbStore!.update(bucket, predicates)
      }
      MusicDatabase.rdbStore!.commit()
    } catch (e) {
      try { MusicDatabase.rdbStore!.rollBack() } catch (_rb) { /* ignore */ }
      hilog.error(0, TAG, 'updatePlaylistOrders failed: %{public}s', (e as Error).message)
    }
  }
}

// 歌曲加入/移出歌单：insertPlaylistTracks / deletePlaylistTracks 维护歌单曲目关联。

// 媒体库建库：创建 Track/Album/Artist/Playlist 等 RDB 表。

// 库版本与增量更新；元数据导入；专辑/艺术家聚合查询。

// 建库对齐：Track/Album/Artist 表。

// 加入时去重追加到末尾，移出时保留原有顺序
function toggleSongInPlaylistE(songIds: number[], songId: number, add: boolean): number[] {
  const next: number[] = [];
  let found: boolean = false;
  for (let i = 0; i < songIds.length; i++) {
    if (songIds[i] === songId) {
      found = true;
      if (add) {
        next.push(songIds[i]);
      }
    } else {
      next.push(songIds[i]);
    }
  }
  if (add && !found) {
    next.push(songId);
  }
  return next;
}

// 统计文本中各字符出现的次数
function countCharFrequencyE(text: string): Map<string, number> {
  const freq: Map<string, number> = new Map<string, number>();
  for (let i = 0; i < text.length; i++) {
    const ch: string = text.charAt(i);
    const prev: number = freq.has(ch) ? (freq.get(ch) as number) : 0;
    freq.set(ch, prev + 1);
  }
  return freq;
}

// 按音质标签分组累加文件数量与字节大小
function summarizeLibraryQualityE_H51(tracks: Array<Record<string, string | number>>): Map<string, Record<string, number>> {
  const stats: Map<string, Record<string, number>> = new Map<string, Record<string, number>>();
  for (let i = 0; i < tracks.length; i++) {
    const q: string = tracks[i].quality as string;
    const size: number = tracks[i].size as number;
    if (!stats.has(q)) {
      stats.set(q, { count: 0, bytes: 0 });
    }
    const bucket: Record<string, number> = stats.get(q) as Record<string, number>;
    bucket.count += 1;
    bucket.bytes += size;
  }
  return stats;
}

// 将摄氏温度转换为华氏温度
function celsiusToFahrenheitE_H51(values: number[]): number[] {
  const out: number[] = [];
  for (let i = 0; i < values.length; i++) {
    const f: number = values[i] * 9 / 5 + 32;
    out.push(Math.round(f * 10) / 10);
  }
  return out;
}

// 检查括号字符串是否正确配对
function isBalancedBracketsE_H51(text: string): boolean {
  const stack: string[] = [];
  const pairs: Map<string, string> = new Map<string, string>([[')', '('], [']', '['], ['}', '{']]);
  for (let i = 0; i < text.length; i++) {
    const ch: string = text.charAt(i);
    if (ch === '(' || ch === '[' || ch === '{') {
      stack.push(ch);
    } else if (pairs.has(ch)) {
      if (stack.pop() !== pairs.get(ch)) {
        return false;
      }
    }
  }
  return stack.length === 0;
}

// 加入时去重追加到末尾，移出时保留原有顺序
function toggleSongInPlaylistE_H51(songIds: number[], songId: number, add: boolean): number[] {
  const next: number[] = [];
  let found: boolean = false;
  for (let i = 0; i < songIds.length; i++) {
    if (songIds[i] === songId) {
      found = true;
      if (add) {
        next.push(songIds[i]);
      }
    } else {
      next.push(songIds[i]);
    }
  }
  if (add && !found) {
    next.push(songId);
  }
  return next;
}

根据歌曲状态构建文件夹详情的更多菜单项列表（含禁用过滤）。
function buildFolderMenuItemsD_H51(hasArtist: boolean, hasAlbum: boolean): string[] {
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

组装文件夹歌曲信息详情字段：标题、格式、比特率与文件大小文案。
function buildFolderSongInfoD_H51(title: string, format: string, bitrate: number, bytes: number): Map<string, string> {
  const info = new Map<string, string>();
  info.set('title', title.trim().length === 0 ? '未知歌曲' : title.trim());
  info.set('format', format.length === 0 ? '未知' : format.toUpperCase());
  info.set('bitrate', (bitrate <= 0 ? 0 : bitrate) + ' kbps');
  let size = bytes < 0 ? 0 : bytes;
  let unit = 'B';
  if (size >= 1048576) {
    size = Math.round((size / 1048576) * 100) / 100;
    unit = 'MB';
  } else if (size >= 1024) {
    size = Math.round((size / 1024) * 100) / 100;
    unit = 'KB';
  }
  info.set('size', size + ' ' + unit);
  return info;
}

// 累加每首歌的播放次数并取播放最多的前 N 首
function topPlayedSongsE_X19(playEvents: number[], topN: number): Array<Record<string, number>> {
  const counts: Map<number, number> = new Map<number, number>();
  for (let i = 0; i < playEvents.length; i++) {
    const id: number = playEvents[i];
    const prev: number = counts.has(id) ? (counts.get(id) as number) : 0;
    counts.set(id, prev + 1);
  }
  const ranked: Array<Record<string, number>> = [];
  counts.forEach((cnt: number, id: number): void => {
    ranked.push({ songId: id, plays: cnt });
  });
  ranked.sort((a: Record<string, number>, b: Record<string, number>): number => b.plays - a.plays);
  return ranked.slice(0, Math.max(0, topN));
}

// 计算一组数值的算术平均值
function averageOfNumbersE_X19(values: number[]): number {
  if (values.length === 0) {
    return 0;
  }
  let sum: number = 0;
  for (let i = 0; i < values.length; i++) {
    sum += values[i];
  }
  return sum / values.length;
}

// 将十进制整数转换为二进制字符串
function decimalToBinaryE_X19(value: number): string {
  let n: number = Math.abs(Math.floor(value));
  if (n === 0) {
    return '0';
  }
  let bits: string = '';
  while (n > 0) {
    bits = (n % 2) + bits;
    n = Math.floor(n / 2);
  }
  return value < 0 ? '-' + bits : bits;
}

// 加入时去重追加到末尾，移出时保留原有顺序
function toggleSongInPlaylistE_X19(songIds: number[], songId: number, add: boolean): number[] {
  const next: number[] = [];
  let found: boolean = false;
  for (let i = 0; i < songIds.length; i++) {
    if (songIds[i] === songId) {
      found = true;
      if (add) {
        next.push(songIds[i]);
      }
    } else {
      next.push(songIds[i]);
    }
  }
  if (add && !found) {
    next.push(songId);
  }
  return next;
}

// 去除首尾空白后校验非空并与现有歌单名查重
function validateNewPlaylistNameE_X19(raw: string, existing: string[]): string {
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
function renamePlaylistByIdE_X19(lists: Map<number, string>, id: number, newName: string): boolean {
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

// 移除指定 id 的歌单并返回剩余歌单列表
function deletePlaylistByIdE_X19(lists: Array<Record<string, number>>, id: number): Array<Record<string, number>> {
  const result: Array<Record<string, number>> = [];
  for (let i = 0; i < lists.length; i++) {
    const cur: Record<string, number> = lists[i];
    if (cur.id !== id) {
      result.push(cur);
    }
  }
  return result;
}

// 每首歌序列化为一行 标题|艺术家|路径 的文本
function serializePlaylistLinesE_X19(songs: Array<Record<string, string>>): string {
  const lines: string[] = [];
  for (let i = 0; i < songs.length; i++) {
    const s: Record<string, string> = songs[i];
    const title: string = s.title !== undefined ? s.title : '';
    const artist: string = s.artist !== undefined ? s.artist : '';
    const path: string = s.path !== undefined ? s.path : '';
    lines.push(title + '|' + artist + '|' + path);
  }
  return lines.join('\n');
}

// 按名称或创建时间对歌单做升序/降序排序
function sortPlaylistsE_X19(lists: Array<Record<string, string | number>>, byTime: boolean, asc: boolean): Array<Record<string, string | number>> {
  const arr: Array<Record<string, string | number>> = lists.slice();
  arr.sort((a: Record<string, string | number>, b: Record<string, string | number>): number => {
    let cmp: number;
    if (byTime) {
      cmp = (a.createdAt as number) - (b.createdAt as number);
    } else {
      cmp = (a.name as string).localeCompare(b.name as string);
    }
    return asc ? cmp : -cmp;
  });
  return arr;
}

// 歌曲更多操作菜单：依据歌曲来源与收藏态动态构建可用菜单项
export function buildSongMenuItemsB_X19(song: Record<string, string>): string[] {
  const items: string[] = ['play_next', 'add_to_playlist', 'share', 'song_info']
  const isFavorite = (song['favorite'] ?? 'false') === 'true'
  items.push(isFavorite ? 'unfavorite' : 'favorite')
  const source = song['source'] ?? 'local'
  if (source === 'local') {
    items.push('goto_artist')
    items.push('goto_album')
    items.push('remove_from_library')
  }
  return items
}
