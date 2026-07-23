// ShareUtil.ets
// 歌曲分享工具 - 对应 Android ShareUtil.kt
// 使用 HarmonyOS systemShare API 调起系统分享面板

import { systemShare } from '@kit.ShareKit'
import { uniformTypeDescriptor as utd } from '@kit.ArkData'
import { fileUri } from '@kit.CoreFileKit'
import { common } from '@kit.AbilityKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { promptAction } from '@kit.ArkUI'

function extractExtension(pathOrUri: string): string {
  // Strip query/fragment, then take basename, then take last dot segment.
  let s = pathOrUri
  let q = s.indexOf('?')
  if (q >= 0) s = s.substring(0, q)
  let h = s.indexOf('#')
  if (h >= 0) s = s.substring(0, h)
  let slash = Math.max(s.lastIndexOf('/'), s.lastIndexOf('\\'))
  let base = slash >= 0 ? s.substring(slash + 1) : s
  let dot = base.lastIndexOf('.')
  if (dot <= 0 || dot === base.length - 1) return ''
  return base.substring(dot + 1).toLowerCase()
}

export async function shareSongFile(
  context: common.UIAbilityContext,
  songTitle: string,
  songFileUri?: string
): Promise<void> {
  if (!songFileUri) {
    promptAction.showToast({ message: '无法分享：歌曲文件不可用' })
    return
  }
  try {
    let uri = songFileUri.startsWith('file://') ? songFileUri : fileUri.getUriFromPath(songFileUri)
    // WeChat saves the shared file using the SharedRecord title as the filename.
    // If the title has no extension, the recipient gets a file with no suffix and can't play it.
    // Append the source file extension so apps that name by title (e.g. WeChat) preserve it.
    let ext = extractExtension(songFileUri)
    let titleHasExt = extractExtension(songTitle) === ext && ext.length > 0
    let displayTitle = ext.length > 0 && !titleHasExt ? `${songTitle}.${ext}` : songTitle
    let record: systemShare.SharedRecord = {
      utd: utd.UniformDataType.AUDIO,
      uri: uri,
      title: displayTitle,
    }
    let shareData: systemShare.SharedData = new systemShare.SharedData(record)
    let controller: systemShare.ShareController = new systemShare.ShareController(shareData)
    controller.show(context, {
      selectionMode: systemShare.SelectionMode.SINGLE,
      previewMode: systemShare.SharePreviewMode.DEFAULT
    })
  } catch (err) {
    let e = err as BusinessError
    console.error('shareSongFile failed: ' + e.code + ' ' + e.message)
    promptAction.showToast({ message: '分享失败' })
  }
}
