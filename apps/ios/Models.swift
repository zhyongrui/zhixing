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

    var platformName: String {
        switch platform {
        case "XIAOHONGSHU": "小红书"
        case "BILIBILI": "B 站"
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
}
