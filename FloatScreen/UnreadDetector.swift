import Foundation

enum UnreadDetector {
    static func parseCountFromTitle(_ title: String) -> Int? {
        let pattern = #"\((\d+)\+?\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                  in: title, range: NSRange(title.startIndex..., in: title)
              ),
              let range = Range(match.range(at: 1), in: title)
        else { return nil }
        return Int(title[range])
    }

    static func hasUnreadIndicator(_ title: String) -> Bool {
        title.hasPrefix("* ") || title.hasPrefix("! ") || title.hasPrefix("\u{25CF} ")
    }

    static let whatsappScript: String = """
    (function() {
        'use strict';
        if (location.hostname !== 'web.whatsapp.com') return;
        if (window.__waBadgeInit) return;
        window.__waBadgeInit = true;

        var _timer = null;
        var _lastCount = -1;

        function countUnread() {
            // Prefer title count — WhatsApp updates it reliably
            var titleMatch = document.title.match(/\\((\\d+)\\)/);
            if (titleMatch) {
                var count = parseInt(titleMatch[1]) || 0;
                post(count, 'title');
                return;
            }

            // Fallback: count unread badges in the main chat list only
            // Exclude muted chats (has muted icon), archived, Status, Communities
            var total = 0;
            var chatList = document.querySelector('[aria-label="Chat list"], #pane-side');
            if (chatList) {
                chatList.querySelectorAll('[data-testid="icon-unread-count"]').forEach(function(badge) {
                    // Skip if parent chat row has a muted indicator
                    var row = badge.closest('[data-testid="cell-frame-container"], [role="listitem"]');
                    if (row && row.querySelector('[data-testid="icon-muted"]')) return;
                    var n = parseInt(badge.textContent);
                    if (!isNaN(n) && n > 0) total += n;
                });
            }
            post(total, 'chatlist');
        }

        function post(count, source) {
            if (count === _lastCount) return;
            _lastCount = count;
            try {
                window.webkit.messageHandlers.unread.postMessage({count: count, source: 'wa-' + source});
            } catch(e) {}
        }

        function debounced() {
            clearTimeout(_timer);
            _timer = setTimeout(countUnread, 500);
        }

        var observer = new MutationObserver(debounced);
        function start() {
            var target = document.body || document.documentElement;
            if (target) {
                observer.observe(target, { childList: true, subtree: true, characterData: true });
                // Slow fallback only — main detection is via MutationObserver
                setInterval(countUnread, 30000);
                countUnread();
            }
        }
        if (document.body) start();
        else document.addEventListener('DOMContentLoaded', start);
    })();
    """

    static let slackScript: String = """
    (function() {
        'use strict';
        if (location.hostname !== 'app.slack.com') return;
        if (window.__slackBadgeInit) return;
        window.__slackBadgeInit = true;

        var _timer = null;
        var _lastCount = -1;

        function countBadges() {
            // Prefer title count
            var titleMatch = document.title.match(/\\((\\d+)\\)/);
            if (titleMatch) {
                var count = parseInt(titleMatch[1]) || 0;
                post(count);
                return;
            }

            // Fallback: sidebar mention badges (exclude muted channels)
            var total = 0;
            document.querySelectorAll(
                '.p-channel_sidebar__badge, ' +
                '[data-qa="channel_sidebar_name_badge"]'
            ).forEach(function(b) {
                // Skip muted channels (parent has muted class or aria)
                var item = b.closest('[class*="sidebar"]');
                if (item && item.querySelector('[data-qa="muted"]')) return;
                var n = parseInt(b.textContent);
                if (!isNaN(n) && n > 0) total += n;
            });
            post(total);
        }

        function post(count) {
            if (count === _lastCount) return;
            _lastCount = count;
            try {
                window.webkit.messageHandlers.unread.postMessage({count: count, source: 'slack'});
            } catch(e) {}
        }

        function debounced() {
            clearTimeout(_timer);
            _timer = setTimeout(countBadges, 500);
        }

        var observer = new MutationObserver(debounced);
        function start() {
            var target = document.body || document.documentElement;
            if (target) {
                observer.observe(target, { childList: true, subtree: true, characterData: true });
                setInterval(countBadges, 30000);
                countBadges();
            }
        }

        if (document.body) start();
        else document.addEventListener('DOMContentLoaded', start);
    })();
    """
}
