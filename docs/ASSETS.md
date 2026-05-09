# Provenance des assets visuels — BeatBitch

_Last updated: 2026-05-09_

🇫🇷 **[Français](#français)** &nbsp;|&nbsp; 🇬🇧 **[English](#english)**

---

## Français

### En une phrase

**Tous les fonds visuels embarqués dans BeatBitch sont générés par IA en local par le mainteneur. Aucun contenu tiers, aucun scraping, aucune ressemblance à une personne réelle.**

### Périmètre

Cette note couvre les binaires visuels distribués hors du dépôt git via le canal externe (Cloudflare R2), récupérés par la CI au moment du build et bundlés dans l'APK :

- `assets/backgrounds/` — fonds (jpeg / png / webp / gif animés / webp animés)

Le code source, les fichiers JSON éditoriaux (sessions, phrases coach, surnoms, etc.) et les samples audio de bips sont versionnés dans le dépôt sous PolyForm Noncommercial 1.0.0 — ils ne sont pas concernés par cette note.

### Méthode de génération

- **Outils** : Stable Diffusion 1.5 + AnimateDiff, exécutés localement via ComfyUI sur du hardware grand public (GPU NVIDIA RTX 3070).
- **Checkpoints utilisés** : modèles publics téléchargés depuis Civitai (epiCRealism, Lazymix Real Amateur, Babes, URPM, et apparentés), tous sous licence **CreativeML Open RAIL-M** ou variantes compatibles avec un usage non-commercial.
- **LoRAs** : uniquement des LoRAs d'action / pose / style générique, jamais de LoRAs de personnes réelles.
- **Aucun asset téléchargé depuis un site tiers** (pas de scraping, pas de pack acheté, pas de réutilisation d'images web).

### Garanties

Les prompts utilisés pour générer ces fonds excluent explicitement :

- **Toute représentation de mineur** — les négatifs incluent systématiquement `child, teen, underage, schoolgirl`, et l'âge adulte (`30 years old`, `mature woman`) est ancré dans le positif.
- **Toute personne réelle identifiable** — aucun LoRA de célébrité ou de personne nommée n'est utilisé. Les outputs sont vérifiés visuellement pour exclure les ressemblances accidentelles.

Les coachs de l'app (Lina, Hélène, Jade, Morgan, Victoria, Nyx) sont des **personnages fictifs**. Toute ressemblance avec une personne réelle serait fortuite et ferait écarter l'asset.

### Statut juridique

L'output purement généré par IA n'est pas une œuvre protégée par le droit d'auteur (jurisprudences US, EU et FR convergentes en 2026 — pas d'auteur humain au sens du droit). Personne ne peut donc revendiquer ces fonds comme volés, et le mainteneur n'en revendique pas la propriété intellectuelle.

L'app dans son ensemble (code, contenu éditorial, agencement) reste sous **PolyForm Noncommercial 1.0.0**, qui s'applique à la composition et au logiciel, pas aux fonds IA pris isolément.

### Carnet de bord

Le mainteneur conserve **localement** une trace des paramètres de génération (checkpoint, LoRAs, prompt, seed, sampler, steps) pour chaque asset bundlé. Cette trace existe sous deux formes :

1. **Métadonnées dans les fichiers ComfyUI originaux** (PNG / webp non-recompressés) — automatiquement embarquées par ComfyUI.
2. **Manifest JSON local** facultatif pour la recherche.

Ces traces ne sont pas publiées (pas dans le dépôt, pas dans le bucket R2 distribué). Elles servent à reproduire un asset en cas de besoin et à documenter la chaîne de génération.

### Contributions externes

Les contributions de fonds par des tiers ne sont **pas acceptées** pour l'instant — ouverture éventuelle plus tard avec un processus de vérification dédié. Voir [`ASSET_CONTRIBUTIONS.md`](ASSET_CONTRIBUTIONS.md) pour les contributions audio.

---

## English

### In one sentence

**All visual backgrounds bundled in BeatBitch are AI-generated locally by the maintainer. No third-party content, no scraping, no resemblance to real people.**

### Scope

This note covers the visual binaries distributed outside of git via an external channel (Cloudflare R2), fetched by CI at build time and bundled into the APK:

- `assets/backgrounds/` — backgrounds (jpeg / png / webp / animated gif / animated webp)

Source code, editorial JSON files (sessions, coach lines, nicknames, etc.) and audio beep samples are versioned in the repo under PolyForm Noncommercial 1.0.0 — they are not covered by this note.

### Generation method

- **Tools**: Stable Diffusion 1.5 + AnimateDiff, run locally via ComfyUI on consumer hardware (NVIDIA RTX 3070 GPU).
- **Checkpoints used**: public models downloaded from Civitai (epiCRealism, Lazymix Real Amateur, Babes, URPM, and related), all under **CreativeML Open RAIL-M** license or variants compatible with non-commercial use.
- **LoRAs**: only generic action / pose / style LoRAs, never LoRAs of real people.
- **No assets downloaded from third-party sites** (no scraping, no purchased packs, no reuse of web images).

### Guarantees

The prompts used to generate these backgrounds explicitly exclude:

- **Any depiction of minors** — negative prompts systematically include `child, teen, underage, schoolgirl`, and adult age (`30 years old`, `mature woman`) is anchored in the positive prompt.
- **Any identifiable real person** — no celebrity or named-person LoRA is used. Outputs are visually reviewed to exclude accidental resemblances.

The in-app coaches (Lina, Hélène, Jade, Morgan, Victoria, Nyx) are **fictional characters**. Any resemblance to a real person would be coincidental and would cause the asset to be discarded.

### Legal status

A purely AI-generated output is not a copyrightable work (US, EU and FR jurisprudences converging in 2026 — no human author in the legal sense). No one can therefore claim these backgrounds as stolen, and the maintainer does not claim intellectual property over them.

The app as a whole (code, editorial content, composition) remains under **PolyForm Noncommercial 1.0.0**, which applies to the composition and the software, not to the AI backgrounds taken in isolation.

### Generation log

The maintainer keeps a **local** record of generation parameters (checkpoint, LoRAs, prompt, seed, sampler, steps) for each bundled asset. This record exists in two forms:

1. **Metadata embedded in the original ComfyUI files** (uncompressed PNG / webp) — automatically embedded by ComfyUI.
2. **Optional local JSON manifest** for searching.

These records are not published (not in the repo, not in the distributed R2 bucket). They allow asset reproduction if needed and document the generation chain.

### External contributions

Third-party background contributions are **not accepted** for now — possibly opened later with a dedicated verification process. See [`ASSET_CONTRIBUTIONS.md`](ASSET_CONTRIBUTIONS.md) for audio contributions.
