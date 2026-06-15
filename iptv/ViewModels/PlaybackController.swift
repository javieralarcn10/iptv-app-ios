import Foundation
import Observation
import UIKit
import VLCKitSPM

/// Reproductor basado en libVLC (VLCKit 4.0). A diferencia de AVPlayer, libVLC
/// reproduce HLS con tokens rotatorios, MPEG-TS crudo y prácticamente cualquier
/// códec (H.264/H.265/MPEG-2/AV1). VLCKit 4.0 añade además Picture in Picture.
///
/// El propio controlador actúa como `drawable` (conformando `VLCDrawable` y
/// reenviando el render a `videoView`) y como `mediaController` de PiP, igual que
/// el ejemplo oficial de VLCKit. Mantenerlo como un único objeto es necesario:
/// si se separan, los callbacks de PiP (`media_cbs`) no se registran y crashea.
@Observable
final class PlaybackController: NSObject, VLCMediaPlayerDelegate, VLCDrawable, VLCPictureInPictureDrawable, VLCPictureInPictureMediaControlling {
    /// Crear un `VLCMediaPlayer` es **caro**: arranca una instancia de libVLC, una
    /// cola de fondo y registra observers. Por eso NO se crea en `init`, sino de
    /// forma perezosa la primera vez que la vista realmente presentada llama a
    /// `prepare()`/`play()`.
    ///
    /// Motivo: SwiftUI construye el destino de cada `NavigationLink`
    /// (`PlayerView(item:)`) de forma anticipada para todas las filas visibles de
    /// la lista. Si el reproductor se creara en `init`, navegar/scrollear el
    /// catálogo instanciaría y descartaría decenas de `VLCMediaPlayer`, agotando
    /// libVLC hasta que `libvlc_media_player_new` devuelve NULL y se dispara el
    /// crash «player initialization failed».
    @ObservationIgnored private var _mediaPlayer: VLCMediaPlayer?

    /// Acceso al reproductor, creándolo bajo demanda. Solo debe accederse desde la
    /// vista ya presentada (vía `prepare()`/`play()` u otros controles).
    var mediaPlayer: VLCMediaPlayer {
        if let player = _mediaPlayer { return player }
        let player = VLCMediaPlayer()
        player.delegate = self
        player.drawable = self
        _mediaPlayer = player
        return player
    }

    /// Superficie persistente sobre la que libVLC añade su vista de render. Se
    /// mantiene viva toda la sesión y se reparenta entre layouts (normal/pantalla
    /// completa) para no perder el render ni provocar microcortes al recomponer.
    @ObservationIgnored let videoView = UIView()

    var statusText = "Preparando stream..."
    var errorText: String?
    var isPlaying = true
    var isPiPAvailable = false
    var isPiPActive = false

    /// Current playback position (0.0 – 1.0). Updated every watchdog tick.
    var position: Double = 0
    /// Total media duration in seconds. Updated every watchdog tick.
    var duration: TimeInterval = 0

    var shouldKeepPlayingWhenViewDisappears: Bool {
        isPiPActive || isPiPStarting
    }

    /// Tamaño del búfer de red en milisegundos. Más alto = menos microcortes
    /// pero más retraso respecto al directo.
    private static let bufferMilliseconds = 10_000

    private let originalURL: URL
    private var playbackURL: URL
    private let isLive: Bool
    private let userAgent = "AppleCoreMedia/1.0.0.21F90 (iPhone; U; CPU OS 17_5 like Mac OS X; es_es)"

    private var userPaused = false
    private var reloadAttempts = 0
    private let maxReloadAttempts = 5
    private var bufferingSince: Date?
    private var lastState: VLCMediaPlayerState?
    private var isPiPStarting = false
    private var isSeeking = false
    private var isPrepared = false
    private var didTryAlternateLiveFormat = false

    @ObservationIgnored private var pipController: (any VLCPictureInPictureWindowControlling)?

    init(url: URL, isLive: Bool = false) {
        self.originalURL = url
        self.playbackURL = url
        self.isLive = isLive
        super.init()
        videoView.backgroundColor = .black
    }

    /// Crea el reproductor (si aún no existe) y carga el medio. Debe llamarse
    /// cuando la vista aparece de verdad en pantalla, nunca desde `init`.
    func prepare() {
        guard !isPrepared else { return }
        isPrepared = true
        configureMedia()
    }

    // MARK: - VLCDrawable

    func addSubview(_ view: UIView!) {
        guard let view else { return }
        view.frame = videoView.bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        videoView.addSubview(view)
    }

    func bounds() -> CGRect {
        videoView.bounds
    }

    // MARK: - VLCPictureInPictureDrawable

    func mediaController() -> VLCPictureInPictureMediaControlling {
        self
    }

    func pictureInPictureReady() -> ((any VLCPictureInPictureWindowControlling)?) -> Void {
        return { [weak self] windowController in
            guard let windowController else { return }
            self?.attachPiP(windowController)
        }
    }

    // MARK: - Media

    private func configureMedia() {
        guard let media = VLCMedia(url: playbackURL) else {
            errorText = "URL no válida"
            return
        }
        media.addOption(":http-user-agent=\(userAgent)")
        media.addOption(":http-reconnect")

        if isLive {
            // HLS (.m3u8) y MPEG-TS (.ts) no toleran exactamente las mismas
            // opciones. `:http-continuous` ayuda en TS crudo, pero puede impedir
            // que VLC trate un HLS como playlist segmentada.
            media.addOption(":network-caching=\(Self.bufferMilliseconds)")
            if playbackURL.pathExtension.lowercased() != "m3u8" {
                media.addOption(":clock-synchro=0")
                media.addOption(":clock-jitter=\(Self.bufferMilliseconds)")
                media.addOption(":http-continuous")
            }
        } else {
            // VOD (películas/series): NO usar opciones de directo. `:http-continuous`
            // y el control de reloj de directo impiden que VLC haga seek por rangos
            // HTTP. Un búfer moderado basta para archivos servidos por HTTP.
            media.addOption(":network-caching=3000")
        }
        mediaPlayer.media = media
    }

    // MARK: - Controls

    func play() {
        prepare()
        userPaused = false
        mediaPlayer.play()
        isPlaying = true
    }

    func pause() {
        guard _mediaPlayer != nil else { return }
        userPaused = true
        mediaPlayer.pause()
        isPlaying = false
    }

    func togglePlayPause() {
        isPlaying ? pause() : play()
    }

    func stop() {
        userPaused = true
        isPiPStarting = false
        isPiPActive = false
        isPlaying = false
        pipController?.stopPictureInPicture()
        // Si el reproductor nunca llegó a crearse (la vista no se presentó), no hay
        // nada que detener: acceder a `mediaPlayer` lo crearía innecesariamente.
        _mediaPlayer?.stop()
        statusText = "Detenido"
    }

    func manualRetry() {
        reloadAttempts = 0
        errorText = nil
        userPaused = false
        bufferingSince = nil
        didTryAlternateLiveFormat = false
        playbackURL = originalURL
        configureMedia()
        mediaPlayer.play()
        isPlaying = true
    }

    // MARK: - Picture in Picture

    func attachPiP(_ controller: any VLCPictureInPictureWindowControlling) {
        Task { @MainActor in
            controller.stateChangeEventHandler = { [weak self] isStarted in
                Task { @MainActor in
                    self?.isPiPStarting = false
                    self?.isPiPActive = isStarted
                    self?.pipController?.invalidatePlaybackState()
                }
            }
            self.pipController = controller
            self.isPiPAvailable = true
        }
    }

    func startPiP() {
        guard let pipController, !isPiPActive, !isPiPStarting else { return }
        isPiPStarting = true
        pipController.startPictureInPicture()
    }

    // MARK: - Recovery

    private func retry() {
        guard !userPaused else { return }
        guard reloadAttempts < maxReloadAttempts else {
            errorText = "No se pudo reproducir este canal tras \(maxReloadAttempts) intentos. Puede estar caído o usar un formato no soportado."
            return
        }
        reloadAttempts += 1
        if switchToAlternateLiveFormatIfNeeded() {
            statusText = "Probando formato \(playbackURL.pathExtension.uppercased())…"
        } else {
            statusText = "Reconectando… (intento \(reloadAttempts))"
        }
        bufferingSince = nil
        configureMedia()
        mediaPlayer.play()
        isPlaying = true
    }

    private func switchToAlternateLiveFormatIfNeeded() -> Bool {
        guard isLive, !didTryAlternateLiveFormat else { return false }
        let ext = playbackURL.pathExtension.lowercased()
        let alternateExt: String
        switch ext {
        case "m3u8":
            alternateExt = "ts"
        case "ts":
            alternateExt = "m3u8"
        default:
            return false
        }
        didTryAlternateLiveFormat = true
        playbackURL = playbackURL
            .deletingPathExtension()
            .appendingPathExtension(alternateExt)
        return true
    }

    // MARK: - Watchdog

    func runWatchdog() async {
        while !Task.isCancelled {
            await MainActor.run { self.tick() }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    private func tick() {
        // El watchdog no debe crear el reproductor: si aún no se ha preparado
        // (la vista no se ha presentado), no hay nada que vigilar.
        guard let player = _mediaPlayer else { return }

        // Red de seguridad: sincroniza el estado leyéndolo del player aunque el
        // delegate no dispare (la firma del delegate cambió entre versiones).
        handleState(player.state)

        if isLive {
            // Live streams are not seekable VOD. Keep timeline state out of the
            // live playback path so VLC is only used for state/recovery here.
            position = 0
            duration = 0
        } else {
            // Only sync position from VLC when not seeking — otherwise the
            // watchdog would overwrite the slider position the user just dragged to.
            if !isSeeking {
                position = Double(player.position)
            }
            if let ms = player.media?.length.value?.doubleValue, ms > 0 {
                duration = ms / 1000.0
            }
        }

        guard !userPaused, !isSeeking else { return }
        let state = player.state
        let isWaitingForPlayback = !player.isPlaying && (state == .buffering || state == .opening)
        if isWaitingForPlayback {
            if let since = bufferingSince {
                if Date().timeIntervalSince(since) > 20 {
                    retry()
                }
            } else {
                bufferingSince = Date()
            }
        } else {
            bufferingSince = nil
        }
    }

    // MARK: - State handling

    private func handleState(_ state: VLCMediaPlayerState) {
        let isNew = (state != lastState)
        lastState = state
        pipController?.invalidatePlaybackState()

        switch state {
        case .opening:
            statusText = "Preparando stream..."

        case .buffering:
            statusText = "Almacenando en búfer…"

        case .playing:
            statusText = "Reproduciendo"
            if !userPaused {
                isPlaying = true
            }
            if isNew {
                errorText = nil
                reloadAttempts = 0
                bufferingSince = nil
            }

        case .paused:
            statusText = userPaused ? "Pausado" : "Detenido"
            isPlaying = false

        case .stopping:
            statusText = userPaused ? "Pausado" : "Reconectando…"
            if userPaused {
                isPlaying = false
            }

        case .stopped:
            if userPaused {
                isPlaying = false
            }
            if isNew, !userPaused, !isSeeking {
                retry()
            }

        case .error:
            if isNew, !isSeeking {
                retry()
            }

        @unknown default:
            break
        }
    }

    // MARK: - VLCMediaPlayerDelegate

    func mediaPlayerStateChanged(_ newState: VLCMediaPlayerState) {
        DispatchQueue.main.async { [weak self] in
            self?.handleState(newState)
        }
    }

    // MARK: - VLCPictureInPictureMediaControlling

    func mediaTime() -> Int64 {
        guard !isLive else { return 0 }
        return mediaPlayer.time.value?.int64Value ?? 0
    }

    func mediaLength() -> Int64 {
        guard !isLive else { return 0 }
        return mediaPlayer.media?.length.value?.int64Value ?? 0
    }

    func isMediaSeekable() -> Bool {
        !isLive && mediaPlayer.isSeekable
    }

    func isMediaPlaying() -> Bool {
        mediaPlayer.isPlaying
    }

    func seek(by offset: Int64, completion: @escaping () -> Void) {
        guard !isLive else {
            completion()
            return
        }
        let shouldResume = isPlaying || mediaPlayer.isPlaying
        beginSeek(shouldResume: shouldResume)
        let didStart = mediaPlayer.jump(withOffset: Int32(clamping: offset)) { [weak self] in
            self?.finishSeek(shouldResume: shouldResume)
            completion()
        }
        if didStart {
            finishSeekAfterDelay(shouldResume: shouldResume)
        } else {
            finishSeek(shouldResume: shouldResume)
            completion()
        }
    }

    /// Seek to a normalised position (0.0 – 1.0).
    func seekTo(position: Double) {
        guard !isLive else { return }
        let clamped = max(0, min(1, position))
        let shouldResume = isPlaying || mediaPlayer.isPlaying

        beginSeek(shouldResume: shouldResume)
        self.position = clamped
        // Prefer absolute time seeking when the duration is known — more reliable
        // than position for VOD served over HTTP. Fall back to position otherwise.
        if duration > 0 {
            let targetMs = Int32(clamping: Int(duration * clamped * 1000))
            mediaPlayer.time = VLCTime(int: targetMs)
        } else {
            mediaPlayer.position = Double(clamped)
        }
        // Keep isSeeking active long enough for VLC to commit to the new position
        // before the watchdog restarts syncing position from the player.
        finishSeekAfterDelay(shouldResume: shouldResume)
    }

    /// Jump forward or backward by `seconds` (negative = rewind).
    func seekBy(seconds: Double) {
        guard !isLive else { return }
        let shouldResume = isPlaying || mediaPlayer.isPlaying
        let offsetMs = Int32(clamping: Int(seconds * 1000))
        beginSeek(shouldResume: shouldResume)
        let didStart = mediaPlayer.jump(withOffset: offsetMs) { [weak self] in
            self?.finishSeek(shouldResume: shouldResume)
        }
        if didStart {
            finishSeekAfterDelay(shouldResume: shouldResume)
        } else {
            finishSeek(shouldResume: shouldResume)
        }
        if duration > 0 {
            position = max(0, min(1, position + seconds / duration))
        }
    }

    private func beginSeek(shouldResume: Bool) {
        isSeeking = true
        bufferingSince = nil
        errorText = nil
        if shouldResume {
            userPaused = false
            isPlaying = true
        }
    }

    private func finishSeek(shouldResume: Bool) {
        isSeeking = false
        bufferingSince = nil
        if shouldResume {
            userPaused = false
            mediaPlayer.play()
            isPlaying = true
        }
    }

    private func finishSeekAfterDelay(shouldResume: Bool) {
        // 1.5 s gives VLC enough time to buffer and commit the new position
        // before the watchdog re-enables live position syncing from the player.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.finishSeek(shouldResume: shouldResume)
        }
    }
}
