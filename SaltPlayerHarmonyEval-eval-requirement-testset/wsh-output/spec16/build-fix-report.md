# Build Fix Report — Stage 6b (Rebuild after Review Fix)

## Build Status

**SUCCESS** — Build completed cleanly on the first iteration (no errors).

## Overview

| Field | Value |
|---|---|
| Stage | 6b — Rebuild after Review Fix |
| HarmonyOS Project | `/Users/moriafly/GitHub/SaltPlayerHarmony` |
| Output Path | `/Users/moriafly/GitHub/SaltPlayerHarmony/wsh-output/spec16` |
| Build Date | 2026/05/15 |
| Build Type | Signed HAP (release) |
| Signing Config | `default` (production cert `Xuncorp.cer` + profile `SPHRelease.p7b` + keystore `xuncorp.p12`) |
| Build Tool | hvigor via DevEco Studio bundled Node.js |
| DevEco Studio Path | `/Applications/DevEco-Studio.app/Contents` |
| Target SDK | `6.1.0(23)` |
| Compatible SDK | `6.0.2(22)` |
| Iterations | 1 / 20 |
| Total Errors Fixed | 0 |
| Total Build Time | 840 ms |

## Pre-Build Environment

| Component | Path | Status |
|---|---|---|
| DevEco Studio | `/Applications/DevEco-Studio.app/Contents` | OK |
| Node executable | `/Applications/DevEco-Studio.app/Contents/tools/node/bin/node` | OK |
| Hvigor script | `/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw.js` | OK |
| ohpm | `/Applications/DevEco-Studio.app/Contents/tools/ohpm/bin/ohpm` | OK |
| SDK directory | `/Applications/DevEco-Studio.app/Contents/sdk` | OK |
| JBR (JAVA_HOME) | `/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home` | OK |
| `local.properties` | `hwsdk.dir=/Applications/DevEco-Studio.app/Contents/sdk` | OK |
| Signing cert | `/Users/moriafly/GitHub/Xuncorp.cer` | OK |
| Signing profile | `/Users/moriafly/GitHub/SPHRelease.p7b` | OK |
| Signing keystore | `/Users/moriafly/GitHub/xuncorp.p12` | OK |

## Signing

Signing configuration `default` from `build-profile.json5` was applied:

- `keyAlias`: `xuncorp`
- `certpath`: `/Users/moriafly/GitHub/Xuncorp.cer`
- `profile`: `/Users/moriafly/GitHub/SPHRelease.p7b`
- `storeFile`: `/Users/moriafly/GitHub/xuncorp.p12`
- `signAlg`: `SHA256withECDSA`

All signing material files were verified to exist on disk before the build. The `SignHap` task in hvigor reported `UP-TO-DATE` (artifact reused from the Stage 5 build — see "Iteration Log" below).

## Build Command

```bash
export DEVECO_SDK_HOME="/Applications/DevEco-Studio.app/Contents/sdk"
export JAVA_HOME="/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home"
export PATH="$JAVA_HOME/bin:$PATH"
"/Applications/DevEco-Studio.app/Contents/tools/node/bin/node" \
  "/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw.js" \
  assembleHap --mode module -p module=entry --no-daemon
```

## Iteration Log

### Iteration 1 — BUILD SUCCESSFUL

- All hvigor tasks completed in **840 ms**.
- Every compile/processing/signing task reported `UP-TO-DATE` (cached from Stage 5), because Stage 6a (Review Fix) did not modify any source files: the working tree was identical to the post-Stage-5 commit `232c0c8` at build time.
- Key task statuses:
  - `:entry:default@CompileArkTS` — UP-TO-DATE
  - `:entry:default@CompileResource` — UP-TO-DATE
  - `:entry:default@PackageHap` — UP-TO-DATE
  - `:entry:default@SignHap` — UP-TO-DATE
  - `:entry:assembleHap` — Finished after 1 ms
- No errors, no warnings.

## Summary of Changes

**None.** Stage 6a (Review Fix) deferred its single PARTIAL issue (3D lyrics visual parity for Scenario 3) to Stage 7 (Self-Testing), so no source files were modified in this rebuild cycle. The HAP produced is byte-identical to the Stage 5 output for spec16 (commit `232c0c8`).

| Files modified during build-fix loop | Reason for fix |
|---|---|
| (none) | (no errors encountered) |

## Output Artifacts

| Artifact | Path |
|---|---|
| Signed HAP (build dir) | `/Users/moriafly/GitHub/SaltPlayerHarmony/entry/build/default/outputs/default/entry-default-signed.hap` |
| Signed HAP (output dir) | `/Users/moriafly/GitHub/SaltPlayerHarmony/wsh-output/spec16/entry-default-signed.hap` |
| HAP size | 30,562,615 bytes (~29.15 MiB) |
| HAP MD5 | `cc9a02793a520dfd75602d780c25470e` |

The signed HAP in `wsh-output/spec16/` has been replaced with the freshly built artifact (MD5 of build-dir HAP matches MD5 of output-dir HAP). Since the source tree is unchanged from Stage 5, the new HAP is byte-identical to the previous one — the replacement is effectively a no-op rewrite but is performed for pipeline consistency.

## Remaining Errors

None.

## Git Commit

No source files were modified during Stage 6a (Review Fix) or this Stage 6b rebuild. The current HEAD remains `232c0c8 [Human-AI] feat(spec16): 立体歌词效果 toggle wires through to PlayerPage`. See `build-fix-commit-info.md` (commit-id: none) for the pipeline-machine-readable record.

## Recommendations

1. **Proceed to Stage 7 (Self-Testing)** — the signed HAP `wsh-output/spec16/entry-default-signed.hap` is ready to install on a real HarmonyOS device.
2. **Visual-parity verification** — capture side-by-side screenshots of HarmonyOS PlayerPage (`lyricsUIEffect3D = true`) vs Android lyrics screen, for both the timed-lyrics and the static-lyrics rendering paths.
3. **Small-screen check** — verify on at least one narrow/foldable device that `centerX:'0%' + translate:{x:-28}` does not clip lyrics at the left edge. If clipping is observed, follow up with a screen-width-relative `LYRICS_3D_TRANSLATE_X_VP` computation.
