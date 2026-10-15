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
}

final class StatePersistence {
    private static let key = "openContainers"

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
}
