# Build-Fix Report — spec25 (Rebuild)

## Overview

| Field | Value |
|-------|-------|
| HarmonyOS Project | `/Users/moriafly/GitHub/SaltPlayerHarmony` |
| Output Path | `/Users/moriafly/GitHub/SaltPlayerHarmony/wsh-output/spec25` |
| Build Type | **Signed HAP** (`--signed`) |
| Build Status | **SUCCESS** |
| Iterations | 1 |
| Total Errors Fixed | 0 |
| Source Files Modified | 0 |
| HEAD at build time | `4ed0db782fc67bf444a5272a8f44900cf123c9ae` |
| Trigger | Rebuild after review-fix commit `4ed0db7` (Stage 6a HAP at `wsh-output/spec25/` was stale because it had been copied from an earlier build at `a8f2b80`). |

This rebuild **supersedes** the earlier Stage 6a report at this path (commit `a8f2b80`, 2 errors fixed). That history is preserved by the `a8f2b8053d2cf6ab5e2137740c51b6b9b9c5a12b` commit in git.

## Build Environment

| Tool | Path |
|------|------|
| DevEco Studio | `/Applications/DevEco-Studio.app/Contents` |
| Node.js | `/Applications/DevEco-Studio.app/Contents/tools/node/bin/node` |
| hvigorw.js | `/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw.js` |
| ohpm | `/Applications/DevEco-Studio.app/Contents/tools/ohpm/bin/ohpm` |
| HarmonyOS SDK | `/Applications/DevEco-Studio.app/Contents/sdk` (`DEVECO_SDK_HOME`) |
| JBR (`JAVA_HOME`) | `/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home` |
| `local.properties` | `hwsdk.dir=/Applications/DevEco-Studio.app/Contents/sdk` (already present) |

Platform: **macOS (darwin arm64)** — env vars exported directly into the shell (no Windows `.bat` wrapper needed).

## Signing Config

Read from `build-profile.json5` → `app.signingConfigs[0]` (`name: "default"`), referenced by `products[0].signingConfig: "default"`. All material files verified present on disk:

- `cert` — `/Users/moriafly/.ohos/config/Debug_SaltPlayerHarmony_x6pcF9HYXQkOICSvovnEYAL0TBgrr6wqNMfvugxUtmU=.cer` (2992 B)
- `profile` — `/Users/moriafly/.ohos/config/Debug_SaltPlayerHarmony_x6pcF9HYXQkOICSvovnEYAL0TBgrr6wqNMfvugxUtmU=.p7b` (4257 B)
- `storeFile` — `/Users/moriafly/.ohos/config/Debug_SaltPlayerHarmony_x6pcF9HYXQkOICSvovnEYAL0TBgrr6wqNMfvugxUtmU=.p12` (1128 B)

## Build Command

```bash
export PATH="$DEVECO/jbr/Contents/Home/bin:$DEVECO/tools/node/bin:$PATH"
export JAVA_HOME="$DEVECO/jbr/Contents/Home"
export DEVECO_SDK_HOME="$DEVECO/sdk"
node "$DEVECO/tools/hvigor/bin/hvigorw.js" assembleHap --mode module -p module=entry --no-daemon
```

## Iteration Log

### Iteration 1 — SUCCESS

All hvigor tasks completed as `UP-TO-DATE` or `Finished`, confirming the on-disk build artifacts already match the current HEAD source tree (the review-fix commit `4ed0db7` had been compiled into `entry/build/default/outputs/default/` by DevEco-Studio's incremental build cache, but the HAP at `wsh-output/spec25/` had been copied from the earlier `a8f2b80` build). No compilation errors, no warnings to address.

Key tasks (excerpt):

```
:entry:default@CompileArkTS               UP-TO-DATE
:entry:default@CompileResource            UP-TO-DATE
:entry:default@PackageHap                 UP-TO-DATE
:entry:default@SignHap                    UP-TO-DATE
:entry:default@CollectDebugSymbol         Finished
:entry:assembleHap                        Finished

BUILD SUCCESSFUL in 631 ms
```

## Output Artifact

Signed HAP copied to output path:

```
/Users/moriafly/GitHub/SaltPlayerHarmony/wsh-output/spec25/entry-default-signed.hap   (31,034,231 bytes)
```

Source artifact:

```
/Users/moriafly/GitHub/SaltPlayerHarmony/entry/build/default/outputs/default/entry-default-signed.hap
```

## Summary of Changes

No source files were modified during this build-fix run — the build succeeded on the first iteration with zero errors. The rebuild's sole purpose was to refresh the HAP copy at `wsh-output/spec25/` so the artifact reflects the current HEAD (`4ed0db7`), which includes the spec25 review-fix changes to `FloatingStatusBarLyricsController.ets` and `FloatingStatusBarLyricsWindow.ets`.

No git commit was created because no source files changed.

## Remaining Errors

None.

## Warnings

Same set of 160 pre-existing non-blocking ArkTS warnings noted in the original Stage 6a report (deprecated `showToast`, `getContext`, `animateTo`, `show` APIs plus `Function may throw exceptions` advisories). None block the build; outside the scope of this rebuild.
