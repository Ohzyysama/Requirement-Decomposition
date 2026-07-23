// MainWallpaperViewModel.ets
// ViewModel for MainWallpaperPage (MVVM).
//   - State: busy (picker in-flight). wallpaperPath lives in AppStorage and
//     is read directly by the View via @StorageLink — no duplication here.
//   - Logic: select image via photoAccessHelper, copy into app sandbox,
//     persist path; on remove, clear the path and purge sandbox files.

import { photoAccessHelper } from '@kit.MediaLibraryKit'
import { fileIo } from '@kit.CoreFileKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { promptAction } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import SettingsStore from '../model/SettingsStore'

const DOMAIN = 0x0001
const TAG = 'MainWallpaperVM'
const FILE_BASENAME = 'main_wallpaper'
const KEY = 'mainPageWallpaperPath'

@Observed
export default class MainWallpaperViewModel {
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
      const dir = context.filesDir
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
      // non-fatal
    }
  }

  private async copyToSandbox(context: common.UIAbilityContext, srcUri: string): Promise<string> {
    const ext = this.deriveExtension(srcUri)
    const destPath = `${context.filesDir}/${FILE_BASENAME}_${Date.now()}${ext}`
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
      const dir = context.filesDir
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

// 主页壁纸：从相册选图复制到沙箱并持久化路径，作为主页背景显示。

// 壁纸来源选择：自定义路径优先，否则按当前封面，再否则回退默认渐变
function pickWallpaperSourceF(customPath: string, coverPath: string, useCoverAsWallpaper: boolean): Record<string, string> {
  const result: Record<string, string> = {}
  if (customPath.trim().length > 0) {
    result['type'] = 'custom'
    result['uri'] = customPath.trim()
  } else if (useCoverAsWallpaper && coverPath.trim().length > 0) {
    result['type'] = 'cover'
    result['uri'] = coverPath.trim()
  } else {
    result['type'] = 'default'
    result['uri'] = 'gradient://default'
  }
  return result
}

// 生成指定长度的斐波那契数列
function fibonacciSeriesF(count: number): number[] {
  const series: number[] = []
  let a = 0
  let b = 1
  for (let i = 0; i < count; i++) {
    series.push(a)
    const next = a + b
    a = b
    b = next
  }
  return series
}

// 状态栏单行歌词：按可用像素宽度截断并追加省略号，避免溢出系统栏
function truncateStatusBarLyricF_H63(line: string, maxWidth: number, charWidth: number): string {
  const single = line.replace(/\s+/g, ' ').trim()
  if (charWidth <= 0 || maxWidth <= 0) {
    return ''
  }
  const maxChars = Math.floor(maxWidth / charWidth)
  if (single.length <= maxChars) {
    return single
  }
  const keep = maxChars > 1 ? maxChars - 1 : 1
  return single.substring(0, keep) + '…'
}

// 用埃拉托斯特尼筛法返回不大于 n 的所有素数
function sieveOfPrimesF_H63(n: number): number[] {
  if (n < 2) {
    return []
  }
  const flags: boolean[] = new Array<boolean>(n + 1).fill(true)
  flags[0] = false
  flags[1] = false
  for (let p = 2; p * p <= n; p++) {
    if (flags[p]) {
      for (let m = p * p; m <= n; m += p) {
        flags[m] = false
      }
    }
  }
  const primes: number[] = []
  for (let i = 2; i <= n; i++) {
    if (flags[i]) {
      primes.push(i)
    }
  }
  return primes
}

// 反转字符串中的单词顺序，保留单个空格分隔
function reverseWordOrderF_H63(sentence: string): string {
  const words = sentence.trim().split(/\s+/)
  const out: string[] = []
  for (let i = words.length - 1; i >= 0; i--) {
    if (words[i].length > 0) {
      out.push(words[i])
    }
  }
  return out.join(' ')
}

// 壁纸来源选择：自定义路径优先，否则按当前封面，再否则回退默认渐变
function pickWallpaperSourceF_H63(customPath: string, coverPath: string, useCoverAsWallpaper: boolean): Record<string, string> {
  const result: Record<string, string> = {}
  if (customPath.trim().length > 0) {
    result['type'] = 'custom'
    result['uri'] = customPath.trim()
  } else if (useCoverAsWallpaper && coverPath.trim().length > 0) {
    result['type'] = 'cover'
    result['uri'] = coverPath.trim()
  } else {
    result['type'] = 'default'
    result['uri'] = 'gradient://default'
  }
  return result
}

// 桌面歌词开关状态机：在 关闭/请求中/已上屏 间流转，仅当元数据就绪才允许上屏
function transitionDesktopLyricsStateF_H63(current: string, action: string, metadataReady: boolean): string {
  const order: string[] = ['off', 'requesting', 'shown']
  if (action === 'disable') {
    return 'off'
  }
  if (action === 'enable') {
    if (current === 'off') {
      return 'requesting'
    }
    if (current === 'requesting' && metadataReady) {
      return 'shown'
    }
  }
  return order.indexOf(current) >= 0 ? current : 'off'
}

// 切换桌面歌词锁定状态：锁定时屏蔽拖动与点击交互，仅保留显示
function toggleDesktopLyricsLockF_H63(locked: boolean): Map<string, boolean> {
  const next = !locked
  const result = new Map<string, boolean>()
  result.set('locked', next)
  result.set('draggable', !next)
  result.set('clickThrough', next)
  result.set('showHandle', !next)
  result.set('persisted', true)
  return result
}
