# Provenance des assets visuels — BeatBitch

_Dernière mise à jour : 2026-05-09_

**Langues** : [English](ASSETS.md) · Français · [Deutsch](ASSETS.de.md)

---

## En une phrase

**Tous les fonds visuels embarqués dans BeatBitch sont générés par IA en local par le mainteneur. Aucun contenu tiers, aucun scraping, aucune ressemblance à une personne réelle.**

## Périmètre

Cette note couvre les binaires visuels distribués hors du dépôt git via le canal externe (Cloudflare R2), récupérés par la CI au moment du build et bundlés dans l'APK :

- `assets/backgrounds/` — fonds (jpeg / png / webp / gif animés / webp animés)

Le code source, les fichiers JSON éditoriaux (sessions, phrases coach, surnoms, etc.) et les samples audio de bips sont versionnés dans le dépôt sous PolyForm Noncommercial 1.0.0 — ils ne sont pas concernés par cette note.

## Méthode de génération

- **Outils** : Stable Diffusion 1.5 + AnimateDiff, exécutés localement via ComfyUI sur du hardware grand public (GPU NVIDIA RTX 3070).
- **Checkpoints utilisés** : modèles publics téléchargés depuis Civitai (epiCRealism, Lazymix Real Amateur, Babes, URPM, et apparentés), tous sous licence **CreativeML Open RAIL-M** ou variantes compatibles avec un usage non-commercial.
- **LoRAs** : uniquement des LoRAs d'action / pose / style générique, jamais de LoRAs de personnes réelles.
- **Aucun asset téléchargé depuis un site tiers** (pas de scraping, pas de pack acheté, pas de réutilisation d'images web).

## Garanties

Les prompts utilisés pour générer ces fonds excluent explicitement :

- **Toute représentation de mineur** — les négatifs incluent systématiquement `child, teen, underage, schoolgirl`, et l'âge adulte (`30 years old`, `mature woman`) est ancré dans le positif.
- **Toute personne réelle identifiable** — aucun LoRA de célébrité ou de personne nommée n'est utilisé. Les outputs sont vérifiés visuellement pour exclure les ressemblances accidentelles.

Les coachs de l'app (Lina, Hélène, Jade, Morgan, Victoria, Nyx) sont des **personnages fictifs**. Toute ressemblance avec une personne réelle serait fortuite et ferait écarter l'asset.

## Statut juridique

L'output purement généré par IA n'est pas une œuvre protégée par le droit d'auteur (jurisprudences US, EU et FR convergentes en 2026 — pas d'auteur humain au sens du droit). Personne ne peut donc revendiquer ces fonds comme volés, et le mainteneur n'en revendique pas la propriété intellectuelle.

L'app dans son ensemble (code, contenu éditorial, agencement) reste sous **PolyForm Noncommercial 1.0.0**, qui s'applique à la composition et au logiciel, pas aux fonds IA pris isolément.

## Carnet de bord

Le mainteneur conserve **localement** une trace des paramètres de génération (checkpoint, LoRAs, prompt, seed, sampler, steps) pour chaque asset bundlé. Cette trace existe sous deux formes :

1. **Métadonnées dans les fichiers ComfyUI originaux** (PNG / webp non-recompressés) — automatiquement embarquées par ComfyUI.
2. **Manifest JSON local** facultatif pour la recherche.

Ces traces ne sont pas publiées (pas dans le dépôt, pas dans le bucket R2 distribué). Elles servent à reproduire un asset en cas de besoin et à documenter la chaîne de génération.

## Contributions externes

Les contributions de fonds par des tiers ne sont **pas acceptées** pour l'instant — ouverture éventuelle plus tard avec un processus de vérification dédié. Voir [`ASSET_CONTRIBUTIONS.md`](ASSET_CONTRIBUTIONS.md) pour les contributions audio.
