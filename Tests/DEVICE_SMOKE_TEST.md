Test with YouTube 21.38.2 and YouMod 2.1.7.<build>. These are device checks, not results claimed by the automated test.

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

Publication: every main push receives a unique run-number suffix. Confirm the
IPA release exists before its Feather entry is published; inspect the latest
entry, an older entry, version history, release notes and the comparison link.

2.2 watch row: verify view count before Like/Dislike; Join stays hidden.
Test Subscribe on a channel you do not follow, then its subscribed notification
menu. Both must still dispatch the original YouTube action. Repeat without a
Join button and on a narrow display; if Gemini moves, test both Gemini and
More actions in the three-dot menu. Check that existing vote counts still align.
