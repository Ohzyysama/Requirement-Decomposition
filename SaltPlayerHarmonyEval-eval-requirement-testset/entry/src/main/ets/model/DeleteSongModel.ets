// DeleteSongModel.ets
// Model layer: data structure and business logic for removing a song from the music library
// This layer is responsible for data definitions and interacting with data sources
// Note: This only removes the song from the app's library (database), it does NOT delete the original file

// Data structure representing the information needed for a song removal operation
export class DeleteSongInfo {
  public songTitle: string = ''

  constructor(songTitle: string) {
    this.songTitle = songTitle
  }
}

// Enum representing the possible actions in the remove song dialog
export enum DeleteSongAction {
  NONE,
  CANCEL,
  CONFIRM
}

// Data source class that encapsulates the removal business logic
// Only removes the song record from the app's music library, does NOT delete the original file
export class DeleteSongDataSource {
  // Remove a song from the music library by delegating to the provided action
  static removeFromLibrary(songTitle: string, removeAction: () => void): void {
    removeAction()
  }
}
