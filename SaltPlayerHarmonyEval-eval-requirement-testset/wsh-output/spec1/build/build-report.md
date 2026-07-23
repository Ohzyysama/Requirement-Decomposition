# HarmonyOS Build Report

## Build Status

**SUCCESS**

## Environment

- **Node executable**: `/Applications/DevEco-Studio.app/Contents/tools/node/bin/node` (auto-detected from DevEco Studio bundle)
- **Hvigor script**: `/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw.js`
- **DEVECO_SDK_HOME**: `/Applications/DevEco-Studio.app/Contents`
- **Project root**: `/Users/moriafly/GitHub/SaltPlayerHarmony`
- **Product**: `default`
- **Target SDK**: `6.1.0(23)` (compatible `6.0.2(22)`, runtimeOS `HarmonyOS`)
- **Model version**: `6.0.2` (from `oh-package.json5`)

## Signing

**Verified.**

- `app.signingConfigs[0].name` = `default`, referenced by `app.products[0].signingConfig` = `default`.
- All material files exist on disk:
  - `material.certpath`: `/Users/moriafly/GitHub/Xuncorp.cer`
  - `material.storeFile`: `/Users/moriafly/GitHub/xuncorp.p12`
  - `material.profile`: `/Users/moriafly/GitHub/SPHRelease.p7b`
- Sign algorithm: `SHA256withECDSA`.
- Output filename contains `signed`, confirming `SignHap` task produced a signed package.

## Sync Result

**Clean.** `--sync -p product=default --analyze=normal --parallel --incremental --no-daemon` completed successfully with no compilation errors reported.

## Fix Iterations

**0.** No compilation errors were encountered; no fix cycles were needed.

## Build Output

`assembleHap --mode module -p product=default` completed `BUILD SUCCESSFUL` in ~839 ms (fully up-to-date from prior incremental state). All tasks reported `UP-TO-DATE` or `Finished` — including `SignHap`.

## HAP Output Path

- **Source**: `/Users/moriafly/GitHub/SaltPlayerHarmony/entry/build/default/outputs/default/entry-default-signed.hap` (30,141,311 bytes)
- **Copied to**: `/Users/moriafly/GitHub/SaltPlayerHarmony/SPEC/build/entry-default-signed.hap`

## Warnings

No warnings surfaced in the sync or assemble output for this incremental build.

## Remaining Errors

None.

## Commit Context

Built against commit `4c3493f36875c768497bf084ddf96d63bbdb15d0` on branch `wsh-release-3` (variant `baseline`), as recorded in `SPEC/commit-info.md` — stage 4a `feat(logic): wire displaySongCover toggle to live-refresh all song lists`.
