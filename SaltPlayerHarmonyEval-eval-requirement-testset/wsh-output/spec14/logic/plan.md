# Spec14 — 音量平衡 (ReplayGain Volume Balance) Implementation Plan

## 1. Overview

Implement the **Volume Balance** feature in Settings > Audio Output. When enabled, the player reads ReplayGain tags (`REPLAYGAIN_TRACK_GAIN` and/or `REPLAYGAIN_ALBUM_GAIN`) embedded in the currently playing audio file and adjusts the internal playback volume multiplier accordingly. This is **not** device volume adjustment — it is an internal gain applied to the AVPlayer so that songs with different loudness levels play at consistent perceived volume.

The UI toggle already exists on `AudioOutputPage` (bound to `AudioOutputViewModel.volumeBalanceEnabled`). This plan wires the toggle into actual playback behavior.

## 2. MVVM Owner Boundary

| Layer | Owner | Responsibility |
|---|---|---|
| **Page** | `AudioOutputPage` | Renders the toggle; delegates change to VM |
| **ViewModel** | `AudioOutputViewModel` | Persists toggle state; no playback logic |
| **Model / Service** | `AudioPlayerService` | Reads gain at song-change time; applies volume multiplier via `AVPlayer.setVolume()` |
| **DataSource** | `ScanningModel` + `MusicDatabase` | Extracts ReplayGain tags during scan/refresh; persists to RDB |
| **Display** | `PlayerPageViewModel` + `PlayerPage` | Shows current RG value (e.g. "RG -3.5 dB") in the audio-info area |

**Key rule:** The playback volume multiplier is owned by `AudioPlayerService` (the same layer that already owns fade-in/fade-out volume ramps). Do not move volume control into `PlayerPageViewModel`.

## 3. Data Flow

```
[ScanningModel.readAudioFromUri]  --extracts-->  replayGainDb (string like "-3.5 dB")
       |
       v
[MusicDatabase.TrackRow]  --persists-->  replayGainDb column (TEXT, default '')
       |
       v
[AudioPlayerService.doPlay / onSongChanged]  --reads-->  replayGainDb from DB by songId
       |
       v
[AudioPlayerService]  --computes-->  volumeMultiplier = dbToMultiplier(replayGainDb)
       |
       v
[AVPlayer.setVolume]  --applies-->  volumeMultiplier (clamped 0..1)
       |
       v
[PlayerPageViewModel]  --displays-->  "RG -3.5 dB" in audio info summary
```

## 4. Implementation Steps

### Step 4.1 — Database Schema Extension

**File:** `entry/src/main/ets/model/MusicDatabase.ets`

Add `replayGainDb` column to the `Track` table via a defensive `ALTER TABLE` in `doInit()` (same pattern as `channels`, `quality`, `qualityClassified`).

```typescript
// In SQL_CREATE_TRACK, add:
//   replayGainDb TEXT NOT NULL DEFAULT ''

// In doInit(), add after existing ALTER TABLE blocks:
try {
  await MusicDatabase.rdbStore.executeSql(
    "ALTER TABLE Track ADD COLUMN replayGainDb TEXT NOT NULL DEFAULT ''"
  )
} catch (_ignored) {}
```

Update `TrackRow` interface to include `replayGainDb: string`.

Update `readTrackRow()` to read `replayGainDb` via `safeGetString()`.

Update `insertTracks()` bucket to include `'replayGainDb': t.replayGainDb ?? ''`.

Update `updateTracksMetadata()` to allow `replayGainDb` in the bucket (the refresh-existing-tracks path will rewrite it when metadata changes).

### Step 4.2 — Scan-Time Tag Extraction

**File:** `entry/src/main/ets/model/ScanningModel.ets`

The HarmonyOS `AVMetadataExtractor` does **not** expose ReplayGain tags through its public API. We must read them via a secondary metadata parser. The project already uses `AVMetadataExtractor` for standard tags. For ReplayGain, we need a lightweight tag reader.

**Approach:** Implement a `ReplayGainExtractor` utility that reads the raw file and parses ReplayGain tags. For MP3 (ID3v2), FLAC (Vorbis comment), and MP4 (ilst), the tag keys are:
- `REPLAYGAIN_TRACK_GAIN`
- `REPLAYGAIN_ALBUM_GAIN`

**Simplification for this plan:** Since HarmonyOS does not provide a native ReplayGain tag API, and building a full tag parser from scratch is out of scope, the implementation will:

1. Add a `ReplayGainExtractor.ets` utility file with a best-effort parser:
   - For FLAC: read Vorbis comments from the FLAC stream (parse the STREAMINFO + VORBIS_COMMENT blocks)
   - For MP3: scan ID3v2.4 tags for TXXX frames with the ReplayGain description
   - For other formats: return empty string (no gain)

2. In `ScanningModel.readAudioFromUri()`, after the existing `AVMetadataExtractor` block, call `ReplayGainExtractor.extract(file.fd, stat.size, song.mimeType)` and assign the result to `song.replayGainDb`.

3. Update `ScannedSongData` to include `replayGainDb: string = ''`.

4. Update `ScanningDataSource.toTrackRow()` to include `replayGainDb: song.replayGainDb`.

5. Update `getScannedSongsAsync()` / `loadFromDatabase()` mapping to carry `replayGainDb` through.

**File:** `entry/src/main/ets/model/ReplayGainExtractor.ets` (new)

```typescript
// Best-effort ReplayGain tag extractor.
// Returns the raw gain string (e.g. "-3.5 dB") or '' if not found.
// Priority: REPLAYGAIN_TRACK_GAIN > REPLAYGAIN_ALBUM_GAIN.

import { fileIo } from '@kit.CoreFileKit'

export class ReplayGainExtractor {
  static extract(fd: number, size: number, mimeType: string): string {
    // FLAC: parse Vorbis comment blocks
    if (mimeType.includes('flac') || mimeType.includes('x-flac')) {
      return this.extractFromFlac(fd, size)
    }
    // MP3: parse ID3v2 TXXX frames
    if (mimeType.includes('mpeg')) {
      return this.extractFromMp3(fd, size)
    }
    return ''
  }

  private static extractFromFlac(fd: number, size: number): string {
    // Read first 64KB of file to find Vorbis comment block
    const bufSize = Math.min(size, 65536)
    const buf = new ArrayBuffer(bufSize)
    fileIo.readSync(fd, buf, { offset: 0, length: bufSize })
    const view = new Uint8Array(buf)
    // FLAC magic: "fLaC" at offset 0
    if (view[0] !== 0x66 || view[1] !== 0x4C || view[2] !== 0x61 || view[3] !== 0x43) {
      return ''
    }
    // Parse metadata blocks...
    // (implementation detail: walk metadata blocks, find VORBIS_COMMENT,
    //  parse vendor string length, then comment list, match keys)
    return '' // TODO: implement FLAC Vorbis comment parsing
  }

  private static extractFromMp3(fd: number, size: number): string {
    // Read first 32KB to find ID3v2 tag
    const bufSize = Math.min(size, 32768)
    const buf = new ArrayBuffer(bufSize)
    fileIo.readSync(fd, buf, { offset: 0, length: bufSize })
    const view = new Uint8Array(buf)
    // ID3v2 magic: "ID3" at offset 0
    if (view[0] !== 0x49 || view[1] !== 0x44 || view[2] !== 0x33) {
      return ''
    }
    // Parse ID3v2 frames...
    // (implementation detail: read tag size, walk frames, find TXXX
    //  with description "REPLAYGAIN_TRACK_GAIN" or "REPLAYGAIN_ALBUM_GAIN")
    return '' // TODO: implement ID3v2 TXXX parsing
  }
}
```

> **Note:** The actual byte-level parsing logic for FLAC Vorbis comments and ID3v2 TXXX frames is a well-defined binary format walk. The coding agent will implement the full parser. The plan only sketches the structure.

### Step 4.3 — AudioPlayerService Integration

**File:** `entry/src/main/ets/model/AudioPlayerService.ets`

Add a private field to track the volume-balance multiplier:

```typescript
private _volumeBalanceMultiplier: number = 1.0
```

Add a method to read the setting and compute the multiplier:

```typescript
private isVolumeBalanceEnabled(): boolean {
  return AppStorage.get<boolean>('volumeBalanceEnabled') ?? true
}

// Convert "-3.5 dB" string to multiplier (e.g. 0.668)
private parseReplayGainDb(gainStr: string): number {
  if (!gainStr || gainStr.length === 0) return 1.0
  const match = gainStr.match(/([+-]?\d+(?:\.\d+)?)/)
  if (!match) return 1.0
  const db = parseFloat(match[1])
  if (isNaN(db)) return 1.0
  // dB to linear: 10^(db/20)
  const multiplier = Math.pow(10, db / 20)
  // Clamp to [0, 1] for safety (AVPlayer volume range)
  return Math.max(0, Math.min(1, multiplier))
}
```

In `doPlay()`, after the song is prepared and before `player.play()` is called (in the `'prepared'` state handler), read the ReplayGain value and apply it:

```typescript
// In the 'prepared' state handler, after applyAudioFocusMode():
// spec14: apply volume balance multiplier
if (this.isVolumeBalanceEnabled()) {
  const rgDb = await MusicDatabase.getReplayGainDb(this.currentSongId)
  this._volumeBalanceMultiplier = this.parseReplayGainDb(rgDb)
} else {
  this._volumeBalanceMultiplier = 1.0
}
// The fade-in path already calls safeSetVolume(0) then ramps to 1.
// We need the ramp target to be _volumeBalanceMultiplier, not 1.0.
```

Modify the fade-in/fade-out logic to respect the volume balance multiplier:

In `rampVolume()`, the target is already parameterized. Update the call sites:

- In `'prepared'` state handler (fade-in for new song): ramp from 0 to `_volumeBalanceMultiplier`
- In `pause()` (fade-out): ramp from current volume to 0
- In `resume()` (fade-in): ramp from 0 to `_volumeBalanceMultiplier`

Update `safeSetVolume()` to apply the multiplier as the effective ceiling:

```typescript
private safeSetVolume(v: number): void {
  if (!this.avPlayer) return
  // v is the fade envelope value (0..1); actual volume is v * balanceMultiplier
  const effective = Math.max(0, Math.min(1, v * this._volumeBalanceMultiplier))
  try {
    this.avPlayer.setVolume(effective)
    this._currentVolume = v  // track the envelope value, not effective
  } catch (e) { ... }
}
```

> **Important:** `_currentVolume` tracks the fade envelope (0..1), not the effective volume. This ensures that toggling volume balance mid-playback doesn't require restarting the fade — the next `safeSetVolume` call will automatically apply the new multiplier. However, per **Scene 4**, the setting only takes effect on the next song switch, so mid-playback toggles do not need immediate application.

Add `MusicDatabase.getReplayGainDb(songId: string)` method (see Step 4.1).

### Step 4.4 — Player Page Display

**File:** `entry/src/main/ets/viewmodel/PlayerPageViewModel.ets`

Add a `@Track` property for the current ReplayGain display:

```typescript
@Track public currentReplayGainText: string = ''
```

In `updateAudioInfo()` (called on every song change), read the ReplayGain value and format it:

```typescript
updateAudioInfo(songId: string): void {
  // ... existing logic ...
  if (song) {
    // ... existing audio info model update ...
    // spec14: format replay gain display
    const rgDb = song.replayGainDb ?? ''
    if (rgDb.length > 0 && (AppStorage.get<boolean>('volumeBalanceEnabled') ?? true)) {
      this.currentReplayGainText = 'RG ' + rgDb
    } else {
      this.currentReplayGainText = ''
    }
  } else {
    this.currentReplayGainText = ''
  }
  // ... rest of existing logic ...
}
```

Update `refreshAudioInfoSummary()` to include the ReplayGain text when present:

```typescript
refreshAudioInfoSummary(): void {
  const parts: string[] = []
  // ... existing parts (format, sampleRate, bitrate) ...
  // spec14: append replay gain if available
  if (this.currentReplayGainText.length > 0) {
    parts.push(this.currentReplayGainText)
  }
  this.audioInfoSummary = parts.length > 0 ? parts.join('  ') : ''
}
```

**File:** `entry/src/main/ets/pages/PlayerPage.ets`

No changes needed — `AudioInfoBelowCover()` already binds to `this.vm.audioInfoSummary` which is refreshed by `refreshAudioInfoSummary()`.

### Step 4.5 — AudioOutputPage / AudioOutputViewModel

**File:** `entry/src/main/ets/viewmodel/AudioOutputViewModel.ets`

The toggle already exists and persists correctly. No changes needed.

However, add a helper method so the VM can notify the service when the toggle changes (for immediate effect on the *next* song, not the current one — per Scene 4):

```typescript
setVolumeBalanceEnabled(value: boolean): void {
  this.volumeBalanceEnabled = value
  this.model.volumeBalanceEnabled = value
  SettingsStore.getInstance().save('volumeBalanceEnabled', value)
  // Note: per Scene 4, the change takes effect on the next song switch.
  // No need to poke AudioPlayerService here.
}
```

This is already the current implementation. No change needed.

### Step 4.6 — EntryAbility Persistence

**File:** `entry/src/main/ets/entryability/EntryAbility.ets`

`volumeBalanceEnabled` is already persisted via `PersistentStorage.persistProp` (line 111) and restored from `SettingsStore` (line 157). No changes needed.

### Step 4.7 — Refresh Existing Tracks

**File:** `entry/src/main/ets/model/ScanningModel.ets`

In `refreshExistingTracks()`, when a changed file is re-read, the `ReplayGainExtractor` will be called just like during initial scan. The `batchUpdates` bucket should include `replayGainDb` so the DB gets updated.

Update the bucket in `refreshExistingTracks()`:

```typescript
const bucket: relationalStore.ValuesBucket = {
  // ... existing fields ...
  'replayGainDb': song.replayGainDb,
  // ...
}
```

## 5. Scene-by-Scene Verification

| Scene | Verification Point |
|---|---|
| **S1** — Toggle ON, song has RG tag | `AudioPlayerService` reads RG, computes multiplier < 1, applies via `setVolume`. Player page shows "RG -X.X dB" |
| **S2** — Toggle ON, song has no RG tag | `parseReplayGainDb('')` returns 1.0. No display text. Volume unchanged |
| **S3** — Toggle OFF | `isVolumeBalanceEnabled()` returns false. `_volumeBalanceMultiplier` stays 1.0. No RG display |
| **S4** — Toggle mid-playback | Setting is persisted but `AudioPlayerService` only reads RG on next `doPlay()` / song switch. Current song volume unchanged |
| **S5** — Both TRACK and ALBUM gain present | `ReplayGainExtractor` returns the first matched tag (implementation order: TRACK first, then ALBUM). Display shows whichever was found first |
| **S6** — Internal volume only | `setVolume()` adjusts AVPlayer internal volume. Device media volume is independent. Final perceived volume = deviceVolume * balanceMultiplier |

## 6. Files to Modify / Create

### New Files
1. `entry/src/main/ets/model/ReplayGainExtractor.ets` — Best-effort RG tag parser for FLAC (Vorbis comment) and MP3 (ID3v2 TXXX)

### Modified Files
1. `entry/src/main/ets/model/MusicDatabase.ets`
   - Add `replayGainDb` column (ALTER TABLE)
   - Add to `TrackRow`, `readTrackRow`, `insertTracks`, `updateTracksMetadata`
   - Add `getReplayGainDb(songId: string): Promise<string>` method

2. `entry/src/main/ets/model/ScanningModel.ets`
   - Add `replayGainDb` to `ScannedSongData`
   - Call `ReplayGainExtractor.extract()` in `readAudioFromUri()`
   - Pass `replayGainDb` through `toTrackRow()` and `getScannedSongsAsync()`
   - Include `replayGainDb` in `refreshExistingTracks()` update bucket

3. `entry/src/main/ets/model/AudioPlayerService.ets`
   - Add `_volumeBalanceMultiplier` field
   - Add `isVolumeBalanceEnabled()` and `parseReplayGainDb()` helpers
   - Modify `'prepared'` state handler to read RG and set multiplier
   - Update fade ramp targets to use `_volumeBalanceMultiplier` instead of hardcoded 1.0
   - Update `safeSetVolume()` to apply multiplier

4. `entry/src/main/ets/viewmodel/PlayerPageViewModel.ets`
   - Add `currentReplayGainText` @Track property
   - Update `updateAudioInfo()` to read and format RG value
   - Update `refreshAudioInfoSummary()` to include RG text

## 7. Risk & Mitigation

| Risk | Mitigation |
|---|---|
| `AVMetadataExtractor` does not expose RG tags | Use a custom `ReplayGainExtractor` that reads raw file bytes. Only implement FLAC and MP3 to start; other formats return empty (graceful fallback) |
| ReplayGain values > 0 dB would require volume > 1.0 | Clamp multiplier to [0, 1]. Positive gains (louder) are silently ignored — this is standard behavior for players that don't want to clip |
| Fade-in/fade-out envelope conflicts with balance multiplier | `safeSetVolume()` multiplies envelope * balance. Envelope tracks 0..1 independently; effective volume never exceeds balance multiplier |
| DB migration on existing installs | Defensive `ALTER TABLE ... ADD COLUMN` with try/catch (already the project's pattern) |
| Parsing performance on large libraries | ReplayGain extraction happens during scan (one-time per file), not during playback. Playback-time lookup is a single indexed DB query by `id` |

## 8. Testing Checklist

1. Scan a FLAC file with `REPLAYGAIN_TRACK_GAIN=-3.5 dB` — verify DB stores the value
2. Scan an MP3 with ID3v2.4 TXXX `REPLAYGAIN_TRACK_GAIN` — verify DB stores the value
3. Play the FLAC with Volume Balance ON — verify `audioInfoSummary` shows "RG -3.5 dB"
4. Play a song without RG tags — verify no "RG" text and volume is normal
5. Turn Volume Balance OFF mid-playback — verify current song volume unchanged; next song plays at normal volume
6. Turn Volume Balance ON mid-playback — verify current song unchanged; next song applies RG
7. Verify device volume keys still work independently
8. Verify fade-in/fade-out still works correctly with volume balance enabled
