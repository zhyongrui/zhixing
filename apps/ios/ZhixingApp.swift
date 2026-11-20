import SwiftUI
import UIKit

@main
struct ZhixingApp: App {
    @State private var session = AccountSession()

    init() {
        // 及早发现字体资源漏打包，避免静默回退成系统黑体。
        assert(UIFont(name: "NotoSerifSC-Medium", size: 43) != nil, "品牌宋体未加载")
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .preferredColorScheme(.light)
        }
    }
}
