# BeatBitch — Binary asset contributions

> This page explains how to submit a pack of **background gifs** or
> **ambience sounds** for BeatBitch.

**Languages**: English · [Français](ASSET_CONTRIBUTIONS.fr.md) · [Deutsch](ASSET_CONTRIBUTIONS.de.md)

---

## Why a separate channel

Heavy binaries (gifs, MP3) are **gitignored** in the repo — they aren't
versioned on GitHub. So you can't add them through a regular PR.
Instead, you submit via an issue with an external link, and we pull
them into a private bucket after vetting.

The code files (config, JSON, docs) that reference those assets stay in
the repo and go through the usual PR workflow.

## What we accept

- **Background gifs**: clean loops for the session screen, ≥ 720p,
  ideally < 5 MB per file, no watermark.
- **Ambience sounds** (MP3): drones, pulses, rain, waves, pads —
  anything that sits under the guidance beeps without covering them.
  Quality ≥ 192 kbps, 30 s – 3 min, loop-friendly.
- **Full packs**: a `mode → asset` mapping (rhythm / lick / biffle /
  hold / breath / hand…) with editorial coherence (intimate, nature,
  studio, etc.). Packs live in `assets/ambience_packs.json`.

## What we **don't** accept

- Any asset you **can't justify license or permission for**. Gifs/clips
  scraped from Pornhub, Redgifs, OnlyFans, Twitter without explicit
  creator consent will be rejected. Not out of prudishness — out of
  legal responsibility, the app is public.
- Files with a **watermark** from a site, brand, or third-party creator.
  It pollutes visually and exposes to takedown.
- Audio with **comprehensible human voice** (moaning OK, words not) —
  the TTS coach must stay audible and unambiguous.
- Any content involving **minors**, **scripted non-consent**, or
  **animals**. Immediate rejection, no discussion.

## Legally safe sources

Starting points for sourcing safely:

| Source | Type | Conditions |
|---|---|---|
| **Freesound.org** | Ambience MP3 | Filter by CC0 or CC-BY (credit in CREDITS.md) |
| **Pixabay** / **Pexels** | SFW abstract gifs/videos | Pixabay / Pexels license, free for commercial use |
| **YouTube Audio Library** | Pads, drones | Public domain or CC, check case by case |
| **Your own captures / creations** | Anything | You're the author, clear rights |
| **Generative AI** (Stable Diffusion, AnimateDiff, Suno, Riffusion…) | Anything | You authored the prompt, but check the model's license |
| **Reddit / Twitter / OnlyFans with written creator consent** | Gifs | DM screenshot required in the submission |

## How to submit

1. **Prepare your pack**:
   - Rename files cleanly (kebab-case, descriptive English or French:
     `deep-drone.mp3`, `intimate-rhythm-loop.gif`).
   - Add a `CREDITS.md` file at the pack root listing **every file**,
     its source, and license/permission.
   - Compress to `.zip` or `.tar.gz`.
2. **Host the archive** on any service: Google Drive, Dropbox, Mega,
   WeTransfer, transfer.sh… anything except GitHub directly. The link
   must stay accessible for **at least 30 days**.
3. **Open an issue** using the
   *[Asset contribution](https://github.com/bbstudioapp/beatbitch/issues/new?template=asset_contribution.md)* template.
   Paste the hosting link and fill in the inventory (filename, source,
   license for each file — or point to your CREDITS.md).
4. On our side, we verify licenses, download, upload to the private R2
   bucket, update `assets/ambience_packs.json` if relevant, commit.
   The contribution ships in the next release.

## Recommended `CREDITS.md` format

```markdown
# Credits

## deep-drone.mp3
- Source: https://freesound.org/people/foo/sounds/123456/
- Author: foo
- License: CC0

## intimate-rhythm-loop.gif
- Source: own work (Stable Diffusion + AnimateDiff)
- Author: <your handle>
- License: CC0
```

## Rejections & feedback

If the contribution is rejected (usually: unclear licensing), you get a
reply on the issue listing what's missing. You can fix and reopen.
License-justification rejections are systematic — non-negotiable.
