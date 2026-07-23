---
commit-id: 3def85272a3ed2cedbd3ff750f52cf1778e28c20
branch: wsh-release-3
variant: baseline
agent: logic-coding-minimal (agent-a00583a131318051d)
stage: 4a
---

# Stage 4a Commit Info

## Commit

- **SHA**: 3def85272a3ed2cedbd3ff750f52cf1778e28c20 (amended from 4c3493f36875c768497bf084ddf96d63bbdb15d0 to add `[Human-AI]` prefix)
- **Message**: [Human-AI] feat(logic): wire displaySongCover toggle to live-refresh all song lists
- **Files changed**: 14 (7 pages + 7 ViewModels)
- **Insertions**: 165
- **Deletions**: 6

## Changed Files

### Pages (7)

- entry/src/main/ets/pages/ArtistContentPage.ets
- entry/src/main/ets/pages/FolderContentPage.ets
- entry/src/main/ets/pages/FolderPathPage.ets
- entry/src/main/ets/pages/PlaylistContentPage.ets
- entry/src/main/ets/pages/PlaylistSearchPage.ets
- entry/src/main/ets/pages/SearchAllSongsPage.ets
- entry/src/main/ets/pages/main/MainPage.ets

### ViewModels (7)

- entry/src/main/ets/viewmodel/ArtistContentViewModel.ets
- entry/src/main/ets/viewmodel/FolderContentPageViewModel.ets
- entry/src/main/ets/viewmodel/FolderPathViewModel.ets
- entry/src/main/ets/viewmodel/MainPageViewModel.ets
- entry/src/main/ets/viewmodel/PlaylistContentViewModel.ets
- entry/src/main/ets/viewmodel/PlaylistSearchViewModel.ets
- entry/src/main/ets/viewmodel/SearchAllSongsViewModel.ets

## Implementation Summary

Implemented the reader-side wiring called out in `SPEC/logic/plan.md`:

1. Per-page `@StorageProp('displaySongCover')` bridge with an `@Watch`-ed handler that forwards to `viewModel.setDisplaySongCoverInList(...)`.
2. New `@Track public displaySongCoverInList` field + `setDisplaySongCoverInList(...)` setter on each consumer ViewModel.
3. `MainPage` line ~1106 changed from hardcoded `showCover: true` to `showCover: this.vm.displaySongCoverInList` so the main song list responds to the toggle.
4. `ArtistContentViewModel.setDisplaySongCoverInList(...)` walks the cached `SongItemViewModel` array and reloads the LazyDataSource because its song VMs are long-lived.

## Verification at commit time

- `grep` across 7 pages confirms exactly one `@StorageProp('displaySongCover')` + one watch handler per page, and every `showCover:` binding reads from the VM.
- `grep` across 7 VMs confirms exactly one `@Track public displaySongCoverInList` field + one `setDisplaySongCoverInList` setter each.
- `hvigorw assembleHap --mode module -p product=default` → BUILD SUCCESSFUL (~9s). Only pre-existing deprecation warnings from unrelated files, no new errors.

## Post-commit amendment

The commit message was amended after the pipeline completed to add the `[Human-AI]` prefix per project convention. The tree content is identical between `4c3493f3...` and `3def8527...` — only the message changed.
