# Changelog

Évolutions notables de BeatBitch. Format inspiré de [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/) ; versionnage type SemVer (`MAJEUR.MINEUR.CORRECTIF`).

## [Non publié]

## [0.3.0] — 2026-05-14

Nouvelle plateforme Linux, refonte de la progression carrière (capabilities, milestones overdue/aging/level-gated, deux body milestones sur les séances longues), horloge de séance et une grosse vague de polish sur le mode Custom.

### Ajouté
- **Build Linux x64 portable** — la release publie maintenant un `tar.gz` Linux à côté de l'APK Android et du zip Windows. Voix TTS via `flutter_tts` sur le moteur du système (`speech-dispatcher`/`espeak-ng`). Caméra des holds et notifications surprise désactivées sur Linux comme sur Windows.
- **Horloge de séance optionnelle** — un compteur de temps restant peut désormais s'afficher pendant la séance, togglable depuis les réglages. Format adaptatif `mm:ss` / `h:mm:ss`.
- **Tags dans les noms de fichiers de fonds** — le sélecteur de background lit des tags suffixés dans le nom (`bg_xxx__mode-hand_phase-warmup.jpg`) et priorise les fonds qui matchent le contexte courant de la séance. Sans tag, fallback identique à avant.
- **Bornes BPM et hold dans l'éditeur Custom** — l'éditeur de config Custom affiche et applique des plafonds clairs pour BPM cible et durée de hold, alignés avec le runtime.
- **Gating des milestones par profil de capacités** (passe 2) — les milestones de mi-/fin de carrière (rythme soutenu, holds gorge/full, gorge en mouvement, tempo extrême, supplique throat/full, biffle rapide…) ne tombent plus que si la joueuse a *prouvé* la capacité physique correspondante (hold throat tenu N s, biffle tenu N s, BPM franchi en throat…). Le `level` reste comme plancher mou, c'est la télémétrie qui pilote l'apparition.
- **Level-up gaté par acquittement de milestone** — la montée de niveau attend que la dernière milestone soit reconnue par la joueuse, pour éviter de sauter par-dessus une étape clé.
- **Milestones overdue priorisées** — quand une milestone tarde anormalement à tomber, le sélecteur la pousse en haut de file pour rattraper le retard de progression.
- **Deux body milestones par séance ≥ 18 min** — les séances longues n'oubliaient plus d'insérer assez de jalons « corporels » ; double dose sur les longues sessions.
- **Tri milestone avec vieillissement de candidature** — à match équivalent, les milestones candidates depuis longtemps remontent dans la file.
- **Tri « branche-la-plus-basse »** — à match spé égal, le sélecteur de milestone favorise désormais celle dont la branche la moins investie chez la joueuse est plus basse, pour étaler la progression au lieu d'empiler dans un seul couloir.
- **Notifications surprises** — l'icône qui ouvre les réglages des notifs surprise (Android) est maintenant débloquée par une milestone dédiée `intro_surprise_notifs` au lieu d'un palier de niveau brut.

### Modifié
- **Caps statiques relâchés en finale** — les plafonds en fin de séance ne bornent plus artificiellement le runtime ; c'est désormais le profil de confort qui pilote, ce qui permet aux séances d'aller plus loin quand la joueuse encaisse, et de redescendre proprement sinon.
- **Nettoyage des déblocages carrière** — chaque milestone débloque désormais exactement une chose, et chaque déblocage a un effet concret (gate d'action, comportement, ou commentaire coach). Conséquences :
  - La branche de spécialisation **Résilience** est retirée (l'Endurance couvre déjà « tenir quand c'est dur »). Les points investis dans Résilience par les joueuses existantes sont automatiquement reversés au pool libre à réattribuer. Les mini-punitions inopinées en cours de séance ne dépendent plus d'une branche de spé mais de la **personnalité du coach** (un coach brutal/sans pitié en glisse beaucoup plus qu'une coach bienveillante).
  - Les milestones « couleur » sloppy `intro_sloppy_loud_suck`, `intro_sloppy_overflow` et `intro_sloppy_spit` débloquent maintenant chacune un sous-pool de commentaires coach dédié (« fais du bruit », « laisse déborder », « crache sur ma queue ») — ces deux derniers ne sortant que quand la bouche est effectivement pleine de salive.
  - 4 milestones Résilience et la milestone `intro_combo_hold_full` (combos pas encore implémentés) sont retirées du pool de carrière.
  - La milestone tutoriel `intro_basics` débloque une clé `basics` unique, prérequis des milestones de premier palier de chaque piste ; les actions de base (main, lick superficiel, rythme tip→head, holds tip/head) sont ouvertes par défaut sans clé.

### Corrigé
- **Phrases coach incohérentes après le chime / pendant un hold** — les phrases qui pouvaient sortir hors-contexte juste après un chime ou en pleine apnée sont désormais filtrées correctement.
- **Désync voix / texte / action** — synchronisation des trois canaux durcie en séance.
- **Boosts Custom qui ignoraient la dose hand** — les boosts respectent maintenant le réglage de dose `hand` choisi dans la config.
- **Mode Custom — save & launch silencieux** — un `setState` recevait un `Future`, ce qui faisait silencieusement échouer la sauvegarde et le lancement d'une config. Les erreurs sont maintenant visibles et la cause racine est corrigée.
- **Compteur de throatfucks** — les retours en bouche depuis la gorge ne sont plus comptés comme un throatfuck supplémentaire dans les stats.
- **Custom — dose `none` exclut vraiment le mode** — choisir `none` sur un mode dans Custom n'aboutissait pas toujours à 0 occurrence ; le scénario généré respecte désormais strictement le choix.
- **Custom — apothéose Extrême retombait sur « branler »** — l'apothéose du palier Extrême en Custom pouvait tomber sur de la main au lieu du hold attendu.
- **Halo final sur Phase 2 de carrière** — le halo de fin de séance restait monté sur le panel Phase 2 et nuisait à la lisibilité.
- **Milestone `intro_biffle` à 45 BPM** — démarre plus lentement, pour laisser le temps d'apprendre le geste avant d'accélérer.
- **`intro_fake_breath` requiert `throat_pulse`** — le faux souffle, qui s'appuie sur un rythme throat, ne peut plus se débloquer sans la milestone rythme throat correspondante.
- **« tiens / hold / halten » hors pools hold** — les phrases « tiens » dans `randomComments` et `branchPhrases.endurance` étaient lues hors pool hold et pouvaient donner un ordre de hold en plein rythme. Reformulées en « encaisse / endure / keep going / durchhalten ».

### Plateformes
- Android (APK signé, side-load) + Windows desktop (zip portable) + **Linux desktop (tar.gz portable, nouveau)**.

## [0.2.1] — 2026-05-12

Ajout de l'allemand (3ᵉ langue) et regroupement des réglages perso dans l'écran Profil.

### Ajouté
- **Localisation allemande complète** — l'app est désormais livrée en FR + EN + DE : UI (`app_de.arb`), phrases coach système, contenu éditorial (surnoms, punitions, commentaires aléatoires, ambiances), banque de phrases carrière, overrides texte des 37 milestones, les 6 packs de coachs et les 4 sessions scénario. `de` ajouté à `kSupportedLocales` + voix TTS allemandes préférées. Le sélecteur de langue, le repli système et l'offre « disponible en X » s'adaptent automatiquement.

### Modifié
- Le sélecteur de langue et les réglages de la voix par défaut (voix TTS, vitesse, hauteur, bouton « Tester ») sont passés de l'écran SONS à l'écran Profil — regroupés avec le prénom et les surnoms, plus accessibles. L'écran SONS garde les démos de bips, le pack d'ambiance et la section Debug.

### Corrigé
- Le sélecteur de langue affichait « DE » au lieu de « Deutsch » (table de libellés dupliquée et incomplète dans le dropdown).

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

[Non publié]: https://github.com/bbstudioapp/beatbitch/compare/v0.2.1...develop
[0.2.1]: https://github.com/bbstudioapp/beatbitch/releases/tag/v0.2.1
[0.2.0]: https://github.com/bbstudioapp/beatbitch/releases/tag/v0.2.0
[0.1.3]: https://github.com/bbstudioapp/beatbitch/releases/tag/v0.1.3
[0.1.2]: https://github.com/bbstudioapp/beatbitch/releases/tag/v0.1.2
[0.1.1]: https://github.com/bbstudioapp/beatbitch/releases/tag/v0.1.1
[0.1.0]: https://github.com/bbstudioapp/beatbitch/releases/tag/v0.1.0
