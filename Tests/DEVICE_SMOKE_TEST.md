Test with YouTube 21.42.4 and the build containing these changes. These are device checks, not results claimed by the automated test.

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
- iPad: compare one-line and multiline cards. Short cards without room below the menu must show the DeArrow toggle beside More, with text flowing around it. Test delayed thumbnail loading, scrolling/reuse, both toggle states, and independent menu taps.
- iPad Home/Subscriptions: with Playback in feeds enabled, leave a normal video centered until it starts, then scroll, rotate, open/close a video and return from Notifications. Repeat with the native playback setting off to confirm it remains respected.

2.5 fullscreen regression (pending device verification):

- iPhone/iPad: enter and exit fullscreen repeatedly using the button and rotation, with controls visible/hidden and DeArrow/RYD enabled. No DeArrow toggle should appear on player controls, and exiting must not crash. Return to Home and verify card toggles and feed counts still work; repeat with an inline preview playing.

2.6 crash follow-up (pending device verification):

- Repeat the fullscreen check above, including repeated taps to show/hide controls and rapid video changes. The September 27 14:43 report matches the 2.5 YouMod UUID `D641DCA4-EF77-3059-ABFB-8C7B332EF280`: return offset `0x10688` follows `objc_retain` in `YouModRefreshThumbnailNode`, entered by the queued `setURL:resetToDefault:` block. Logos captures hook `self` without retaining it; queued thumbnail/watch-row callbacks must use zeroing weak references and skip destroyed or detached controls.

October 26 DeArrow regressions (pending device verification on YouTube 21.42.4):

- Expand a channel's “Uploaded 7 videos” notification before visiting any of its videos. The group heading must stay unchanged and the first video's row must retain its actual title. Toggle original/replacement twice, collapse/re-expand, then repeat with another group from the same channel.
- Open comments containing timestamps, linked video titles, emoji and ordinary text. No comment or reply should receive a DeArrow toggle or have its text replaced. Scroll rapidly and reopen comments to exercise reused cells.
- Cold-launch Home and scroll through cards with one-line and multiline titles, delayed thumbnails and playing previews. Toggles must stay below the menu, or beside More when there is no space below, without jumping to the top. Repeat after opening/closing a video, rotating and on iPad.

October 31 floating tab bar and OLED settings (pending device verification on YouTube 21.42.4):

3.1 device result: the user confirmed the default glass tabs remained, the white row after Privacy remained, and Gemini was still clipped with excessive spacing before views. Compilation and geometry checks did not establish that the active runtime paths were reached. The revised data getters, Settings surface traversal and deferred live-node remeasurement below need another iPhone check.

- With the glass bar active, disable Shorts and Create (+), enable Notifications, and reorder the remaining tabs. Return to Home without relaunching: only the enabled tabs should appear in the saved order. Tap Notifications and Home repeatedly; verify both the selected icon and displayed page change. Scroll down until the bar hides, then up until it returns; the order and disabled tabs must stay applied. Re-enable Shorts/Create and repeat, including a cold launch and rotation. Repeat with the classic bar and on iPad.
- Enable Hide Tab Labels, scroll the glass bar away/back, then change tabs and rotate. Labels must stay hidden. Disable the preference and confirm YouTube's native label behavior returns.
- In OLED dark mode, open Settings and scroll through Privacy and the following row: its text/icon must remain visible against black. Tap it to verify its original action and selection feedback, scroll away/back to recycle it, then switch light/dark appearance in both YouTube and iOS. Light mode must retain the original background; repeat with OLED disabled after relaunch.
- Watch row: compare subscribed and unsubscribed channels, with and without Join. The view counter should have a compact slot immediately before Like, with no stretched gap after Subscribe. On narrow screens, Gemini and other overflowing actions must wrap below; Comments must move down with the measured row. Tap Subscribe/the bell, Like/Dislike, Share, Gemini and More, then rotate and change videos repeatedly. Repeat with large text and an RTL language. On iPad, verify the separate scrollable action row and its view counter remain usable.

November 10 acceptance checks (pending on iPhone 17 and iPad Pro M2 11-inch):

- Feed: compare the supplied South Korea card, long titles, compact notifications, RTL cards, delayed thumbnails and playing previews. The DeArrow control must stay outside the thumbnail. On short cards it aligns beside More and text leaves its hit target clear. Scroll/reuse and rotate in both states.
- Watch title: open a video directly, from a notification and from Home with an empty DeArrow cache. The title must update when branding arrives. Tap the DeArrow control beside the native watch More button below the views row; switch original/replacement twice. Both the normal and experimental title labels must update. More must still open its native menu. Repeat with branding unavailable, title replacement disabled, rapid video changes, larger text and iPad Split View.
- Text: check emoji, accents, Japanese, quotes, question/exclamation marks and genuine mathematical `>` symbols. Replacements must use ordinary spaces without inheriting inline icon/glyph runs. Original restores the native attributed title.
- Player: repeatedly open videos, enter/exit fullscreen by button and rotation, show/hide controls and return to the feed. Video/player geometry must remain native. Watch-row height changes must stay inside the action row. Repeat with DeArrow and RYD independently disabled.
- Shorts: test Repeat, Next and Pause at end, separate Shorts speed, fallback regular speed and global speed lock. Swipe repeatedly to the next Short with the seekbar hidden. Pinch a regular video with two-finger pause enabled: zoom must not pause playback.
- Preview audio: enable Auto mute with Preview sound on; each new preview must start muted and remain manually switchable. Disable Auto mute and confirm new previews start with sound again.
- Hold-speed indicator: test portrait vertical videos and landscape; the capsule must remain below the Dynamic Island/notch and inside the safe horizontal area.
- OLED keyboard: type in Search and comments, open emoji search, rotate, then switch dark/light appearance. Native keys, suggestions and dock buttons must stay visible.

November 11 watch-title follow-up:

The user confirmed v3.4 positions the watch toggle correctly but leaves the original title visible, including when the feed already shows the cached replacement. The legacy `YTSlimVideoInformationCell` hook alone does not cover the Elements watch header. YouTube 21.42.4 bundles `video_metadata.eml|3035ad7f9a19183f`, which references `video_metadata_inner.eml|fcece9abf78ae91c`; both are now recognized through their owning component's template URI.

- Open the Louis Rossmann video from the supplied screenshots. The watch title should show the same DeArrow title as the feed: “Overview and criticisms of the NYT vs. Brave case”. Toggle original/replacement repeatedly, rotate, and scroll the title out of view and back. The chosen state must survive layout changes.
- Repeat with an empty branding cache and slow connectivity. The native title should remain until branding arrives, then update automatically. Repeat with a cached title and a previously toggled feed card; a newly watched video defaults to DeArrow.
- Change videos while a branding request is pending. An old video's response must not replace the new title. Comments and recommendations with matching title text must remain untouched, including recycled text nodes. Repeat on iPad, with title replacement disabled, and after light/dark or text-size changes.

The macOS fixture now exercises the actual Elements binding and controller notification/display callbacks with no legacy title cell. Device confirmation of this follow-up remains pending.

November 11 second follow-up:

The user confirmed the watch title still stayed original in v3.5, and reported a freeze/crash after opening a video and immediately tapping its channel. The previous fixtures always pre-seeded the native title-cell video ID. The native `YTSlimVideoInformationCellController` initializer does not populate that field; the window/notification path now also handles an absent renderer ID using the active playback ID and matching cached/native title. A playback identity change resets the default once, independently of cell layout and player reparenting.

Source hazards repaired in the same patch: watch-row searches no longer request UIViews from loaded layer-backed nodes; component ownership traversal detects cycles; feed toggle placement retains a chosen side slot so added text wrapping cannot alternate side/below placement indefinitely. These are code-level findings, not a symbolicated diagnosis of the reported device crash.

- Recheck the supplied Reject Convenience video: the watch title should match the feed's “Criticisms of services that sponsor YouTubers…” title, and both toggle directions must work. Repeat with cached branding and direct links, then rotate and minimize/restore the player.
- Open a video and immediately tap its channel, repeat with another video/channel, then use Back, close the miniplayer, and switch tabs. Test while branding loads and with a short feed card becoming taller after title replacement. Navigation and controls must remain responsive.
- Automated checks cover missing renderer IDs through real window/notification hook bodies, repeated attach/detach, same-video player replacement, cyclic ownership and loaded layer-backed traversal. They do not reproduce UIKit transitions on physical hardware. A matching YouTube `.ips` report is still required to identify the exact crash stack if crashes continue.

The same installed build also froze in fullscreen with audio continuing while picture, controls and screenshot handling stalled. The feed text setter now returns immediately for unbound and recycled text, without reading ancestor nodes or querying branding. Only bound feed title nodes subscribe to feed branding notifications. The production setter fixture performs 10,000 fullscreen-text updates while forbidding parent access and verifies no branding queries; bound feed-title replacement is exercised separately. These checks reduce shared rendering work but do not establish the device's exact blocking stack.
