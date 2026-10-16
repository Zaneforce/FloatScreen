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

        function countUnread() {
            var total = 0;
            document.querySelectorAll(
                '[data-testid="icon-unread-count"], ' +
                'span[aria-label*="unread"]'
            ).forEach(function(b) {
                var n = parseInt(b.textContent);
                if (!isNaN(n) && n > 0) total += n;
            });
            if (total === 0) {
                var m = document.title.match(/\\((\\d+)\\)/);
                if (m) total = parseInt(m[1]) || 0;
            }
            if (total > 0) {
                try { window.webkit.messageHandlers.unread.postMessage({count: total}); } catch(e) {}
            }
        }

        var observer = new MutationObserver(countUnread);
        function start() {
            var target = document.body || document.documentElement;
            if (target) {
                observer.observe(target, { childList: true, subtree: true, characterData: true });
                setInterval(countUnread, 3000);
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

        function countBadges() {
            var total = 0;
            document.querySelectorAll(
                '.p-channel_sidebar__badge, ' +
                '[data-qa="channel_sidebar_name_badge"], ' +
                '.c-mention_badge'
            ).forEach(function(b) {
                var n = parseInt(b.textContent);
                if (!isNaN(n) && n > 0) total += n;
            });
            try {
                window.webkit.messageHandlers.unread.postMessage({count: total});
            } catch(e) {}
        }

        var observer = new MutationObserver(function() {
            countBadges();
        });

        function start() {
            var target = document.body || document.documentElement;
            if (target) {
                observer.observe(target, {
                    childList: true, subtree: true, characterData: true
                });
                setInterval(countBadges, 5000);
                countBadges();
            }
        }

        if (document.body) start();
        else document.addEventListener('DOMContentLoaded', start);
    })();
    """
}
