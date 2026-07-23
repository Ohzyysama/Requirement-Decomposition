// Guqin.ets
// Audio tag cleaning / normalization utility.
// Port of the Android SaltPlayer Guqin (spc-core) logic to ArkTS.
//
// Responsibilities:
// - Normalize multi-artist / multi-genre delimiters (/ 、 , ; &) into a single "/"
// - Protect special names that legitimately contain a delimiter (e.g. "AC/DC", "R&B")
// - Deduplicate entries while preserving order
// - Map genre aliases to standard genre tags (lightweight, extensible)
// - Parse track / disc numbers in "n/total" and iTunes-style (disc*1000+track) formats
// - Parse year from a date string, preferring YYYY from date over a raw year field

// Delimiters: / 、 , ; &  with optional surrounding whitespace
const DELIMITER_REGEX: RegExp = /\s*[/、,;&]\s*/g

// Default protected (unsplit) artist names, synced with Android GuqinDefaults.
const DEFAULT_UNSPLIT_ARTISTS: string[] = [
  '25時、ナイトコードで。',
  '小六的网易云、',
  '神様、僕は気づいてしまった',
  'リリィ、さよなら。',
  'ハロー、ハッピーワールド!',
  '小娟&山谷里的居民',
  'Tears & Years',
  'Iron & Wine',
  'K/DA',
  '伍佰 & China Blue',
  'VH (Vast & Hazy)',
  'MC $oho & KidNey',
  'The Mamas & The Papas',
  'MYTH & ROID',
  'AC/DC',
  '&TEAM',
  'W&W',
  '22/7',
  'LOONA / ODD EYE CIRCLE',
  'LOONA/yyxy',
  'LOONA 1/3',
  'Tyler, The Creator',
  'Au/Ra',
  'Hillsong Young & Free',
  'Nick & Simon',
  'Fred V & Grafix',
  'Leo/need',
  'Black Country, New Road',
  'COOL&CREATE'
]

// Special genre names containing a delimiter that must be protected from splitting.
const DEFAULT_SPECIAL_GENRES: string[] = ['R&B']

// Lightweight genre alias -> canonical tag map (uppercase keys).
// Extend as needed; keeps behavior similar to the Android GenreTag matcher.
const GENRE_ALIAS_MAP: Map<string, string> = (() => {
  const m: Map<string, string> = new Map()
  const entries: string[][] = [
    ['POP', 'Pop'],
    ['POP MUSIC', 'Pop'],
    ['ROCK', 'Rock'],
    ['ROCK MUSIC', 'Rock'],
    ['HIPHOP', 'Hip-Hop'],
    ['HIP-HOP', 'Hip-Hop'],
    ['HIP HOP', 'Hip-Hop'],
    ['RAP', 'Hip-Hop'],
    ['R&B', 'R&B'],
    ['RNB', 'R&B'],
    ['RHYTHM AND BLUES', 'R&B'],
    ['ELECTRONIC', 'Electronic'],
    ['ELECTRONICA', 'Electronic'],
    ['EDM', 'Electronic'],
    ['CLASSICAL', 'Classical'],
    ['CLASSIC', 'Classical'],
    ['JAZZ', 'Jazz'],
    ['BLUES', 'Blues'],
    ['COUNTRY', 'Country'],
    ['FOLK', 'Folk'],
    ['METAL', 'Metal'],
    ['HEAVY METAL', 'Metal'],
    ['PUNK', 'Punk'],
    ['REGGAE', 'Reggae'],
    ['SOUL', 'Soul'],
    ['FUNK', 'Funk'],
    ['DISCO', 'Disco'],
    ['HOUSE', 'House'],
    ['TECHNO', 'Techno'],
    ['TRANCE', 'Trance'],
    ['DUBSTEP', 'Dubstep'],
    ['AMBIENT', 'Ambient'],
    ['SOUNDTRACK', 'Soundtrack'],
    ['OST', 'Soundtrack'],
    ['ANIME', 'Anime'],
    ['J-POP', 'J-Pop'],
    ['JPOP', 'J-Pop'],
    ['K-POP', 'K-Pop'],
    ['KPOP', 'K-Pop'],
    ['C-POP', 'C-Pop'],
    ['CPOP', 'C-Pop'],
    ['华语', '华语'],
    ['国语', '华语'],
    ['流行', 'Pop'],
    ['摇滚', 'Rock'],
    ['民谣', 'Folk'],
    ['电子', 'Electronic'],
    ['古典', 'Classical']
  ]
  for (const e of entries) {
    m.set(e[0], e[1])
  }
  return m
})()

interface ProtectedData {
  regex: RegExp | null
  originalToPlaceholder: Map<string, string>
  placeholderToOriginal: Map<string, string>
  hasItems: boolean
}

function escapeRegex(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
}

function buildProtectedData(names: string[], placeholderPrefix: string): ProtectedData {
  if (!names || names.length === 0) {
    return {
      regex: null,
      originalToPlaceholder: new Map(),
      placeholderToOriginal: new Map(),
      hasItems: false
    }
  }
  // Sort descending by length to match longer names first (e.g. "AC/DC" before "AC").
  const sorted: string[] = names.slice().sort((a: string, b: string): number => b.length - a.length)
  const originalToPlaceholder: Map<string, string> = new Map()
  const placeholderToOriginal: Map<string, string> = new Map()
  const escaped: string[] = []
  for (let i = 0; i < sorted.length; i++) {
    const original: string = sorted[i]
    const placeholder: string = `___GUQIN_${placeholderPrefix}_${i}___`
    originalToPlaceholder.set(original, placeholder)
    placeholderToOriginal.set(placeholder, original)
    escaped.push(escapeRegex(original))
  }
  // (^|[/、,;&])\s*(name1|name2|...)\s*(?=$|[/、,;&])
  const pattern: string = '(^|[/、,;&])\\s*(' + escaped.join('|') + ')\\s*(?=$|[/、,;&])'
  return {
    regex: new RegExp(pattern, 'g'),
    originalToPlaceholder,
    placeholderToOriginal,
    hasItems: true
  }
}

export class DiscTrack {
  discNo: number = 1
  discTotal: number = 0
  track: number = 0
  trackTotal: number = 0
}

export class Guqin {
  private static unsplitArtists: string[] = DEFAULT_UNSPLIT_ARTISTS.slice()
  private static artistData: ProtectedData = buildProtectedData(Guqin.unsplitArtists, 'P')
  private static genreData: ProtectedData = buildProtectedData(DEFAULT_SPECIAL_GENRES, 'G')

  // Allow app to extend the protected artist list (e.g. from user settings).
  static setUserUnsplitArtists(names: string[]): void {
    const merged: string[] = DEFAULT_UNSPLIT_ARTISTS.slice()
    if (names && names.length > 0) {
      for (const n of names) {
        if (n && merged.indexOf(n) < 0) merged.push(n)
      }
    }
    Guqin.unsplitArtists = merged
    Guqin.artistData = buildProtectedData(merged, 'P')
  }

  private static formatWith(value: string, data: ProtectedData, mapGenre: boolean): string {
    if (!value || value.length === 0) return ''
    let temp: string = value.trim()
    if (temp.length === 0) return ''

    // 1. Protect special names with placeholders.
    if (data.hasItems && data.regex) {
      temp = temp.replace(data.regex, (_match: string, prefix: string, name: string): string => {
        const ph: string | undefined = data.originalToPlaceholder.get(name)
        return prefix + (ph ? ph : name)
      })
    }

    // 2. Normalize all delimiters to "/".
    temp = temp.replace(DELIMITER_REGEX, '/')

    // 3. Split, trim, dedupe, restore, optionally canonicalize genre.
    const parts: string[] = temp.split('/')
    const seen: Set<string> = new Set()
    const out: string[] = []
    for (const raw of parts) {
      const trimmed: string = raw.trim()
      if (trimmed.length === 0) continue
      let restored: string = trimmed
      if (data.hasItems) {
        const orig: string | undefined = data.placeholderToOriginal.get(trimmed)
        if (orig) restored = orig
      }
      if (mapGenre) {
        const canon: string | undefined = GENRE_ALIAS_MAP.get(restored.toUpperCase())
        if (canon) restored = canon
      }
      if (!seen.has(restored)) {
        seen.add(restored)
        out.push(restored)
      }
    }
    return out.join('/')
  }

  /** Format a title: trim; fall back to filename (without extension) if empty. */
  static formatTitle(value: string, filename?: string): string {
    const t: string = value ? value.trim() : ''
    if (t.length > 0) return t
    if (filename && filename.length > 0) {
      const dot: number = filename.lastIndexOf('.')
      return dot > 0 ? filename.substring(0, dot) : filename
    }
    return ''
  }

  /** Format an artist string: normalize delimiters, protect specials, dedupe. */
  static formatArtist(value: string): string {
    if (!value) return ''
    return Guqin.formatWith(value, Guqin.artistData, false)
  }

  /** Format an album: trim; fall back to folder name if empty. */
  static formatAlbum(value: string, foldername?: string): string {
    const t: string = value ? value.trim() : ''
    if (t.length > 0) return t
    return foldername ? foldername : ''
  }

  /** Format a genre string: normalize delimiters, protect "R&B", map aliases, dedupe. */
  static formatGenre(value: string): string {
    if (!value) return ''
    return Guqin.formatWith(value, Guqin.genreData, true)
  }

  /** Year from a date string "YYYY-MM-DD" or fallback year string. Returns 0 if unknown. */
  static formatYear(year: string, date: string): number {
    if (date && date.length >= 4) {
      const y: number = parseInt(date.substring(0, 4))
      if (!isNaN(y) && y > 0) return y
    }
    if (year && year.length > 0) {
      const y2: number = parseInt(year)
      if (!isNaN(y2) && y2 > 0) return y2
    }
    return 0
  }

  /** Split an artist string into a list, respecting protected names. */
  static getArtists(metadata: string): string[] {
    const formatted: string = Guqin.formatArtist(metadata)
    if (formatted.length === 0) return []
    return formatted.split('/')
  }

  /**
   * Parse disc/track numbers; supports "n/total" and iTunes-style
   * (track > 1000 => discNo = track/1000, track = track%1000).
   */
  static formatDiscTrack(discNo?: string, discTotal?: string, track?: string, trackTotal?: string): DiscTrack {
    const result: DiscTrack = new DiscTrack()

    // Track "n/total"
    let curTrack: number = 0
    let curTrackTotal: number = 0
    if (track && track.length > 0) {
      const parts: string[] = track.split('/')
      const a: number = parseInt(parts[0])
      if (!isNaN(a)) curTrack = a
      if (parts.length > 1) {
        const b: number = parseInt(parts[1])
        if (!isNaN(b)) curTrackTotal = b
      }
    }
    if (curTrackTotal === 0 && trackTotal && trackTotal.length > 0) {
      const b: number = parseInt(trackTotal)
      if (!isNaN(b)) curTrackTotal = b
    }

    // Disc "n/total"
    let curDisc: number = 1
    let curDiscTotal: number = 0
    if (discNo && discNo.length > 0) {
      const parts: string[] = discNo.split('/')
      const a: number = parseInt(parts[0])
      if (!isNaN(a)) curDisc = a
      if (parts.length > 1) {
        const b: number = parseInt(parts[1])
        if (!isNaN(b)) curDiscTotal = b
      }
    }
    if (curDiscTotal === 0 && discTotal && discTotal.length > 0) {
      const b: number = parseInt(discTotal)
      if (!isNaN(b)) curDiscTotal = b
    }

    // iTunes-style: track encodes disc*1000+track.
    if (curTrack > 1000) {
      curDisc = Math.floor(curTrack / 1000)
      curTrack = curTrack % 1000
    }

    result.discNo = curDisc >= 1 ? curDisc : 1
    result.discTotal = curDiscTotal >= 0 ? curDiscTotal : 0
    result.track = curTrack >= 0 ? curTrack : 0
    result.trackTotal = curTrackTotal >= 0 ? curTrackTotal : 0
    return result
  }
}

// 重命名内部变量以提升可读性，标签归一化行为保持不变。

// 标签处理：多艺术家字段归一化与流派别名映射。
