# BeatBitch — Contribution d'assets binaires

> Cette page explique comment proposer un pack de **gifs de fond** ou de
> **sons d'ambiance** pour BeatBitch.
>
> 🇫🇷 / 🇬🇧 Read the English version below.

---

## 🇫🇷 Français

### Pourquoi un canal séparé

Les binaires lourds (gifs, MP3) sont **gitignorés** dans le dépôt — ils ne
sont pas versionnés sur GitHub. Tu ne peux donc pas les ajouter via une
PR classique. À la place, on passe par une issue avec lien externe et on
les rapatrie dans un bucket privé après validation.

Les fichiers code (config, JSON, doc) qui réfèrent à ces assets restent
dans le repo et passent par le workflow PR habituel.

### Ce qu'on accepte

- **Gifs de fond** : loops propres pour l'écran de session, résolution
  ≥ 720p, < 5 Mo idéalement par fichier, sans watermark.
- **Sons d'ambiance** (MP3) : drones, pulses, pluie, vagues, pads — tout
  ce qui peut tenir derrière les bips de guidage sans les couvrir.
  Qualité ≥ 192 kbps, durée 30 s – 3 min, loop-friendly.
- **Packs complets** : un mapping `mode → asset` (rhythm / lick / biffle /
  hold / breath / hand…) avec une cohérence éditoriale (intime, nature,
  studio, etc.). Les packs vivent dans `assets/ambience_packs.json`.

### Ce qu'on **n'accepte pas**

- Tout asset dont tu **ne peux pas justifier la licence ou l'autorisation**.
  Les gifs/captures arrachés à Pornhub, Redgifs, OnlyFans, Twitter sans
  consentement explicite du créateur seront refusés. Pas par puritanisme,
  par responsabilité juridique — l'app est publique.
- Fichiers contenant un **watermark** d'un site, d'une marque, d'un
  créateur tiers. Ça pollue visuellement et ça expose à un takedown.
- Audio avec **voix humaine compréhensible** (gémissements OK, paroles non)
  — la coach TTS doit rester audible et parser sans ambiguïté.
- Tout contenu impliquant des **mineurs**, du **non-consensuel scénarisé**,
  ou des **animaux**. Refus immédiat sans discussion.

### Sources légalement saines

Liste de points de départ sûrs pour sourcer du contenu :

| Source | Type | Conditions |
|---|---|---|
| **Freesound.org** | MP3 ambiance | Filtre par licence CC0 ou CC-BY (attribuer dans CREDITS.md) |
| **Pixabay** / **Pexels** | Gifs / vidéos abstraites SFW | Licence Pixabay / Pexels, free pour usage commercial |
| **YouTube Audio Library** | Pads, drones | Domaine public ou CC, à vérifier au cas par cas |
| **Tes propres captures / créations** | Tout | Tu en es l'auteur, droits clairs |
| **IA générative** (Stable Diffusion, AnimateDiff, Suno, Riffusion…) | Tout | Tu es l'auteur du prompt, mais vérifie la licence du modèle utilisé |
| **Reddit / Twitter / OnlyFans avec accord écrit du créateur** | Gifs | Capture du DM de consentement requise dans la contribution |

### Comment soumettre

1. **Prépare ton pack** :
   - Renomme proprement les fichiers (kebab-case, anglais ou français
     descriptif : `deep-drone.mp3`, `intime-rythm-loop.gif`).
   - Ajoute un fichier `CREDITS.md` à la racine du pack listant **chaque
     fichier**, sa source, et sa licence/autorisation.
   - Compresse en `.zip` ou `.tar.gz`.
2. **Héberge l'archive** sur un service au choix : Google Drive,
   Dropbox, Mega, WeTransfer, transfer.sh… Tout sauf GitHub directement.
   Le lien doit rester accessible **au minimum 30 jours**.
3. **Ouvre une issue** avec le template
   *[Asset contribution](https://github.com/bbstudioapp/beatbitch/issues/new?template=asset_contribution.md)*.
   Colle le lien d'hébergement et remplis l'inventaire (filename,
   source, licence pour chaque fichier — ou pointe vers ton CREDITS.md).
4. Côté maintenance, on vérifie les licences, on télécharge, on uploade
   dans le bucket privé R2, on met à jour `assets/ambience_packs.json`
   si pertinent, on commit. La contribution apparaît dans la prochaine
   release.

### Format `CREDITS.md` recommandé

```markdown
# Credits

## deep-drone.mp3
- Source: https://freesound.org/people/foo/sounds/123456/
- Author: foo
- License: CC0

## intime-rythm-loop.gif
- Source: own work (Stable Diffusion + AnimateDiff)
- Author: <ton pseudo>
- License: CC0
```

### Refus & retours

Si la contribution est refusée (souvent : licence floue), tu reçois une
réponse sur l'issue avec ce qui manque. Tu peux corriger et la rouvrir.
Les refus pour cause de licence non justifiée sont systématiques —
ce n'est pas négociable.

---

## 🇬🇧 English

### Why a separate channel

Heavy binaries (gifs, MP3) are **gitignored** in the repo — they aren't
versioned on GitHub. So you can't add them through a regular PR.
Instead, you submit via an issue with an external link, and we pull
them into a private bucket after vetting.

The code files (config, JSON, docs) that reference those assets stay in
the repo and go through the usual PR workflow.

### What we accept

- **Background gifs**: clean loops for the session screen, ≥ 720p,
  ideally < 5 MB per file, no watermark.
- **Ambience sounds** (MP3): drones, pulses, rain, waves, pads —
  anything that sits under the guidance beeps without covering them.
  Quality ≥ 192 kbps, 30 s – 3 min, loop-friendly.
- **Full packs**: a `mode → asset` mapping (rhythm / lick / biffle /
  hold / breath / hand…) with editorial coherence (intimate, nature,
  studio, etc.). Packs live in `assets/ambience_packs.json`.

### What we **don't** accept

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

### Legally safe sources

Starting points for sourcing safely:

| Source | Type | Conditions |
|---|---|---|
| **Freesound.org** | Ambience MP3 | Filter by CC0 or CC-BY (credit in CREDITS.md) |
| **Pixabay** / **Pexels** | SFW abstract gifs/videos | Pixabay / Pexels license, free for commercial use |
| **YouTube Audio Library** | Pads, drones | Public domain or CC, check case by case |
| **Your own captures / creations** | Anything | You're the author, clear rights |
| **Generative AI** (Stable Diffusion, AnimateDiff, Suno, Riffusion…) | Anything | You authored the prompt, but check the model's license |
| **Reddit / Twitter / OnlyFans with written creator consent** | Gifs | DM screenshot required in the submission |

### How to submit

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

### Recommended `CREDITS.md` format

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

### Rejections & feedback

If the contribution is rejected (usually: unclear licensing), you get a
reply on the issue listing what's missing. You can fix and reopen.
License-justification rejections are systematic — non-negotiable.
