import AppKit
import WebKit

struct Profile: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var colorHex: String
    var emoji: String
    var defaultHideFromScreenSharing: Bool?

    var color: NSColor {
        NSColor(hex: colorHex) ?? .controlAccentColor
    }

    static let personal = Profile(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "Personal",
        colorHex: "#5E9CFF",
        emoji: "👤"
    )

    static let work = Profile(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        name: "Work",
        colorHex: "#FF6B6B",
        emoji: "💼"
    )
}

final class ProfileManager {
    static let shared = ProfileManager()
    private static let key = "profiles"
    private static let defaultProfileKey = "defaultProfileId"

    private init() {}

    var profiles: [Profile] {
        get {
            guard let data = UserDefaults.standard.data(forKey: Self.key),
                  let decoded = try? JSONDecoder().decode([Profile].self, from: data)
            else { return [.personal, .work] }
            return decoded
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    var defaultProfileId: UUID {
        get {
            if let str = UserDefaults.standard.string(forKey: Self.defaultProfileKey),
               let id = UUID(uuidString: str) {
                return id
            }
            return Profile.personal.id
        }
        set {
            UserDefaults.standard.set(newValue.uuidString, forKey: Self.defaultProfileKey)
        }
    }

    var defaultProfile: Profile {
        profiles.first { $0.id == defaultProfileId } ?? .personal
    }

    func profile(for id: UUID) -> Profile {
        profiles.first { $0.id == id } ?? .personal
    }

    func add(name: String, colorHex: String, emoji: String) -> Profile {
        let p = Profile(id: UUID(), name: name, colorHex: colorHex, emoji: emoji)
        var list = profiles
        list.append(p)
        profiles = list
        return p
    }

    func rename(_ id: UUID, to name: String) {
        var list = profiles
        if let idx = list.firstIndex(where: { $0.id == id }) {
            list[idx].name = name
            profiles = list
        }
    }

    func setColor(_ id: UUID, hex: String) {
        var list = profiles
        if let idx = list.firstIndex(where: { $0.id == id }) {
            list[idx].colorHex = hex
            profiles = list
        }
    }

    func delete(_ id: UUID) async {
        var list = profiles
        list.removeAll { $0.id == id }
        profiles = list

        // Remove the profile's browsing data
        do {
            try await WKWebsiteDataStore.remove(forIdentifier: id)
        } catch {
            print("[ProfileManager] Failed to remove data store for \(id): \(error)")
        }
    }

    static func dataStore(for profile: Profile) -> WKWebsiteDataStore {
        // Personal profile uses the default store to preserve existing logins
        if profile.id == Profile.personal.id {
            return .default()
        }
        return WKWebsiteDataStore(forIdentifier: profile.id)
    }
}

// MARK: - Hex Color Helper

extension NSColor {
    convenience init?(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let val = UInt64(h, radix: 16) else { return nil }
        self.init(
            red: CGFloat((val >> 16) & 0xFF) / 255.0,
            green: CGFloat((val >> 8) & 0xFF) / 255.0,
            blue: CGFloat(val & 0xFF) / 255.0,
            alpha: 1.0
        )
    }
}
