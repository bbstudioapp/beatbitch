# Changelog

Évolutions notables de BeatBitch. Format inspiré de [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/) ; versionnage type SemVer (`MAJEUR.MINEUR.CORRECTIF`).

## [Non publié]

## [0.4.1] — 2026-05-17

Correctif ciblé d'un blocage de progression carrière apparu après l'update v0.4.0.

### Corrigé
- **Bloqué au niveau 9 en boucle (post-update v0.4.0)** — pour les joueuses sans la zone `balls` (`hasBalls=false`) et qui n'ont pas consolidé `biffle.streak ≥ 10`, le calcul de fin de séance de `hasPendingAtCurrentLevel` n'appliquait pas le filtre anatomy alors que le calcul de début de séance le faisait. Conséquence : la milestone `intro_balls_lick` (niveau 9) restait fantôme dans le pool « pending » au moment du check level-up, bloquant le passage au niveau 10 indéfiniment alors que la séance se jouait sans contenu de palier insérable. `session_screen._recordCareerCompletion` propage désormais `anatomy` à `MilestoneService.pendingFor` pour rester cohérent avec le start ; test de régression dédié + garde-fou statique contre régression silencieuse.

## [0.4.0] — 2026-05-16

Nouvelle plateforme **Web / PWA installable iOS** (canal officiel iOS, App Store hors-jeu), introduction de la 6ᵉ position `balls` avec son anatomie associée, nouveau mode bouche **`suckle`** (aspirer / téter), TTS Linux passé au neuronal Piper, et une vague de fixes audio + voix + UI Custom.

### Ajouté
- **Plateforme Web (PWA installable iOS)** — la version web est désormais le canal officiel d'install iOS (l'App Store est hors-jeu pour ce contenu). PWA installable depuis Safari iOS, déploiement automatique sur `beatbitch.pages.dev` via GitHub Actions (workflow `web-deploy.yml`) sur push `main`. Guides d'installation iOS multilingues FR/EN/DE intégrés au repo (`docs/`).
- **Position `balls`** — 6ᵉ niveau de profondeur (zone latérale, pas un cran de profondeur supplémentaire) accompagnée d'un `AnatomyProfile` qui filtre le contenu selon l'anatomie du partenaire. Le ladder visuel passe à 6 lignes, les fonds reconnaissent `balls` comme tag de position.
- **Milestones `balls`** — nouveau jeu de milestones carrière dédiées à la position balls, avec révélation progressive du ladder hors-carrière dès que l'anatomie le permet.
- **Mode `suckle` (aspirer / téter)** — 3ᵉ mode bouche dédié à côté de rhythm/lick/hold. Chaîne pédagogique : `hold_head` débloque `suckle_head`, et `suckle_balls` ne dépend que de `hold_balls` (pas de prérequis profondeur — c'est de la stimulation locale).
- **Pool de phrases coach `suckle`** FR/EN/DE pour les steps gobe (tous les coachs concernés).
- **TTS Linux neuronal** — `piper` (modèles neuronaux locaux) en priorité, repli sur `spd-say` (Speech Dispatcher) si Piper n'est pas dispo. Qualité de voix nettement meilleure que `espeak-ng` sur les distros qui ont Piper installé.

### Modifié
- **Branches `balls` retirées de l'axe profondeur** — `balls` est traitée comme une zone latérale, pas comme un cran de profondeur plus grand que `full`. Les milestones balls ne consomment plus le levier profondeur du profil de capacités.

### Corrigé
- **Throat beep manqué après resume** — sur les samples longs (throat / full), `seek(0)` est désormais appelé avant `resume()` pour garantir que le bip rejoue depuis le début même quand le sample précédent n'est pas complètement terminé.
- **Boutons de session Custom peu réactifs sous Linux** (issue #85) — les boutons play/stop répondent maintenant immédiatement sur la version desktop Linux.
- **Mode Custom — suckle / balls / fallback** — le mode `suckle` est désormais correctement tiré par `_mapDifficultyToStep` avec clamp de profondeur balls et fallback safe ; la position est tenue correctement entre les steps, la révélation balls fonctionne hors carrière, et la couleur du mode est distincte des autres.
- **TTS vitesse / langue** — la vitesse TTS est normalisée par plateforme (Android / Windows / Linux ont des baselines différentes) et `setLocale` est désormais partagé entre la voix par défaut et les coachs.
- **Sélecteur de voix dans le Profil** — le dropdown des voix se rafraîchit immédiatement au changement de langue (au lieu de garder l'ancienne liste).
- **Milestones — overrides de langue ignorés pour la langue native** — les overrides texte des milestones étaient appliqués même quand la langue cible est la langue native du JSON source, ce qui pouvait écraser une variante locale par sa version anglaise. Le merge skip désormais quand `lang == native`.
- **« Tester la voix » lit toujours la phrase de test** (closes #75) — le bouton ne se contentait plus de lancer un sample générique : la phrase de test localisée est désormais lue à chaque appui. Bonus : la résolution du prénom dans la phrase est déterministe.
- **`_TrajectoryPainter` respecte `rowCount`** — l'alignement vertical du curseur restait calé sur 5 lignes même après l'ajout de la 6ᵉ position. Corrigé pour tout `rowCount` arbitraire.
- **CI release-linux** — passe sur `ubuntu-24.04` (au lieu de `ubuntu-22.04` EOL) et est désormais retriggerable manuellement via `workflow_dispatch` pour rejouer un build Linux/Windows raté sans rebump de version.

### Plateformes
- Android (APK signé, side-load) + Windows desktop (zip portable) + Linux desktop (tar.gz portable) + **Web / PWA installable iOS (nouveau, `beatbitch.pages.dev`)**.

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

[Non publié]: https://github.com/bbstudioapp/beatbitch/compare/v0.4.1...develop
[0.4.1]: https://github.com/bbstudioapp/beatbitch/releases/tag/v0.4.1
[0.4.0]: https://github.com/bbstudioapp/beatbitch/releases/tag/v0.4.0
[0.3.0]: https://github.com/bbstudioapp/beatbitch/releases/tag/v0.3.0
[0.2.1]: https://github.com/bbstudioapp/beatbitch/releases/tag/v0.2.1
[0.2.0]: https://github.com/bbstudioapp/beatbitch/releases/tag/v0.2.0
[0.1.3]: https://github.com/bbstudioapp/beatbitch/releases/tag/v0.1.3
[0.1.2]: https://github.com/bbstudioapp/beatbitch/releases/tag/v0.1.2
[0.1.1]: https://github.com/bbstudioapp/beatbitch/releases/tag/v0.1.1
[0.1.0]: https://github.com/bbstudioapp/beatbitch/releases/tag/v0.1.0
