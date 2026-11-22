import AVFoundation
import SwiftUI
import UIKit

enum WelcomeFlowPersistence {
    static let completedKey = "welcome.videoFeed.completed"
    static let orderKey = "welcome.videoFeed.order"
    static let pageKey = "welcome.videoFeed.page"
}

private struct WelcomeClip: Identifiable {
    let id: String
    let fileName: String
    let fileExtension: String

    var url: URL? {
        Bundle.main.url(forResource: fileName, withExtension: fileExtension, subdirectory: "OnboardingVideos")
    }

    static let all: [WelcomeClip] = [
        .init(id: "new-things", fileName: "new_things", fileExtension: "mp4"),
        .init(id: "geography-studies", fileName: "worldview_geography", fileExtension: "mp4"),
        .init(id: "geography-quotes", fileName: "worldview_quotes", fileExtension: "mp4"),
        .init(id: "life-is-short", fileName: "life_is_short", fileExtension: "mp4"),
        .init(id: "leave-home", fileName: "leave_hometown", fileExtension: "mp4"),
        .init(id: "go-outside", fileName: "go_outside", fileExtension: "mov"),
        .init(id: "travel-investment", fileName: "travel_is_an_investment", fileExtension: "mp4"),
        .init(id: "rest", fileName: "rest_somewhere_new", fileExtension: "mp4"),
        .init(id: "travel-memory", fileName: "travel_extends_life", fileExtension: "mp4"),
        .init(id: "life-voice", fileName: "life_voice", fileExtension: "mp4"),
    ]

    static func loadOrCreateOrder() -> [WelcomeClip] {
        let defaults = UserDefaults.standard
        let clipsByID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

        if let savedIDs = defaults.stringArray(forKey: WelcomeFlowPersistence.orderKey),
           savedIDs.count == all.count,
           Set(savedIDs) == Set(clipsByID.keys) {
            let savedOrder = savedIDs.compactMap { clipsByID[$0] }
            if savedOrder.count == all.count { return savedOrder }
        }

        let shuffled = all.shuffled()
        defaults.set(shuffled.map(\.id), forKey: WelcomeFlowPersistence.orderKey)
        return shuffled
    }
}

struct WelcomeVideoFeed: View {
    let onComplete: () -> Void

    private let clips: [WelcomeClip]
    @State private var visiblePage: Int?
    @State private var isMuted = false
    @State private var hasInteractedWithFeed = false
    @State private var swipeTutorialPhase: SwipeTutorialPhase = .resting
    @State private var isVideoNudging = false
    @State private var hasFinishedWelcome = false
    @State private var exitOffset: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0

    init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
        let clips = WelcomeClip.loadOrCreateOrder()
        let savedPage = UserDefaults.standard.integer(forKey: WelcomeFlowPersistence.pageKey)
        self.clips = clips
        _visiblePage = State(initialValue: min(max(savedPage, 0), clips.count - 1))
        _hasInteractedWithFeed = State(initialValue: savedPage > 0)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(clips.indices, id: \.self) { index in
                            WelcomeClipPlayer(
                                clip: clips[index],
                                isActive: visiblePage == index,
                                isMuted: isMuted,
                                onUserInteraction: { hasInteractedWithFeed = true }
                            )
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .background(.black)
                                .offset(y: index == 0 && isVideoNudging ? -64 : 0)
                                .animation(.easeInOut(duration: 0.56), value: isVideoNudging)
                                .id(index)
                        }

                        Color.black
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .id(clips.count)
                    }
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.paging)
                .scrollDisabled(hasFinishedWelcome)
                .scrollPosition(id: $visiblePage, anchor: .top)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .background(.black)
                .onChange(of: visiblePage) { _, page in
                    guard let page else { return }
                    if page >= clips.count {
                        finish()
                        return
                    }

                    UserDefaults.standard.set(page, forKey: WelcomeFlowPersistence.pageKey)
                    if page > 0 {
                        hasInteractedWithFeed = true
                        swipeTutorialPhase = .hidden
                        isVideoNudging = false
                    }
                }

                feedChrome(index: min(visiblePage ?? 0, clips.count - 1), tutorialPhase: swipeTutorialPhase)
                feedControls
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .offset(y: exitOffset)
            .onAppear { viewportHeight = geometry.size.height }
            .onChange(of: geometry.size.height) { _, height in viewportHeight = height }
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
        .onAppear(perform: activateVideoAudio)
        .onDisappear(perform: deactivateVideoAudio)
        .task(id: visiblePage) {
            guard visiblePage == 0 else {
                swipeTutorialPhase = .hidden
                isVideoNudging = false
                return
            }
            await playSwipeTutorial()
        }
    }

    private func feedChrome(index: Int, tutorialPhase: SwipeTutorialPhase) -> some View {
        ZStack {
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [.black.opacity(0.44), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 180)

                Spacer(minLength: 0)

                LinearGradient(
                    colors: [.clear, .black.opacity(0.68)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 250)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image("BrandMark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                    Text("知行")
                        .font(.custom("NotoSerifSC-Medium", size: 19, relativeTo: .headline))
                        .foregroundStyle(.white)
                    Spacer()
                }

                Spacer()

                VStack(alignment: .leading, spacing: 11) {
                    Text("知一方风土，行万里山河")
                        .font(.custom("NotoSerifSC-Medium", size: 24, relativeTo: .title2))
                        .foregroundStyle(.white)
                        .offset(y: 14)

                    HStack(spacing: 4) {
                        ForEach(clips.indices, id: \.self) { page in
                            Capsule()
                                .fill(page <= index ? .white : .white.opacity(0.35))
                                .frame(height: 3)
                        }
                    }
                    .offset(y: 10)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 42)
            }
            .padding(.horizontal, 20)
            .padding(.top, 46)

            if index == clips.count - 1 {
                HStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "chevron.up")
                        .font(.caption.weight(.bold))
                    Text("上滑进入知行")
                        .font(.subheadline.weight(.medium))
                }
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 24)
                .padding(.bottom, 42)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .allowsHitTesting(false)
            }

            if index == 0 && tutorialPhase != .hidden {
                GeometryReader { geometry in
                    SwipeUpHint(phase: tutorialPhase)
                        .position(x: geometry.size.width * 0.5, y: geometry.size.height * 0.62)
                }
                .allowsHitTesting(false)
            }
        }
        .allowsHitTesting(false)
    }

    private var feedControls: some View {
        HStack(spacing: 10) {
            Spacer()
            Button { isMuted.toggle() } label: {
                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 34)
                    .background(.black.opacity(0.28), in: Capsule())
            }
            .accessibilityLabel(isMuted ? "打开声音" : "关闭声音")
            Button("跳过") { finish() }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.black.opacity(0.28), in: Capsule())
        }
        .padding(.horizontal, 20)
        .padding(.top, 46)
    }

    private func finish() {
        guard !hasFinishedWelcome else { return }
        hasFinishedWelcome = true
        // Remove the feed only after its full-screen bounds have cleared the top edge.
        withAnimation(.easeOut(duration: 0.32), completionCriteria: .removed) {
            exitOffset = -viewportHeight
        } completion: {
            UserDefaults.standard.removeObject(forKey: WelcomeFlowPersistence.orderKey)
            UserDefaults.standard.removeObject(forKey: WelcomeFlowPersistence.pageKey)
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { onComplete() }
        }
    }

    private func playSwipeTutorial() async {
        for cycle in 0..<3 {
            guard !Task.isCancelled && !hasInteractedWithFeed else { break }
            swipeTutorialPhase = .pressing
            try? await Task.sleep(nanoseconds: 340_000_000)
            guard !Task.isCancelled && !hasInteractedWithFeed else { break }

            withAnimation(.easeOut(duration: 0.56)) {
                swipeTutorialPhase = .swiping
                isVideoNudging = true
            }
            try? await Task.sleep(nanoseconds: 560_000_000)
            guard !Task.isCancelled && !hasInteractedWithFeed else { break }

            withAnimation(.easeIn(duration: 0.24)) {
                swipeTutorialPhase = .resting
                isVideoNudging = false
            }
            if cycle < 2 && !Task.isCancelled && !hasInteractedWithFeed {
                try? await Task.sleep(nanoseconds: 760_000_000)
            }
        }

        swipeTutorialPhase = .hidden
        isVideoNudging = false
    }

    private func activateVideoAudio() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("Unable to activate welcome video audio: \(error)")
        }
    }

    private func deactivateVideoAudio() {
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: [.notifyOthersOnDeactivation])
        try? session.setCategory(.soloAmbient)
    }
}

private enum SwipeTutorialPhase {
    case hidden
    case resting
    case pressing
    case swiping
}

private struct SwipeUpHint: View {
    let phase: SwipeTutorialPhase

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(white: 0.84).opacity(phase == .pressing ? 0.62 : 0))
                .frame(width: 44, height: 44)
                .scaleEffect(phase == .pressing ? 0.8 : 1.35)

            Image(systemName: "hand.point.up.left.fill")
                .font(.system(size: 42, weight: .regular))
                .rotationEffect(.degrees(45))
                .foregroundStyle(Color(white: 0.82).opacity(0.82))
                .shadow(color: .black.opacity(0.35), radius: 5, y: 2)
                .scaleEffect(phase == .pressing ? 0.9 : 1)
                .offset(y: phase == .swiping ? -82 : 0)
        }
        .frame(width: 90, height: 100)
        .animation(.easeInOut(duration: 0.34), value: phase)
        .accessibilityLabel("向上滑动浏览视频")
    }
}

private struct WelcomeClipPlayer: View {
    let clip: WelcomeClip
    let isActive: Bool
    let isMuted: Bool
    let onUserInteraction: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @State private var player: AVQueuePlayer?
    @State private var playerLooper: AVPlayerLooper?
    @State private var isPaused = false

    var body: some View {
        Group {
            if let player {
                PlayerLayerView(player: player)
            } else {
                Color.black
            }
        }
        .overlay {
            if isPaused {
                Image(systemName: "play.fill")
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 70, height: 70)
                    .background(.black.opacity(0.38), in: Circle())
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: togglePlayback)
        .onAppear(perform: preparePlayer)
        .onDisappear { player?.pause() }
        .onChange(of: isActive) { _, active in
            if active {
                isPaused = false
                preparePlayer()
                player?.play()
            } else {
                player?.pause()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && isActive && !isPaused {
                player?.play()
            } else {
                player?.pause()
            }
        }
        .onChange(of: isMuted) { _, muted in
            player?.isMuted = muted
        }
    }

    private func preparePlayer() {
        guard player == nil else { return }
        guard let url = clip.url else { return }
        let newPlayer = AVQueuePlayer()
        let item = AVPlayerItem(url: url)
        let looper = AVPlayerLooper(player: newPlayer, templateItem: item)
        newPlayer.isMuted = isMuted
        newPlayer.volume = 1
        playerLooper = looper
        player = newPlayer
        if isActive && scenePhase == .active && !isPaused {
            newPlayer.play()
        }
    }

    private func togglePlayback() {
        guard isActive, scenePhase == .active else { return }
        onUserInteraction()
        if isPaused {
            isPaused = false
            player?.play()
        } else {
            player?.pause()
            isPaused = true
        }
    }
}

private struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerLayerHostView {
        let view = PlayerLayerHostView()
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ view: PlayerLayerHostView, context: Context) {
        if view.playerLayer.player !== player {
            view.playerLayer.player = player
        }
    }
}

private final class PlayerLayerHostView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        playerLayer.videoGravity = .resizeAspect
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
