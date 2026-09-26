# YouMod — Sersium's fork

[![Build](https://github.com/Sersium/YouMod/actions/workflows/build.yml/badge.svg)](https://github.com/Sersium/YouMod/actions/workflows/build.yml)
[![Release](https://img.shields.io/github/v/release/Sersium/YouMod)](https://github.com/Sersium/YouMod/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/Sersium/YouMod/total)](https://github.com/Sersium/YouMod/releases)

A personal fork of [Tonwalter888/YouMod](https://github.com/Tonwalter888/YouMod), retaining its downloads, SponsorBlock, background playback and customization features.

## What this fork adds

- **DeArrow:** replacement titles and thumbnails across Home, channels and notifications, with a quick original/replacement toggle.
- **Video stats:** Return YouTube Dislike counts and a compact view count beside the watch-page controls.
- **Simpler watch controls:** no paid Join button and an icon-only Subscribe control.
- **Preview defaults:** sound on, captions off, with working manual controls.
- **Distribution:** each main-branch push builds an IPA and publishes a separate Feather entry with release notes and a source diff.

## Install

Download the IPA from [Releases](https://github.com/Sersium/YouMod/releases/latest), or add this source in Feather:

```text
https://raw.githubusercontent.com/Sersium/YouMod/main/feather.json
```

Refresh the source and select the newest version. Later versions remain separately available for rollback.

## Build with another YouTube IPA

- **Saved default:** edit the direct HTTPS `url` in [`ipa-source.json`](ipa-source.json). An optional `sha256` pins the downloaded file. Pushing the change builds and publishes automatically.
- **One build:** open [Actions → Build YouMod → Run workflow](https://github.com/Sersium/YouMod/actions/workflows/build.yml), select `main`, and provide `ipa_url` and optionally `ipa_sha256`. Blank inputs use the saved default. A manual override does not change that default.
- If a hosting service replaces a file at the **same URL**, select **refresh_ipa**, or update its checksum.

Provide a direct download to a **decrypted YouTube IPA**, not a download webpage. The build checks the IPA and reads its YouTube version automatically; changing the source also changes the cache key. New YouTube versions can change private APIs, so a successful build still needs device testing. YouTube **21.38.2** is the currently device-tested base; the minimum iOS version also depends on the base IPA.

## AI disclosure, license and credits

AI tools were used extensively to write, debug and review this fork. Automated checks and user device testing help validate changes, but do not guarantee compatibility with every YouTube version.

Licensed under [GPLv3](LICENSE). Original work and contributor credit remain with [Tonwalter888/YouMod](https://github.com/Tonwalter888/YouMod) and its contributors, including grohit1810, dayanch96, PoomSmart, YTLite/YTLitePlus, uYouEnhanced and YTweaks. This fork also uses [DeArrow](https://dearrow.ajay.app/), [SponsorBlock](https://sponsor.ajay.app/), [Return YouTube Dislike](https://returnyoutubedislike.com/), YTVideoOverlay and DontEatMyContent. Not affiliated with YouTube or Google.
