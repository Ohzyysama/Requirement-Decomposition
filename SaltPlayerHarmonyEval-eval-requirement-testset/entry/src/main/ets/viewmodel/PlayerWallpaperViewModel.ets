// PlayerWallpaperViewModel.ets
// ViewModel for PlayerWallpaperPage (MVVM).
//   - State: busy (picker in-flight). wallpaperPath lives in AppStorage and
//     is read directly by the View via @StorageLink — no duplication here.
//   - Logic: select image via photoAccessHelper, copy into app sandbox under
//     `covers/`, persist path; on remove, clear the path and purge sandbox files.
// Mirror of MainWallpaperViewModel; only KEY / FILE_BASENAME / sandbox subdir differ.

import { photoAccessHelper } from '@kit.MediaLibraryKit'
import { fileIo } from '@kit.CoreFileKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { promptAction } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import SettingsStore from '../model/SettingsStore'

const DOMAIN = 0x0001
const TAG = 'PlayerWallpaperVM'
const COVERS_DIR = 'covers'
const FILE_BASENAME = 'player_screen_cover'
const KEY = 'playerScreenBgCover'

@Observed
export default class PlayerWallpaperViewModel {
  @Track public busy: boolean = false

  async selectImage(context: common.UIAbilityContext): Promise<void> {
    if (this.busy) {
      return
    }
    this.busy = true
    try {
      const picker = new photoAccessHelper.PhotoViewPicker()
      const options = new photoAccessHelper.PhotoSelectOptions()
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE
      options.maxSelectNumber = 1
      const result: photoAccessHelper.PhotoSelectResult = await picker.select(options)
      if (!result.photoUris || result.photoUris.length === 0) {
        return
      }
      const srcUri = result.photoUris[0]
      const destPath = await this.copyToSandbox(context, srcUri)
      this.applyPath(destPath)
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'selectImage failed: %{public}s', JSON.stringify(err))
      promptAction.showToast({ message: $r('app.string.error') })
    } finally {
      this.busy = false
    }
  }

  // removeWallpaper:
  //   AppStorage write FIRST, then file unlink. The @StorageLink/@StorageProp
  //   observers (PlayerWallpaperPage delete-row gate, PlayerPage Image, PlayQueue
  //   background) react in the SAME tick — the conditional `if (path.length > 0)`
  //   collapses, the Image is removed from the tree, the file handle is released,
  //   THEN unlinkSync runs. Reversing this order would race the file unlink
  //   against the still-mounted Image and could trip "file in use" errors on
  //   some kernels. This ordering is the live-refresh contract Scene 1 steps
  //   8 + 9 of spec19 depend on.
  async removeWallpaper(context: common.UIAbilityContext): Promise<void> {
    if (this.busy) {
      return
    }
    this.busy = true
    try {
      // Clear persisted path first so UI observers refresh immediately.
      this.applyPath('')
      // Best-effort sandbox cleanup. Covers current file and any stragglers
      // left behind by earlier crash-mid-copy runs.
      this.deleteAllWallpaperFiles(context)
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'removeWallpaper failed: %{public}s', JSON.stringify(err))
    } finally {
      this.busy = false
    }
  }

  private applyPath(path: string): void {
    SettingsStore.getInstance().save(KEY, path)
  }

  private deleteAllWallpaperFiles(context: common.UIAbilityContext): void {
    try {
      const dir = `${context.filesDir}/${COVERS_DIR}`
      const entries = fileIo.listFileSync(dir)
      for (const name of entries) {
        if (!name.startsWith(FILE_BASENAME + '_')) {
          continue
        }
        try {
          fileIo.unlinkSync(`${dir}/${name}`)
        } catch (_e) {
          // non-fatal
        }
      }
    } catch (_e) {
      // non-fatal (directory may not exist yet)
    }
  }

  private async copyToSandbox(context: common.UIAbilityContext, srcUri: string): Promise<string> {
    const ext = this.deriveExtension(srcUri)
    const dir = `${context.filesDir}/${COVERS_DIR}`
    try {
      fileIo.mkdirSync(dir)
    } catch (_e) {
      // directory already exists — non-fatal
    }
    const destPath = `${dir}/${FILE_BASENAME}_${Date.now()}${ext}`
    const src = await fileIo.open(srcUri, fileIo.OpenMode.READ_ONLY)
    try {
      const dest = await fileIo.open(destPath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC)
      try {
        await fileIo.copyFile(src.fd, dest.fd)
      } finally {
        await fileIo.close(dest.fd)
      }
    } finally {
      await fileIo.close(src.fd)
    }
    this.cleanupOldFiles(context, destPath)
    return 'file://' + destPath
  }

  private deriveExtension(uri: string): string {
    const dot = uri.lastIndexOf('.')
    if (dot < 0) {
      return '.jpg'
    }
    const tail = uri.substring(dot).toLowerCase()
    if (tail.length > 5 || tail.length < 2) {
      return '.jpg'
    }
    return tail
  }

  private cleanupOldFiles(context: common.UIAbilityContext, keepPath: string): void {
    try {
      const dir = `${context.filesDir}/${COVERS_DIR}`
      const entries = fileIo.listFileSync(dir)
      for (const name of entries) {
        if (!name.startsWith(FILE_BASENAME + '_')) {
          continue
        }
        const full = `${dir}/${name}`
        if (full === keepPath) {
          continue
        }
        try {
          fileIo.unlinkSync(full)
        } catch (_e) {
          // non-fatal
        }
      }
    } catch (_e) {
      // non-fatal
    }
  }
}
