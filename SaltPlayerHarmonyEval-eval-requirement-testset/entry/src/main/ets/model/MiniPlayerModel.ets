// MiniPlayerModel.ets
// Model layer: data structure for mini player state

export default class MiniPlayerModel {
  public songTitle: string = ''
  public songArtist: string = ''
  public isPlaying: boolean = false

  constructor(songTitle: string = '', songArtist: string = '', isPlaying: boolean = false) {
    this.songTitle = songTitle
    this.songArtist = songArtist
    this.isPlaying = isPlaying
  }
}
