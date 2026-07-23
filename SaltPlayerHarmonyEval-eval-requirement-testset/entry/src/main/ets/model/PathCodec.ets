// PathCodec.ets
// Helpers for reasoning about the song-path strings used by playlist .txt
// export / import:
//
//   - DB form: the path stored in MusicDatabase.Track.path. It comes
//     verbatim from the HarmonyOS DocumentViewPicker URI, whose exact
//     percent-encoding is OS-dependent — e.g. '&' is encoded as %26, but
//     non-ASCII (Chinese) might be either %XX-encoded or literal depending
//     on the device. We deliberately do NOT try to predict that encoding.
//
//   - Display form: the human-readable line written to the exported .txt.
//     Every percent-escape is decoded so users can read filenames in their
//     native script.
//
// The earlier export code used `decodeURI`, which intentionally leaves the
// URI-reserved set (`; , / ? : @ & = + $ #`) as-is — so `%26` (the encoded
// form of '&') leaked through to the .txt as the literal text "%26". The
// import code then `encodeURI`'d that string, which encoded the '%' itself
// to '%25', producing '%2526' — never matching the DB row.
//
// Rather than re-derive the OS encoding to fix the round-trip, this module
// just exposes a single fully-decoded "canonical" form. The export side
// writes the canonical form (so users see '&', not '%26'). The import side
// matches by comparing canonical forms on BOTH the parsed line and the DB
// row's path — that way matching works for any percent-encoding variant
// the OS produces, and a similar bug can't reappear for '#', '?', '=', etc.

// Decode every percent-escape to its literal character. Used both as the
// "display form" written to exported .txt files and as the canonical key
// used by the import-side DB matcher.
//
// '%2F' (the encoded forward slash) decodes to '/'. POSIX filesystems
// forbid '/' inside a filename, so %2F doesn't legitimately appear in a
// scanner-produced URI; if it ever did, decoding it would only collapse
// distinct paths together — not corrupt them.
//
// Falls back to the raw input if decoding throws on a malformed escape.
export function canonicalizePath(uri: string): string {
  if (!uri || uri.length === 0) return ''
  try {
    return decodeURIComponent(uri)
  } catch (_e) {
    return uri
  }
}

// Alias kept for the export-call site: the .txt body uses exactly the
// canonical (fully decoded) form so users can read filenames in their
// native script.
export function decodePathForDisplay(uri: string): string {
  return canonicalizePath(uri)
}

// 提取路径编码常量并重命名内部变量，行为保持不变。

// 再次整理空行，无功能变更。

// 整理空行，无功能变更。
