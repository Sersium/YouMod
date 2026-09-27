Test with YouTube 21.38.2 and the build containing these changes. These are device checks, not results claimed by the automated test.

- Home: confirm one DeArrow toggle below each three-dot menu; tap both controls independently. Swap a title/thumbnail twice, then scroll away and back.
- MrBeast channel Videos: repeat for Latest/Popular/Oldest and horizontal shelves. Scroll rapidly for several minutes, open/close a video and comments, and verify no freeze or wrong-video swaps after cell reuse.
- Notifications: confirm the toggle stays in the menu column, outside the thumbnail and notification text, including grouped uploads.
- Previews: sound starts on; mute/unmute five times on the same preview. Scroll to a new preview and verify sound starts on again. Captions start off and remain manually switchable.
- Watch page: both like and dislike counts appear at their icons, including the compact action bar shown in the report. Change videos quickly; counts must follow the watched video. Test light/dark mode and both count preferences.
- Network failure: block DeArrow/RYD briefly. Original thumbnails remain usable; unavailable votes show a dash rather than invented zeroes. Restore connectivity and re-enter the card after a minute.

Crash evidence: all three supplied September 26 reports identify the same
YouMod dylib UUID (99DA9860-0205-3144-B71B-D9FFD251F577), return offset 0x3bcc4.
The preceding call enters ASDisplayNode addYogaChild: (YouTube 0x1047f8090),
then its insertYogaChild path dereferences null + 0x240. The new count path
must never add Yoga children, add Texture subnodes, or alter layout styles.
The September 23 missing libroothide launch failure and watchdog exit are
separate failures; the September 24 disk-writes report is not this crash.

Publication: new workflow runs advance 2.3, 2.4, …, 2.9, 3.0; retries retain their version. Confirm the
IPA release exists before its Feather entry is published; inspect the latest
entry, an older entry, version history, release notes and the comparison link.

2.2 watch row: verify view count before Like/Dislike; Join stays hidden.
Test Subscribe on a channel you do not follow, then its subscribed notification
menu. Both must still dispatch the original YouTube action. Repeat without a
Join button and on a narrow display; if Gemini moves, test both Gemini and
More actions in the three-dot menu. Check that existing vote counts still align.

September 27 phone/iPad regressions (pending device verification):

- Force-quit and launch on iPad with Hide Shorts Shelf and Hide Horizontal Shelf enabled. The first Home render must match a pull-to-refresh, with no forbidden shelves flashing in. Repeat with Remove Ads disabled and with Keep Shorts in Subscriptions on/off.
- On iPhone and iPad, open a video with/without Join. Views must sit immediately before the vote controls. On iPad, both counters must be distinct and readable, with no original count underneath. Tap like/dislike and confirm selected state still updates; rotate and test Split View.
- Manage Tabs: disable Shorts, return to Home, re-enable it, and reorder two tabs. The changes must apply without relaunching. Repeat on iPad and with one valid navigation tab left.
- Home, Subscriptions and related-video previews: verify likes/dislikes beside native views. Scroll quickly to recycle cards, enter a different video, and rotate. Counts must stay with each preview and metadata must wrap without covering the next row or DeArrow toggle. Repeat with DeArrow off and each RYD count preference off.
- With RYD unreachable, feed cards retain their original metadata; no fabricated counts or request loop. Restore connectivity, re-enter the card after a minute and verify counts appear once.

2.4 regression checks (pending device verification):

- iPhone/iPad: Home → Notifications → Home, then Subscriptions → Home. Repeat after reordering tabs and after disabling/re-enabling Shorts. Confirm both the selected icon and displayed feed change.
- iPad landscape: open several videos and verify the right-hand recommendations remain visible with Hide Related Videos off, including when Hide Horizontal Shelf is on. Rotate and return to Home.
- iPad: compare one-line and multiline cards. Short cards without room below the menu must show the DeArrow toggle in the top corner. Test delayed thumbnail loading, scrolling/reuse, both toggle states, and independent menu taps.
- iPad Home/Subscriptions: with Playback in feeds enabled, leave a normal video centered until it starts, then scroll, rotate, open/close a video and return from Notifications. Repeat with the native playback setting off to confirm it remains respected.

2.5 fullscreen regression (pending device verification):

- iPhone/iPad: enter and exit fullscreen repeatedly using the button and rotation, with controls visible/hidden and DeArrow/RYD enabled. No DeArrow toggle should appear on player controls, and exiting must not crash. Return to Home and verify card toggles and feed counts still work; repeat with an inline preview playing.

2.6 crash follow-up (pending device verification):

- Repeat the fullscreen check above, including repeated taps to show/hide controls and rapid video changes. The September 27 14:43 report matches the 2.5 YouMod UUID `D641DCA4-EF77-3059-ABFB-8C7B332EF280`: return offset `0x10688` follows `objc_retain` in `YouModRefreshThumbnailNode`, entered by the queued `setURL:resetToDefault:` block. Logos captures hook `self` without retaining it; queued thumbnail/watch-row callbacks must use zeroing weak references and skip destroyed or detached controls.
