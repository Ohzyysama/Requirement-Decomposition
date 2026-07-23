// MainPageModel.ets
// Model layer: data structures and data access logic for MainPage.
// Contains pure data definitions and data loading operations.
// Does not depend on UI or ViewModel.

import {
  SongInfoData,
  createDefaultSongInfoData
} from './SongItemModel'
import { SDCardInfo, FolderInfo } from './FolderModel'
import PlaylistModel from './PlaylistModel'
import { ScanningDataSource, ScannedSongData } from './ScanningModel'
import { MusicDatabase, AlbumRow, ArtistRow, PlaylistRow } from './MusicDatabase'
import { Guqin } from './Guqin'
import { BlockedFolderDataSource } from './BlockedFolderModel'
import { SongLazySort } from './SongSortModel'
import { statfs } from '@kit.CoreFileKit'

// Re-export types for ViewModel to consume
export { SongInfoData, createDefaultSongInfoData } from './SongItemModel'
export { SDCardInfo, FolderInfo } from './FolderModel'

// Album info data used in the album tab
export interface AlbumInfoData {
  id: string
  title: string
  albumArtist: string
  count: number
  year: number
  coverUri: string
  coverSongId: string  // song id that provided the cover (for memory cache lookup)
  coverModified: number
  pinyin: string
}

// Artist info data used in the artist tab
export interface ArtistInfoData {
  id: string
  name: string
  count: number
  coverUri: string
  coverSongId: string  // song id that provided the cover (for memory cache lookup)
  pinyin: string
}

// Tab type enum for the main page content tabs
export class MainTabType {
  static readonly SONG: string = 'song'
  static readonly ALBUM: string = 'album'
  static readonly ARTIST: string = 'artist'
  static readonly FOLDER: string = 'folder'
  static readonly PLAYLIST: string = 'playlist'
}

// Result type for single-pass data loading
export interface LoadAllResult {
  songs: SongInfoData[]
  albums: AlbumInfoData[]
  artists: ArtistInfoData[]
  sdCards: SDCardInfo[]
  folders: FolderInfo[]
}

// Data source class: encapsulates data loading logic.
export class MainPageDataSource {
  // Check if scanned song cache has data (used to detect if DB load already finished)
  static hasData(): boolean {
    return ScanningDataSource.getScannedSongs().length > 0
  }

  // Single-pass aggregation: loads songs, albums, artists, sdCards, folders in one iteration.
  // Replaces calling loadDefaultSongs/Albums/Artists/SDCards/Folders individually (5 iterations → 1).
  static loadAll(): LoadAllResult {
    const scanned: ScannedSongData[] = ScanningDataSource.getScannedSongs()
    const blockedPaths: string[] = BlockedFolderDataSource.loadBlockedFolderPaths()

    const songs: SongInfoData[] = []
    const albumMap = new Map<string, AlbumInfoData>()
    const artistMap = new Map<string, ArtistInfoData>()
    const folderMap = new Map<string, FolderInfo>()
    const rootSet = new Set<string>()

    for (const s of scanned) {
      // Skip songs inside blocked folders so they vanish from Songs/Albums/Artists tabs.
      if (blockedPaths.length > 0 && s.fileUri.length > 0) {
        let isBlocked = false
        for (const blocked of blockedPaths) {
          if (blocked.length > 0 && s.fileUri.startsWith(blocked + '/')) {
            isBlocked = true
            break
          }
        }
        if (isBlocked) continue
      }
      // --- Song mapping ---
      const song: SongInfoData = {
        id: s.id,
        title: s.title,
        artist: s.artist,
        album: s.album,
        subTitle: s.artist.length > 0 ? s.artist : s.displayName,
        coverUri: s.coverUri ?? '',
        valid: true,
        quality: s.quality,
        fileUri: s.fileUri,
        duration: s.duration,
        bitrate: s.bitrate,
        sampleRate: s.sampleRate,
        channels: s.channels,
        bits: s.bitsPerSample,
        size: s.size,
        path: s.path,
        albumArtist: s.albumArtist,
        dateAdded: s.dateAdded,
        dateModified: s.dateModified,
        year: s.year,
        trackNumber: s.trackNumber,
        // spec14: carry ReplayGain through
        replayGainDb: s.replayGainDb
      }
      songs.push(song)

      // --- Album aggregation ---
      if (s.album.length > 0) {
        const albumKey = s.album + '|' + s.albumArtist
        const existingAlbum = albumMap.get(albumKey)
        if (existingAlbum) {
          existingAlbum.count++
          if (existingAlbum.coverSongId.length === 0) {
            existingAlbum.coverSongId = s.id
          }
          if (existingAlbum.coverUri.length === 0 && s.coverUri.length > 0) {
            existingAlbum.coverUri = s.coverUri
            existingAlbum.coverSongId = s.id
          }
        } else {
          albumMap.set(albumKey, {
            id: albumKey,
            title: s.album,
            albumArtist: s.albumArtist,
            count: 1,
            year: s.year,
            coverUri: s.coverUri ?? '',
            coverSongId: s.id,
            coverModified: 0,
            pinyin: SongLazySort.getPinyinInitial(s.album)
          })
        }
      }

      // --- Artist aggregation ---
      if (s.artist.length > 0) {
        const artistNames: string[] = Guqin.getArtists(s.artist)
        for (const artistName of artistNames) {
          if (artistName.length === 0) continue
          const existingArtist = artistMap.get(artistName)
          if (existingArtist) {
            existingArtist.count++
            if (existingArtist.coverSongId.length === 0) {
              existingArtist.coverSongId = s.id
            }
            if (existingArtist.coverUri.length === 0 && s.coverUri.length > 0) {
              existingArtist.coverUri = s.coverUri
              existingArtist.coverSongId = s.id
            }
          } else {
            artistMap.set(artistName, {
              id: artistName,
              name: artistName,
              count: 1,
              coverUri: s.coverUri ?? '',
              coverSongId: s.id,
              pinyin: SongLazySort.getPinyinInitial(artistName)
            })
          }
        }
      }

      // --- Folder aggregation ---
      const uri = s.fileUri
      if (uri.length > 0) {
        const lastSlash = uri.lastIndexOf('/')
        if (lastSlash > 0) {
          const folderPath = uri.substring(0, lastSlash)
          const existingFolder = folderMap.get(folderPath)
          if (existingFolder) {
            existingFolder.count++
          } else {
            const nameStart = folderPath.lastIndexOf('/')
            const rawName = nameStart >= 0 ? folderPath.substring(nameStart + 1) : folderPath
            let folderName = rawName
            try {
              folderName = decodeURIComponent(rawName)
            } catch (_e) { /* use raw */ }
            folderMap.set(folderPath, {
              id: folderPath,
              name: folderName,
              path: folderPath,
              count: 1,
              pingyinChar: folderName.length > 0 ? SongLazySort.getPinyinInitial(folderName) : '#'
            })
          }
        }

        // --- SD card root extraction ---
        const parts = uri.split('/')
        if (parts.length >= 4) {
          const rootEnd = uri.indexOf('/', uri.indexOf('/', uri.indexOf('/', 1) + 1) + 1)
          if (rootEnd > 0) {
            rootSet.add(uri.substring(0, rootEnd))
          }
        }
      }
    }

    // Build albums array
    const albums: AlbumInfoData[] = []
    albumMap.forEach((album: AlbumInfoData) => { albums.push(album) })

    // Build artists array
    const artists: ArtistInfoData[] = []
    artistMap.forEach((artist: ArtistInfoData) => { artists.push(artist) })

    // Folders from blocked paths were already filtered out during aggregation above.
    const folders: FolderInfo[] = []
    folderMap.forEach((folder: FolderInfo) => { folders.push(folder) })
    folders.sort((a: FolderInfo, b: FolderInfo): number => {
      return SongLazySort.collator.compare(a.name, b.name)
    })

    // Build SD cards
    let sdCards: SDCardInfo[] = []
    if (scanned.length > 0) {
      let usedSize = ''
      let totalSize = ''
      const storagePath = rootSet.size > 0 ? Array.from(rootSet)[0] : '/storage'
      try {
        const statfsPath = storagePath.startsWith('file://') ? '/data' : storagePath
        const total = statfs.getTotalSizeSync(statfsPath)
        const free = statfs.getFreeSizeSync(statfsPath)
        const used = total - free
        totalSize = MainPageDataSource.formatBytes(total)
        usedSize = MainPageDataSource.formatBytes(used)
      } catch (_e) { /* stats not available */ }
      sdCards = [{
        name: '内部存储',
        path: storagePath,
        usedSize: usedSize,
        totalSize: totalSize
      }]
    }

    return { songs, albums, artists, sdCards, folders }
  }

  // Load song list from scanned results (sync, uses cached data)
  static loadDefaultSongs(): SongInfoData[] {
    const scanned: ScannedSongData[] = ScanningDataSource.getScannedSongs()
    const blockedPaths: string[] = BlockedFolderDataSource.loadBlockedFolderPaths()
    const filtered: ScannedSongData[] = blockedPaths.length === 0
      ? scanned
      : scanned.filter((s: ScannedSongData): boolean => {
        if (s.fileUri.length === 0) return true
        for (const blocked of blockedPaths) {
          if (blocked.length > 0 && s.fileUri.startsWith(blocked + '/')) return false
        }
        return true
      })
    return filtered.map((s: ScannedSongData): SongInfoData => {
      const song: SongInfoData = {
        id: s.id,
        title: s.title,
        artist: s.artist,
        album: s.album,
        subTitle: s.artist.length > 0 ? s.artist : s.displayName,
        coverUri: s.coverUri ?? '',
        valid: true,
        quality: s.quality,
        fileUri: s.fileUri,
        duration: s.duration,
        bitrate: s.bitrate,
        sampleRate: s.sampleRate,
        channels: s.channels,
        bits: s.bitsPerSample,
        size: s.size,
        path: s.path,
        albumArtist: s.albumArtist,
        dateAdded: s.dateAdded,
        dateModified: s.dateModified,
        year: s.year,
        trackNumber: s.trackNumber,
        // spec14: carry ReplayGain through to SongInfoData
        replayGainDb: s.replayGainDb
      }
      return song
    })
  }

  // Load album list from RDB Album table
  static async loadAlbumsFromDb(): Promise<AlbumInfoData[]> {
    const albums: AlbumRow[] = await MusicDatabase.getAllAlbums()
    return albums.map((a: AlbumRow): AlbumInfoData => {
      return {
        id: a.title + '|' + a.artist,
        title: a.title,
        albumArtist: a.artist,
        count: a.trackCount,
        year: a.year,
        coverUri: a.cover,
        coverSongId: a.coverSongId,
        coverModified: a.coverModifiedTime,
        pinyin: SongLazySort.getPinyinInitial(a.title)
      }
    })
  }

  // Load artist list from RDB Artist table
  static async loadArtistsFromDb(): Promise<ArtistInfoData[]> {
    const artists: ArtistRow[] = await MusicDatabase.getAllArtists()
    return artists.map((a: ArtistRow): ArtistInfoData => {
      return {
        id: a.name,
        name: a.name,
        count: 0, // will be set by caller if needed
        coverUri: a.cover,
        coverSongId: a.coverSongId,
        pinyin: SongLazySort.getPinyinInitial(a.name)
      }
    })
  }

  // Sync fallback: load albums from cached songs (for backward compat)
  static loadDefaultAlbums(): AlbumInfoData[] {
    const scanned: ScannedSongData[] = ScanningDataSource.getScannedSongs()
    const blockedPaths: string[] = BlockedFolderDataSource.loadBlockedFolderPaths()
    const albumMap = new Map<string, AlbumInfoData>()

    for (const s of scanned) {
      if (s.album.length === 0) {
        continue
      }
      if (blockedPaths.length > 0 && s.fileUri.length > 0) {
        let isBlocked = false
        for (const blocked of blockedPaths) {
          if (blocked.length > 0 && s.fileUri.startsWith(blocked + '/')) {
            isBlocked = true
            break
          }
        }
        if (isBlocked) continue
      }
      const key = s.album + '|' + s.albumArtist
      const existing = albumMap.get(key)
      if (existing) {
        existing.count++
        if (existing.coverSongId.length === 0) {
          existing.coverSongId = s.id
        }
        if (existing.coverUri.length === 0 && s.coverUri.length > 0) {
          existing.coverUri = s.coverUri
          existing.coverSongId = s.id
        }
      } else {
        const album: AlbumInfoData = {
          id: key,
          title: s.album,
          albumArtist: s.albumArtist,
          count: 1,
          year: s.year,
          coverUri: s.coverUri ?? '',
          coverSongId: s.id,
          coverModified: 0,
          pinyin: SongLazySort.getPinyinInitial(s.album)
        }
        albumMap.set(key, album)
      }
    }

    const result: AlbumInfoData[] = []
    albumMap.forEach((album: AlbumInfoData) => {
      result.push(album)
    })
    return result
  }

  // Sync fallback: load artists from cached songs (for backward compat)
  static loadDefaultArtists(): ArtistInfoData[] {
    const scanned: ScannedSongData[] = ScanningDataSource.getScannedSongs()
    const blockedPaths: string[] = BlockedFolderDataSource.loadBlockedFolderPaths()
    const artistMap = new Map<string, ArtistInfoData>()

    for (const s of scanned) {
      if (s.artist.length === 0) {
        continue
      }
      if (blockedPaths.length > 0 && s.fileUri.length > 0) {
        let isBlocked = false
        for (const blocked of blockedPaths) {
          if (blocked.length > 0 && s.fileUri.startsWith(blocked + '/')) {
            isBlocked = true
            break
          }
        }
        if (isBlocked) continue
      }
      // Split artist by "/" delimiter (respects protected names like "AC/DC")
      const artists: string[] = Guqin.getArtists(s.artist)
      for (const artistName of artists) {
        if (artistName.length === 0) {
          continue
        }
        const existing = artistMap.get(artistName)
        if (existing) {
          existing.count++
          if (existing.coverSongId.length === 0) {
            existing.coverSongId = s.id
          }
          if (existing.coverUri.length === 0 && s.coverUri.length > 0) {
            existing.coverUri = s.coverUri
            existing.coverSongId = s.id
          }
        } else {
          const artist: ArtistInfoData = {
            id: artistName,
            name: artistName,
            count: 1,
            coverUri: s.coverUri ?? '',
            coverSongId: s.id,
            pinyin: SongLazySort.getPinyinInitial(artistName)
          }
          artistMap.set(artistName, artist)
        }
      }
    }

    const result: ArtistInfoData[] = []
    artistMap.forEach((artist: ArtistInfoData) => {
      result.push(artist)
    })
    return result
  }

  // Load SD card info from system
  // Shows device internal storage derived from scanned song paths
  static loadDefaultSDCards(): SDCardInfo[] {
    const scanned: ScannedSongData[] = ScanningDataSource.getScannedSongs()
    if (scanned.length === 0) {
      return []
    }

    // Find the common storage root from song paths
    // Typical HarmonyOS paths: file:///data/storage/... or /storage/...
    const rootSet = new Set<string>()
    for (const s of scanned) {
      const uri = s.fileUri
      if (uri.length === 0) continue
      // Try to extract storage root (e.g., first 3 path segments)
      const parts = uri.split('/')
      // For file:///storage/media/... -> parts = ['file:', '', '', 'storage', 'media', ...]
      // For /storage/emulated/0/... -> parts = ['', 'storage', 'emulated', '0', ...]
      if (parts.length >= 4) {
        // Use a reasonable root prefix
        const rootEnd = uri.indexOf('/', uri.indexOf('/', uri.indexOf('/', 1) + 1) + 1)
        if (rootEnd > 0) {
          rootSet.add(uri.substring(0, rootEnd))
        }
      }
    }

    // Create one entry for internal storage
    let usedSize = ''
    let totalSize = ''
    const storagePath = rootSet.size > 0 ? Array.from(rootSet)[0] : '/storage'
    // Try to get storage stats using a real filesystem path
    // statfs requires a real path, not a URI (file:///...), so try /data as fallback
    try {
      const statfsPath = storagePath.startsWith('file://') ? '/data' : storagePath
      const total = statfs.getTotalSizeSync(statfsPath)
      const free = statfs.getFreeSizeSync(statfsPath)
      const used = total - free
      totalSize = MainPageDataSource.formatBytes(total)
      usedSize = MainPageDataSource.formatBytes(used)
    } catch (e) {
      // Storage stats may not be available - leave empty
    }
    const sdCard: SDCardInfo = {
      name: '内部存储',
      path: storagePath,
      usedSize: usedSize,
      totalSize: totalSize
    }
    return [sdCard]
  }

  // Load folder list from cached scanned songs (same pattern as loadDefaultAlbums)
  static loadDefaultFolders(): FolderInfo[] {
    const scanned: ScannedSongData[] = ScanningDataSource.getScannedSongs()
    const folderMap = new Map<string, FolderInfo>()

    for (const s of scanned) {
      const uri = s.fileUri
      if (uri.length === 0) continue

      // Extract parent folder path
      const lastSlash = uri.lastIndexOf('/')
      if (lastSlash <= 0) continue
      const folderPath = uri.substring(0, lastSlash)

      const existing = folderMap.get(folderPath)
      if (existing) {
        existing.count++
      } else {
        // Extract folder display name (last path segment), decode URL encoding
        const nameStart = folderPath.lastIndexOf('/')
        const rawName = nameStart >= 0 ? folderPath.substring(nameStart + 1) : folderPath
        let folderName = rawName
        try {
          folderName = decodeURIComponent(rawName)
        } catch (e) {
          // If decode fails, use raw name
        }

        // Simple first char for ABC index
        const firstChar = folderName.length > 0 ? SongLazySort.getPinyinInitial(folderName) : '#'

        const folder: FolderInfo = {
          id: folderPath,
          name: folderName,
          path: folderPath,
          count: 1,
          pingyinChar: firstChar
        }
        folderMap.set(folderPath, folder)
      }
    }

    const result: FolderInfo[] = []
    // Filter out blocked folders
    const blockedPaths = BlockedFolderDataSource.loadBlockedFolderPaths()
    folderMap.forEach((folder: FolderInfo) => {
      let isBlocked = false
      for (const blocked of blockedPaths) {
        if (blocked.length > 0 &&
          (folder.path === blocked || folder.path.startsWith(blocked + '/'))) {
          isBlocked = true
          break
        }
      }
      if (!isBlocked) {
        result.push(folder)
      }
    })
    // Sort by folder name
    result.sort((a: FolderInfo, b: FolderInfo): number => {
      return SongLazySort.collator.compare(a.name, b.name)
    })
    return result
  }

  // Load playlists from data source (deprecated stub — kept for compat).
  // Always returns an empty array. New callers should use loadPlaylistsFromDb().
  static loadDefaultPlaylists(): PlaylistModel[] {
    return []
  }

  // Load playlists from the RDB Playlist table. Rows are pre-sorted by
  // playlistOrder ASC (so a newly-inserted row with playlistOrder = -1
  // appears at index 0 until saveIndex() normalises it on the next create).
  static async loadPlaylistsFromDb(): Promise<PlaylistModel[]> {
    const rows: PlaylistRow[] = await MusicDatabase.getAllPlaylists()
    // Fan out two aggregate queries once and compose the full Playlist shape
    // model-side so every consumer (MainPage tab, AddToPlaylist dialog, ...)
    // receives identical coverUri / songCount values.
    const counts: Map<string, number> = await MusicDatabase.getPlaylistTrackCounts()
    // Map value is now the cover-source SONG ID (not a cover URI) — the UI
    // lazy-loads the image via CoverCacheDb keyed by this id.
    const coverSongIds: Map<string, string> = await MusicDatabase.getPlaylistFirstCovers()
    return rows.map((r: PlaylistRow): PlaylistModel => {
      const count: number = counts.get(r.id) ?? 0
      const coverSongId: string = coverSongIds.get(r.id) ?? ''
      return new PlaylistModel(r.id, r.title, count, coverSongId)
    })
  }

  // Format bytes to human-readable string (e.g., "2.10 GB")
  private static formatBytes(bytes: number): string {
    if (bytes <= 0) return '0 B'
    const gb = bytes / (1024 * 1024 * 1024)
    if (gb >= 1) {
      return `${gb.toFixed(2)} GB`
    }
    const mb = bytes / (1024 * 1024)
    if (mb >= 1) {
      return `${mb.toFixed(2)} MB`
    }
    const kb = bytes / 1024
    return `${kb.toFixed(2)} KB`
  }
}
