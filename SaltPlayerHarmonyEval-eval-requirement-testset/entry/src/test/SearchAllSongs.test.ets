import { describe, beforeEach, it, expect } from '@ohos/hypium'
import { SearchAllSongsModel } from '../main/ets/model/SearchAllSongsModel'
import { ScanningDataSource, ScannedSongData } from '../main/ets/model/ScanningModel'

// Helper: create a ScannedSongData with specified fields, rest defaults
function makeSong(id: string, title: string, artist: string, album: string, displayName?: string): ScannedSongData {
  const s = new ScannedSongData()
  s.id = id
  s.title = title
  s.artist = artist
  s.album = album
  s.displayName = displayName ?? title
  s.fileUri = `/data/music/${id}.mp3`
  s.duration = 240000
  s.bitrate = 320000
  s.sampleRate = 44100
  s.size = 9600000
  s.year = 2024
  s.dateAdded = 1700000000
  s.dateModified = 1700000000
  s.coverUri = ''
  return s
}

export default function searchAllSongsTest() {
  describe('SearchAllSongsModel_searchSongs', () => {
    // Inject test data via the array reference returned by getScannedSongs()
    let songsRef: ScannedSongData[]

    beforeEach(() => {
      songsRef = ScanningDataSource.getScannedSongs()
      // Clear any existing data
      songsRef.splice(0, songsRef.length)
      // Populate test data
      songsRef.push(makeSong('1', '晴天', '周杰伦', '叶惠美'))
      songsRef.push(makeSong('2', '夜曲', '周杰伦', '十一月的萧邦'))
      songsRef.push(makeSong('3', 'Shape of You', 'Ed Sheeran', 'Divide'))
      songsRef.push(makeSong('4', 'Hello', 'Adele', '25'))
      songsRef.push(makeSong('5', '稻香', '周杰伦', '魔杰座'))
    })

    // ---- Empty / whitespace keyword ----

    it('returns_empty_for_empty_keyword', 0, () => {
      const results = SearchAllSongsModel.searchSongs('')
      expect(results.length).assertEqual(0)
    })

    it('returns_empty_for_whitespace_only_keyword', 0, () => {
      const results = SearchAllSongsModel.searchSongs('   ')
      expect(results.length).assertEqual(0)
    })

    // ---- Title matching ----

    it('matches_exact_title', 0, () => {
      const results = SearchAllSongsModel.searchSongs('晴天')
      expect(results.length).assertEqual(1)
      expect(results[0].title).assertEqual('晴天')
      expect(results[0].id).assertEqual('1')
    })

    it('matches_partial_title', 0, () => {
      const results = SearchAllSongsModel.searchSongs('Shape')
      expect(results.length).assertEqual(1)
      expect(results[0].title).assertEqual('Shape of You')
    })

    // ---- Case insensitivity ----

    it('matches_title_case_insensitive', 0, () => {
      const results = SearchAllSongsModel.searchSongs('hello')
      expect(results.length).assertEqual(1)
      expect(results[0].title).assertEqual('Hello')
    })

    it('matches_title_uppercase_input', 0, () => {
      const results = SearchAllSongsModel.searchSongs('SHAPE')
      expect(results.length).assertEqual(1)
      expect(results[0].title).assertEqual('Shape of You')
    })

    // ---- Artist matching ----

    it('matches_by_artist', 0, () => {
      const results = SearchAllSongsModel.searchSongs('Adele')
      expect(results.length).assertEqual(1)
      expect(results[0].artist).assertEqual('Adele')
    })

    it('matches_multiple_songs_by_same_artist', 0, () => {
      const results = SearchAllSongsModel.searchSongs('周杰伦')
      expect(results.length).assertEqual(3)
    })

    // ---- Album matching ----

    it('matches_by_album', 0, () => {
      const results = SearchAllSongsModel.searchSongs('Divide')
      expect(results.length).assertEqual(1)
      expect(results[0].album).assertEqual('Divide')
    })

    it('matches_by_partial_album', 0, () => {
      const results = SearchAllSongsModel.searchSongs('萧邦')
      expect(results.length).assertEqual(1)
      expect(results[0].album).assertEqual('十一月的萧邦')
    })

    // ---- No match ----

    it('returns_empty_for_no_match', 0, () => {
      const results = SearchAllSongsModel.searchSongs('不存在的歌曲xyz')
      expect(results.length).assertEqual(0)
    })

    // ---- Keyword with leading/trailing spaces ----

    it('trims_keyword_before_search', 0, () => {
      const results = SearchAllSongsModel.searchSongs('  晴天  ')
      expect(results.length).assertEqual(1)
      expect(results[0].title).assertEqual('晴天')
    })

    // ---- Result field mapping ----

    it('result_contains_correct_fields', 0, () => {
      const results = SearchAllSongsModel.searchSongs('晴天')
      expect(results.length).assertEqual(1)
      const song = results[0]
      expect(song.id).assertEqual('1')
      expect(song.title).assertEqual('晴天')
      expect(song.artist).assertEqual('周杰伦')
      expect(song.album).assertEqual('叶惠美')
      expect(song.subTitle).assertEqual('周杰伦')
      expect(song.valid).assertTrue()
      expect(song.fileUri).assertEqual('/data/music/1.mp3')
      expect(song.duration).assertEqual(240000)
      expect(song.bitrate).assertEqual(320000)
      expect(song.sampleRate).assertEqual(44100)
      expect(song.size).assertEqual(9600000)
      expect(song.year).assertEqual(2024)
    })

    it('subTitle_falls_back_to_displayName_when_artist_empty', 0, () => {
      // Add a song with empty artist
      songsRef.push(makeSong('6', '纯音乐', '', '轻音乐集', 'pure_music.mp3'))
      const results = SearchAllSongsModel.searchSongs('纯音乐')
      expect(results.length).assertEqual(1)
      expect(results[0].subTitle).assertEqual('pure_music.mp3')
    })

    // ---- Cross-field matching ----

    it('keyword_matching_both_title_and_artist_returns_all', 0, () => {
      // '周' appears in artist '周杰伦' for songs 1,2,5
      const results = SearchAllSongsModel.searchSongs('周')
      expect(results.length).assertEqual(3)
    })

    // ---- Empty data source ----

    it('returns_empty_when_no_songs_in_source', 0, () => {
      songsRef.splice(0, songsRef.length)
      const results = SearchAllSongsModel.searchSongs('anything')
      expect(results.length).assertEqual(0)
    })

    // ---- Multi-language: Japanese ----

    it('matches_japanese_title', 0, () => {
      songsRef.push(makeSong('10', 'さくら', '宇多田ヒカル', 'First Love'))
      const results = SearchAllSongsModel.searchSongs('さくら')
      expect(results.length).assertEqual(1)
      expect(results[0].title).assertEqual('さくら')
    })

    it('matches_japanese_artist_partial', 0, () => {
      songsRef.push(makeSong('11', 'Automatic', '宇多田ヒカル', 'First Love'))
      const results = SearchAllSongsModel.searchSongs('宇多田')
      expect(results.length).assertEqual(1)
      expect(results[0].artist).assertEqual('宇多田ヒカル')
    })

    // ---- Multi-language: Korean ----

    it('matches_korean_title', 0, () => {
      songsRef.push(makeSong('12', '봄날', '방탄소년단', '화양연화'))
      const results = SearchAllSongsModel.searchSongs('봄날')
      expect(results.length).assertEqual(1)
      expect(results[0].title).assertEqual('봄날')
    })

    it('matches_korean_album', 0, () => {
      songsRef.push(makeSong('13', 'DNA', '방탄소년단', '화양연화'))
      const results = SearchAllSongsModel.searchSongs('화양연화')
      expect(results.length).assertEqual(1)
      expect(results[0].album).assertEqual('화양연화')
    })

    it('matches_korean_artist_partial', 0, () => {
      songsRef.push(makeSong('14', 'Butter', '방탄소년단', 'Butter'))
      const results = SearchAllSongsModel.searchSongs('방탄')
      expect(results.length).assertEqual(1)
      expect(results[0].artist).assertEqual('방탄소년단')
    })

    // ---- Multi-language: French with diacritics ----

    it('matches_french_artist_with_diacritics', 0, () => {
      songsRef.push(makeSong('15', 'La Vie en rose', 'Édith Piaf', 'Chanson'))
      const results = SearchAllSongsModel.searchSongs('Édith')
      expect(results.length).assertEqual(1)
      expect(results[0].artist).assertEqual('Édith Piaf')
    })

    it('matches_french_title_with_accent', 0, () => {
      songsRef.push(makeSong('16', 'Liberté', 'Indochine', 'Alice & June'))
      const results = SearchAllSongsModel.searchSongs('Liberté')
      expect(results.length).assertEqual(1)
      expect(results[0].title).assertEqual('Liberté')
    })

    // ---- Mixed language in same song ----

    it('matches_mixed_cjk_english_title', 0, () => {
      songsRef.push(makeSong('17', 'Love Story 爱情故事', 'Taylor', 'Fearless'))
      const results = SearchAllSongsModel.searchSongs('爱情故事')
      expect(results.length).assertEqual(1)
      expect(results[0].title).assertEqual('Love Story 爱情故事')
    })

    it('matches_mixed_title_english_part', 0, () => {
      songsRef.push(makeSong('18', 'Love Story 爱情故事', 'Taylor', 'Fearless'))
      const results = SearchAllSongsModel.searchSongs('Love Story')
      expect(results.length).assertEqual(1)
      expect(results[0].title).assertEqual('Love Story 爱情故事')
    })

    // ---- Single character search ----

    it('matches_single_chinese_char', 0, () => {
      // '晴' should match '晴天'
      const results = SearchAllSongsModel.searchSongs('晴')
      expect(results.length).assertEqual(1)
      expect(results[0].title).assertEqual('晴天')
    })

    it('matches_single_english_char_case_insensitive', 0, () => {
      // 'h' should match 'Hello' and 'Shape of You' (both contain 'h')
      const results = SearchAllSongsModel.searchSongs('h')
      expect(results.length).assertLarger(0)
    })

    // ---- Special characters / symbols ----

    it('matches_title_with_special_chars', 0, () => {
      songsRef.push(makeSong('19', 'AC/DC - Thunderstruck', 'AC/DC', 'The Razors Edge'))
      const results = SearchAllSongsModel.searchSongs('AC/DC')
      expect(results.length).assertEqual(1)
      expect(results[0].title).assertEqual('AC/DC - Thunderstruck')
    })

    it('matches_title_with_parentheses', 0, () => {
      songsRef.push(makeSong('20', '告白气球 (Live)', '周杰伦', '演唱会'))
      const results = SearchAllSongsModel.searchSongs('告白气球')
      expect(results.length).assertEqual(1)
      expect(results[0].title).assertEqual('告白气球 (Live)')
    })

    // ---- Multiple results across languages ----

    it('returns_multiple_multilang_results_for_shared_album', 0, () => {
      songsRef.push(makeSong('21', 'Track A', 'Artist A', 'Global Hits'))
      songsRef.push(makeSong('22', 'トラックB', 'アーティストB', 'Global Hits'))
      songsRef.push(makeSong('23', '트랙C', '아티스트C', 'Global Hits'))
      const results = SearchAllSongsModel.searchSongs('Global Hits')
      expect(results.length).assertEqual(3)
    })
  })
}

// 全局搜索用例：覆盖标题/艺术家/专辑大小写不敏感匹配。
