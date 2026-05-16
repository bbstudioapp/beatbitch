# Visual assets provenance — BeatBitch

_Last updated: 2026-05-09_

**Languages**: English · [Français](ASSETS.fr.md) · [Deutsch](ASSETS.de.md)

---

## In one sentence

**All visual backgrounds bundled in BeatBitch are AI-generated locally by the maintainer. No third-party content, no scraping, no resemblance to real people.**

## Scope

This note covers the visual binaries distributed outside of git via an external channel (Cloudflare R2), fetched by CI at build time and bundled into the APK:

- `assets/backgrounds/` — backgrounds (jpeg / png / webp / animated gif / animated webp)

Source code, editorial JSON files (sessions, coach lines, nicknames, etc.) and audio beep samples are versioned in the repo under PolyForm Noncommercial 1.0.0 — they are not covered by this note.

## Generation method

- **Tools**: Stable Diffusion 1.5 + AnimateDiff, run locally via ComfyUI on consumer hardware (NVIDIA RTX 3070 GPU).
- **Checkpoints used**: public models downloaded from Civitai (epiCRealism, Lazymix Real Amateur, Babes, URPM, and related), all under **CreativeML Open RAIL-M** license or variants compatible with non-commercial use.
- **LoRAs**: only generic action / pose / style LoRAs, never LoRAs of real people.
- **No assets downloaded from third-party sites** (no scraping, no purchased packs, no reuse of web images).

## Guarantees

The prompts used to generate these backgrounds explicitly exclude:

- **Any depiction of minors** — negative prompts systematically include `child, teen, underage, schoolgirl`, and adult age (`30 years old`, `mature woman`) is anchored in the positive prompt.
- **Any identifiable real person** — no celebrity or named-person LoRA is used. Outputs are visually reviewed to exclude accidental resemblances.

The in-app coaches (Lina, Hélène, Jade, Morgan, Victoria, Nyx) are **fictional characters**. Any resemblance to a real person would be coincidental and would cause the asset to be discarded.

## Legal status

A purely AI-generated output is not a copyrightable work (US, EU and FR jurisprudences converging in 2026 — no human author in the legal sense). No one can therefore claim these backgrounds as stolen, and the maintainer does not claim intellectual property over them.

The app as a whole (code, editorial content, composition) remains under **PolyForm Noncommercial 1.0.0**, which applies to the composition and the software, not to the AI backgrounds taken in isolation.

## Generation log

The maintainer keeps a **local** record of generation parameters (checkpoint, LoRAs, prompt, seed, sampler, steps) for each bundled asset. This record exists in two forms:

1. **Metadata embedded in the original ComfyUI files** (uncompressed PNG / webp) — automatically embedded by ComfyUI.
2. **Optional local JSON manifest** for searching.

These records are not published (not in the repo, not in the distributed R2 bucket). They allow asset reproduction if needed and document the generation chain.

## External contributions

Third-party background contributions are **not accepted** for now — possibly opened later with a dedicated verification process. See [`ASSET_CONTRIBUTIONS.md`](ASSET_CONTRIBUTIONS.md) for audio contributions.
