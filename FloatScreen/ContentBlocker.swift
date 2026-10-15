import Foundation
import WebKit

final class ContentBlocker {
    static let shared = ContentBlocker()

    private static let enabledKey = "adblock.enabled"
    private static let disabledDomainsKey = "adblock.disabledDomains"
    private static let lastDownloadKey = "adblock.lastDownload"
    private static let refreshInterval: TimeInterval = 86400 // 24 hours
    private static let maxRulesPerList = 50_000

    private static let easyListURL = URL(string: "https://easylist.to/easylist/easylist.txt")!
    private static let easyPrivacyURL = URL(string: "https://easylist.to/easylist/easyprivacy.txt")!

    private var compiledLists: [WKContentRuleList] = []
    private var whitelistRuleList: WKContentRuleList?
    private var isLoading = false

    var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.enabledKey) }
    }

    var disabledDomains: Set<String> {
        get {
            let arr = UserDefaults.standard.stringArray(forKey: Self.disabledDomainsKey) ?? []
            return Set(arr)
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: Self.disabledDomainsKey)
            Task { await recompileWhitelist() }
        }
    }

    private init() {}

    // MARK: - Public

    func loadRulesIfNeeded() {
        guard !isLoading else { return }
        isLoading = true

        Task {
            // Try cached lists first
            let cached = await lookupCached()
            if !cached.isEmpty {
                await MainActor.run { self.compiledLists = cached }
                print("[ContentBlocker] Loaded \(cached.count) cached rule lists")
            }

            // Download if needed
            let lastDownload = UserDefaults.standard.double(forKey: Self.lastDownloadKey)
            let elapsed = Date().timeIntervalSince1970 - lastDownload
            if cached.isEmpty || elapsed > Self.refreshInterval {
                await downloadAndCompile()
            }

            await recompileWhitelist()
            self.isLoading = false
        }
    }

    func apply(to controller: WKUserContentController) {
        guard isEnabled else { return }
        for list in compiledLists {
            controller.add(list)
        }
        if let wl = whitelistRuleList {
            controller.add(wl)
        }
    }

    func remove(from controller: WKUserContentController) {
        controller.removeAllContentRuleLists()
    }

    // MARK: - Download & Compile

    private func downloadAndCompile() async {
        print("[ContentBlocker] Downloading filter lists...")
        var allRules: [[String: Any]] = []

        for url in [Self.easyListURL, Self.easyPrivacyURL] {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let text = String(data: data, encoding: .utf8) else { continue }
                let parsed = parseAdblockRules(text)
                allRules.append(contentsOf: parsed)
                print("[ContentBlocker] Parsed \(parsed.count) rules from \(url.lastPathComponent)")
            } catch {
                print("[ContentBlocker] Download failed for \(url): \(error)")
            }
        }

        guard !allRules.isEmpty else { return }

        // Split into chunks
        let chunks = stride(from: 0, to: allRules.count, by: Self.maxRulesPerList).map {
            Array(allRules[$0..<min($0 + Self.maxRulesPerList, allRules.count)])
        }

        var newLists: [WKContentRuleList] = []
        for (index, chunk) in chunks.enumerated() {
            let id = "floatscreen_adblock_\(index)"
            if let list = await compileRuleList(identifier: id, rules: chunk) {
                newLists.append(list)
            }
        }

        let finalLists = newLists
        if !finalLists.isEmpty {
            await MainActor.run { self.compiledLists = finalLists }
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastDownloadKey)
            print("[ContentBlocker] Compiled \(finalLists.count) rule lists (\(allRules.count) rules total)")
        }
    }

    private func lookupCached() async -> [WKContentRuleList] {
        let store = await MainActor.run { WKContentRuleListStore.default() }
        guard let store else { return [] }
        var results: [WKContentRuleList] = []

        for index in 0..<10 {
            let id = "floatscreen_adblock_\(index)"
            if let list = await lookupRuleList(store: store, identifier: id) {
                results.append(list)
            } else {
                break
            }
        }
        return results
    }

    private func lookupRuleList(store: WKContentRuleListStore,
                                 identifier: String) async -> WKContentRuleList? {
        await withCheckedContinuation { cont in
            DispatchQueue.main.async {
                store.lookUpContentRuleList(forIdentifier: identifier) { list, _ in
                    cont.resume(returning: list)
                }
            }
        }
    }

    private func compileRuleList(identifier: String,
                                  rules: [[String: Any]]) async -> WKContentRuleList? {
        let store = await MainActor.run { WKContentRuleListStore.default() }
        guard let store,
              let jsonData = try? JSONSerialization.data(withJSONObject: rules),
              let jsonString = String(data: jsonData, encoding: .utf8)
        else { return nil }

        return await withCheckedContinuation { cont in
            DispatchQueue.main.async {
                store.compileContentRuleList(forIdentifier: identifier,
                                              encodedContentRuleList: jsonString) { list, error in
                    if let error {
                        print("[ContentBlocker] Compile error for \(identifier): \(error.localizedDescription)")
                    }
                    cont.resume(returning: list)
                }
            }
        }
    }

    // MARK: - Per-site Whitelist

    private func recompileWhitelist() async {
        let domains = disabledDomains
        guard !domains.isEmpty else {
            await MainActor.run { self.whitelistRuleList = nil }
            return
        }

        let rules: [[String: Any]] = domains.map { domain in
            [
                "trigger": [
                    "url-filter": ".*",
                    "if-domain": ["*\(domain)"]
                ] as [String: Any],
                "action": ["type": "ignore-previous-rules"]
            ]
        }

        let list = await compileRuleList(identifier: "floatscreen_whitelist", rules: rules)
        await MainActor.run { self.whitelistRuleList = list }
    }

    // MARK: - Adblock Plus Parser

    private func parseAdblockRules(_ text: String) -> [[String: Any]] {
        var results: [[String: Any]] = []

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty,
                  !trimmed.hasPrefix("!"),
                  !trimmed.hasPrefix("[")
            else { continue }

            if let rule = convertRule(trimmed) {
                results.append(rule)
            }
        }

        return results
    }

    private func convertRule(_ line: String) -> [String: Any]? {
        // Element hiding: domain##selector or ##selector
        if let range = line.range(of: "##") {
            let domainPart = String(line[line.startIndex..<range.lowerBound])
            let selector = String(line[range.upperBound...])
            guard !selector.isEmpty, !selector.hasPrefix("@") else { return nil }

            var trigger: [String: Any] = ["url-filter": ".*"]
            if !domainPart.isEmpty {
                let domains = domainPart.split(separator: ",").compactMap { d -> String? in
                    let s = String(d)
                    if s.hasPrefix("~") { return nil }
                    return "*\(s)"
                }
                guard !domains.isEmpty else { return nil }
                trigger["if-domain"] = domains
            }

            return [
                "trigger": trigger,
                "action": ["type": "css-display-none", "selector": selector]
            ]
        }

        // Exception rules: @@||domain^
        if line.hasPrefix("@@") {
            let inner = String(line.dropFirst(2))
            guard let pattern = convertURLPattern(inner) else { return nil }
            return [
                "trigger": ["url-filter": pattern],
                "action": ["type": "ignore-previous-rules"]
            ]
        }

        // Skip rules with complex unsupported options
        if let dollarIdx = line.firstIndex(of: "$") {
            let options = String(line[line.index(after: dollarIdx)...]).lowercased()
            let supported = Set(["third-party", "script", "image", "stylesheet",
                                  "subdocument", "popup", "media", "font"])
            let parts = options.split(separator: ",").map { String($0) }
            for part in parts {
                let clean = part.hasPrefix("~") ? String(part.dropFirst()) : part
                if clean.contains("=") || !supported.contains(clean) {
                    return nil
                }
            }
        }

        // URL blocking rules
        guard let pattern = convertURLPattern(line) else { return nil }
        var trigger: [String: Any] = ["url-filter": pattern]

        if let dollarIdx = line.firstIndex(of: "$") {
            let options = String(line[line.index(after: dollarIdx)...]).lowercased()
            if options.contains("third-party") {
                trigger["load-type"] = ["third-party"]
            }
        }

        return [
            "trigger": trigger,
            "action": ["type": "block"]
        ]
    }

    private func convertURLPattern(_ rule: String) -> String? {
        var pattern = rule

        // Strip options
        if let dollarIdx = pattern.firstIndex(of: "$") {
            pattern = String(pattern[pattern.startIndex..<dollarIdx])
        }

        guard !pattern.isEmpty else { return nil }

        // ||domain → match domain
        if pattern.hasPrefix("||") {
            pattern = String(pattern.dropFirst(2))
            let escaped = escapeForRegex(pattern)
            return "[a-z-]+://([^/]+\\.)?" + escaped
        }

        // |http → match start of URL
        if pattern.hasPrefix("|") {
            pattern = String(pattern.dropFirst(1))
            return escapeForRegex(pattern)
        }

        // /regex/ → pass through (rare, skip for safety)
        if pattern.hasPrefix("/") && pattern.hasSuffix("/") && pattern.count > 2 {
            return nil
        }

        // Plain pattern → match anywhere in URL
        return escapeForRegex(pattern)
    }

    private func escapeForRegex(_ pattern: String) -> String {
        NSRegularExpression.escapedPattern(for: pattern)
            .replacingOccurrences(of: "\\^", with: "[^a-z0-9._%-]?")
            .replacingOccurrences(of: "\\*", with: ".*")
    }
}
