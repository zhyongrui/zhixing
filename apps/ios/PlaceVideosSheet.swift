import SwiftUI

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
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("地点视频")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(BrandTheme.cinnabar)
                        Text(place.name)
                            .font(.headline)
                            .foregroundStyle(BrandTheme.ink)
                    }
                }
            }
            .task(id: place.id) { await loadDetail() }
        }
    }

    private func linkList(_ detail: PlaceDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("从这里出发")
                        .font(.system(size: 27, weight: .bold, design: .serif))
                        .foregroundStyle(BrandTheme.ink)
                    Text(detail.path)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let intro = detail.intro, !intro.isEmpty {
                        Text(intro)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 14)

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
                                Link(destination: destination) {
                                    linkRow(link)
                                }
                                .buttonStyle(.plain)
                            } else {
                                linkRow(link)
                                    .opacity(0.55)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 22)
                }
            }
        }
    }

    private func linkRow(_ link: PlaceVideoLink) -> some View {
        HStack(spacing: 13) {
            Image(systemName: "play.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(BrandTheme.cinnabar,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                Text(link.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BrandTheme.ink)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                HStack(spacing: 7) {
                    Text(link.platformName)
                        .foregroundStyle(BrandTheme.cinnabar)
                    if let tag = link.tag {
                        Text("·")
                        Text(tag).lineLimit(1)
                    }
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Image(systemName: "arrow.up.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(BrandTheme.ink.opacity(0.06), lineWidth: 1)
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
}
