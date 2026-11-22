import SwiftUI

struct RootView: View {
    @Environment(AccountSession.self) private var session
    @AppStorage(WelcomeFlowPersistence.completedKey) private var hasCompletedWelcome = false

    var body: some View {
        Group {
            if session.restoring {
                ZStack {
                    BrandTheme.rice.ignoresSafeArea()
                    VStack(spacing: 14) {
                        Image("BrandMark")
                            .resizable()
                            .scaledToFit()
                            .padding(9)
                            .frame(width: 64, height: 64)
                            .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 16))
                        ProgressView("正在展开地图…")
                            .tint(BrandTheme.pine)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                ZStack {
                    if session.isSignedIn {
                        MapScreen()
                            .tint(BrandTheme.pine)
                    } else {
                        RegistrationView()
                    }

                    if !hasCompletedWelcome {
                        WelcomeVideoFeed {
                            hasCompletedWelcome = true
                        }
                        .transition(.identity)
                        .zIndex(1)
                    }
                }
            }
        }
        .task { await session.restore() }
    }
}
