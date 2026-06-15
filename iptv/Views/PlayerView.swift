import SwiftUI
import UIKit

/// Hosts the persistent libVLC render surface. Reparenting instead of recreating
/// avoids micro-stutters and lost frames when toggling between layouts.
struct VLCVideoView: UIViewRepresentable {
    let controller: PlaybackController

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .black
        attach(to: container)
        return container
    }

    func updateUIView(_ container: UIView, context: Context) {
        attach(to: container)
    }

    private func attach(to container: UIView) {
        let video = controller.videoView
        guard video.superview !== container else { return }
        video.removeFromSuperview()
        video.frame = container.bounds
        video.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(video)
    }
}

struct PlayerView: View {
    let item: PlayableItem

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var controller: PlaybackController
    @State private var showControls = true
    @State private var isExpanded = false
    @State private var isClosingPlayer = false
    @State private var isDraggingSeek = false
    @State private var seekValue: Double = 0

    private var isLive: Bool { item.isLive }

    init(item: PlayableItem) {
        self.item = item
        _controller = State(initialValue: PlaybackController(url: item.url, isLive: item.isLive))
    }

    var body: some View {
        ZStack {
            DarkBackground()

            if isExpanded {
                expandedLayout
            } else {
                portraitLayout
            }
        }
        .statusBarHidden(isExpanded)
        .navigationBarBackButtonHidden(true)
        .toolbar(isExpanded ? .hidden : .visible, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            if !isExpanded {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        closePlayer()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        toggleExpanded()
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.body.weight(.medium))
                    }
                }
            }
        }
        .background(InteractivePopGestureEnabler())
        .onAppear {
            applyOrientation(.portrait)
            // El reproductor de libVLC se crea aquí (no en `init`) porque esta vista
            // solo aparece cuando el usuario navega de verdad al reproductor.
            controller.prepare()
            controller.play()
        }
        .task {
            await controller.runWatchdog()
        }
        .onChange(of: scenePhase) { phase in
            handleScenePhaseChange(phase)
        }
        .onChange(of: controller.position) { newValue in
            if !isDraggingSeek {
                seekValue = newValue
            }
        }
        .onDisappear {
            if isClosingPlayer || !controller.shouldKeepPlayingWhenViewDisappears {
                controller.stop()
            }
            applyOrientation(.portrait)
        }
    }

    // MARK: - Portrait Layout

    private var portraitLayout: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                VLCVideoView(controller: controller)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .stroke(.white.opacity(0.10), lineWidth: 1)
                    }
                    .padding(.horizontal)

                Text(item.name)
                    .font(.title3.bold())
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding(.top, 8)

            Spacer(minLength: 0)
        }
    }

    // MARK: - Expanded (Fullscreen) Layout

    private var expandedLayout: some View {
        ZStack {
            VLCVideoView(controller: controller)
                .ignoresSafeArea()

            if showControls {
                expandedControls
                    .transition(.opacity)
                    .zIndex(1)
            } else {
                fullscreenTapLayer
                    .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showControls)
    }

    private var fullscreenTapLayer: some View {
        Color.clear
            .contentShape(Rectangle())
            .ignoresSafeArea()
            .onTapGesture { toggleControls() }
    }

    private var expandedControls: some View {
        ZStack {
            fullscreenTapLayer

            // Subtle gradient so controls are readable against bright video
            LinearGradient(
                colors: [.black.opacity(0.55), .clear, .clear, .black.opacity(0.65)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                // Top bar: close · title · collapse
                HStack {
                    GlassCircleButton(systemImage: "xmark", size: 16, diameter: 44) {
                        closePlayer()
                    }
                    .padding(.leading)

                    Spacer()

                    Text(item.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .shadow(radius: 3)

                    Spacer()

                    GlassCircleButton(systemImage: "arrow.down.right.and.arrow.up.left", size: 16, diameter: 44) {
                        toggleExpanded()
                    }
                    .padding(.trailing)
                }
                .padding(.top, 8)

                Spacer()

                // Center: skip-back · play-pause · skip-forward (skip only for VOD)
                HStack(spacing: 36) {
                    if !isLive {
                        GlassCircleButton(systemImage: "gobackward.10", size: 20, diameter: 48) {
                            controller.seekBy(seconds: -10)
                        }
                    }

                    GlassCircleButton(
                        systemImage: controller.isPlaying ? "pause.fill" : "play.fill",
                        size: 26,
                        diameter: 56
                    ) {
                        controller.togglePlayPause()
                    }

                    if !isLive {
                        GlassCircleButton(systemImage: "goforward.10", size: 20, diameter: 48) {
                            controller.seekBy(seconds: 10)
                        }
                    }
                }

                Spacer()

                // Bottom: seek bar + timestamps (VOD only, visible when duration is known)
                if !isLive && controller.duration > 0 {
                    VStack(spacing: 6) {
                        Slider(
                            value: $seekValue,
                            in: 0...1,
                            onEditingChanged: { editing in
                                isDraggingSeek = editing
                                if !editing {
                                    controller.seekTo(position: seekValue)
                                }
                            }
                        )
                        .tint(.white)
                        .padding(.horizontal)

                        HStack {
                            Text(formatTime(controller.duration * seekValue))
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.85))
                                .monospacedDigit()

                            Spacer()

                            Text(formatTime(controller.duration))
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.85))
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.bottom, 20)
                }
            }
        }
    }

    // MARK: - Controls visibility

    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showControls.toggle()
        }
    }

    // MARK: - Player lifecycle

    private func closePlayer() {
        guard !isClosingPlayer else { return }
        isClosingPlayer = true
        applyOrientation(.portrait)
        dismiss()
    }

    // MARK: - Orientation

    private func toggleExpanded() {
        withAnimation(.easeInOut(duration: 0.25)) {
            isExpanded.toggle()
            showControls = true
        }
        applyOrientation(isExpanded ? .landscape : .portrait)
    }

    private func handleScenePhaseChange(_ phase: ScenePhase) {
        guard phase == .inactive || phase == .background else { return }
        guard isExpanded, !isClosingPlayer else { return }
        controller.startPiP()
    }

    private func applyOrientation(_ mask: UIInterfaceOrientationMask) {
        AppDelegate.orientationLock = mask
        let orientation: UIInterfaceOrientationMask = mask == .landscape ? .landscape : .portrait
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientation)) { _ in }
        }
        UIViewController.attemptRotationToDeviceOrientation()
    }

    // MARK: - Helpers

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Liquid Glass circle button

/// Circular Liquid Glass button for fullscreen overlay controls.
struct GlassCircleButton: View {
    let systemImage: String
    var size: CGFloat = 20
    var diameter: CGFloat = 44
    let action: () -> Void

    @GestureState private var isPressed = false

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: diameter, height: diameter)
            .glassEffect(.regular.interactive(), in: .circle)
            .contentShape(Circle())
            .scaleEffect(isPressed ? 1.08 : 1)
            .animation(.easeOut(duration: 0.12), value: isPressed)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isPressed) { _, state, _ in
                        state = true
                    }
                    .onEnded { value in
                        guard hitArea.contains(value.location) else { return }
                        action()
                    }
            )
            .accessibilityAddTraits(.isButton)
    }

    private var hitArea: CGRect {
        CGRect(x: -12, y: -12, width: diameter + 24, height: diameter + 24)
    }
}

private struct InteractivePopGestureEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ viewController: UIViewController, context: Context) {
        DispatchQueue.main.async {
            guard let navigationController = viewController.navigationController else { return }
            navigationController.interactivePopGestureRecognizer?.isEnabled = true
            navigationController.interactivePopGestureRecognizer?.delegate = nil
        }
    }
}
