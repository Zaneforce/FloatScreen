import Foundation

enum YouTubeAdSkipper {
    static let script: String = """
    (function() {
        'use strict';
        if (location.hostname.indexOf('youtube.com') === -1) return;
        if (window.__ytAdSkipInit) return;
        window.__ytAdSkipInit = true;

        var observer = new MutationObserver(function() {
            // Auto-click any skip button
            var skipBtns = document.querySelectorAll(
                '.ytp-skip-ad-button, .ytp-ad-skip-button, ' +
                '.ytp-ad-skip-button-modern, button.ytp-ad-skip-button-modern'
            );
            for (var i = 0; i < skipBtns.length; i++) {
                if (skipBtns[i].offsetParent !== null) {
                    skipBtns[i].click();
                    return;
                }
            }

            // Speed through unskippable ads
            var player = document.querySelector('.html5-video-player');
            if (!player) return;
            var video = player.querySelector('video');
            if (!video) return;

            var adShowing = player.classList.contains('ad-showing');

            if (adShowing) {
                if (!video.__adSpeedup) {
                    video.__savedRate = video.playbackRate;
                    video.__savedMuted = video.muted;
                    video.playbackRate = 16;
                    video.muted = true;
                    video.__adSpeedup = true;
                }
            } else if (video.__adSpeedup) {
                video.playbackRate = video.__savedRate || 1;
                video.muted = video.__savedMuted || false;
                video.__adSpeedup = false;
            }
        });

        function start() {
            var target = document.body || document.documentElement;
            if (target) {
                observer.observe(target, {
                    childList: true,
                    subtree: true,
                    attributes: true,
                    attributeFilter: ['class']
                });
            }
        }

        if (document.body) { start(); }
        else { document.addEventListener('DOMContentLoaded', start); }
    })();
    """
}
