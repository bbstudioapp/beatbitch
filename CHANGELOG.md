# Changelog

Évolutions notables de BeatBitch. Format inspiré de [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/) ; versionnage type SemVer (`MAJEUR.MINEUR.CORRECTIF`).

## [Non publié]

### Ajouté
- **Localisation allemande complète** — l'app est désormais livrée en FR + EN + DE : UI (`app_de.arb`), phrases coach système, contenu éditorial (surnoms, punitions, commentaires aléatoires, ambiances), banque de phrases carrière, overrides texte des 37 milestones, les 6 packs de coachs et les 4 sessions scénario. `de` ajouté à `kSupportedLocales` + voix TTS allemandes préférées. Le sélecteur de langue, le repli système et l'offre « disponible en X » s'adaptent automatiquement.

## [0.2.0] — 2026-05-12

Grosse mise à jour du mode carrière : nouvelle enveloppe de difficulté, nouveau mode de jeu, voix des coachs étoffée.

### Ajouté
- **Profil de capacités (mode carrière)** — une 2ᵉ enveloppe de difficulté, orthogonale à l'humiliation/obéissance : des compteurs par pratique (profondeur, apnée, franchissement de gorge, vitesse, salive, souffle…) mesurent ce que la joueuse a *prouvé* tenir et adaptent la séance axe par axe. Le générateur cible la zone de confort prouvée, surcharge **un seul axe** par séance pour faire progresser, et borne tout le reste. Un « je peux pas » plafonne désormais la suite de la séance (pas de re-fail sur la même limite). Panneau « Capacités » dans le profil (les exploits, pas les réglages). Punitions carrière générées qui maximisent l'humiliation dans l'enveloppe prouvée. Phrases de progression rares chez certains coachs (tentative / record / abandon reconnu comme limite légitime).
- **Mode de jeu « Custom »** — 3ᵉ carte aux côtés de Carrière et Scénario : compose une séance paramétrable (durée ou non-stop, difficulté progressive, difficulté globale, dosage par mode, profondeur max, coach), éditeur de configs sauvegardées, halo de finale. Mode bac à sable : tout débloqué, aucune écriture de stats lifetime, pas de gating de capacités. Boutons « Termine-moi » (sprint final à la demande) et enchaînement automatique en non-stop.
- **Portraits des coachs** — un portrait par coach dans le sélecteur (Carrière + Custom) et sur la carte du coach actif ; repli stylisé si l'image n'est pas dans le build.
- Phrases des coachs étoffées : Lina, Hélène, Jade, Morgan, Victoria, Nyx (FR + EN), avec des phrases colorées par branche de spécialisation et les phrases de progression du profil de capacités.

### Modifié
- Animation de la séance : glissement smooth entre positions + courbe d'anticipation des beats, curseur calé exactement sur le bip (plus de drift visible en haut du spectre BPM), crossfade entre modes et pulse de bordure synchro.
- Tuning carrière : moins de `lick` dans la pondération ; `hand` retiré des finales normales dès le niveau 4 (reste fallback ultime).

### Corrigé
- Curseur d'animation calé sur le 1ᵉʳ bip du step (et non plus en avance) ; pool de bips élargi pour les steps qui combinent deux samples.
- Pitch TTS de Jade ramené (1.76 → 1.38) et retrait des `~` parasites de ses phrases.

### Plateformes
- Android (APK signé, side-load) + Windows desktop (zip portable). Inchangé depuis v0.1.3.

## [0.1.3] — 2026-05-10
- Build desktop Windows (zip portable, voix Microsoft Julie via SAPI). Caméra des holds et notifications surprise désactivées sur Windows.
- Doc multi-plateforme (`docs/DEVELOPMENT.md`), durcissement de l'analyse statique, workflow CI (format / analyze / validation des assets / tests + jobs sécurité).

## [0.1.2] — 2026-05-09
- Premiers fonds visuels animés, livrés via le bucket R2 (assets binaires hors dépôt).
- Section « Mises à jour automatiques (Obtainium) » dans le README, note de provenance des assets visuels.

## [0.1.1] — 2026-05-08
- Correctifs i18n : pack d'ambiance, streak quotidien, surnoms qui suivent la locale.

## [0.1.0] — 2026-05-08
- Premier release public : coach vocal rythmique hors-ligne pour Android, adult gate 18+, onboarding, mode carrière + scénarios, badges, profil/réputation.

[Non publié]: https://github.com/bbstudioapp/beatbitch/compare/v0.2.0...develop
[0.2.0]: https://github.com/bbstudioapp/beatbitch/releases/tag/v0.2.0
[0.1.3]: https://github.com/bbstudioapp/beatbitch/releases/tag/v0.1.3
[0.1.2]: https://github.com/bbstudioapp/beatbitch/releases/tag/v0.1.2
[0.1.1]: https://github.com/bbstudioapp/beatbitch/releases/tag/v0.1.1
[0.1.0]: https://github.com/bbstudioapp/beatbitch/releases/tag/v0.1.0
