import SwiftUI
import UIKit

struct PlaceVideosSheet: View {
    let place: PlacePin

    @State private var detail: PlaceDetail?
    @State private var errorMessage: String?
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            ZStack {
                BrandTheme.rice.ignoresSafeArea()
                Group {
                    if isLoading {
                        ProgressView("正在找相关视频…")
                            .tint(BrandTheme.pine)
                    } else if let errorMessage {
                        ContentUnavailableView {
                            Label("暂时加载失败", systemImage: "wifi.exclamationmark")
                        } description: {
                            Text(errorMessage)
                        } actions: {
                            Button("重新加载") { Task { await loadDetail() } }
                                .buttonStyle(.borderedProminent)
                                .tint(BrandTheme.pine)
                        }
                    } else if let detail {
                        linkList(detail)
                    }
                }
            }
            .navigationTitle(place.name)
            .navigationBarTitleDisplayMode(.inline)
            .task(id: place.id) { await loadDetail() }
        }
    }

    private func linkList(_ detail: PlaceDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if detail.links.isEmpty {
                    ContentUnavailableView(
                        "这里还没有视频",
                        systemImage: "play.rectangle",
                        description: Text("这个地点的分享链接正在收集。换个地图上的地点看看吧。")
                    )
                    .padding(.top, 22)
                } else {
                    LazyVStack(spacing: 11) {
                        ForEach(detail.links) { link in
                            if let destination = link.destination {
                                Button {
                                    open(link, fallback: destination)
                                } label: {
                                    VideoLinkCard(link: link)
                                }
                                .buttonStyle(.plain)
                            } else {
                                VideoLinkCard(link: link)
                                    .opacity(0.55)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 22)
                }
            }
            .padding(.top, 18)
        }
    }

    @MainActor
    private func loadDetail() async {
        isLoading = true
        errorMessage = nil
        do {
            detail = try await APIClient.get("/places/\(place.id)")
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func open(_ link: PlaceVideoLink, fallback: URL) {
        guard let appURL = link.douyinAppDestination else {
            UIApplication.shared.open(fallback)
            return
        }

        guard UIApplication.shared.canOpenURL(appURL) else {
            UIApplication.shared.open(fallback)
            return
        }

        UIApplication.shared.open(appURL) { opened in
            if !opened {
                UIApplication.shared.open(fallback)
            }
        }
    }
}

private struct VideoLinkCard: View {
    let link: PlaceVideoLink
    @State private var preview: BilibiliPreview?

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
                .frame(width: 108, height: 78)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(link.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BrandTheme.ink)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)

                HStack(spacing: 5) {
                    Text(link.platformName)
                        .foregroundStyle(BrandTheme.cinnabar)
                    if let author = link.creatorName?.trimmingCharacters(in: .whitespacesAndNewlines), !author.isEmpty {
                        Text("·")
                        Text(author).lineLimit(1)
                    } else if let author = preview?.author, !author.isEmpty {
                        Text("·")
                        Text(author).lineLimit(1)
                    } else if let tag = link.tag {
                        Text("·")
                        Text(tag).lineLimit(1)
                    }
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "arrow.up.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(BrandTheme.ink.opacity(0.06), lineWidth: 1)
        }
        .task(id: link.url) {
            preview = await BilibiliPreview.load(for: link)
        }
    }

    private var thumbnail: some View {
        ZStack {
            thumbnailBackground
            if let imageURL = link.thumbnailUrl.flatMap({ URL(string: $0) }) ?? preview?.imageURL {
                AsyncImage(url: imageURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    fallbackSymbol
                }
            } else {
                fallbackSymbol
            }
            Image(systemName: "play.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(.black.opacity(0.58), in: Circle())
        }
        .clipped()
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var thumbnailBackground: some View {
        if link.platform == "DOUYIN" {
            LinearGradient(
                colors: [Color(red: 0.07, green: 0.08, blue: 0.10), Color(red: 0.16, green: 0.17, blue: 0.20)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            BrandTheme.pineDeep
        }
    }

    @ViewBuilder
    private var fallbackSymbol: some View {
        if link.platform == "DOUYIN" {
            ZStack {
                Image(systemName: "music.note")
                    .foregroundStyle(Color(red: 1, green: 0.20, blue: 0.35))
                    .offset(x: 1.5, y: -1)
                Image(systemName: "music.note")
                    .foregroundStyle(Color(red: 0.20, green: 0.91, blue: 0.94))
                    .offset(x: -1.5, y: 1)
                Image(systemName: "music.note")
                    .foregroundStyle(.white.opacity(0.94))
            }
            .font(.system(size: 28, weight: .semibold))
        } else {
            Image(systemName: "play.rectangle")
                .font(.system(size: 25, weight: .light))
                .foregroundStyle(.white.opacity(0.55))
        }
    }
}

private struct BilibiliPreview {
    let imageURL: URL?
    let author: String?

    static func load(for link: PlaceVideoLink) async -> Self? {
        guard link.platform == "BILIBILI", let url = link.destination,
              url.host == "bilibili.com" || url.host?.hasSuffix(".bilibili.com") == true,
              let videoIndex = url.pathComponents.firstIndex(of: "video"),
              url.pathComponents.indices.contains(videoIndex + 1) else { return nil }
        let videoID = url.pathComponents[videoIndex + 1]
        guard videoID.hasPrefix("BV"), videoID.count == 12,
              let endpoint = URL(string: "https://api.bilibili.com/x/web-interface/view?bvid=\(videoID)") else {
            return nil
        }

        do {
            var request = URLRequest(url: endpoint)
            request.timeoutInterval = 8
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(BilibiliResponse.self, from: data)
            guard response.code == 0, let video = response.data else { return nil }
            let image = video.pic.replacingOccurrences(of: "http://", with: "https://")
            return Self(imageURL: URL(string: image), author: video.owner.name)
        } catch {
            return nil
        }
    }

    private struct BilibiliResponse: Decodable {
        let code: Int
        let data: Video?

        struct Video: Decodable {
            let pic: String
            let owner: Owner
        }

        struct Owner: Decodable {
            let name: String
        }
    }
}
