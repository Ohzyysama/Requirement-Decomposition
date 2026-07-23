// ReplayGainExtractor.ets
// Best-effort ReplayGain tag extractor for FLAC (Vorbis comments) and MP3 (ID3v2 TXXX).
// Returns the raw gain string (e.g. "-3.5 dB") or '' if not found.
// Priority: REPLAYGAIN_TRACK_GAIN > REPLAYGAIN_ALBUM_GAIN.

import { fileIo } from '@kit.CoreFileKit'
import { util } from '@kit.ArkTS'

const TAG = 'ReplayGainExtractor'

// ReplayGain tag keys we look for, in priority order
const RG_TRACK_KEY = 'REPLAYGAIN_TRACK_GAIN'
const RG_ALBUM_KEY = 'REPLAYGAIN_ALBUM_GAIN'

// Named interface for TXXX frame parse result (ArkTS: no inline object literal types)
interface TxxxFrameResult {
  key: string
  value: string
}

export class ReplayGainExtractor {
  static extract(fd: number, size: number, mimeType: string): string {
    // FLAC: parse Vorbis comment blocks
    if (mimeType.includes('flac') || mimeType.includes('x-flac')) {
      return ReplayGainExtractor.extractFromFlac(fd, size)
    }
    // MP3: parse ID3v2 TXXX frames
    if (mimeType.includes('mpeg')) {
      return ReplayGainExtractor.extractFromMp3(fd, size)
    }
    return ''
  }

  // ==================== FLAC Vorbis Comment Parser ====================

  private static extractFromFlac(fd: number, size: number): string {
    // Read first 128KB of file to find Vorbis comment block
    const bufSize = Math.min(size, 131072)
    const buf = new ArrayBuffer(bufSize)
    try {
      fileIo.readSync(fd, buf, { offset: 0, length: bufSize })
    } catch (_e) {
      return ''
    }
    const view = new Uint8Array(buf)

    // FLAC magic: "fLaC" at offset 0
    if (view[0] !== 0x66 || view[1] !== 0x4C || view[2] !== 0x61 || view[3] !== 0x43) {
      return ''
    }

    let offset = 4
    // Walk metadata blocks
    while (offset < view.length - 4) {
      // Metadata block header: 1 byte block type + 3 bytes size + last-block flag
      if (offset + 4 > view.length) break
      const blockType = view[offset] & 0x7F
      const isLast = (view[offset] & 0x80) !== 0
      const blockSize = (view[offset + 1] << 16) | (view[offset + 2] << 8) | view[offset + 3]
      offset += 4

      if (offset + blockSize > view.length) break

      // Block type 4 = VORBIS_COMMENT
      if (blockType === 4) {
        return ReplayGainExtractor.parseVorbisCommentBlock(view, offset, blockSize)
      }

      offset += blockSize
      if (isLast) break
    }
    return ''
  }

  // Parse a FLAC Vorbis comment metadata block.
  // Structure: vendor string length (LE uint32) + vendor string +
  //            user comment list length (LE uint32) +
  //            for each comment: comment length (LE uint32) + comment string
  private static parseVorbisCommentBlock(view: Uint8Array, offset: number, blockSize: number): string {
    const end = offset + blockSize
    if (offset + 4 > end) return ''

    // Vendor string length (little-endian uint32)
    const vendorLen = view[offset] | (view[offset + 1] << 8) | (view[offset + 2] << 16) | (view[offset + 3] << 24)
    offset += 4 + vendorLen
    if (offset + 4 > end) return ''

    // User comment list length
    const commentCount = view[offset] | (view[offset + 1] << 8) | (view[offset + 2] << 16) | (view[offset + 3] << 24)
    offset += 4

    let trackGain = ''
    let albumGain = ''

    for (let i = 0; i < commentCount && offset < end; i++) {
      if (offset + 4 > end) break
      const commentLen = view[offset] | (view[offset + 1] << 8) | (view[offset + 2] << 16) | (view[offset + 3] << 24)
      offset += 4
      if (offset + commentLen > end) break

      // Decode comment as UTF-8
      const commentBytes = view.subarray(offset, offset + commentLen)
      const comment = ReplayGainExtractor.utf8Decode(commentBytes)
      offset += commentLen

      // Vorbis comments are "KEY=value" format
      const eqIdx = comment.indexOf('=')
      if (eqIdx < 0) continue
      const key = comment.substring(0, eqIdx).trim()
      const value = comment.substring(eqIdx + 1).trim()

      if (key === RG_TRACK_KEY && trackGain.length === 0) {
        trackGain = value
      } else if (key === RG_ALBUM_KEY && albumGain.length === 0) {
        albumGain = value
      }

      // Early exit if we found both
      if (trackGain.length > 0) {
        return trackGain
      }
    }

    // Return album gain if track gain not found
    return albumGain
  }

  // ==================== MP3 ID3v2 TXXX Parser ====================

  private static extractFromMp3(fd: number, size: number): string {
    // Read first 64KB to find ID3v2 tag
    const bufSize = Math.min(size, 65536)
    const buf = new ArrayBuffer(bufSize)
    try {
      fileIo.readSync(fd, buf, { offset: 0, length: bufSize })
    } catch (_e) {
      return ''
    }
    const view = new Uint8Array(buf)

    // ID3v2 magic: "ID3" at offset 0
    if (view[0] !== 0x49 || view[1] !== 0x44 || view[2] !== 0x33) {
      return ''
    }

    // ID3v2 version (major.minor)
    const majorVersion = view[3]
    // const minorVersion = view[4]
    // Flags byte at offset 5
    const flags = view[5]
    // Tag size (synchsafe int, 4 bytes)
    const tagSize = ReplayGainExtractor.synchsafeToInt(view[6], view[7], view[8], view[9])
    if (tagSize <= 0 || tagSize > bufSize) return ''

    let offset = 10

    // Check for extended header (flag bit 6)
    if ((flags & 0x40) !== 0) {
      if (offset + 4 > view.length) return ''
      const extHeaderSize = ReplayGainExtractor.readInt32(view, offset, majorVersion >= 4)
      offset += extHeaderSize
    }

    const tagEnd = Math.min(10 + tagSize, view.length)
    let trackGain = ''
    let albumGain = ''

    // Walk frames
    while (offset + 10 <= tagEnd) {
      // Frame ID: 4 bytes for ID3v2.3/2.4, 3 bytes for 2.2
      let frameId: string
      let frameSize: number
      let frameHeaderSize: number

      if (majorVersion >= 3) {
        // ID3v2.3/2.4: 4-char frame ID + 4-byte size + 2-byte flags
        frameId = String.fromCharCode(view[offset], view[offset + 1], view[offset + 2], view[offset + 3])
        frameSize = ReplayGainExtractor.readInt32(view, offset + 4, majorVersion >= 4)
        // flags at offset+8, offset+9 — skip
        frameHeaderSize = 10
      } else {
        // ID3v2.2: 3-char frame ID + 3-byte size
        frameId = String.fromCharCode(view[offset], view[offset + 1], view[offset + 2])
        frameSize = (view[offset + 3] << 16) | (view[offset + 4] << 8) | view[offset + 5]
        frameHeaderSize = 6
      }

      // End of frames (padding)
      if (frameId.charCodeAt(0) === 0) break

      offset += frameHeaderSize
      if (offset + frameSize > tagEnd) break

      // We only care about TXXX frames (user-defined text)
      if (frameId === 'TXXX') {
        const gain = ReplayGainExtractor.parseTxxxFrame(view, offset, frameSize)
        if (gain.key === RG_TRACK_KEY && trackGain.length === 0) {
          trackGain = gain.value
        } else if (gain.key === RG_ALBUM_KEY && albumGain.length === 0) {
          albumGain = gain.value
        }
        if (trackGain.length > 0) {
          return trackGain
        }
      }

      offset += frameSize
    }

    return albumGain
  }

  // Parse a TXXX frame: encoding byte + description (null-terminated) + value
  private static parseTxxxFrame(view: Uint8Array, offset: number, size: number): TxxxFrameResult {
    if (size < 2) {
      const emptyResult: TxxxFrameResult = { key: '', value: '' }
      return emptyResult
    }
    const encoding = view[offset]
    let descEnd = offset + 1

    // Find null terminator for description
    if (encoding === 0x01 || encoding === 0x02) {
      // UTF-16: look for 0x00 0x00
      while (descEnd + 1 < offset + size) {
        if (view[descEnd] === 0x00 && view[descEnd + 1] === 0x00) {
          descEnd += 2
          break
        }
        descEnd += 2
      }
    } else {
      // ISO-8859-1 or UTF-8: look for 0x00
      while (descEnd < offset + size && view[descEnd] !== 0x00) {
        descEnd++
      }
      if (descEnd < offset + size) descEnd++ // skip null
    }

    const descBytes = view.subarray(offset + 1, descEnd - (encoding === 0x01 || encoding === 0x02 ? 2 : 1))
    const valueBytes = view.subarray(descEnd, offset + size)

    const description = ReplayGainExtractor.decodeText(descBytes, encoding)
    const value = ReplayGainExtractor.decodeText(valueBytes, encoding)

    const result: TxxxFrameResult = { key: description, value: value }
    return result
  }

  // ==================== Helpers ====================

  // Convert synchsafe integer (used in ID3v2 tag/frame sizes) to normal int
  private static synchsafeToInt(b0: number, b1: number, b2: number, b3: number): number {
    return ((b0 & 0x7F) << 21) | ((b1 & 0x7F) << 14) | ((b2 & 0x7F) << 7) | (b3 & 0x7F)
  }

  // Read a 4-byte integer from view at offset. For ID3v2.4, it's synchsafe.
  private static readInt32(view: Uint8Array, offset: number, synchsafe: boolean): number {
    if (synchsafe) {
      return ReplayGainExtractor.synchsafeToInt(view[offset], view[offset + 1], view[offset + 2], view[offset + 3])
    }
    return (view[offset] << 24) | (view[offset + 1] << 16) | (view[offset + 2] << 8) | view[offset + 3]
  }

  // Decode text bytes based on ID3v2 encoding byte
  private static decodeText(bytes: Uint8Array, encoding: number): string {
    switch (encoding) {
      case 0x00: // ISO-8859-1
        return ReplayGainExtractor.iso88591Decode(bytes)
      case 0x01: // UTF-16 with BOM
      case 0x02: // UTF-16 BE
        return ReplayGainExtractor.utf16Decode(bytes, encoding === 0x02)
      case 0x03: // UTF-8
      default:
        return ReplayGainExtractor.utf8Decode(bytes)
    }
  }

  // UTF-8 decode
  private static utf8Decode(bytes: Uint8Array): string {
    try {
      // Use TextDecoder if available, fallback to manual decode
      const decoder = new util.TextDecoder('utf-8')
      return decoder.decodeToString(bytes)
    } catch (_e) {
      return ReplayGainExtractor.manualUtf8Decode(bytes)
    }
  }

  private static manualUtf8Decode(bytes: Uint8Array): string {
    let result = ''
    let i = 0
    while (i < bytes.length) {
      const c = bytes[i]
      if (c < 0x80) {
        result += String.fromCharCode(c)
        i++
      } else if ((c & 0xE0) === 0xC0 && i + 1 < bytes.length) {
        const code = ((c & 0x1F) << 6) | (bytes[i + 1] & 0x3F)
        result += String.fromCharCode(code)
        i += 2
      } else if ((c & 0xF0) === 0xE0 && i + 2 < bytes.length) {
        const code = ((c & 0x0F) << 12) | ((bytes[i + 1] & 0x3F) << 6) | (bytes[i + 2] & 0x3F)
        result += String.fromCharCode(code)
        i += 3
      } else if ((c & 0xF8) === 0xF0 && i + 3 < bytes.length) {
        const code = ((c & 0x07) << 18) | ((bytes[i + 1] & 0x3F) << 12) | ((bytes[i + 2] & 0x3F) << 6) | (bytes[i + 3] & 0x3F)
        // Surrogate pair for codes > 0xFFFF
        if (code > 0xFFFF) {
          const high = 0xD800 + ((code - 0x10000) >> 10)
          const low = 0xDC00 + ((code - 0x10000) & 0x3FF)
          result += String.fromCharCode(high, low)
        } else {
          result += String.fromCharCode(code)
        }
        i += 4
      } else {
        result += String.fromCharCode(c)
        i++
      }
    }
    return result
  }

  // UTF-16 decode
  private static utf16Decode(bytes: Uint8Array, bigEndian: boolean): string {
    if (bytes.length < 2) return ''
    let offset = 0
    let be = bigEndian

    // Check for BOM
    if (!bigEndian && bytes.length >= 2) {
      if (bytes[0] === 0xFE && bytes[1] === 0xFF) {
        be = true
        offset = 2
      } else if (bytes[0] === 0xFF && bytes[1] === 0xFE) {
        be = false
        offset = 2
      }
    }

    let result = ''
    for (let i = offset; i + 1 < bytes.length; i += 2) {
      const code = be ? (bytes[i] << 8) | bytes[i + 1] : bytes[i] | (bytes[i + 1] << 8)
      if (code >= 0xD800 && code <= 0xDBFF && i + 3 < bytes.length) {
        // High surrogate
        const low = be
          ? (bytes[i + 2] << 8) | bytes[i + 3]
          : bytes[i + 2] | (bytes[i + 3] << 8)
        if (low >= 0xDC00 && low <= 0xDFFF) {
          const full = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
          result += String.fromCharCode(full)
          i += 2
          continue
        }
      }
      result += String.fromCharCode(code)
    }
    return result
  }

  // ISO-8859-1 decode (1:1 byte to char mapping)
  private static iso88591Decode(bytes: Uint8Array): string {
    let result = ''
    for (let i = 0; i < bytes.length; i++) {
      result += String.fromCharCode(bytes[i])
    }
    return result
  }
}

// ReplayGain：从标签提取 ReplayGain 增益用于音量归一化。
