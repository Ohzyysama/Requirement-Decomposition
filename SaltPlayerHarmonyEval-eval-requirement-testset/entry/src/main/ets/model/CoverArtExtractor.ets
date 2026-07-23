// CoverArtExtractor.ets
// Model layer: extracts embedded album art from audio files using AVMetadataExtractor.
// On-demand extraction — populates CoverCacheDb (RDB persistence + JPEG file) so all
// UI components can display covers via ImageKnifePro file URIs.
//
// Called lazily when a list item scrolls into view or when a song starts playing.
// Callers must supply modifiedTime + fileSize so the caches can invalidate stale
// entries automatically (mirrors the Android CoverFetcher disk-cache key pattern).
//
// When the system API (fetchAlbumCover) fails to return a cover, format-specific
// fallback parsers are invoked to manually extract embedded artwork from:
//   FLAC (METADATA_BLOCK_PICTURE), MP3/WAV (ID3v2 APIC), M4A/AAC (MP4 covr atom),
//   OGG/Opus (Vorbis comment METADATA_BLOCK_PICTURE), APE/WV (APEv2 tag).

import { media } from '@kit.MediaKit'
import { fileIo, fileShare } from '@kit.CoreFileKit'
import { image } from '@kit.ImageKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { CoverCacheDb } from './CoverCacheDb'

const TAG = 'CoverArtExtractor'
// Max picture data size we'll attempt to read (32 MB)
const MAX_PICTURE_SIZE = 32 * 1024 * 1024
// Max file-header region to scan for metadata (16 MB)
const MAX_SCAN_SIZE = 16 * 1024 * 1024
// Front cover picture type (shared by FLAC PICTURE, ID3v2 APIC, APEv2)
const PIC_TYPE_FRONT_COVER = 3

// Result of parsing a picture block (FLAC / APIC / APEv2)
interface CoverImageResult {
  picType: number
  imageData: ArrayBuffer
}

export class CoverArtExtractor {
  // Dedup map: prevents concurrent extraction for the same songId
  private static extracting: Map<string, Promise<image.PixelMap | undefined>> = new Map()
  // Concurrency limiter: max simultaneous extractions to prevent DMA pool exhaustion
  // and AVMetadataHelper service overload
  private static readonly MAX_CONCURRENT_EXTRACTIONS = 4
  private static activeExtractions = 0
  // LIFO queue (stack) — newest requests are processed first so items the user
  // is currently looking at get their covers before items that have scrolled away.
  private static waitQueue: Array<() => void> = []

  /** Acquire an extraction slot; resolves when a slot is available. */
  private static async acquireSlot(): Promise<void> {
    if (CoverArtExtractor.activeExtractions < CoverArtExtractor.MAX_CONCURRENT_EXTRACTIONS) {
      CoverArtExtractor.activeExtractions++
      return
    }
    return new Promise<void>((resolve) => {
      CoverArtExtractor.waitQueue.push(() => {
        CoverArtExtractor.activeExtractions++
        resolve()
      })
    })
  }

  /** Release an extraction slot and wake the MOST RECENT waiter (LIFO). */
  private static releaseSlot(): void {
    CoverArtExtractor.activeExtractions--
    if (CoverArtExtractor.waitQueue.length > 0) {
      // pop() = LIFO — prioritize the newest (most recently visible) request
      const next = CoverArtExtractor.waitQueue.pop()
      if (next) next()
    }
  }

  /**
   * Extract cover art for a song and populate the RDB + file caches.
   * Returns the PixelMap if successful, undefined otherwise.
   * UI components use the resulting JPEG file via ImageKnife; the returned
   * PixelMap is consumed by CurrentSongCoverController for AVSession.
   *
   * Flow: file-cache check → dedup → RDB/file check → file extraction.
   */
  static async extractAndCache(songId: string, fileUri: string,
    modifiedTime: number = 0, fileSize: number = 0,
    _thumbnail: boolean = false): Promise<image.PixelMap | undefined> {
    // Top-level guard: this method must NEVER reject — any unhandled rejection
    // propagates to UI callers and can crash the app.
    try {
      if (!songId || songId.length === 0 || !fileUri || fileUri.length === 0) {
        return undefined
      }

      // 1. Quick file-cache check (cover JPEG already on disk?)
      if (CoverCacheDb.getCoverFileUri(songId).length > 0) {
        return undefined // file exists — UI uses file URI via ImageKnife
      }

      // 2. Deduplicate concurrent extractions for the same songId
      let existing = CoverArtExtractor.extracting.get(songId)
      if (existing) {
        return existing
      }

      // 3. Launch extraction (includes RDB check + file extraction)
      const promise = CoverArtExtractor.doExtract(songId, fileUri, modifiedTime, fileSize)
      CoverArtExtractor.extracting.set(songId, promise)

      return promise.then((pm: image.PixelMap | undefined) => {
        CoverArtExtractor.extracting.delete(songId)
        return pm
      }).catch((_e: Error): undefined => {
        CoverArtExtractor.extracting.delete(songId)
        hilog.error(0, TAG, 'extractAndCache failed: %{public}s', _e.message)
        return undefined
      })
    } catch (outerError) {
      // Catch-all: covers sync throws from getSync/getPixelMap/Map ops, etc.
      try { CoverArtExtractor.extracting.delete(songId) } catch (_) { /* */ }
      hilog.error(0, TAG, 'extractAndCache critical: %{public}s',
        (outerError instanceof Error) ? outerError.message : String(outerError))
      return undefined
    }
  }


  /**
   * Extract embedded album art from audio file and save to RDB + file cache.
   * If modifiedTime/fileSize are 0, they are read from file stat.
   * Uses a concurrency limiter to avoid DMA pool exhaustion and service overload.
   *
   * Flow: acquire slot → re-check file cache (may have been written while queued)
   *     → check RDB → extract from file → persist + return.
   */
  private static async doExtract(songId: string, fileUri: string,
    modifiedTime: number, fileSize: number): Promise<image.PixelMap | undefined> {
    // Wait for a slot before starting the heavy work
    await CoverArtExtractor.acquireSlot()

    // Re-check file cache — another extraction may have completed while queued.
    if (CoverCacheDb.getCoverFileUri(songId).length > 0) {
      CoverArtExtractor.releaseSlot()
      return undefined
    }

    // Check RDB cache (only now, after acquiring the slot — avoids flooding
    // the database with queries from all queued items at once).
    // If RDB has the blob, ensure the JPEG file is written.
    try {
      const fileUri = await CoverCacheDb.ensureCoverFile(songId)
      if (fileUri.length > 0) {
        CoverArtExtractor.releaseSlot()
        return undefined
      }
    } catch (_rdbErr) {
      // RDB failed — proceed to file extraction
    }

    // --- From here, the finally block is responsible for releaseSlot() ---
    let file: fileIo.File | null = null
    let extractor: media.AVMetadataExtractor | null = null

    try {
      // Activate permission (may have expired after app restart)
      try {
        const policy: fileShare.PolicyInfo = {
          uri: fileUri,
          operationMode: fileShare.OperationMode.READ_MODE
        } as fileShare.PolicyInfo
        await fileShare.activatePermission([policy])
      } catch (_permErr) {
        // Permission may already be active — ignore
      }

      // Open file
      file = fileIo.openSync(fileUri, fileIo.OpenMode.READ_ONLY)
      const stat = fileIo.statSync(file.fd)

      // Use file-stat values when the caller didn't supply them
      const effectiveMt = modifiedTime > 0 ? modifiedTime : stat.mtime
      const effectiveSz = fileSize > 0 ? fileSize : stat.size

      // Create extractor and set source
      extractor = await media.createAVMetadataExtractor()
      extractor.fdSrc = { fd: file.fd, offset: 0, length: stat.size }

      // Extract album cover via system API
      let pixelMap: image.PixelMap | undefined = undefined
      try {
        pixelMap = await extractor.fetchAlbumCover()
      } catch (fetchErr) {
        hilog.warn(0, TAG, 'fetchAlbumCover threw for %{public}s: %{public}s',
          songId.substring(songId.length - 30), (fetchErr as Error).message)
      }

      // Fallback: manually parse audio file metadata for covers that the system
      // API may not decode (e.g. PNG-in-FLAC, certain ID3v2 APIC frames, etc.)
      if (!pixelMap) {
        pixelMap = await CoverArtExtractor.extractCoverFallback(file.fd, stat.size, fileUri)
        if (pixelMap) {
          hilog.info(0, TAG, 'Extracted cover via manual fallback for %{public}s',
            songId.substring(songId.length - 30))
        }
      }

      if (!pixelMap) {
        hilog.info(0, TAG, 'No embedded cover for songId=%{public}s',
          songId.substring(songId.length - 30))
        return undefined
      }

      hilog.info(0, TAG, 'Extracted cover for songId=%{public}s',
        songId.substring(songId.length - 30))

      // Downscale to max 800px before persisting.
      // List items display at 50vp (~200px), player at ~360vp (~800px);
      // 800px is sufficient for both while dramatically reducing JPEG size.
      const coverInfo = await pixelMap.getImageInfo()
      const coverMaxDim = Math.max(coverInfo.size.width, coverInfo.size.height)
      const MAX_MEMORY_DIM = 800
      if (coverMaxDim > MAX_MEMORY_DIM) {
        const scaleFactor = MAX_MEMORY_DIM / coverMaxDim
        await pixelMap.scale(scaleFactor, scaleFactor)
      }

      // Persist to RDB and write cover JPEG file (for ImageKnife).
      // Awaited so the file exists when extractAndCache resolves.
      await CoverCacheDb.saveCover(songId, pixelMap, effectiveMt, effectiveSz)
        .catch((_e: Error) => {
          hilog.warn(0, TAG, 'saveCover failed: %{public}s', _e.message)
        })

      return pixelMap
    } catch (e) {
      hilog.warn(0, TAG, 'Extract failed for %{public}s: %{public}s',
        songId.substring(songId.length - 30), (e as Error).message)
      return undefined
    } finally {
      // Release concurrency slot
      CoverArtExtractor.releaseSlot()
      // Release extractor
      if (extractor) {
        try {
          await extractor.release()
        } catch (_) { /* ignore */ }
      }
      // Close file
      if (file) {
        try {
          fileIo.closeSync(file)
        } catch (_) { /* ignore */ }
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Format dispatcher — detects format via file magic, falls back to APEv2
  // ─────────────────────────────────────────────────────────────────────────

  private static async extractCoverFallback(fd: number, fileSize: number,
    fileUri: string): Promise<image.PixelMap | undefined> {
    if (fileSize < 12) return undefined

    // Read first 12 bytes for format detection
    let header: Uint8Array
    try {
      const headerBuf = new ArrayBuffer(12)
      fileIo.readSync(fd, headerBuf, { offset: 0, length: 12 })
      header = new Uint8Array(headerBuf)
    } catch (e) {
      hilog.warn(0, TAG, 'Failed to read file header: %{public}s', (e as Error).message)
      return undefined
    }

    // FLAC: "fLaC" magic
    if (header[0] === 0x66 && header[1] === 0x4C &&
      header[2] === 0x61 && header[3] === 0x43) {
      return await CoverArtExtractor.safeParserCall('FLAC',
        () => CoverArtExtractor.extractFlacPicture(fd, fileSize))
    }

    // ID3v2: "ID3" magic (MP3, some AAC, some WAV)
    if (header[0] === 0x49 && header[1] === 0x44 && header[2] === 0x33) {
      const id3Result = await CoverArtExtractor.safeParserCall('ID3v2',
        () => CoverArtExtractor.extractId3v2Picture(fd, fileSize, 0))
      if (id3Result) return id3Result
      // MP3 may also have APEv2 tags at end of file
      return await CoverArtExtractor.safeParserCall('APEv2',
        () => CoverArtExtractor.extractApev2Cover(fd, fileSize))
    }

    // RIFF/WAVE: may contain ID3v2 in an "id3 " or "ID32" chunk
    if (header[0] === 0x52 && header[1] === 0x49 &&
      header[2] === 0x46 && header[3] === 0x46 &&
      header[8] === 0x57 && header[9] === 0x41 &&
      header[10] === 0x56 && header[11] === 0x45) {
      return await CoverArtExtractor.safeParserCall('WAV',
        () => CoverArtExtractor.extractWavPicture(fd, fileSize))
    }

    // AIFF: "FORM" at 0–3, "AIFF" or "AIFC" at 8–11 (IFF container, big-endian)
    if (header[0] === 0x46 && header[1] === 0x4F &&
      header[2] === 0x52 && header[3] === 0x4D &&
      header[8] === 0x41 && header[9] === 0x49 && header[10] === 0x46 &&
      (header[11] === 0x46 || header[11] === 0x43)) {
      return await CoverArtExtractor.safeParserCall('AIFF',
        () => CoverArtExtractor.extractAiffPicture(fd, fileSize))
    }

    // OGG: "OggS" magic (Vorbis, Opus, FLAC-in-OGG)
    if (header[0] === 0x4F && header[1] === 0x67 &&
      header[2] === 0x67 && header[3] === 0x53) {
      return await CoverArtExtractor.safeParserCall('OGG',
        () => CoverArtExtractor.extractOggPicture(fd, fileSize))
    }

    // MP4/M4A/AAC-in-MP4: "ftyp" box at bytes 4–7
    if (header[4] === 0x66 && header[5] === 0x74 &&
      header[6] === 0x79 && header[7] === 0x70) {
      return await CoverArtExtractor.safeParserCall('MP4',
        () => CoverArtExtractor.extractMp4Cover(fd, fileSize))
    }

    // DSF (DSD Stream File): "DSD " at 0–3, ID3v2 offset stored in header
    if (header[0] === 0x44 && header[1] === 0x53 &&
      header[2] === 0x44 && header[3] === 0x20) {
      return await CoverArtExtractor.safeParserCall('DSF',
        () => CoverArtExtractor.extractDsfPicture(fd, fileSize))
    }

    // DFF (DSDIFF): "FRM8" at 0–3, ID3v2 appended after container
    if (header[0] === 0x46 && header[1] === 0x52 &&
      header[2] === 0x4D && header[3] === 0x38) {
      return await CoverArtExtractor.safeParserCall('DFF',
        () => CoverArtExtractor.extractDffPicture(fd, fileSize))
    }

    // Last resort: APEv2 at end of file (covers APE, WavPack, some MP3)
    return await CoverArtExtractor.safeParserCall('APEv2',
      () => CoverArtExtractor.extractApev2Cover(fd, fileSize))
  }

  /** Run a parser function, catching any error so one bad file never crashes the app. */
  private static async safeParserCall(label: string,
    fn: () => Promise<image.PixelMap | undefined>): Promise<image.PixelMap | undefined> {
    try {
      return await fn()
    } catch (e) {
      hilog.warn(0, TAG, '%{public}s parser threw: %{public}s', label,
        (e instanceof Error) ? e.message : String(e))
      return undefined
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  FLAC — METADATA_BLOCK_PICTURE (block type 6)
  // ─────────────────────────────────────────────────────────────────────────

  private static async extractFlacPicture(fd: number,
    fileSize: number): Promise<image.PixelMap | undefined> {
    // "fLaC" already verified by caller — skip it
    let pos = 4
    let bestPicture: ArrayBuffer | null = null

    while (pos + 4 <= fileSize) {
      const hdrBuf = new ArrayBuffer(4)
      fileIo.readSync(fd, hdrBuf, { offset: pos, length: 4 })
      const hdr = new Uint8Array(hdrBuf)
      const isLast = (hdr[0] & 0x80) !== 0
      const blockType = hdr[0] & 0x7F
      const blockLength = (hdr[1] << 16) | (hdr[2] << 8) | hdr[3]
      pos += 4

      if (blockType === 6 && blockLength > 32 && blockLength <= MAX_PICTURE_SIZE) {
        const blockBuf = new ArrayBuffer(blockLength)
        fileIo.readSync(fd, blockBuf, { offset: pos, length: blockLength })
        const block = new Uint8Array(blockBuf)

        const result = CoverArtExtractor.parseFlacPictureBlockData(block)
        if (result) {
          if (result.picType === PIC_TYPE_FRONT_COVER) {
            return await CoverArtExtractor.decodeImageBuffer(result.imageData)
          }
          if (!bestPicture) {
            bestPicture = result.imageData
          }
        }
      }

      pos += blockLength
      if (isLast) break
    }

    if (bestPicture) {
      return await CoverArtExtractor.decodeImageBuffer(bestPicture)
    }
    return undefined
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  ID3v2 — APIC frame (MP3, WAV-embedded, some AAC)
  // ─────────────────────────────────────────────────────────────────────────

  private static async extractId3v2Picture(fd: number, fileSize: number,
    startOffset: number): Promise<image.PixelMap | undefined> {
    if (startOffset + 10 > fileSize) return undefined

    // Read 10-byte ID3v2 header: "ID3" + version(2) + flags(1) + size(4 syncsafe)
    const headerBuf = new ArrayBuffer(10)
    fileIo.readSync(fd, headerBuf, { offset: startOffset, length: 10 })
    const h = new Uint8Array(headerBuf)

    if (h[0] !== 0x49 || h[1] !== 0x44 || h[2] !== 0x33) return undefined
    const majorVersion = h[3]
    if (majorVersion < 2 || majorVersion > 4) return undefined

    const flags = h[5]
    const tagSize = CoverArtExtractor.readSyncsafeInt(h, 6)
    if (!CoverArtExtractor.isValidSize(tagSize, MAX_SCAN_SIZE)) return undefined
    if (startOffset + 10 + tagSize > fileSize) return undefined

    const tagBuf = new ArrayBuffer(tagSize)
    fileIo.readSync(fd, tagBuf, { offset: startOffset + 10, length: tagSize })
    const tag = new Uint8Array(tagBuf)

    // Handle extended header (skip it)
    let frameStart = 0
    if ((flags & 0x40) !== 0) {
      if (majorVersion === 4) {
        // v2.4: extended header size is syncsafe, includes itself
        frameStart = CoverArtExtractor.readSyncsafeInt(tag, 0)
      } else {
        // v2.3: size is big-endian u32, does NOT include itself
        frameStart = CoverArtExtractor.readU32BE(tag, 0) + 4
      }
    }

    const frameIdLen = majorVersion === 2 ? 3 : 4
    const frameHeaderLen = majorVersion === 2 ? 6 : 10
    const apicId = majorVersion === 2 ? 'PIC' : 'APIC'

    let pos = frameStart
    let bestPicture: ArrayBuffer | null = null

    while (pos + frameHeaderLen <= tagSize) {
      // Padding detection
      if (tag[pos] === 0) break

      // Read frame ID
      let frameId = ''
      for (let i = 0; i < frameIdLen; i++) {
        frameId += String.fromCharCode(tag[pos + i])
      }

      // Read frame size
      let frameSize: number
      if (majorVersion === 2) {
        frameSize = (tag[pos + 3] << 16) | (tag[pos + 4] << 8) | tag[pos + 5]
      } else if (majorVersion === 4) {
        frameSize = CoverArtExtractor.readSyncsafeInt(tag, pos + 4)
      } else {
        frameSize = CoverArtExtractor.readU32BE(tag, pos + 4)
      }
      pos += frameHeaderLen

      if (frameSize <= 0 || pos + frameSize > tagSize) break

      if (frameId === apicId) {
        const result = CoverArtExtractor.parseApicFrame(tag, pos, frameSize, majorVersion)
        if (result) {
          if (result.picType === PIC_TYPE_FRONT_COVER) {
            return await CoverArtExtractor.decodeImageBuffer(result.imageData)
          }
          if (!bestPicture) {
            bestPicture = result.imageData
          }
        }
      }

      pos += frameSize
    }

    if (bestPicture) {
      return await CoverArtExtractor.decodeImageBuffer(bestPicture)
    }
    return undefined
  }

  /** Parse a single ID3v2 APIC (or v2.2 PIC) frame. */
  private static parseApicFrame(tag: Uint8Array, offset: number, size: number,
    version: number): CoverImageResult | null {
    let pos = offset
    const end = offset + size
    if (pos + 4 >= end) return null

    const encoding = tag[pos]; pos += 1

    if (version === 2) {
      // PIC: encoding(1) + imageFormat(3) + picType(1) + description(null) + data
      pos += 3 // skip image format ("JPG", "PNG", etc.)
      if (pos >= end) return null
      const picType = tag[pos]; pos += 1
      pos = CoverArtExtractor.skipNullTerminated(tag, pos, end, encoding)
      if (pos >= end) return null
      return { picType: picType, imageData: tag.buffer.slice(pos, end) }
    } else {
      // APIC: encoding(1) + MIME(null-term ASCII) + picType(1) + description(null) + data
      while (pos < end && tag[pos] !== 0) pos++ // skip MIME
      pos++ // skip null
      if (pos >= end) return null
      const picType = tag[pos]; pos += 1
      pos = CoverArtExtractor.skipNullTerminated(tag, pos, end, encoding)
      if (pos >= end) return null
      return { picType: picType, imageData: tag.buffer.slice(pos, end) }
    }
  }

  /** Advance past a null-terminated string respecting text encoding. */
  private static skipNullTerminated(data: Uint8Array, pos: number,
    end: number, encoding: number): number {
    if (encoding === 1 || encoding === 2) {
      // UTF-16 (LE/BE): double-byte null terminator 0x00 0x00
      while (pos + 1 < end) {
        if (data[pos] === 0 && data[pos + 1] === 0) return pos + 2
        pos += 2
      }
      return end
    }
    // ISO-8859-1 (0) or UTF-8 (3): single-byte null
    while (pos < end && data[pos] !== 0) pos++
    return pos + 1
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  WAV — RIFF chunks containing ID3v2
  // ─────────────────────────────────────────────────────────────────────────

  private static async extractWavPicture(fd: number,
    fileSize: number): Promise<image.PixelMap | undefined> {
    // RIFF/WAVE already verified by caller — iterate chunks starting after header
    let pos = 12
    const maxPos = Math.min(fileSize, MAX_SCAN_SIZE)

    while (pos + 8 <= maxPos) {
      const chunkHdrBuf = new ArrayBuffer(8)
      fileIo.readSync(fd, chunkHdrBuf, { offset: pos, length: 8 })
      const chunkHdr = new Uint8Array(chunkHdrBuf)

      let chunkId = ''
      for (let i = 0; i < 4; i++) chunkId += String.fromCharCode(chunkHdr[i])
      const chunkSize = CoverArtExtractor.readU32LE(chunkHdr, 4)
      pos += 8

      // "id3 " or "ID32" chunk contains an ID3v2 tag
      const chunkIdLower = chunkId.toLowerCase()
      if ((chunkIdLower === 'id3 ' || chunkIdLower === 'id32') &&
        chunkSize > 10 && chunkSize <= MAX_SCAN_SIZE) {
        return await CoverArtExtractor.extractId3v2Picture(fd, pos + chunkSize, pos)
      }

      pos += chunkSize
      if (chunkSize % 2 !== 0) pos++ // RIFF chunks are word-aligned
    }
    return undefined
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  AIFF — IFF container with ID3v2 chunk (big-endian sizes)
  // ─────────────────────────────────────────────────────────────────────────

  private static async extractAiffPicture(fd: number,
    fileSize: number): Promise<image.PixelMap | undefined> {
    // FORM/AIFF|AIFC already verified — iterate chunks starting after 12-byte header
    let pos = 12
    const maxPos = Math.min(fileSize, MAX_SCAN_SIZE)

    while (pos + 8 <= maxPos) {
      const chunkHdrBuf = new ArrayBuffer(8)
      fileIo.readSync(fd, chunkHdrBuf, { offset: pos, length: 8 })
      const chunkHdr = new Uint8Array(chunkHdrBuf)

      let chunkId = ''
      for (let i = 0; i < 4; i++) chunkId += String.fromCharCode(chunkHdr[i])
      const chunkSize = CoverArtExtractor.readU32BE(chunkHdr, 4) // AIFF is big-endian
      pos += 8

      // "ID3 " or "id3 " chunk contains an ID3v2 tag
      const chunkIdLower = chunkId.toLowerCase()
      if ((chunkIdLower === 'id3 ' || chunkIdLower === 'id32') &&
        chunkSize > 10 && CoverArtExtractor.isValidSize(chunkSize, MAX_SCAN_SIZE)) {
        return await CoverArtExtractor.extractId3v2Picture(fd, pos + chunkSize, pos)
      }

      pos += chunkSize
      if (chunkSize % 2 !== 0) pos++ // IFF chunks are word-aligned
    }
    return undefined
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  MP4/M4A/AAC — covr atom in iTunes metadata
  // ─────────────────────────────────────────────────────────────────────────

  private static async extractMp4Cover(fd: number,
    fileSize: number): Promise<image.PixelMap | undefined> {
    // Navigate box hierarchy: moov > udta > meta > ilst > covr
    // Then read the first 'data' sub-box inside 'covr'
    const path: string[] = ['moov', 'udta', 'meta', 'ilst', 'covr', 'data']
    const dataBox = CoverArtExtractor.findMp4Box(fd, 0, Math.min(fileSize, MAX_SCAN_SIZE), path)
    if (!dataBox || dataBox.byteLength <= 8) return undefined

    // 'data' box content: type_indicator(4) + locale(4) + image_bytes
    const imageData = dataBox.slice(8)
    return await CoverArtExtractor.decodeImageBuffer(imageData)
  }

  /**
   * Recursively locate an MP4 box by traversing the path.
   * Returns the box content (excluding 8-byte header) when the leaf is reached.
   */
  private static findMp4Box(fd: number, start: number, end: number,
    path: string[]): ArrayBuffer | null {
    if (path.length === 0 || start >= end) return null
    const target = path[0]
    let pos = start

    while (pos + 8 <= end) {
      const hdrBuf = new ArrayBuffer(8)
      fileIo.readSync(fd, hdrBuf, { offset: pos, length: 8 })
      const hdr = new Uint8Array(hdrBuf)

      let boxSize = CoverArtExtractor.readU32BE(hdr, 0)
      let boxType = ''
      for (let i = 4; i < 8; i++) boxType += String.fromCharCode(hdr[i])

      // size == 0 means box extends to EOF; size == 1 means 64-bit extended size
      if (boxSize === 0) {
        boxSize = end - pos
      } else if (boxSize === 1) {
        // 64-bit extended size — skip (extremely rare for metadata)
        break
      }
      if (boxSize < 8) break // invalid

      if (boxType === target) {
        if (path.length === 1) {
          // Leaf — return box content
          const contentSize = boxSize - 8
          if (contentSize <= 0 || contentSize > MAX_PICTURE_SIZE) return null
          const contentBuf = new ArrayBuffer(contentSize)
          fileIo.readSync(fd, contentBuf, { offset: pos + 8, length: contentSize })
          return contentBuf
        }
        // Recurse into children
        let childStart = pos + 8
        // 'meta' is a full box with 4-byte version+flags before children
        if (boxType === 'meta') childStart += 4
        return CoverArtExtractor.findMp4Box(fd, childStart, pos + boxSize,
          path.slice(1))
      }

      pos += boxSize
    }
    return null
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  OGG (Vorbis / Opus) — Vorbis comment METADATA_BLOCK_PICTURE
  // ─────────────────────────────────────────────────────────────────────────

  private static async extractOggPicture(fd: number,
    fileSize: number): Promise<image.PixelMap | undefined> {
    const commentData = CoverArtExtractor.readOggCommentPacket(fd, fileSize)
    if (!commentData || commentData.length < 16) return undefined

    // Determine comment header prefix:
    //   Opus:   "OpusTags" (8 bytes)
    //   Vorbis: 0x03 + "vorbis" (7 bytes)
    let prefixLen = 0
    if (commentData.length > 8 &&
      commentData[0] === 0x4F && commentData[1] === 0x70 &&
      commentData[2] === 0x75 && commentData[3] === 0x73 &&
      commentData[4] === 0x54 && commentData[5] === 0x61 &&
      commentData[6] === 0x67 && commentData[7] === 0x73) {
      prefixLen = 8 // "OpusTags"
    } else if (commentData.length > 7 &&
      commentData[0] === 0x03 &&
      commentData[1] === 0x76 && commentData[2] === 0x6F &&
      commentData[3] === 0x72 && commentData[4] === 0x62 &&
      commentData[5] === 0x69 && commentData[6] === 0x73) {
      prefixLen = 7 // "\x03vorbis"
    } else {
      return undefined
    }

    // Parse Vorbis comment structure
    let off = prefixLen
    if (off + 4 > commentData.length) return undefined
    const vendorLen = CoverArtExtractor.readU32LE(commentData, off); off += 4
    off += vendorLen
    if (off + 4 > commentData.length) return undefined
    const numComments = CoverArtExtractor.readU32LE(commentData, off); off += 4

    // Case-insensitive key to match
    const pictureKey = 'metadata_block_picture='
    let bestPicture: ArrayBuffer | null = null

    for (let i = 0; i < numComments && off + 4 <= commentData.length; i++) {
      const commentLen = CoverArtExtractor.readU32LE(commentData, off); off += 4
      if (commentLen <= 0 || off + commentLen > commentData.length) break

      if (commentLen > pictureKey.length) {
        // Case-insensitive prefix match
        let matches = true
        for (let j = 0; j < pictureKey.length; j++) {
          const c = commentData[off + j]
          const lower = (c >= 0x41 && c <= 0x5A) ? (c | 0x20) : c
          if (lower !== pictureKey.charCodeAt(j)) {
            matches = false
            break
          }
        }

        if (matches) {
          const b64Start = off + pictureKey.length
          const b64Len = commentLen - pictureKey.length
          const decoded = CoverArtExtractor.base64Decode(commentData, b64Start, b64Len)
          if (decoded) {
            const result = CoverArtExtractor.parseFlacPictureBlockData(decoded)
            if (result) {
              if (result.picType === PIC_TYPE_FRONT_COVER) {
                return await CoverArtExtractor.decodeImageBuffer(result.imageData)
              }
              if (!bestPicture) {
                bestPicture = result.imageData
              }
            }
          }
        }
      }
      off += commentLen
    }

    if (bestPicture) {
      return await CoverArtExtractor.decodeImageBuffer(bestPicture)
    }
    return undefined
  }

  /**
   * Read OGG pages and assemble the second logical packet (comment header).
   * The first packet is the identification header; the second contains Vorbis
   * comments (and thus the METADATA_BLOCK_PICTURE values).
   */
  private static readOggCommentPacket(fd: number, fileSize: number): Uint8Array | null {
    let pos = 0
    let packetNum = 0 // 0 = identification, 1 = comment
    let parts: ArrayBuffer[] = []
    let totalSize = 0

    while (pos + 27 <= fileSize && pos < MAX_SCAN_SIZE && packetNum <= 1) {
      // OGG page header: 27 fixed bytes
      const hdrBuf = new ArrayBuffer(27)
      fileIo.readSync(fd, hdrBuf, { offset: pos, length: 27 })
      const hdr = new Uint8Array(hdrBuf)

      // Verify "OggS" capture pattern
      if (hdr[0] !== 0x4F || hdr[1] !== 0x67 ||
        hdr[2] !== 0x67 || hdr[3] !== 0x53) return null

      const numSegments = hdr[26]

      // Read segment table
      const segBuf = new ArrayBuffer(numSegments)
      fileIo.readSync(fd, segBuf, { offset: pos + 27, length: numSegments })
      const segTable = new Uint8Array(segBuf)

      // Calculate total page data size
      let pageDataSize = 0
      for (let s = 0; s < numSegments; s++) pageDataSize += segTable[s]

      const dataStart = pos + 27 + numSegments
      const dataBuf = new ArrayBuffer(pageDataSize)
      fileIo.readSync(fd, dataBuf, { offset: dataStart, length: pageDataSize })

      // Walk segments to track packet boundaries
      let dataPos = 0
      for (let s = 0; s < numSegments; s++) {
        const segSize = segTable[s]

        if (packetNum === 1 && segSize > 0) {
          parts.push(dataBuf.slice(dataPos, dataPos + segSize))
          totalSize += segSize
        }
        dataPos += segSize

        // A segment < 255 bytes terminates the current packet
        if (segSize < 255) {
          if (packetNum === 1) {
            // Comment packet complete
            return CoverArtExtractor.assembleBuffer(parts, totalSize)
          }
          packetNum++
          parts = []
          totalSize = 0
        }
      }

      pos = dataStart + pageDataSize
    }

    // Comment packet may extend to last page without a terminating short segment
    if (packetNum === 1 && totalSize > 0) {
      return CoverArtExtractor.assembleBuffer(parts, totalSize)
    }
    return null
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  APEv2 — Cover Art item (APE, WavPack, some MP3)
  // ─────────────────────────────────────────────────────────────────────────

  private static async extractApev2Cover(fd: number,
    fileSize: number): Promise<image.PixelMap | undefined> {
    if (fileSize < 32) return undefined

    // APEv2 footer is the last 32 bytes: "APETAGEX" + version + tagSize + ...
    const footerBuf = new ArrayBuffer(32)
    fileIo.readSync(fd, footerBuf, { offset: fileSize - 32, length: 32 })
    const footer = new Uint8Array(footerBuf)

    // Verify "APETAGEX" magic
    const apeMagic = [0x41, 0x50, 0x45, 0x54, 0x41, 0x47, 0x45, 0x58]
    for (let i = 0; i < 8; i++) {
      if (footer[i] !== apeMagic[i]) return undefined
    }

    const tagSize = CoverArtExtractor.readU32LE(footer, 12) // includes footer
    const itemCount = CoverArtExtractor.readU32LE(footer, 16)
    if (tagSize < 32 || tagSize > MAX_SCAN_SIZE) return undefined

    const flags = CoverArtExtractor.readU32LE(footer, 20)
    const hasHeader = (flags & (1 << 29)) !== 0

    // Items start after the optional header, before the footer
    const tagStart = fileSize - tagSize
    const itemsStart = hasHeader ? tagStart + 32 : tagStart
    const itemsSize = fileSize - 32 - itemsStart
    if (itemsSize <= 0 || itemsSize > MAX_SCAN_SIZE) return undefined

    const itemsBuf = new ArrayBuffer(itemsSize)
    fileIo.readSync(fd, itemsBuf, { offset: itemsStart, length: itemsSize })
    const items = new Uint8Array(itemsBuf)

    let pos = 0
    let bestPicture: ArrayBuffer | null = null

    for (let i = 0; i < itemCount && pos + 8 < itemsSize; i++) {
      const valueSize = CoverArtExtractor.readU32LE(items, pos); pos += 4
      pos += 4 // item flags

      // Read null-terminated key
      let keyEnd = pos
      while (keyEnd < itemsSize && items[keyEnd] !== 0) keyEnd++
      let key = ''
      for (let j = pos; j < keyEnd; j++) key += String.fromCharCode(items[j])
      pos = keyEnd + 1 // skip null terminator

      if (pos + valueSize > itemsSize) break

      const keyLower = key.toLowerCase()
      if (keyLower === 'cover art (front)' || keyLower === 'cover art (back)' ||
        keyLower === 'cover art (other)') {
        // Value: filename (null-terminated) + raw image bytes
        let nullPos = pos
        while (nullPos < pos + valueSize && items[nullPos] !== 0) nullPos++
        const imageStart = nullPos + 1
        const imageLen = valueSize - (imageStart - pos)

        if (imageLen > 0) {
          const imageData = itemsBuf.slice(imageStart, imageStart + imageLen)
          if (keyLower === 'cover art (front)') {
            return await CoverArtExtractor.decodeImageBuffer(imageData)
          }
          if (!bestPicture) {
            bestPicture = imageData
          }
        }
      }
      pos += valueSize
    }

    if (bestPicture) {
      return await CoverArtExtractor.decodeImageBuffer(bestPicture)
    }
    return undefined
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  DSF (DSD Stream File) — ID3v2 at metadata offset stored in DSD chunk
  // ─────────────────────────────────────────────────────────────────────────

  private static async extractDsfPicture(fd: number,
    fileSize: number): Promise<image.PixelMap | undefined> {
    // "DSD " magic already verified. The 28-byte DSD chunk contains:
    //   offset 20..27  =  little-endian uint64  ID3v2 metadata offset
    // If the offset is 0, no metadata is embedded.
    if (fileSize < 28) return undefined

    const dsfBuf = new ArrayBuffer(28)
    fileIo.readSync(fd, dsfBuf, { offset: 0, length: 28 })
    const dsf = new Uint8Array(dsfBuf)

    const metaLow = CoverArtExtractor.readU32LE(dsf, 20)
    const metaHigh = CoverArtExtractor.readU32LE(dsf, 24)

    if (metaLow === 0 && metaHigh === 0) return undefined // no metadata
    if (metaHigh !== 0) return undefined // offset > 4 GB, skip
    if (metaLow < 28 || metaLow >= fileSize) return undefined // out of range

    return await CoverArtExtractor.extractId3v2Picture(fd, fileSize, metaLow)
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  DFF (DSDIFF) — ID3v2 appended after the FRM8 container (non-standard
  //  but widely used by tagging tools; the DSDIFF spec has no native cover)
  // ─────────────────────────────────────────────────────────────────────────

  private static async extractDffPicture(fd: number,
    fileSize: number): Promise<image.PixelMap | undefined> {
    // "FRM8" magic already verified. Read full 16-byte header to get:
    //   offset 4..11  =  big-endian uint64  FRM8 data size (excludes first 12 bytes)
    //   offset 12..15 =  form type, must be "DSD "
    if (fileSize < 16) return undefined

    const hdrBuf = new ArrayBuffer(16)
    fileIo.readSync(fd, hdrBuf, { offset: 0, length: 16 })
    const hdr = new Uint8Array(hdrBuf)

    // Verify form type "DSD "
    if (hdr[12] !== 0x44 || hdr[13] !== 0x53 ||
      hdr[14] !== 0x44 || hdr[15] !== 0x20) return undefined

    // FRM8 data size (big-endian uint64) — treat high 4 bytes as overflow guard
    const sizeHigh = CoverArtExtractor.readU32BE(hdr, 4)
    const sizeLow = CoverArtExtractor.readU32BE(hdr, 8)
    if (sizeHigh !== 0) return undefined // container > 4 GB, skip

    // Container ends at: 4 (FRM8 ID) + 8 (size field) + data_size
    const containerEnd = 12 + sizeLow
    if (containerEnd < 16 || containerEnd >= fileSize) return undefined

    // If there's trailing data, probe for an appended ID3v2 tag
    return await CoverArtExtractor.extractId3v2Picture(fd, fileSize, containerEnd)
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Shared helpers
  // ─────────────────────────────────────────────────────────────────────────

  /**
   * Parse a FLAC PICTURE block (used both in native FLAC files and in OGG
   * Vorbis comments where METADATA_BLOCK_PICTURE is base64-encoded).
   */
  private static parseFlacPictureBlockData(data: Uint8Array): CoverImageResult | null {
    if (data.length < 32) return null

    let off = 0
    const picType = CoverArtExtractor.readU32BE(data, off); off += 4
    const mimeLen = CoverArtExtractor.readU32BE(data, off); off += 4
    off += mimeLen
    if (off + 4 > data.length) return null
    const descLen = CoverArtExtractor.readU32BE(data, off); off += 4
    off += descLen
    if (off + 20 > data.length) return null
    off += 16 // width(4) + height(4) + depth(4) + colors(4)
    const dataLen = CoverArtExtractor.readU32BE(data, off); off += 4

    if (dataLen > 0 && off + dataLen <= data.length) {
      const imageData = data.buffer.slice(data.byteOffset + off,
        data.byteOffset + off + dataLen)
      return { picType: picType, imageData: imageData }
    }
    return null
  }

  /** Assemble multiple ArrayBuffer parts into a single Uint8Array. */
  private static assembleBuffer(parts: ArrayBuffer[], totalSize: number): Uint8Array {
    const result = new Uint8Array(totalSize)
    let offset = 0
    for (const part of parts) {
      result.set(new Uint8Array(part), offset)
      offset += part.byteLength
    }
    return result
  }

  /**
   * Decode base64 from raw bytes (no string conversion needed).
   * Operates directly on a Uint8Array slice for efficiency with large covers.
   */
  private static base64Decode(data: Uint8Array, start: number,
    length: number): Uint8Array | null {
    if (length <= 0) return null

    // Build lookup table: ASCII char code → 6-bit value
    const lookup = new Array<number>(128)
    for (let i = 0; i < 128; i++) lookup[i] = -1
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    for (let i = 0; i < 64; i++) lookup[chars.charCodeAt(i)] = i

    // Skip trailing '=' padding
    let end = start + length
    while (end > start && data[end - 1] === 0x3D) end--
    const inputLen = end - start

    const outLen = Math.floor(inputLen * 3 / 4)
    const out = new Uint8Array(outLen)
    let j = 0

    for (let i = start; i < end; i += 4) {
      const a = i < end && data[i] < 128 ? lookup[data[i]] : 0
      const b = i + 1 < end && data[i + 1] < 128 ? lookup[data[i + 1]] : 0
      const c = i + 2 < end && data[i + 2] < 128 ? lookup[data[i + 2]] : 0
      const d = i + 3 < end && data[i + 3] < 128 ? lookup[data[i + 3]] : 0
      if (a < 0 || b < 0 || c < 0 || d < 0) return null // invalid char

      const n = (a << 18) | (b << 12) | (c << 6) | d
      if (j < outLen) out[j++] = (n >> 16) & 0xFF
      if (j < outLen) out[j++] = (n >> 8) & 0xFF
      if (j < outLen) out[j++] = n & 0xFF
    }
    return out
  }

  /** Guard: reject NaN, negative, fractional, or excessively large allocation sizes. */
  private static isValidSize(size: number, limit: number = MAX_PICTURE_SIZE): boolean {
    return Number.isFinite(size) && size > 0 && size <= limit && (size | 0) === size
  }

  /** Read a big-endian uint32 from a Uint8Array at the given offset. */
  private static readU32BE(u8: Uint8Array, offset: number): number {
    return (u8[offset] * 0x1000000) +
      ((u8[offset + 1] << 16) | (u8[offset + 2] << 8) | u8[offset + 3])
  }

  /** Read a little-endian uint32 from a Uint8Array at the given offset. */
  private static readU32LE(u8: Uint8Array, offset: number): number {
    return u8[offset] | (u8[offset + 1] << 8) |
      (u8[offset + 2] << 16) | (u8[offset + 3] * 0x1000000)
  }

  /** Read an ID3v2 syncsafe integer (4 bytes, 7 bits per byte). */
  private static readSyncsafeInt(u8: Uint8Array, offset: number): number {
    return ((u8[offset] & 0x7F) << 21) |
      ((u8[offset + 1] & 0x7F) << 14) |
      ((u8[offset + 2] & 0x7F) << 7) |
      (u8[offset + 3] & 0x7F)
  }

  /** Max cover art dimension — 2000px covers high-res displays and AVSession. */
  private static readonly MAX_COVER_DIMENSION = 2000

  /** Decode raw image bytes (PNG, JPEG, BMP, WebP, etc.) into a PixelMap. */
  private static async decodeImageBuffer(buffer: ArrayBuffer): Promise<image.PixelMap | undefined> {
    if (!buffer || buffer.byteLength === 0) return undefined
    let imageSource: image.ImageSource | null = null
    try {
      imageSource = image.createImageSource(buffer)
      if (!imageSource) return undefined
      // Read original dimensions and scale down if oversized to avoid
      // huge PixelMap allocations (e.g. 15000x15000 → 900 MB) that block
      // the main thread when passed to AVSession.
      const info = await imageSource.getImageInfo()
      const opts: image.DecodingOptions = {}
      const w = info.size.width
      const h = info.size.height
      if (w > CoverArtExtractor.MAX_COVER_DIMENSION || h > CoverArtExtractor.MAX_COVER_DIMENSION) {
        const scale = CoverArtExtractor.MAX_COVER_DIMENSION / Math.max(w, h)
        opts.desiredSize = { width: Math.round(w * scale), height: Math.round(h * scale) }
      }
      const pixelMap = await imageSource.createPixelMap(opts)
      if (!pixelMap) return undefined
      return pixelMap
    } catch (e) {
      hilog.warn(0, TAG, 'decodeImageBuffer failed: %{public}s',
        (e instanceof Error) ? e.message : String(e))
      return undefined
    } finally {
      if (imageSource) {
        try {
          imageSource.release()
        } catch (_) { /* ignore */ }
      }
    }
  }
}

// 补充封面提取流程的实现说明注释。

// 封面提取：从 FLAC/ID3v2/MP4/OGG 等标签解析内嵌封面。
