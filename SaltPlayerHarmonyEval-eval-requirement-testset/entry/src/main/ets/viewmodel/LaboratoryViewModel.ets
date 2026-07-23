// LaboratoryViewModel.ets
// ViewModel layer: provides observable data and business logic for LaboratoryPage (View).
// Bridges the Model layer (LaboratoryModel) with the View layer.
// Manages all toggle states, enforces mutual-exclusion rules (Salt UI Material vs Liquid Glass),
// and exposes child ViewModels for reusable switcher components.

import LaboratoryModel from '../model/LaboratoryModel'
import SwitcherRowModel from '../model/SwitcherRowModel'
import SwitcherRowViewModel from './SwitcherRowViewModel'
import SwitcherWithIconAndSubRowModel from '../model/SwitcherWithIconAndSubRowModel'
import SwitcherWithIconAndSubRowViewModel from './SwitcherWithIconAndSubRowViewModel'
import SettingsStore from '../model/SettingsStore'
import LyricsInterfaceViewModel from './LyricsInterfaceViewModel'

@Observed
export default class LaboratoryViewModel {
  // Underlying Model data
  @Track private model: LaboratoryModel = new LaboratoryModel()

  // Pro subscription state
  @Track public isPro: boolean = false

  // --- Child ViewModels for each toggle row ---

  // Toggle: auto open playback screen on app launch (simple switcher, no icon)
  @Track public autoOpenPlaybackVM: SwitcherRowViewModel = new SwitcherRowViewModel()

  // Toggle: 3D lyrics effect (crown icon, Pro-gated, no subtitle)
  @Track public lyricsEffect3DVM: SwitcherWithIconAndSubRowViewModel = new SwitcherWithIconAndSubRowViewModel()

  // Toggle: get album art when embedded cover is unavailable (no icon, with warning subtitle)
  // Using SwitcherRowViewModel for simplicity since the original had no icon.
  // The warning subtitle will be rendered directly in the View.
  @Track public getAlbumArtIsOn: boolean = false

  // Toggle: Salt UI Material (crown icon, Pro-gated, no subtitle)
  @Track public saltUiMaterialVM: SwitcherWithIconAndSubRowViewModel = new SwitcherWithIconAndSubRowViewModel()

  // Toggle: Liquid Glass (crown icon, Pro-gated, subtitle "Android 13+")
  @Track public liquidGlassVM: SwitcherWithIconAndSubRowViewModel = new SwitcherWithIconAndSubRowViewModel()

  constructor(model?: LaboratoryModel) {
    if (model) {
      this.model = model
    }
    // Seed from AppStorage so the first frame reflects the persisted value on
    // re-entry (EntryAbility restored `autoOpenPlaybackScreen` before any page
    // mounts). Mirrors the MainPageViewModel pattern for `displaySongCoverInList`.
    const persistedAutoOpen = AppStorage.get<boolean>('autoOpenPlaybackScreen')
    if (persistedAutoOpen !== undefined) {
      this.model.autoOpenPlaybackScreen = persistedAutoOpen
    }
    // Spec16: seed lyricsUIEffect3D from AppStorage so the first frame reflects
    // the cold-start value (EntryAbility restored it before any page mounts).
    const persisted3D = AppStorage.get<boolean>('lyricsUIEffect3D')
    if (persisted3D !== undefined) {
      this.model.lyricsUIEffect3D = persisted3D
    }
    // Spec16: read global Pro state from AppStorage so a future Pro activation
    // lights up Pro-gated rows live. Mirrors LyricsInterfaceViewModel.constructor.
    this.isPro = (AppStorage.get<boolean>('isPro') ?? false)
    this.model.isPro = this.isPro
    this.getAlbumArtIsOn = this.model.getAlbumArt
    this.initChildViewModels()
  }

  // Initialize child ViewModels from Model data
  private initChildViewModels(): void {
    // Auto open playback screen
    this.autoOpenPlaybackVM = new SwitcherRowViewModel(
      new SwitcherRowModel(this.model.autoOpenPlaybackScreen, true, $r('app.string.auto_open_playback_label')),
      (isOn: boolean) => {
        this.onAutoOpenPlaybackChanged(isOn)
      }
    )

    // 3D lyrics effect (no longer Pro-gated)
    this.lyricsEffect3DVM = new SwitcherWithIconAndSubRowViewModel(
      new SwitcherWithIconAndSubRowModel(
        this.model.lyricsUIEffect3D,
        true,
        $r('app.media.ic_crown'),
        $r('app.string.lyrics_3d_effect_label'),
        ''
      ),
      (isOn: boolean) => {
        this.onLyricsEffect3DChanged(isOn)
      }
    )

    // Salt UI Material (Pro-gated)
    this.saltUiMaterialVM = new SwitcherWithIconAndSubRowViewModel(
      new SwitcherWithIconAndSubRowModel(
        this.model.saltUiMaterial,
        this.isPro,
        $r('app.media.ic_crown'),
        'Salt UI Material',
        ''
      ),
      (isOn: boolean) => {
        this.onSaltUiMaterialChanged(isOn)
      }
    )

    // Liquid Glass (Pro-gated, with sub text)
    this.liquidGlassVM = new SwitcherWithIconAndSubRowViewModel(
      new SwitcherWithIconAndSubRowModel(
        this.model.liquidGlass,
        this.isPro,
        $r('app.media.ic_crown'),
        'Liquid Glass',
        'Android 13+'
      ),
      (isOn: boolean) => {
        this.onLiquidGlassChanged(isOn)
      }
    )
  }

  // --- Business logic callbacks ---

  private onAutoOpenPlaybackChanged(isOn: boolean): void {
    this.model.autoOpenPlaybackScreen = isOn
    // Spec9: persist immediately so the next launch can decide whether to
    // auto-open the player overlay. AppStorage is updated by SettingsStore.save
    // and the disk flush happens in EntryAbility.onBackground().
    SettingsStore.getInstance().save('autoOpenPlaybackScreen', isOn)
  }

  private onLyricsEffect3DChanged(isOn: boolean): void {
    this.model.lyricsUIEffect3D = isOn
    // Spec16: persist (AppStorage + Preferences flushSync).
    // PlayerPage subscribes via @StorageProp; the write here is the live broadcast.
    SettingsStore.getInstance().save('lyricsUIEffect3D', isOn)
    // Scene 1: mutual exclusion with lyricsTextAlignCenter.
    // When 3D is turned ON, force center alignment OFF. When turned OFF,
    // leave center alignment alone (user's prior choice is preserved).
    if (isOn) {
      SettingsStore.getInstance().save('lyricsTextAlignCenter', false)
      // Keep the LyricsInterfaceViewModel singleton in sync so the next
      // settings-page / dialog entry reflects the flip without staleness.
      // This is a non-binding sync write — the AppStorage key set above is
      // already the authoritative source for PlayerPage's @StorageProp.
      try {
        LyricsInterfaceViewModel.getInstance().refreshTextAlignFromStorage()
      } catch (_e) {
        // VM not constructed yet — no-op; loadSettings() will pick it up
        // on the next entry.
      }
    }
  }

  // Called from View when getAlbumArt toggle changes
  toggleGetAlbumArt(isOn: boolean): void {
    this.getAlbumArtIsOn = isOn
    this.model.getAlbumArt = isOn
    // TODO: Persist with data preferences
    console.info('Get album art toggled: ' + isOn)
  }

  private onSaltUiMaterialChanged(isOn: boolean): void {
    this.model.saltUiMaterial = isOn
    // Mutual exclusion: if Salt UI Material is turned on, turn off Liquid Glass
    if (isOn) {
      this.liquidGlassVM.isOn = false
      this.model.liquidGlass = false
    }
    // TODO: Persist with data preferences
    console.info('Salt UI Material toggled: ' + isOn)
  }

  private onLiquidGlassChanged(isOn: boolean): void {
    this.model.liquidGlass = isOn
    // Mutual exclusion: if Liquid Glass is turned on, turn off Salt UI Material
    if (isOn) {
      this.saltUiMaterialVM.isOn = false
      this.model.saltUiMaterial = false
    }
    // TODO: Persist with data preferences
    console.info('Liquid Glass toggled: ' + isOn)
  }

  // Load settings from persistent storage (to be called from aboutToAppear)
  loadSettings(): void {
    // Spec16: refresh Pro state from AppStorage so Pro-gated rows light up
    // on re-entry after a (future) Pro activation flow.
    this.isPro = (AppStorage.get<boolean>('isPro') ?? false)
    this.model.isPro = this.isPro
    // Spec16: refresh live 3D toggle from AppStorage in case the value was
    // mutated externally while the page was off-screen.
    const persisted3D = AppStorage.get<boolean>('lyricsUIEffect3D')
    if (persisted3D !== undefined) {
      this.model.lyricsUIEffect3D = persisted3D
      this.lyricsEffect3DVM.isOn = persisted3D
    }
    // Pro state may have changed → refresh isEnabled on the child VMs.
    this.lyricsEffect3DVM.isEnabled = true
    this.saltUiMaterialVM.isEnabled = this.isPro
    this.liquidGlassVM.isEnabled = this.isPro
  }

  // Export current state back to Model
  toModel(): LaboratoryModel {
    return new LaboratoryModel(
      this.autoOpenPlaybackVM.isOn,
      this.lyricsEffect3DVM.isOn,
      this.getAlbumArtIsOn,
      this.saltUiMaterialVM.isOn,
      this.liquidGlassVM.isOn,
      this.isPro
    )
  }
}

// 实验室：autoOpenPlaybackScreen 持久化。
