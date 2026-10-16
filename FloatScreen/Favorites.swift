import Foundation

struct Favorite: Codable, Identifiable {
    var id: UUID
    var name: String
    var urlString: String
    var hideFromScreenSharing: Bool?
}

final class FavoritesManager {
    private static let key = "favorites"

    static let presets: [Favorite] = [
        Favorite(id: UUID(), name: "YouTube", urlString: "https://youtube.com"),
        Favorite(id: UUID(), name: "Claude", urlString: "https://claude.ai"),
        Favorite(id: UUID(), name: "GitHub", urlString: "https://github.com"),
        Favorite(id: UUID(), name: "Notion", urlString: "https://notion.so"),
        Favorite(id: UUID(), name: "Slack", urlString: "https://app.slack.com"),
    ]

    var items: [Favorite] {
        get {
            guard let data = UserDefaults.standard.data(forKey: Self.key),
                  let decoded = try? JSONDecoder().decode([Favorite].self, from: data)
            else { return Self.presets }
            return decoded
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    func add(name: String, urlString: String) {
        var list = items
        list.append(Favorite(id: UUID(), name: name, urlString: urlString))
        items = list
    }

    func remove(id: UUID) {
        var list = items
        list.removeAll { $0.id == id }
        items = list
    }
}
