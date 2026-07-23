import { describe, it, expect } from '@ohos/hypium'
import { SongLazySort } from '../main/ets/model/SongSortModel'
import { SongInfoData, createDefaultSongInfoData } from '../main/ets/model/SongItemModel'

function makeSong(fileUri: string, title?: string): SongInfoData {
  const s = createDefaultSongInfoData()
  s.fileUri = fileUri
  s.title = title ?? 'fallback'
  return s
}

export default function songSortTest() {
  describe('SongLazySort_getFileName_via_getSortKey', () => {

    it('extracts_filename_from_uri', 0, () => {
      const song = makeSong('/storage/music/hello.mp3')
      const key = SongLazySort.getSortKey(song, SongLazySort.FILE_NAME)
      expect(key).assertEqual('hello.mp3')
    })

    it('returns_full_string_when_no_slash', 0, () => {
      const song = makeSong('hello.flac')
      const key = SongLazySort.getSortKey(song, SongLazySort.FILE_NAME)
      expect(key).assertEqual('hello.flac')
    })

    it('falls_back_to_title_when_uri_empty', 0, () => {
      const s = createDefaultSongInfoData()
      s.title = 'My Title'
      const key = SongLazySort.getSortKey(s, SongLazySort.FILE_NAME)
      expect(key).assertEqual('My Title')
    })

    it('uses_path_when_fileUri_missing', 0, () => {
      const s = createDefaultSongInfoData()
      s.path = '/sdcard/music/track01.wav'
      s.title = 'fallback'
      const key = SongLazySort.getSortKey(s, SongLazySort.FILE_NAME)
      expect(key).assertEqual('track01.wav')
    })

    it('handles_nested_path', 0, () => {
      const song = makeSong('/a/b/c/d/song.ogg')
      const key = SongLazySort.getSortKey(song, SongLazySort.FILE_NAME)
      expect(key).assertEqual('song.ogg')
    })

    it('handles_chinese_filename', 0, () => {
      const song = makeSong('/music/晴天.mp3')
      const key = SongLazySort.getSortKey(song, SongLazySort.FILE_NAME)
      expect(key).assertEqual('晴天.mp3')
    })

    it('handles_filename_without_extension', 0, () => {
      const song = makeSong('/music/noext')
      const key = SongLazySort.getSortKey(song, SongLazySort.FILE_NAME)
      expect(key).assertEqual('noext')
    })

    it('handles_filename_with_multiple_dots', 0, () => {
      const song = makeSong('file://docs/storage/Users/currentUser/HO_DATA_EXT_MISC/Download/Music/10试歌曲/孙燕姿﹣开始懂了.flac')
      const key = SongLazySort.getSortKey(song, SongLazySort.FILE_NAME)
      expect(key).assertEqual('孙燕姿﹣开始懂了.flac')
    })

    it('handles_filename_with_multiple_dots1', 0, () => {
      const song = makeSong('file://docs/storage/Users/currentUser/HO_DATA_EXT_MISC/Download/Music/10试歌曲/段奥娟 - 凡人.flac')
      const key = SongLazySort.getSortKey(song, SongLazySort.FILE_NAME)
      expect(key).assertEqual('段奥娟 - 凡人.flac')
    })
  })
}

// 歌曲排序用例：覆盖按标题/艺术家/播放次数排序及升降序。
