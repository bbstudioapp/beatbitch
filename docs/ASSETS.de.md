# Herkunft der visuellen Assets — BeatBitch

_Zuletzt aktualisiert: 2026-05-09_

**Sprachen** : [English](ASSETS.md) · [Français](ASSETS.fr.md) · Deutsch

---

## In einem Satz

**Alle in BeatBitch gebündelten visuellen Hintergründe werden vom Maintainer lokal mit KI generiert. Kein Drittanbieterinhalt, kein Scraping, keine Ähnlichkeit zu realen Personen.**

## Geltungsbereich

Diese Notiz behandelt die visuellen Binärdateien, die über einen externen Kanal (Cloudflare R2) außerhalb von Git verteilt werden, von der CI beim Build abgerufen und in die APK gebündelt werden:

- `assets/backgrounds/` — Hintergründe (jpeg / png / webp / animierte GIF / animierte webp)

Der Quellcode, die redaktionellen JSON-Dateien (Sessions, Coach-Phrasen, Spitznamen usw.) und die Audio-Beep-Samples sind im Repo unter PolyForm Noncommercial 1.0.0 versioniert — sie fallen nicht unter diese Notiz.

## Generierungsmethode

- **Werkzeuge**: Stable Diffusion 1.5 + AnimateDiff, lokal ausgeführt via ComfyUI auf Consumer-Hardware (NVIDIA RTX 3070 GPU).
- **Verwendete Checkpoints**: öffentliche Modelle, heruntergeladen von Civitai (epiCRealism, Lazymix Real Amateur, Babes, URPM und verwandte), alle unter **CreativeML Open RAIL-M**-Lizenz oder Varianten, die mit nicht-kommerzieller Nutzung kompatibel sind.
- **LoRAs**: nur generische Action-/Pose-/Stil-LoRAs, niemals LoRAs realer Personen.
- **Keine Assets von Drittanbieter-Seiten heruntergeladen** (kein Scraping, keine gekauften Packs, keine Wiederverwendung von Webbildern).

## Garantien

Die zur Generierung dieser Hintergründe verwendeten Prompts schließen explizit aus:

- **Jede Darstellung von Minderjährigen** — Negativ-Prompts beinhalten systematisch `child, teen, underage, schoolgirl`, und das Erwachsenenalter (`30 years old`, `mature woman`) ist im positiven Prompt verankert.
- **Jede identifizierbare reale Person** — kein LoRA einer Berühmtheit oder benannten Person wird verwendet. Outputs werden visuell überprüft, um zufällige Ähnlichkeiten auszuschließen.

Die In-App-Coaches (Lina, Hélène, Jade, Morgan, Victoria, Nyx) sind **fiktive Charaktere**. Jede Ähnlichkeit mit einer realen Person wäre zufällig und würde dazu führen, dass das Asset verworfen wird.

## Rechtsstatus

Ein rein KI-generierter Output ist kein urheberrechtlich geschütztes Werk (US-, EU- und FR-Rechtsprechung konvergieren 2026 — kein menschlicher Autor im rechtlichen Sinne). Niemand kann diese Hintergründe daher als gestohlen reklamieren, und der Maintainer beansprucht kein geistiges Eigentum daran.

Die App als Ganzes (Code, redaktioneller Inhalt, Komposition) bleibt unter **PolyForm Noncommercial 1.0.0**, was auf die Komposition und die Software zutrifft, nicht aber auf die KI-Hintergründe für sich genommen.

## Generierungsprotokoll

Der Maintainer führt ein **lokales** Protokoll der Generierungsparameter (Checkpoint, LoRAs, Prompt, Seed, Sampler, Steps) für jedes gebündelte Asset. Dieses Protokoll existiert in zwei Formen:

1. **In die originalen ComfyUI-Dateien eingebettete Metadaten** (unkomprimierte PNG / webp) — von ComfyUI automatisch eingebettet.
2. **Optionales lokales JSON-Manifest** zum Durchsuchen.

Diese Protokolle werden nicht veröffentlicht (nicht im Repo, nicht im verteilten R2-Bucket). Sie ermöglichen die Reproduktion eines Assets bei Bedarf und dokumentieren die Generierungskette.

## Externe Beiträge

Hintergrundbeiträge von Drittanbietern werden derzeit **nicht akzeptiert** — eventuelle spätere Öffnung mit einem dedizierten Verifizierungsprozess. Siehe [`ASSET_CONTRIBUTIONS.md`](ASSET_CONTRIBUTIONS.md) für Audio-Beiträge.
