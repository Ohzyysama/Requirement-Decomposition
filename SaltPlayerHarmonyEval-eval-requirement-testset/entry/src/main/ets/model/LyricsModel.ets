// LyricsModel.ets
// Model layer: lyrics data structures, LRC parser, and lyrics loader.
// MVVM role: Pure data structures and data access. No UI logic.

import { fileIo, fileShare, fileUri as coreFileUri } from '@kit.CoreFileKit'
import { media } from '@kit.MediaKit'
import { util } from '@kit.ArkTS'

// ==================== Data Models ====================

// A single cell in a karaoke line (word-level timing)
export class LyricsCell {
  public startTime: number = 0
  public endTime: number = 0
  public text: string = ''

  constructor(startTime: number = 0, endTime: number = 0, text: string = '') {
    this.startTime = startTime
    this.endTime = endTime
    this.text = text
  }
}

// A single lyrics line with main text, optional translation, and timing
@Observed
export class LyricsLine {
  @Track public startTime: number = 0
  @Track public endTime: number = 0
  @Track public cells: LyricsCell[] = []
  @Track public mainText: string = ''
  @Track public subText: string = ''
  @Track public isCurrent: boolean = false

  constructor(startTime: number = 0, endTime: number = 0, mainText: string = '',
    subText: string = '', cells: LyricsCell[] = []) {
    this.startTime = startTime
    this.endTime = endTime
    this.mainText = mainText
    this.subText = subText
    this.cells = cells
  }
}

// Complete parsed lyrics document
@Observed
export class LyricsDocument {
  @Track public lines: LyricsLine[] = []
  @Track public sourceText: string = ''
  @Track public isScrollable: boolean = false
  @Track public isEmpty: boolean = true
  @Track public hasTranslation: boolean = false
  // Whether any line in the document has word-level karaoke timing (cells.length > 0)
  // Used by KaraokeRenderDecision to choose per-word vs whole-line rendering.
  @Track public hasAnyKaraoke: boolean = false

  constructor(lines: LyricsLine[] = [], sourceText: string = '') {
    this.lines = lines
    this.sourceText = sourceText
    this.isScrollable = lines.length > 0
    this.isEmpty = lines.length === 0 && sourceText.length === 0
    this.hasTranslation = lines.some((line: LyricsLine) => line.subText.length > 0)
    this.hasAnyKaraoke = lines.some((line: LyricsLine) => line.cells.length > 0)
  }
}

// Lyrics source type
export class LyricsSource {
  static readonly EMBEDDED: string = 'EMBEDDED'
  static readonly LRC_FILE: string = 'LRC_FILE'
  static readonly NOT_FOUND: string = 'NOT_FOUND'
}

// Complete lyrics package with source info
export class LyricsPackage {
  public document: LyricsDocument = new LyricsDocument()
  public source: string = LyricsSource.NOT_FOUND

  constructor(document: LyricsDocument = new LyricsDocument(),
    source: string = LyricsSource.NOT_FOUND) {
    this.document = document
    this.source = source
  }
}

// ==================== LRC Parser ====================

interface RawTimedLine {
  timeMs: number
  text: string
}

export class LrcParser {
  // Strip all [mm:ss], [mm:ss.xx], [mm:ss:xx], [mm:ss,xx] timestamp patterns from text
  private static stripTimestamps(text: string): string {
    return text.replace(/\[\d{1,3}:\d{1,2}(?:[.:,]\d{1,6})?\]/g, '').trim()
  }

  // Strip both [mm:ss.xx] and <mm:ss.xxx> inline timestamps
  static stripAllInlineTimestamps(text: string): string {
    return text.replace(/[<\[]\d{1,3}:\d{1,2}(?:[.:,]\d{1,6})?[>\]]/g, '').trim()
  }

  // Serialize a parsed document back to a standard line-level LRC string,
  // using each line's cleaned mainText — i.e. the exact text the playback
  // page renders, with inline word-level (karaoke) timestamps already
  // removed. Only the leading [mm:ss.xx] line tag is kept.
  //
  // Emits exactly ONE LRC line per logical lyric line (one LyricsLine). The
  // translation (subText) is intentionally NOT emitted as a separate
  // same-timestamp line: the system desktop-lyrics overlay is a single-line
  // display that tracks playback by LRC line, so a duplicate translation line
  // would double the line count for bilingual songs and shift the overlay one
  // line out of sync with the playback page.
  //
  // The system overlay reads AVMetadata.lyric as plain LRC and renders any
  // inline <mm:ss.xx> word tags literally, so feeding it this serialized form
  // keeps it consistent with the in-app lyric view while preserving the line
  // timestamps the overlay needs to follow playback.
  static toPlainLrc(doc: LyricsDocument): string {
    if (!doc || doc.lines.length === 0) {
      return ''
    }
    const out: string[] = []
    for (const line of doc.lines) {
      out.push(LrcParser.formatLrcTimeTag(line.startTime) + line.mainText)
    }
    return out.join('\n')
  }

  // Format a millisecond offset as a standard LRC line tag: [mm:ss.xx].
  private static formatLrcTimeTag(timeMs: number): string {
    const totalMs = timeMs > 0 ? timeMs : 0
    const minutes = Math.floor(totalMs / 60000)
    const seconds = Math.floor((totalMs % 60000) / 1000)
    const centis = Math.floor((totalMs % 1000) / 10)
    const mm = minutes < 10 ? '0' + minutes : '' + minutes
    const ss = seconds < 10 ? '0' + seconds : '' + seconds
    const cc = centis < 10 ? '0' + centis : '' + centis
    return '[' + mm + ':' + ss + '.' + cc + ']'
  }

  // Parse LRC text into a LyricsDocument
  static parse(text: string): LyricsDocument {
    if (!text || text.trim().length === 0) {
      return new LyricsDocument()
    }

    // Remove BOM
    let cleaned = text
    if (cleaned.charCodeAt(0) === 0xFEFF) {
      cleaned = cleaned.substring(1)
    }

    // Split lines
    const rawLines = cleaned.split(/\r\n|\n|\r/)

    // Parse all timed lines
    const timedLines: RawTimedLine[] = []
    let hasTimestamps = false

    for (let i = 0; i < rawLines.length; i++) {
      const line = rawLines[i].trim()

      // Skip empty lines and comment lines
      if (line.length === 0 || line.startsWith('//')) {
        continue
      }

      // Skip metadata tags like [ti:...] [ar:...] [al:...] [by:...] [offset:...]
      const metaMatch = line.match(/^\[([a-zA-Z]+):.*\]$/)
      if (metaMatch) {
        continue
      }

      // Extract all timestamps and text from line
      // Supports multi-timestamp lines: [00:15.30][00:16.00]text
      // Supports formats: [mm:ss.xx], [mm:ss:xx], [mm:ss] (no fractional)
      const timestamps: number[] = []
      let remaining = line
      const tsRegex = /^\[(\d{1,3}):(\d{1,2})(?:[.:,](\d{1,6}))?\]/

      let match = remaining.match(tsRegex)
      while (match) {
        const minutes = parseInt(match[1])
        const seconds = parseInt(match[2])
        let millis = 0
        if (match[3] && match[3].length > 0) {
          let milliStr = match[3]
          // Normalize to milliseconds
          if (milliStr.length === 1) {
            milliStr = milliStr + '00'
          } else if (milliStr.length === 2) {
            milliStr = milliStr + '0'
          } else if (milliStr.length > 3) {
            milliStr = milliStr.substring(0, 3)
          }
          millis = parseInt(milliStr)
        }
        const timeMs = minutes * 60000 + seconds * 1000 + millis
        timestamps.push(timeMs)
        hasTimestamps = true
        remaining = remaining.substring(match[0].length)
        match = remaining.match(tsRegex)
      }

      // Create a timed line for each timestamp.
      // Keep inline timestamps (e.g. [mm:ss.xx] or <mm:ss.xx>) for karaoke parsing.
      for (let j = 0; j < timestamps.length; j++) {
        timedLines.push({ timeMs: timestamps[j], text: remaining.trim() })
      }
    }

    // If no timestamps found, return as static text (strip any timestamp-like patterns)
    if (!hasTimestamps) {
      const staticText = text.replace(/\[\d{1,3}:\d{1,2}(?:[.:,]\d{1,6})?\]/g, '').trim()
      return new LyricsDocument([], staticText)
    }

    // Sort by time
    timedLines.sort((a: RawTimedLine, b: RawTimedLine) => a.timeMs - b.timeMs)

    // Merge same-timestamp lines as translation (subText)
    const mergedLines: LyricsLine[] = []
    let i = 0
    while (i < timedLines.length) {
      const current = timedLines[i]
      let subText = ''

      // Check if next line has the same timestamp (translation)
      if (i + 1 < timedLines.length && timedLines[i + 1].timeMs === current.timeMs) {
        subText = LrcParser.stripAllInlineTimestamps(timedLines[i + 1].text)
        i += 2
      } else {
        i++
      }

      // Skip lines with empty main text
      if (current.text.length === 0 && subText.length === 0) {
        // Still add empty lines to preserve timing for gaps
        mergedLines.push(new LyricsLine(current.timeMs, 0, '', ''))
        continue
      }

      // Parse karaoke cells if present (inline <mm:ss.xxx> format)
      const cells = LrcParser.parseKaraokeCells(current.text, current.timeMs)
      const mainText = cells.length > 0
        ? cells.map((c: LyricsCell) => c.text).join('')
        : LrcParser.stripAllInlineTimestamps(current.text)

      mergedLines.push(new LyricsLine(current.timeMs, 0, mainText, subText, cells))
    }

    // Calculate endTime for each line (use next line's startTime)
    for (let k = 0; k < mergedLines.length; k++) {
      if (k + 1 < mergedLines.length) {
        mergedLines[k].endTime = mergedLines[k + 1].startTime
      } else {
        // Last line: extend 5 seconds beyond start
        mergedLines[k].endTime = mergedLines[k].startTime + 5000
      }
    }

    return new LyricsDocument(mergedLines, text)
  }

  // Parse karaoke inline timestamps: text<mm:ss.xxx>text or text[mm:ss.xxx]text
  private static parseKaraokeCells(text: string, lineStartTime: number): LyricsCell[] {
    const karaokeRegex = /[<\[](\d{1,3}):(\d{1,2})\.(\d{1,6})[>\]]/
    if (!karaokeRegex.test(text)) {
      return []
    }

    const cells: LyricsCell[] = []
    let remaining = text
    let lastTime = lineStartTime

    while (remaining.length > 0) {
      const match = remaining.match(karaokeRegex)
      if (!match) {
        // Remaining text is the last cell
        if (remaining.length > 0) {
          cells.push(new LyricsCell(lastTime, lastTime + 1000, remaining))
        }
        break
      }

      const beforeText = remaining.substring(0, match.index!)
      const minutes = parseInt(match[1])
      const seconds = parseInt(match[2])
      let milliStr = match[3]
      if (milliStr.length === 1) {
        milliStr = milliStr + '00'
      } else if (milliStr.length === 2) {
        milliStr = milliStr + '0'
      } else if (milliStr.length > 3) {
        milliStr = milliStr.substring(0, 3)
      }
      const timeMs = minutes * 60000 + seconds * 1000 + parseInt(milliStr)

      if (beforeText.length > 0) {
        cells.push(new LyricsCell(lastTime, timeMs, beforeText))
      }
      lastTime = timeMs
      remaining = remaining.substring(match.index! + match[0].length)
    }

    return cells
  }
}

// ==================== Raw Lyrics Tag Reader ====================
// Reads lyrics directly from audio file bytes, bypassing AVMetadataExtractor.
// Avoids deadlock with AVPlayer and works reliably during playback.

class LyricsTagReader {
  private static readonly MAX_TAG_SIZE: number = 5 * 1024 * 1024 // 5MB cap

  // Read lyrics from raw audio file bytes (MP3 ID3v2 USLT, FLAC Vorbis LYRICS, M4A/MP4 ©lyr, WAV id3 USLT)
  static readFromFile(fd: number, fileSize: number): string {
    if (fileSize < 10) return ''

    // Read first 4 bytes to detect file type
    const magicBuf = new ArrayBuffer(4)
    const magicRead = fileIo.readSync(fd, magicBuf)
    if (magicRead < 4) return ''
    const magic = new Uint8Array(magicBuf)

    // MP3 with ID3v2: starts with "ID3"
    if (magic[0] === 0x49 && magic[1] === 0x44 && magic[2] === 0x33) {
      // Read remaining 6 bytes of ID3v2 header (total 10 bytes)
      const restBuf = new ArrayBuffer(6)
      const restRead = fileIo.readSync(fd, restBuf)
      if (restRead < 6) return ''
      const rest = new Uint8Array(restBuf)

      const majorVersion = magic[3] // 3 or 4
      // Syncsafe size (4 bytes, 7 bits per byte)
      const tagSize = (rest[2] << 21) | (rest[3] << 14) | (rest[4] << 7) | rest[5]

      if (tagSize <= 0 || tagSize > LyricsTagReader.MAX_TAG_SIZE) return ''

      // Check for extended header flag (bit 6 of flags byte)
      const flags = rest[1]
      let extHeaderSize = 0
      if ((flags & 0x40) !== 0) {
        // Extended header present — read its size and skip it
        const extBuf = new ArrayBuffer(4)
        const extRead = fileIo.readSync(fd, extBuf)
        if (extRead < 4) return ''
        const extData = new Uint8Array(extBuf)
        if (majorVersion === 4) {
          extHeaderSize = ((extData[0] << 21) | (extData[1] << 14) | (extData[2] << 7) | extData[3]) - 4
        } else {
          extHeaderSize = ((extData[0] << 24) | (extData[1] << 16) | (extData[2] << 8) | extData[3]) - 4
        }
        if (extHeaderSize > 0 && extHeaderSize < tagSize) {
          // Skip the rest of the extended header
          const skipBuf = new ArrayBuffer(extHeaderSize)
          fileIo.readSync(fd, skipBuf)
        }
      }

      // Read tag frame data
      const readSize = Math.min(tagSize - extHeaderSize - (extHeaderSize > 0 ? 4 : 0), LyricsTagReader.MAX_TAG_SIZE)
      if (readSize <= 0) return ''
      const tagBuf = new ArrayBuffer(readSize)
      const tagRead = fileIo.readSync(fd, tagBuf)
      if (tagRead <= 0) return ''
      const tagData = new Uint8Array(tagBuf).slice(0, tagRead)

      return LyricsTagReader.findUSLTFrame(tagData, majorVersion)
    }

    // FLAC: starts with "fLaC"
    if (magic[0] === 0x66 && magic[1] === 0x4C && magic[2] === 0x61 && magic[3] === 0x43) {
      return LyricsTagReader.parseFLACVorbisLyrics(fd, fileSize)
    }

    // WAV/RIFF: starts with 'RIFF'
    if (magic[0] === 0x52 && magic[1] === 0x49 && magic[2] === 0x46 && magic[3] === 0x46) {
      return LyricsTagReader.parseWAVLyrics(fd, fileSize)
    }

    // M4A/MP4: first box type is 'ftyp' at bytes 4-7
    // File position is at byte 4 after magic read
    const ftypBuf = new ArrayBuffer(4)
    if (fileIo.readSync(fd, ftypBuf) >= 4) {
      const ftyp = new Uint8Array(ftypBuf)
      // 'ftyp' = 0x66 0x74 0x79 0x70
      if (ftyp[0] === 0x66 && ftyp[1] === 0x74 && ftyp[2] === 0x79 && ftyp[3] === 0x70) {
        const ftypSize = (magic[0] << 24) | (magic[1] << 16) | (magic[2] << 8) | magic[3]
        return LyricsTagReader.parseM4ALyrics(fd, fileSize, ftypSize)
      }
    }

    return ''
  }

  // Scan ID3v2 frames for USLT (Unsynchronized Lyrics)
  private static findUSLTFrame(tagData: Uint8Array, majorVersion: number): string {
    let offset = 0
    while (offset + 10 < tagData.length) {
      // Frame ID: 4 bytes
      const b0 = tagData[offset]
      const b1 = tagData[offset + 1]
      const b2 = tagData[offset + 2]
      const b3 = tagData[offset + 3]

      // Check for padding (null bytes) or invalid frame ID
      if (b0 === 0 || b1 === 0) break
      // Frame IDs should be uppercase letters or digits
      if (b0 < 0x30 || b0 > 0x5A) break

      const frameId = String.fromCharCode(b0, b1, b2, b3)

      // Frame size: 4 bytes
      let frameSize: number
      if (majorVersion === 4) {
        // ID3v2.4: syncsafe integer
        frameSize = (tagData[offset + 4] << 21) | (tagData[offset + 5] << 14) |
          (tagData[offset + 6] << 7) | tagData[offset + 7]
      } else {
        // ID3v2.3: regular big-endian integer
        frameSize = (tagData[offset + 4] << 24) | (tagData[offset + 5] << 16) |
          (tagData[offset + 6] << 8) | tagData[offset + 7]
      }

      if (frameSize <= 0 || offset + 10 + frameSize > tagData.length) break

      if (frameId === 'USLT') {
        const frameData = tagData.slice(offset + 10, offset + 10 + frameSize)
        const lyrics = LyricsTagReader.parseUSLTData(frameData)
        if (lyrics.length > 0) return lyrics
      }

      offset += 10 + frameSize
    }
    return ''
  }

  // Parse USLT frame data: encoding(1) + language(3) + descriptor(null-term) + lyrics text
  private static parseUSLTData(data: Uint8Array): string {
    if (data.length < 5) return ''

    const encoding = data[0]
    // language: 3 bytes (skip)
    let pos = 4

    // Skip content descriptor (null-terminated, encoding-dependent)
    if (encoding === 0 || encoding === 3) {
      // ISO-8859-1 or UTF-8: single null terminator
      while (pos < data.length && data[pos] !== 0) pos++
      pos++ // skip null
    } else if (encoding === 1 || encoding === 2) {
      // UTF-16: skip optional BOM in descriptor, then find double-null
      while (pos + 1 < data.length) {
        if (data[pos] === 0 && data[pos + 1] === 0) {
          pos += 2
          break
        }
        pos += 2
      }
    }

    if (pos >= data.length) return ''
    const textBytes = data.slice(pos)

    return LyricsTagReader.decodeText(textBytes, encoding)
  }

  // Parse FLAC Vorbis comment metadata block for LYRICS field
  private static parseFLACVorbisLyrics(fd: number, fileSize: number): string {
    // Read metadata blocks until we find VORBIS_COMMENT (type 4)
    let totalRead = 4 // already read the "fLaC" magic
    const maxScan = Math.min(fileSize, LyricsTagReader.MAX_TAG_SIZE)

    while (totalRead < maxScan) {
      // Block header: 1 byte (last flag + type) + 3 bytes (length)
      const blockHeaderBuf = new ArrayBuffer(4)
      const hRead = fileIo.readSync(fd, blockHeaderBuf)
      if (hRead < 4) break
      totalRead += 4

      const bh = new Uint8Array(blockHeaderBuf)
      const isLast = (bh[0] & 0x80) !== 0
      const blockType = bh[0] & 0x7F
      const blockLength = (bh[1] << 16) | (bh[2] << 8) | bh[3]

      if (blockLength <= 0 || totalRead + blockLength > maxScan) break

      if (blockType === 4) {
        // VORBIS_COMMENT block
        const commentBuf = new ArrayBuffer(blockLength)
        const cRead = fileIo.readSync(fd, commentBuf)
        if (cRead < blockLength) break
        return LyricsTagReader.parseVorbisCommentLyrics(new Uint8Array(commentBuf))
      } else {
        // Skip this block
        const skipBuf = new ArrayBuffer(blockLength)
        fileIo.readSync(fd, skipBuf)
        totalRead += blockLength
      }

      if (isLast) break
    }
    return ''
  }

  // Parse Vorbis comment data for LYRICS field
  private static parseVorbisCommentLyrics(data: Uint8Array): string {
    if (data.length < 8) return ''
    let pos = 0

    // Vendor string: 4-byte LE length + string
    const vendorLen = data[pos] | (data[pos + 1] << 8) | (data[pos + 2] << 16) | (data[pos + 3] << 24)
    pos += 4 + vendorLen
    if (pos + 4 > data.length) return ''

    // Comment count: 4-byte LE
    const commentCount = data[pos] | (data[pos + 1] << 8) | (data[pos + 2] << 16) | (data[pos + 3] << 24)
    pos += 4

    const decoder = new util.TextDecoder('utf-8')
    const lyricsKeys: string[] = ['LYRICS', 'UNSYNCEDLYRICS', 'UNSYNCED LYRICS']

    for (let i = 0; i < commentCount && pos + 4 <= data.length; i++) {
      const commentLen = data[pos] | (data[pos + 1] << 8) | (data[pos + 2] << 16) | (data[pos + 3] << 24)
      pos += 4
      if (pos + commentLen > data.length) break

      const commentBytes = data.slice(pos, pos + commentLen)
      pos += commentLen

      const comment = decoder.decodeToString(commentBytes)
      const eqIndex = comment.indexOf('=')
      if (eqIndex > 0) {
        const key = comment.substring(0, eqIndex).toUpperCase()
        if (lyricsKeys.indexOf(key) >= 0) {
          return comment.substring(eqIndex + 1)
        }
      }
    }
    return ''
  }

  // Parse M4A/MP4 container for lyrics in moov→udta→meta→ilst→©lyr atom
  // Scans all top-level boxes (including past large mdat) to find moov.
  private static parseM4ALyrics(fd: number, fileSize: number, ftypBoxSize: number): string {
    // Skip remaining ftyp content (8 bytes already read: 4 size + 4 'ftyp')
    if (ftypBoxSize > 8) LyricsTagReader.skipBytes(fd, ftypBoxSize - 8)
    let pos = ftypBoxSize

    // Scan top-level boxes for 'moov', skipping mdat and others
    while (pos + 8 <= fileSize) {
      const hBuf = new ArrayBuffer(8)
      if (fileIo.readSync(fd, hBuf) < 8) return ''
      const h = new Uint8Array(hBuf)
      let boxSize = (h[0] << 24) | (h[1] << 16) | (h[2] << 8) | h[3]
      let headerSize = 8

      if (boxSize === 1) {
        // Extended 64-bit size (common for large mdat boxes)
        const extBuf = new ArrayBuffer(8)
        if (fileIo.readSync(fd, extBuf) < 8) return ''
        const ext = new Uint8Array(extBuf)
        // Only support sizes where upper 4 bytes are 0 (< 4GB)
        if (ext[0] !== 0 || ext[1] !== 0 || ext[2] !== 0 || ext[3] !== 0) return ''
        boxSize = ext[4] * 0x1000000 + (ext[5] << 16) + (ext[6] << 8) + ext[7]
        headerSize = 16
      } else if (boxSize === 0) {
        boxSize = fileSize - pos // extends to EOF
      }

      if (boxSize < headerSize) return ''
      const contentSize = boxSize - headerSize

      // 'moov' = 0x6D 0x6F 0x6F 0x76
      if (h[4] === 0x6D && h[5] === 0x6F && h[6] === 0x6F && h[7] === 0x76) {
        if (contentSize <= 0 || contentSize > LyricsTagReader.MAX_TAG_SIZE) return ''
        const moovBuf = new ArrayBuffer(contentSize)
        if (fileIo.readSync(fd, moovBuf) < contentSize) return ''
        return LyricsTagReader.findLyricsInMoov(new Uint8Array(moovBuf))
      }

      // Skip non-moov box content
      if (contentSize > 0) LyricsTagReader.skipBytes(fd, contentSize)
      pos += boxSize
    }
    return ''
  }

  // Skip N bytes by reading and discarding in chunks
  private static skipBytes(fd: number, count: number): void {
    const CHUNK = 65536
    let remaining = count
    while (remaining > 0) {
      const n = Math.min(remaining, CHUNK)
      const buf = new ArrayBuffer(n)
      const rd = fileIo.readSync(fd, buf)
      if (rd <= 0) break
      remaining -= rd
    }
  }

  // Navigate moov box content to find lyrics: udta→meta→ilst→©lyr→data
  private static findLyricsInMoov(moovData: Uint8Array): string {
    const udta = LyricsTagReader.findBoxInBuffer(moovData, 0, moovData.length, 'udta')
    if (!udta) return ''

    const meta = LyricsTagReader.findBoxInBuffer(moovData, udta[0], udta[1], 'meta')
    if (!meta) return ''

    // meta box has 4 extra bytes (version + flags) after standard box header
    if (meta[1] <= 4) return ''

    const ilst = LyricsTagReader.findBoxInBuffer(moovData, meta[0] + 4, meta[1] - 4, 'ilst')
    if (!ilst) return ''

    // ©lyr = 0xA9 'l' 'y' 'r'
    const lyrBox = LyricsTagReader.findBoxInBuffer(moovData, ilst[0], ilst[1], '\xA9lyr')
    if (!lyrBox) return ''

    const dataBox = LyricsTagReader.findBoxInBuffer(moovData, lyrBox[0], lyrBox[1], 'data')
    if (!dataBox) return ''

    // data content: 4 bytes type indicator + 4 bytes locale, then UTF-8 text
    if (dataBox[1] <= 8) return ''
    const textBytes = moovData.slice(dataBox[0] + 8, dataBox[0] + dataBox[1])
    const decoder = new util.TextDecoder('utf-8')
    return decoder.decodeToString(textBytes)
  }

  // Find a box by type within a buffer region
  // Returns [contentOffset, contentSize] or null
  private static findBoxInBuffer(data: Uint8Array, startOffset: number, rangeSize: number,
    boxType: string): number[] | null {
    let pos = 0
    while (pos + 8 <= rangeSize) {
      const p = startOffset + pos
      if (p + 8 > data.length) return null

      let boxSize = (data[p] << 24) | (data[p + 1] << 16) | (data[p + 2] << 8) | data[p + 3]
      if (boxSize === 0) boxSize = rangeSize - pos
      if (boxSize < 8 || pos + boxSize > rangeSize) return null

      const type = String.fromCharCode(data[p + 4], data[p + 5], data[p + 6], data[p + 7])
      if (type === boxType) {
        return [p + 8, boxSize - 8]
      }
      pos += boxSize
    }
    return null
  }

  // Parse WAV/RIFF container for lyrics in an 'id3 ' chunk (ID3v2 USLT)
  // File position is at byte 4 after reading 'RIFF' magic
  private static parseWAVLyrics(fd: number, fileSize: number): string {
    // Read RIFF file size (4 bytes LE) + format tag (4 bytes, expect 'WAVE')
    const headerBuf = new ArrayBuffer(8)
    if (fileIo.readSync(fd, headerBuf) < 8) return ''
    const header = new Uint8Array(headerBuf)
    // 'WAVE' = 0x57 0x41 0x56 0x45
    if (header[4] !== 0x57 || header[5] !== 0x41 || header[6] !== 0x56 || header[7] !== 0x45) return ''

    const MAX_SCAN = Math.min(fileSize, LyricsTagReader.MAX_TAG_SIZE)
    let pos = 12 // past 'RIFF' + size + 'WAVE'

    // Scan RIFF chunks for 'id3 ' or 'ID3 '
    while (pos + 8 <= MAX_SCAN) {
      const chBuf = new ArrayBuffer(8)
      if (fileIo.readSync(fd, chBuf) < 8) return ''
      const ch = new Uint8Array(chBuf)

      // Chunk size is little-endian 32-bit
      const chunkSize = ch[4] | (ch[5] << 8) | (ch[6] << 16) | (ch[7] << 24)
      if (chunkSize < 0) return ''

      // 'id3 ' = 0x69 0x64 0x33 0x20, 'ID3 ' = 0x49 0x44 0x33 0x20
      const isId3 = ch[3] === 0x20 && ch[2] === 0x33 &&
        ((ch[0] === 0x69 && ch[1] === 0x64) || (ch[0] === 0x49 && ch[1] === 0x44))

      if (isId3 && chunkSize > 10 && chunkSize <= MAX_SCAN) {
        const id3Buf = new ArrayBuffer(chunkSize)
        if (fileIo.readSync(fd, id3Buf) < chunkSize) return ''
        const id3Data = new Uint8Array(id3Buf)

        // Validate ID3v2 header: 'ID3' signature
        if (id3Data[0] !== 0x49 || id3Data[1] !== 0x44 || id3Data[2] !== 0x33) return ''
        const majorVersion = id3Data[3]
        const flags = id3Data[5]

        // Skip extended header if present
        let frameStart = 10
        if ((flags & 0x40) !== 0 && frameStart + 4 <= id3Data.length) {
          let extSize: number
          if (majorVersion === 4) {
            extSize = (id3Data[frameStart] << 21) | (id3Data[frameStart + 1] << 14) |
              (id3Data[frameStart + 2] << 7) | id3Data[frameStart + 3]
          } else {
            extSize = (id3Data[frameStart] << 24) | (id3Data[frameStart + 1] << 16) |
              (id3Data[frameStart + 2] << 8) | id3Data[frameStart + 3]
          }
          if (extSize > 0 && frameStart + extSize < id3Data.length) frameStart += extSize
        }

        const frameData = id3Data.slice(frameStart)
        return LyricsTagReader.findUSLTFrame(frameData, majorVersion)
      }

      // Skip chunk (RIFF chunks are padded to even byte boundary)
      const paddedSize = chunkSize + (chunkSize % 2)
      if (pos + 8 + paddedSize > MAX_SCAN) return ''
      if (paddedSize > 0) LyricsTagReader.skipBytes(fd, paddedSize)
      pos += 8 + paddedSize
    }
    return ''
  }

  // Decode text bytes based on ID3 encoding byte
  private static decodeText(bytes: Uint8Array, encoding: number): string {
    if (bytes.length === 0) return ''

    if (encoding === 0) {
      // ISO-8859-1
      let result = ''
      for (let i = 0; i < bytes.length; i++) {
        if (bytes[i] === 0) break
        result += String.fromCharCode(bytes[i])
      }
      return result
    } else if (encoding === 3) {
      // UTF-8
      const decoder = new util.TextDecoder('utf-8')
      return decoder.decodeToString(bytes)
    } else if (encoding === 1) {
      // UTF-16 with BOM
      let bomOffset = 0
      let encodingName = 'utf-16le'
      if (bytes.length >= 2) {
        if (bytes[0] === 0xFF && bytes[1] === 0xFE) {
          encodingName = 'utf-16le'
          bomOffset = 2
        } else if (bytes[0] === 0xFE && bytes[1] === 0xFF) {
          encodingName = 'utf-16be'
          bomOffset = 2
        }
      }
      const decoder = new util.TextDecoder(encodingName)
      return decoder.decodeToString(bytes.slice(bomOffset))
    } else if (encoding === 2) {
      // UTF-16BE without BOM
      const decoder = new util.TextDecoder('utf-16be')
      return decoder.decodeToString(bytes)
    }
    return ''
  }
}

// ==================== Lyrics Loader ====================

export class LyricsLoader {
  // Load lyrics for a given audio file
  static async loadLyrics(fileUri: string, _songId: string): Promise<LyricsPackage> {
    console.info('[LyricsLoader] loadLyrics called, fileUri: ' + fileUri)

    // 1. Try reading lyrics directly from file bytes (most reliable — no AVPlayer conflict)
    try {
      const rawText = await LyricsLoader.readLyricsFromRawFile(fileUri)
      if (rawText && rawText.trim().length > 0) {
        console.info('[LyricsLoader] Found lyrics via raw file reading, length: ' + rawText.length)
        const doc = LrcParser.parse(rawText)
        return new LyricsPackage(doc, LyricsSource.EMBEDDED)
      }
    } catch (err) {
      console.info('[LyricsLoader] Raw file reading failed: ' + (err as Error).message)
    }

    // 2. Try AVMetadataExtractor customInfo (fallback for non-MP3/FLAC formats)
    try {
      const embeddedText = await LyricsLoader.loadEmbeddedLyrics(fileUri)
      if (embeddedText && embeddedText.trim().length > 0) {
        console.info('[LyricsLoader] Found embedded lyrics via extractor, length: ' + embeddedText.length)
        const doc = LrcParser.parse(embeddedText)
        return new LyricsPackage(doc, LyricsSource.EMBEDDED)
      }
    } catch (err) {
      console.info('[LyricsLoader] No embedded lyrics: ' + (err as Error).message)
    }

    // 3. Try to find .lrc file in same directory
    try {
      const lrcText = await LyricsLoader.loadLrcFile(fileUri)
      if (lrcText && lrcText.trim().length > 0) {
        console.info('[LyricsLoader] Found .lrc file, length: ' + lrcText.length)
        const doc = LrcParser.parse(lrcText)
        return new LyricsPackage(doc, LyricsSource.LRC_FILE)
      }
    } catch (err) {
      console.info('[LyricsLoader] No .lrc file found: ' + (err as Error).message)
    }

    // 4. Not found
    console.info('[LyricsLoader] No lyrics found for file')
    return new LyricsPackage(new LyricsDocument(), LyricsSource.NOT_FOUND)
  }

  // Read lyrics directly from raw audio file bytes (MP3 ID3v2 USLT, FLAC Vorbis LYRICS)
  private static async readLyricsFromRawFile(audioFileUri: string): Promise<string> {
    let fd = -1
    try {
      let file: fileIo.File
      try {
        file = fileIo.openSync(audioFileUri, fileIo.OpenMode.READ_ONLY)
      } catch (_openErr) {
        // URI permission may have expired after app restart or background — re-activate and retry
        const policy: fileShare.PolicyInfo = {
          uri: audioFileUri,
          operationMode: fileShare.OperationMode.READ_MODE
        } as fileShare.PolicyInfo
        await fileShare.activatePermission([policy])
        file = fileIo.openSync(audioFileUri, fileIo.OpenMode.READ_ONLY)
      }
      fd = file.fd
      const stat = fileIo.statSync(fd)
      const result = LyricsTagReader.readFromFile(fd, stat.size)
      return result
    } finally {
      if (fd >= 0) {
        try { fileIo.closeSync(fd) } catch (_e) { /* ignore */ }
      }
    }
  }

  // Try to read embedded lyrics from audio file metadata via AVMetadataExtractor
  private static async loadEmbeddedLyrics(fileUri: string): Promise<string> {
    const timeoutMs = 5000
    const extractPromise = LyricsLoader.doExtractLyrics(fileUri)
    const timeoutPromise = new Promise<string>((_, reject) => {
      setTimeout(() => {
        reject(new Error('AVMetadataExtractor timeout'))
      }, timeoutMs)
    })
    return Promise.race([extractPromise, timeoutPromise])
  }

  private static async doExtractLyrics(fileUri: string): Promise<string> {
    let extractor: media.AVMetadataExtractor | null = null
    let fd = -1
    try {
      extractor = await media.createAVMetadataExtractor()
      const file = fileIo.openSync(fileUri, fileIo.OpenMode.READ_ONLY)
      fd = file.fd
      const stat = fileIo.statSync(fd)
      extractor.fdSrc = { fd: fd, offset: 0, length: stat.size }
      const metadata = await extractor.fetchMetadata()

      // Log all customInfo keys for debugging
      if (metadata.customInfo) {
        const keys: string[] = Object.keys(metadata.customInfo)
        console.info('[LyricsLoader] customInfo keys: ' + keys.join(', '))

        // Try all known lyrics keys
        const lyricsKeys: string[] = ['lyrics', 'lyric', 'LYRICS', 'UNSYNCEDLYRICS', 'USLT']
        for (let i = 0; i < lyricsKeys.length; i++) {
          const val = metadata.customInfo[lyricsKeys[i]]
          if (val && val.length > 0) {
            console.info('[LyricsLoader] Found lyrics in customInfo key: ' + lyricsKeys[i])
            return val
          }
        }
      } else {
        console.info('[LyricsLoader] customInfo is null/undefined')
      }
      return ''
    } catch (err) {
      throw (err instanceof Error) ? err : new Error(String(err))
    } finally {
      if (extractor) {
        try {
          await extractor.release()
        } catch (_e) {
          // ignore release error
        }
      }
      if (fd >= 0) {
        try {
          fileIo.closeSync(fd)
        } catch (_e) {
          // ignore close error
        }
      }
    }
  }

  // Try to find and read a .lrc file with the same name as the audio file
  private static async loadLrcFile(audioUri: string): Promise<string> {
    // Strategy: try multiple path constructions to find the .lrc file
    const lastDotIndex = audioUri.lastIndexOf('.')
    const lastSlashIndex = audioUri.lastIndexOf('/')
    if (lastDotIndex <= lastSlashIndex) {
      throw new Error('Cannot determine file extension')
    }

    // Approach 1: Replace extension in the full URI (works if URI grants directory access)
    const lrcUri = audioUri.substring(0, lastDotIndex) + '.lrc'
    console.info('[LyricsLoader] Trying .lrc URI: ' + lrcUri)
    const text1 = LyricsLoader.tryReadFile(lrcUri)
    if (text1.length > 0) return text1

    // Approach 2: Use FileUri to get real filesystem path, then construct .lrc path
    try {
      const uriObj = new coreFileUri.FileUri(audioUri)
      const realPath: string = uriObj.path
      console.info('[LyricsLoader] Real path from FileUri: ' + realPath)

      if (realPath.length > 0) {
        const pathDotIndex = realPath.lastIndexOf('.')
        if (pathDotIndex > 0) {
          const lrcPath = realPath.substring(0, pathDotIndex) + '.lrc'
          console.info('[LyricsLoader] Trying .lrc path: ' + lrcPath)
          const text2 = LyricsLoader.tryReadFile(lrcPath)
          if (text2.length > 0) return text2
        }
      }
    } catch (uriErr) {
      console.info('[LyricsLoader] FileUri parsing failed: ' + (uriErr as Error).message)
    }

    // Approach 3: Strip file:// prefix manually and try absolute path
    if (audioUri.startsWith('file://')) {
      let rawPath = audioUri.substring(7) // strip "file://"
      // Handle file:///path (three slashes) vs file://authority/path
      if (!rawPath.startsWith('/')) {
        // e.g., "docs/storage/..." — try prepending /
        rawPath = '/' + rawPath
      }
      const rawDotIndex = rawPath.lastIndexOf('.')
      if (rawDotIndex > 0) {
        const lrcRawPath = rawPath.substring(0, rawDotIndex) + '.lrc'
        console.info('[LyricsLoader] Trying .lrc raw path: ' + lrcRawPath)
        const text3 = LyricsLoader.tryReadFile(lrcRawPath)
        if (text3.length > 0) return text3
      }
    }

    throw new Error('.lrc file not found for: ' + audioUri)
  }

  // Helper: try to read a text file, return empty string on failure
  private static tryReadFile(pathOrUri: string): string {
    let file: fileIo.File | null = null
    try {
      file = fileIo.openSync(pathOrUri, fileIo.OpenMode.READ_ONLY)
      const stat = fileIo.statSync(file.fd)
      if (stat.size === 0 || stat.size > 2 * 1024 * 1024) {
        fileIo.closeSync(file.fd)
        return ''
      }
      const buf = new ArrayBuffer(stat.size)
      fileIo.readSync(file.fd, buf)
      fileIo.closeSync(file.fd)
      file = null
      const decoder = new util.TextDecoder('utf-8')
      return decoder.decodeToString(new Uint8Array(buf))
    } catch (_err) {
      if (file) {
        try { fileIo.closeSync(file.fd) } catch (_e) { /* ignore */ }
      }
      return ''
    }
  }
}

// 歌词加载：优先读取内嵌 ID3 歌词标签，否则加载同名 .lrc 文件并解析。

// 卡拉OK歌词：解析逐字时间戳，支持逐字高亮渲染。

// 歌词加载对齐：内嵌与独立 LRC。

解析 LRC 文本中的 [mm:ss.xx] 时间标签为按时间排序的歌词行
function parseLrcLinesC(raw: string): Array<{ time: number; text: string }> {
  const out: Array<{ time: number; text: string }> = [];
  const tag = /\[(\d{1,2}):(\d{1,2})(?:[.:](\d{1,3}))?\]/g;
  for (const line of raw.split('\n')) {
    const text = line.replace(tag, '').trim();
    let m: RegExpExecArray | null;
    tag.lastIndex = 0;
    while ((m = tag.exec(line)) !== null) {
      const min = parseInt(m[1], 10);
      const sec = parseInt(m[2], 10);
      const frac = m[3] ? parseInt(m[3].padEnd(3, '0'), 10) : 0;
      out.push({ time: min * 60000 + sec * 1000 + frac, text });
    }
  }
  return out.sort((a, b) => a.time - b.time);
}

将字节数转换为带单位的可读体积字符串
function humanizeBytesC(bytes: number): string {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  let idx = 0;
  let value = bytes;
  while (value >= 1024 && idx < units.length - 1) {
    value = value / 1024;
    idx++;
  }
  const rounded = Math.round(value * 100) / 100;
  return rounded + ' ' + units[idx];
}

// 歌曲多选操作：切换某曲目的选中态并返回最新的选中集合
export function toggleSongSelectionB_H21(selected: string[], songId: string): string[] {
  const set = new Set<string>(selected)
  if (set.has(songId)) {
    set.delete(songId)
  } else {
    set.add(songId)
  }
  const out: string[] = []
  set.forEach((id: string) => {
    out.push(id)
  })
  return out
}

对操作进行防抖，仅在静默期后执行最后一次调用
function debounceCallC_H21(calls: number[], gapMs: number): number[] {
  const fired: number[] = [];
  let last = -Infinity;
  for (let i = 0; i < calls.length; i++) {
    const t = calls[i];
    const isLast = i === calls.length - 1;
    const nextGap = isLast ? Infinity : calls[i + 1] - t;
    if (t - last >= gapMs || nextGap >= gapMs) {
      fired.push(t);
      last = t;
    }
  }
  return fired;
}

将连字符或下划线分隔的标识转换为驼峰命名
function toCamelCaseC_H21(name: string): string {
  const parts = name.split(/[-_\s]+/).filter(p => p.length > 0);
  if (parts.length === 0) return '';
  let result = parts[0].toLowerCase();
  for (let i = 1; i < parts.length; i++) {
    const p = parts[i];
    result += p.charAt(0).toUpperCase() + p.slice(1).toLowerCase();
  }
  return result;
}

解析 LRC 文本中的 [mm:ss.xx] 时间标签为按时间排序的歌词行
function parseLrcLinesC_H21(raw: string): Array<{ time: number; text: string }> {
  const out: Array<{ time: number; text: string }> = [];
  const tag = /\[(\d{1,2}):(\d{1,2})(?:[.:](\d{1,3}))?\]/g;
  for (const line of raw.split('\n')) {
    const text = line.replace(tag, '').trim();
    let m: RegExpExecArray | null;
    tag.lastIndex = 0;
    while ((m = tag.exec(line)) !== null) {
      const min = parseInt(m[1], 10);
      const sec = parseInt(m[2], 10);
      const frac = m[3] ? parseInt(m[3].padEnd(3, '0'), 10) : 0;
      out.push({ time: min * 60000 + sec * 1000 + frac, text });
    }
  }
  return out.sort((a, b) => a.time - b.time);
}

// 歌曲列表ABC快速索引：按歌名首字母归类并记录每个字母的起始下标
export function buildSongAbcIndexB_H21(titles: string[]): Record<string, number> {
  const index: Record<string, number> = {}
  for (let i = 0; i < titles.length; i++) {
    const first = (titles[i] ?? '').trim().charAt(0).toUpperCase()
    let key = '#'
    if (first >= 'A' && first <= 'Z') {
      key = first
    }
    if (index[key] === undefined) {
      index[key] = i
    }
  }
  return index
}

// 歌曲随机播放全部：用洗牌算法生成全部歌曲的随机播放顺序
export function shuffleAllSongsB_H21(songIds: string[]): string[] {
  const order = songIds.slice()
  for (let i = order.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1))
    const tmp = order[i]
    order[i] = order[j]
    order[j] = tmp
  }
  return order
}
