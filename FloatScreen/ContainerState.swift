import Foundation

struct ContainerState: Codable {
    var id: UUID
    var urlString: String
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var opacity: Double
    var isAlwaysOnTop: Bool
    var isToolbarAutoHidden: Bool
    var fullscreenFillsContainer: Bool?
    var profileId: String?
    var isMobileMode: Bool?
    var isAutoMobile: Bool?
    var isMinimized: Bool?
    var bubbleX: Double?
    var bubbleY: Double?
    var bubbleEdge: String?
    var soundMode: String?
    var hiddenFromScreenSharing: Bool?
}

final class StatePersistence {
    private static let key = "openContainers"
    private static let recentlyClosedKey = "recentlyClosed"

    static func save(_ states: [ContainerState]) {
        guard let data = try? JSONEncoder().encode(states) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func load() -> [ContainerState] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let states = try? JSONDecoder().decode([ContainerState].self, from: data)
        else { return [] }
        return states
    }

    static func saveRecentlyClosed(_ states: [ContainerState]) {
        guard let data = try? JSONEncoder().encode(states) else { return }
        UserDefaults.standard.set(data, forKey: recentlyClosedKey)
    }

    static func loadRecentlyClosed() -> [ContainerState] {
        guard let data = UserDefaults.standard.data(forKey: recentlyClosedKey),
              let states = try? JSONDecoder().decode([ContainerState].self, from: data)
        else { return [] }
        return states
    }
}
