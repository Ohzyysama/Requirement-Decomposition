// CoverCacheDb.ets
// Model layer: RDB-based persistence for cover art PixelMaps.
// Save: ImagePacker → JPEG ArrayBuffer → BLOB
// Load: BLOB → ImageSource → createPixelMap
//
// Cache invalidation: rows are keyed by songId but also store modifiedTime and
// fileSize. loadCover() is a miss when either value disagrees with the current
// file, so a re-embedded cover will be re-extracted automatically on the next
// access. Schema upgrades drop legacy rows that lack the metadata columns.

import { relationalStore } from '@kit.ArkData'
import { image } from '@kit.ImageKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { fileIo } from '@kit.CoreFileKit'
import { cryptoFramework } from '@kit.CryptoArchitectureKit'
import { buffer } from '@kit.ArkTS'

const TAG = 'CoverCacheDb'
const DB_NAME = 'cover_cache.db'
const TABLE_NAME = 'cover_art'
const SQL_CREATE_TABLE =
  `CREATE TABLE IF NOT EXISTS ${TABLE_NAME} (
    song_id TEXT PRIMARY KEY,
    cover_data BLOB,
    width INTEGER,
    height INTEGER,
    modified_time INTEGER NOT NULL DEFAULT 0,
    file_size INTEGER NOT NULL DEFAULT 0
  )`

export class CoverCacheDb {
  // Thumbnail size for list items — 200px covers high-density list items at ~50vp
  static readonly THUMBNAIL_SIZE = 200
  private static rdbStore: relationalStore.RdbStore | null = null
  private static initPromise: Promise<void> | null = null
  // Directory for JPEG cover files (set via initCoverDir)
  private static coverDir: string = ''

  static init(context: Context): void {
    if (CoverCacheDb.initPromise) return
    CoverCacheDb.initPromise = CoverCacheDb.doInit(context)
  }

  private static async doInit(context: Context): Promise<void> {
    try {
      const config: relationalStore.StoreConfig = {
        name: DB_NAME,
        securityLevel: relationalStore.SecurityLevel.S1
      }
      CoverCacheDb.rdbStore = await relationalStore.getRdbStore(context, config)
      await CoverCacheDb.rdbStore.executeSql(SQL_CREATE_TABLE)
      // Upgrade path: older installs created the table without metadata columns.
      // ALTER TABLE ADD COLUMN is idempotent-safe via try/catch.
      try {
        await CoverCacheDb.rdbStore.executeSql(
          `ALTER TABLE ${TABLE_NAME} ADD COLUMN modified_time INTEGER NOT NULL DEFAULT 0`)
      } catch (_e) { /* column already exists */ }
      try {
        await CoverCacheDb.rdbStore.executeSql(
          `ALTER TABLE ${TABLE_NAME} ADD COLUMN file_size INTEGER NOT NULL DEFAULT 0`)
      } catch (_e) { /* column already exists */ }
      // Thumbnail column: small JPEG for list items, avoids decoding the full blob
      try {
        await CoverCacheDb.rdbStore.executeSql(
          `ALTER TABLE ${TABLE_NAME} ADD COLUMN thumb_data BLOB`)
      } catch (_e) { /* column already exists */ }
      hilog.info(0, TAG, 'RDB store initialized')
    } catch (e) {
      hilog.error(0, TAG, 'init failed: %{public}s', (e as Error).message)
    }
  }

  private static async ensureReady(): Promise<boolean> {
    if (CoverCacheDb.initPromise) {
      await CoverCacheDb.initPromise
    }
    return CoverCacheDb.rdbStore !== null
  }

  // Initialize the covers directory for JPEG file storage.
  static initCoverDir(context: Context): void {
    const dir = context.cacheDir + '/covers'
    try {
      if (!fileIo.accessSync(dir)) {
        fileIo.mkdirSync(dir, true)
      }
    } catch (_e) {
      try { fileIo.mkdirSync(dir, true) } catch (_e2) { /* already exists */ }
    }
    CoverCacheDb.coverDir = dir
    hilog.info(0, TAG, 'coverDir initialized: %{public}s', dir)
  }

  // Create a filesystem-safe filename from a songId using SHA-256 hash.
  // Guarantees uniqueness — the old char-replacement approach collapsed CJK
  // characters and special chars into '_', causing different songs to share
  // the same cache file.
  static safeFileName(songId: string): string {
    const md = cryptoFramework.createMd('SHA256')
    md.updateSync({ data: new Uint8Array(buffer.from(songId, 'utf-8').buffer) })
    const digest = md.digestSync()
    const bytes = digest.data
    let hex = ''
    for (let i = 0; i < bytes.length; i++) {
      const b = bytes[i]
      hex += ('0' + b.toString(16)).slice(-2)
    }
    return hex
  }

  // Sync: return file:// URI for a cover JPEG if the file exists, '' otherwise.
  static getCoverFileUri(songId: string): string {
    if (CoverCacheDb.coverDir.length === 0 || songId.length === 0) return ''
    const filePath = CoverCacheDb.coverDir + '/' + CoverCacheDb.safeFileName(songId) + '.jpg'
    try {
      if (fileIo.accessSync(filePath)) {
        return 'file://' + filePath
      }
    } catch (_e) { /* file does not exist */ }
    return ''
  }

  // Async: if cover file doesn't exist, read BLOB from RDB and write to file.
  static async ensureCoverFile(songId: string): Promise<string> {
    if (CoverCacheDb.coverDir.length === 0 || songId.length === 0) return ''
    const filePath = CoverCacheDb.coverDir + '/' + CoverCacheDb.safeFileName(songId) + '.jpg'
    try {
      if (fileIo.accessSync(filePath)) {
        return 'file://' + filePath
      }
    } catch (_e) { /* not found, proceed */ }
    if (!(await CoverCacheDb.ensureReady())) return ''
    try {
      const predicates = new relationalStore.RdbPredicates(TABLE_NAME)
      predicates.equalTo('song_id', songId)
      const resultSet = await CoverCacheDb.rdbStore!.query(predicates, ['cover_data'])
      if (!resultSet.goToFirstRow()) { resultSet.close(); return '' }
      const blobRaw = resultSet.getBlob(resultSet.getColumnIndex('cover_data'))
      resultSet.close()
      if (!blobRaw || blobRaw.length === 0) return ''
      const buffer = new ArrayBuffer(blobRaw.length)
      new Uint8Array(buffer).set(blobRaw)
      const fd = fileIo.openSync(filePath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC)
      fileIo.writeSync(fd.fd, buffer)
      fileIo.closeSync(fd)
      hilog.info(0, TAG, 'ensureCoverFile: exported %{public}d bytes', blobRaw.length)
      return 'file://' + filePath
    } catch (e) {
      hilog.warn(0, TAG, 'ensureCoverFile failed: %{public}s', (e as Error).message)
      return ''
    }
  }

  // Write JPEG buffer to cover file (called from saveCover).
  private static writeCoverFile(songId: string, jpegBuffer: ArrayBuffer): void {
    if (CoverCacheDb.coverDir.length === 0) return
    try {
      const filePath = CoverCacheDb.coverDir + '/' + CoverCacheDb.safeFileName(songId) + '.jpg'
      const fd = fileIo.openSync(filePath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC)
      fileIo.writeSync(fd.fd, jpegBuffer)
      fileIo.closeSync(fd)
    } catch (e) {
      hilog.warn(0, TAG, 'writeCoverFile failed: %{public}s', (e as Error).message)
    }
  }

  // Save cover: PixelMap → JPEG via ImagePacker → BLOB. Also generates a
  // thumbnail (THUMBNAIL_SIZE px) stored alongside to speed up list scrolling.
  static async saveCover(songId: string, pixelMap: image.PixelMap,
    modifiedTime: number, fileSize: number): Promise<boolean> {
    if (!(await CoverCacheDb.ensureReady())) {
      hilog.error(0, TAG, 'saveCover: RDB not ready')
      return false
    }
    try {
      const info = await pixelMap.getImageInfo()
      const w = info.size.width
      const h = info.size.height

      // Encode to JPEG
      const packer = image.createImagePacker()
      const packOpts: image.PackingOption = { format: 'image/jpeg', quality: 85 }
      const jpegBuffer: ArrayBuffer = await packer.packing(pixelMap, packOpts)
      packer.release()

      if (!jpegBuffer || jpegBuffer.byteLength === 0) {
        hilog.error(0, TAG, 'saveCover: packing returned empty buffer')
        return false
      }

      // Write JPEG to file for ImageKnife consumption
      CoverCacheDb.writeCoverFile(songId, jpegBuffer)

      // Generate thumbnail from the JPEG buffer
      let thumbBlob: Uint8Array | undefined = undefined
      try {
        const thumbSrc = image.createImageSource(jpegBuffer)
        const thumbSize = CoverCacheDb.THUMBNAIL_SIZE
        const thumbOpts: image.DecodingOptions = {
          desiredSize: { width: thumbSize, height: thumbSize }
        }
        const thumbPm = await thumbSrc.createPixelMap(thumbOpts)
        thumbSrc.release()

        const thumbPacker = image.createImagePacker()
        const thumbPackOpts: image.PackingOption = { format: 'image/jpeg', quality: 75 }
        const thumbJpeg = await thumbPacker.packing(thumbPm, thumbPackOpts)
        thumbPacker.release()
        thumbPm.release()

        if (thumbJpeg && thumbJpeg.byteLength > 0) {
          thumbBlob = new Uint8Array(thumbJpeg)
        }
      } catch (_thumbErr) {
        hilog.warn(0, TAG, 'saveCover: thumbnail generation failed, skipping')
      }

      const blob = new Uint8Array(jpegBuffer)
      const bucket: relationalStore.ValuesBucket = {
        'song_id': songId,
        'cover_data': blob,
        'width': w,
        'height': h,
        'modified_time': modifiedTime,
        'file_size': fileSize,
        'thumb_data': thumbBlob ?? null
      }
      const predicates = new relationalStore.RdbPredicates(TABLE_NAME)
      predicates.equalTo('song_id', songId)
      await CoverCacheDb.rdbStore!.delete(predicates)
      await CoverCacheDb.rdbStore!.insert(TABLE_NAME, bucket)
      hilog.info(0, TAG, 'saveCover ok: %{public}dx%{public}d jpeg=%{public}d thumb=%{public}d mt=%{public}d',
        w, h, blob.length, thumbBlob ? thumbBlob.length : 0, modifiedTime)
      return true
    } catch (e) {
      hilog.error(0, TAG, 'saveCover FAILED: %{public}s', (e as Error).message)
      return false
    }
  }

  // Load cover: BLOB (JPEG) → ImageSource → PixelMap. Treats the row as a miss
  // if modifiedTime/fileSize disagree with the caller's current file stat. Pass
  // 0 for either value to skip validation. When thumbnail=true, loads the smaller
  // thumb_data column (fast for list scrolling); falls back to full cover if no
  // thumbnail is stored yet.
  static async loadCover(songId: string,
    modifiedTime: number = 0, fileSize: number = 0,
    thumbnail: boolean = false): Promise<image.PixelMap | undefined> {
    if (!(await CoverCacheDb.ensureReady())) {
      hilog.warn(0, TAG, 'loadCover: RDB not ready')
      return undefined
    }
    try {
      const columns = thumbnail
        ? ['thumb_data', 'cover_data', 'width', 'height', 'modified_time', 'file_size']
        : ['cover_data', 'width', 'height', 'modified_time', 'file_size']
      const predicates = new relationalStore.RdbPredicates(TABLE_NAME)
      predicates.equalTo('song_id', songId)
      const resultSet = await CoverCacheDb.rdbStore!.query(predicates, columns)
      if (!resultSet.goToFirstRow()) {
        resultSet.close()
        hilog.info(0, TAG, 'loadCover: no row found')
        return undefined
      }

      const storedMt = resultSet.getLong(resultSet.getColumnIndex('modified_time'))
      const storedSz = resultSet.getLong(resultSet.getColumnIndex('file_size'))

      // Staleness check
      if (modifiedTime > 0 && fileSize > 0 &&
          (storedMt !== modifiedTime || storedSz !== fileSize)) {
        resultSet.close()
        hilog.info(0, TAG, 'loadCover: stale (stored mt=%{public}d sz=%{public}d, current mt=%{public}d sz=%{public}d)',
          storedMt, storedSz, modifiedTime, fileSize)
        try {
          const delPred = new relationalStore.RdbPredicates(TABLE_NAME)
          delPred.equalTo('song_id', songId)
          await CoverCacheDb.rdbStore!.delete(delPred)
        } catch (_delErr) { /* best-effort cleanup */ }
        return undefined
      }

      // Pick data source: prefer thumbnail for list items, fallback to full cover
      let blobRaw: Uint8Array | null = null
      if (thumbnail) {
        try {
          const thumbIdx = resultSet.getColumnIndex('thumb_data')
          if (thumbIdx >= 0) {
            const thumbData = resultSet.getBlob(thumbIdx)
            if (thumbData && thumbData.length > 0) {
              blobRaw = thumbData
            }
          }
        } catch (_) {
          // thumb_data column may not exist in older schema; fall through to full cover
        }
      }
      if (!blobRaw || blobRaw.length === 0) {
        blobRaw = resultSet.getBlob(resultSet.getColumnIndex('cover_data'))
      }
      const w = resultSet.getLong(resultSet.getColumnIndex('width'))
      const h = resultSet.getLong(resultSet.getColumnIndex('height'))
      resultSet.close()

      if (!blobRaw || blobRaw.length === 0) {
        hilog.warn(0, TAG, 'loadCover: empty blob')
        return undefined
      }

      // Copy to clean ArrayBuffer
      const buffer = new ArrayBuffer(blobRaw.length)
      new Uint8Array(buffer).set(blobRaw)

      // Decode JPEG via ImageSource
      const imageSource = image.createImageSource(buffer)
      const imgInfo = await imageSource.getImageInfo()
      const decodeOpts: image.DecodingOptions = {}

      // For thumbnail requests, decode at THUMBNAIL_SIZE; for full, cap at MAX_DIM
      if (thumbnail) {
        const thumbDim = CoverCacheDb.THUMBNAIL_SIZE
        if (imgInfo.size.width > thumbDim || imgInfo.size.height > thumbDim) {
          const scale = thumbDim / Math.max(imgInfo.size.width, imgInfo.size.height)
          decodeOpts.desiredSize = {
            width: Math.round(imgInfo.size.width * scale),
            height: Math.round(imgInfo.size.height * scale)
          }
        }
      } else {
        const MAX_DIM = 2000
        if (imgInfo.size.width > MAX_DIM || imgInfo.size.height > MAX_DIM) {
          const scale = MAX_DIM / Math.max(imgInfo.size.width, imgInfo.size.height)
          decodeOpts.desiredSize = {
            width: Math.round(imgInfo.size.width * scale),
            height: Math.round(imgInfo.size.height * scale)
          }
        }
      }
      const pm = await imageSource.createPixelMap(decodeOpts)
      imageSource.release()

      hilog.info(0, TAG, 'loadCover ok: %{public}dx%{public}d blob=%{public}d thumb=%{public}s',
        w, h, blobRaw.length, thumbnail ? 'yes' : 'no')
      return pm
    } catch (e) {
      hilog.error(0, TAG, 'loadCover FAILED: %{public}s', (e as Error).message)
      return undefined
    }
  }

  // Delete the JPEG cover file from the covers directory.
  static deleteCoverFile(songId: string): void {
    if (CoverCacheDb.coverDir.length === 0 || songId.length === 0) return
    const filePath = CoverCacheDb.coverDir + '/' + CoverCacheDb.safeFileName(songId) + '.jpg'
    try { fileIo.unlinkSync(filePath) } catch (_e) { /* file may not exist */ }
  }

  // Remove a cached cover entry (used when the caller knows the row is stale).
  static async deleteCover(songId: string): Promise<void> {
    CoverCacheDb.deleteCoverFile(songId)
    if (!(await CoverCacheDb.ensureReady())) return
    try {
      const predicates = new relationalStore.RdbPredicates(TABLE_NAME)
      predicates.equalTo('song_id', songId)
      await CoverCacheDb.rdbStore!.delete(predicates)
    } catch (e) {
      hilog.warn(0, TAG, 'deleteCover failed: %{public}s', (e as Error).message)
    }
  }

  // Bulk variant — chunked file unlinks + chunked `WHERE song_id IN (...)`
  // SQL delete. Used by handleSongsRemovedFromLibrary so a 2000-song
  // multi-select removal does ~4 DB round-trips instead of 2000.
  //
  // The unlink loop is split into UNLINK_CHUNK-sized batches with a
  // setTimeout(0) yield between batches. fileIo.unlinkSync blocks the JS
  // thread per call, so a tight 2000-file loop would freeze the song-list
  // page for the full unlink duration; yielding lets ArkUI paint and other
  // user input get processed between batches.
  static async deleteCovers(songIds: string[]): Promise<void> {
    if (songIds.length === 0) return
    const UNLINK_CHUNK = 200
    for (let i = 0; i < songIds.length; i += UNLINK_CHUNK) {
      const end = Math.min(i + UNLINK_CHUNK, songIds.length)
      for (let j = i; j < end; j++) {
        CoverCacheDb.deleteCoverFile(songIds[j])
      }
      if (end < songIds.length) {
        await new Promise<void>((resolve: () => void) => setTimeout(resolve, 0))
      }
    }
    if (!(await CoverCacheDb.ensureReady())) return
    try {
      const DB_CHUNK = 500
      for (let i = 0; i < songIds.length; i += DB_CHUNK) {
        const slice = songIds.slice(i, i + DB_CHUNK)
        const predicates = new relationalStore.RdbPredicates(TABLE_NAME)
        predicates.in('song_id', slice)
        await CoverCacheDb.rdbStore!.delete(predicates)
      }
    } catch (e) {
      hilog.warn(0, TAG, 'deleteCovers failed: %{public}s', (e as Error).message)
    }
  }

  static async countCovers(): Promise<number> {
    if (!(await CoverCacheDb.ensureReady())) return -1
    try {
      const predicates = new relationalStore.RdbPredicates(TABLE_NAME)
      const resultSet = await CoverCacheDb.rdbStore!.query(predicates, ['song_id'])
      const count = resultSet.rowCount
      resultSet.close()
      return count
    } catch (_e) {
      return -1
    }
  }

  static async hasCover(songId: string): Promise<boolean> {
    if (!(await CoverCacheDb.ensureReady())) return false
    try {
      const predicates = new relationalStore.RdbPredicates(TABLE_NAME)
      predicates.equalTo('song_id', songId)
      const resultSet = await CoverCacheDb.rdbStore!.query(predicates, ['song_id'])
      const exists = resultSet.goToFirstRow()
      resultSet.close()
      return exists
    } catch (_e) {
      return false
    }
  }
}

// 缩进与空行整理，无功能变更。

// 封面缓存：缓存库读写与缓存清理失效。
