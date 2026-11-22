import Foundation

struct PlacePin: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let level: String
    let parentId: String?
    let lat: Double
    let lng: Double
    let cardCount: Int
    let linkCount: Int
}

struct Footprint: Decodable, Identifiable {
    let id: String
    let placeId: String
    let text: String?
    let date: String
}

struct PlaceDetail: Decodable {
    let id: String
    let name: String
    let level: String
    let intro: String?
    let ancestors: [PlaceAncestor]
    let links: [PlaceVideoLink]

    var path: String {
        (ancestors.map(\.name) + [name]).joined(separator: " · ")
    }
}

struct PlaceAncestor: Decodable {
    let id: String
    let name: String
    let level: String
}

struct PlaceVideoLink: Decodable, Identifiable {
    let id: String
    let platform: String
    let title: String
    let url: String
    let sortOrder: Int
    let tag: String?
    let creatorName: String?
    let thumbnailUrl: String?

    var platformName: String {
        switch platform {
        case "XIAOHONGSHU": "小红书"
        case "BILIBILI": "哔哩哔哩"
        case "DOUYIN": "抖音"
        case "WEIBO": "微博"
        default: "网页"
        }
    }

    var destination: URL? {
        let value = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let destination = URL(string: value), destination.scheme?.lowercased() == "https" else {
            return nil
        }
        return destination
    }

    var douyinAppDestination: URL? {
        guard platform == "DOUYIN",
              let destination,
              let host = destination.host?.lowercased(),
              host == "douyin.com" || host.hasSuffix(".douyin.com"),
              let videoIndex = destination.pathComponents.firstIndex(of: "video"),
              destination.pathComponents.indices.contains(videoIndex + 1) else {
            return nil
        }

        let videoID = destination.pathComponents[videoIndex + 1]
        guard videoID.range(of: #"^\d+$"#, options: .regularExpression) != nil else { return nil }
        return URL(string: "snssdk1128://aweme/detail/\(videoID)")
    }
}
