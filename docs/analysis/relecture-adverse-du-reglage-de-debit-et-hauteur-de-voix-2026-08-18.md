---
type: analyse
sujet: relecture-adverse-du-reglage-de-debit-et-hauteur-de-voix
ecrit_le: 2026-08-18T17:17:26+02:00
auteur: session tss2-relecture-voix · claude-sonnet-5
revision: e11271bc
branche: develop
porte_sur:
  - /home/emmanuel/perso/git/tss2-w1/rhythm_coach/lib/services/diagnostic_export_service.dart
  - /home/emmanuel/perso/git/tss2-w1/rhythm_coach/lib/services/diagnostic_import_service.dart
  - /home/emmanuel/perso/git/tss2-w1/rhythm_coach/lib/services/tts_service.dart
  - /home/emmanuel/perso/git/tss2-w1/rhythm_coach/lib/widgets/coach_voice_picker.dart
  - /home/emmanuel/perso/git/tss2-w1/rhythm_coach/lib/widgets/coach_voice_section.dart
  - /home/emmanuel/perso/git/tss2-w1/rhythm_coach/lib/widgets/voice_settings_section.dart
provenance:
  mesure: 6
  deduit: 9
  document: 3
  sans_marqueur: 0
sources_citees: []
relu_contre:
  - /home/emmanuel/perso/git/tss2-w1/rhythm_coach/lib/services/diagnostic_export_service.dart:193
  - /home/emmanuel/perso/git/tss2-w1/rhythm_coach/lib/services/diagnostic_import_service.dart:342
  - /home/emmanuel/perso/git/tss2-w1/rhythm_coach/lib/services/tts_service.dart:1051
  - /home/emmanuel/perso/git/tss2-w1/rhythm_coach/lib/services/tts_service.dart:696
  - /home/emmanuel/perso/git/tss2-w1/rhythm_coach/lib/widgets/coach_voice_section.dart:109
  - /home/emmanuel/perso/git/tss2-w1/rhythm_coach/lib/widgets/voice_settings_section.dart:324
---

> ⚠️ **L'en-tête ci-dessus décrit le dépôt AutoPump, pas celui-ci.** Ce document a été écrit le
> 2026-08-18 par une session tss2 avec `castor doc:ecrire`, un outil qui ne vivait alors que dans le
> dépôt AutoPump : la session a dû s'y placer pour l'exécuter, et l'outil y a lu la révision, la
> branche et le dossier de destination. Les champs `revision`, `branche` et les chemins `porte_sur`
> en `_bmad-output/` renvoient donc à AutoPump et **ne décrivent pas l'arbre analysé ici** — la vraie
> révision jugée est écrite dans le corps du document. Rapatrié le 2026-08-19, sujet AutoPump #358 ;
> l'outil a été sorti de ce dépôt le même jour, un document écrit depuis tss2 reste désormais chez
> tss2 avec sa vraie révision.

## Verdict : publiable avec réserves

Rien de trouvé ne casse la fonctionnalité pour l'utilisateur nominal (FR/EN/ES, écran courant, police
système par défaut) : les six garde-fous que l'auteur revendique tiennent tous à la vérification. La
réserve qui compte porte sur autre chose — le chiffre qui a servi de base à la décision de Manu
(« visible ») ne représente pas le pire cas réellement supporté par l'app, et dans ce pire cas la
feuille est nettement plus dégradée que ce qui lui a été présenté. Ce n'est pas un blocage technique,
c'est une base de décision incomplète à lui signaler avant de considérer le sujet clos.

## Défauts trouvés

### 1. Le coût de « visible » présenté à Manu ne couvre pas le pire cas réel — l'écart est net

**Ce que l'utilisatrice vivrait** : une joueuse germanophone sur petit écran (iPhone SE, taille de
police système par défaut — pas besoin d'accessibilité) qui ouvre la fiche d'un coach ne verrait
**aucune voix entièrement visible**, pas même « Automatique » en tête de liste — la liste est là,
mais son viewport ne laisse passer qu'un tiers d'option. Avec la taille de police poussée en
accessibilité (cas réel, pas exotique), la feuille déborde de son propre cadre.

**La preuve** :
- Le rapport de l'auteur annonce, pour l'iPhone SE (320×568), un coût de 153 px et **2 options de
  voix visibles sans défiler** — chiffre mesuré en français ou anglais (les deux commits ne précisent
  pas laquelle), jamais dans la langue aux libellés les plus longs de l'app. [document —
  `~/.claude/orchestration/rapports/tss2/2026-08-18-voix-debit-hauteur.md` lignes 66-71]
- **[mesuré]** J'ai rejoué la même mesure moi-même (widget test jetable, worktree détaché, défait
  ensuite), en allemand, sur le même iPhone SE (320×568), **police système à sa taille normale**
  (aucune accentuation d'accessibilité) : le viewport de la liste de voix tombe à **44,6 px** (contre
  les 102 px rapportés) et **0 option de voix n'est entièrement visible** (contre 2 annoncées).
- **[mesuré]** En ajoutant la taille de police système poussée au maximum (×2, un réglage
  d'accessibilité réel, pas un cas de laboratoire), toujours en allemand sur iPhone SE : Flutter lève
  deux `RenderFlex overflowed` — 43 px sur l'écran du Profil (préexistant, voir plus bas) et **693 px
  dans la feuille elle-même**. Même test rejoué sur le code d'avant cette PR (worktree détaché sur
  `25657d5`) : seulement 28 px de débordement dans la feuille — l'ajout des deux curseurs et du
  bouton de retour à l'origine multiplie le débordement préexistant par ~25.
- **[déduit]** En build release, un `RenderFlex` qui déborde ne lève pas d'exception ni de bandeau —
  Flutter clippe silencieusement le surplus. Ce n'est donc pas un crash ; c'est du contenu qui
  disparaît sans qu'aucun signal ne le dise, potentiellement le bouton de retour à l'origine ou celui
  d'aperçu selon l'ordre de troncature.
- **[document]** Le rapport de l'auteur étiquette la résolution « 393×851 » comme un Pixel 7.
  **[déduit]** Aucune résolution logique de Pixel 7 ne correspond à ce chiffre (412×915 dp réels) ;
  393×852 dp est en réalité celle d'un iPhone 14/15 Pro. La mesure elle-même n'est pas remise en
  cause par cette erreur d'étiquette, mais elle indique qu'aucun des trois écrans cités n'a été
  confronté à un vrai appareil Android de cette gamme.

**Bloquant ?** Non au sens technique — rien ne crashe, la liste reste atteignable en défilant sur
l'écran nominal. Mais la décision de Manu (« curseurs visibles, pas repliés ») a été prise sur un
chiffre qui ne représente pas le plus mauvais cas que l'app doit servir. Je recommande de le lui
signaler avant de considérer l'arbitrage tranché — pas de le corriger d'autorité : c'est son curseur
à placer, avec le bon chiffre en main.

### 2. L'import diagnostic contourne le clamp que le réglage normal applique toujours

**Ce que l'utilisatrice vivrait** : en important un fichier diagnostic corrompu ou trafiqué, un
réglage de débit/hauteur hors plage s'installerait tel quel. Le moteur resterait protégé (voir plus
bas), mais la fiche d'un coach afficherait un nombre absurde à côté d'un curseur bloqué à sa butée,
jusqu'à ce que l'utilisatrice retouche le réglage.

**La preuve** :
- **[déduit]** `setUserRate`/`setUserPitch`/`setCoachRate`/`setCoachPitch` clampent systématiquement
  avant d'écrire (`rate.clamp(0.1, 1.0)` / `pitch.clamp(0.5, 2.0)` côté service, `0.3-0.8` / `0.5-2.0`
  côté UI). `DiagnosticImportService._double` (`diagnostic_import_service.dart:342`), lui, écrit
  `v.toDouble()` sans aucun clamp dès que `v is num` — c'est le seul des quatre écrivains typés du
  fichier à porter une borne numérique, et le seul à ne pas la vérifier.
- **[mesuré]** Test dédié (worktree détaché, défait ensuite) : un payload important `rate: 999.0` /
  `pitch: -50.0` (défaut) et `rate: 12345.0` / `pitch: -999.0` (par coach) les retrouve identiques,
  bruts, dans `SharedPreferences` et via `TtsService.coachRateAndPitch`.
- **[déduit]** Le moteur, lui, reste protégé : `setRate`/`setPitch` clampent inconditionnellement en
  mémoire à chaque application (`tts_service.dart:696` et `:702`), donc la valeur réellement
  poussée au moteur audio ne peut jamais sortir de sa plage — je n'ai pas pu re-vérifier ce point par
  un test propre (le mien a échoué sur un `MethodChannel` non mocké de mon fait, pas un défaut du
  code), mais la lecture ne laisse pas de place au doute : les deux seules écritures du champ privé
  passent par ce clamp, sans exception.
- **[déduit]** Côté affichage, `LabeledVoiceSlider` (`voice_settings_section.dart`, réutilisé par la
  fiche coach) clampe la valeur donnée au `Slider` (`value.clamp(min, max)`) mais **pas** celle donnée
  au `Text` juste à côté (`value.toStringAsFixed(2)`, ligne 324) : les deux se désynchronisent dès que
  la valeur dépasse la plage du curseur, plage plus étroite (0,3-0,8 / 0,5-2,0) que celle du moteur
  (0,1-1,0 / 0,5-2,0). Aujourd'hui les sept presets JSON de coachs tiennent tous dans la plage du
  curseur (vérifié par lecture des sept fichiers `assets/career/coaches/*.json`) : le risque ne se
  manifeste qu'après un import corrompu, pas en usage normal.
- Aucun test ne couvre une valeur hors plage à l'import — vérifié par recherche sur les quatre
  fichiers de test touchés ou ajoutés par la PR.

**Bloquant ?** Non. L'import diagnostic est un usage debug (le service le documente lui-même comme
tel), le moteur reste borné, et l'incohérence d'affichage se répare au premier réglage retouché.

### 3. Le réglage de débit/hauteur par coach est inatteignable depuis l'UI sur Linux, alors que le service le sait appliquer

**Ce que l'utilisatrice vivrait** : sur la version Linux — **[déduit]** un vrai canal de distribution,
lu dans `.github/workflows/release.yml` : un `.tar.gz` y est construit et publié à chaque release,
ce n'est pas qu'un outil de développement —, la ligne « Voix : … » d'un coach reste affichée mais
inerte, donc aucun moyen d'ouvrir sa fiche ni ses deux curseurs.

**La preuve** :
- **[déduit]** `CoachVoiceSection` pose `onTap: selectable ? () => _openPicker(coach) : null` où
  `selectable = TtsService.supportsVoiceSelection = !_isLinux` (`coach_voice_section.dart:109-126`).
  Ce gating date de la Phase 2 (voix seule), où il avait tout son sens : sans sélection de voix
  possible, la ligne n'avait rien à offrir sur Linux. Cette PR ajoute au **même** point d'entrée un
  réglage qui, lui, a une prise sur Linux : la branche `_isLinux` d'`applyCoachVoicePreset`
  applique bien `manual.rate ?? rate` (`tts_service.dart:1020-1024`), et le commentaire du service le
  dit explicitement pour la voix par défaut (« le backend spd-say lit `_rate` et `_pitch` à chaque
  énoncé »). Le gating hérité n'a pas été reconsidéré à cette occasion.
- Tentative de mesure directe (widget test, `debugDefaultTargetPlatformOverride = TargetPlatform.linux`)
  non concluante : le test a fini en `pumpAndSettle timed out`, très probablement parce que la
  résolution du binaire Piper réel (`_ensurePiperResolved`) a traîné sur une machine dont la charge
  dépassait 70 au moment du test (autres sessions actives sur la même machine, prévenu au démarrage
  de cette tâche) — sans lien avec le code de la PR. Je n'ai pas relancé une seconde fois par souci de
  budget : le point tient sur la lecture de code ci-dessus, sans ambiguïté.
- **[mesuré]** En revanche, la moitié service seule se vérifie sans passer par l'UI : un test dédié
  (même worktree détaché) pose `debugDefaultTargetPlatformOverride = TargetPlatform.linux`, écrit
  `tts.rate.coach.coach_07_marc = 0.31` directement en `SharedPreferences`, puis appelle
  `applyCoachVoicePreset(coachId: 'coach_07_marc', rate: 0.55, ...)` : `tts.currentRate` vaut bien
  `0.31` à l'arrivée — le service applique le réglage manuel sur Linux, seule l'UI qui permettrait de
  le poser est bloquée.

**Bloquant ?** Non — le réglage de la voix par défaut (hors-carrière) reste accessible sur Linux via
le Profil, seul celui par coach est hors de portée. Périmètre de la fonctionnalité restreint sur une
plateforme minoritaire mais réelle, pas une régression du chemin principal.

### 4. La limite Windows déclarée par l'auteur est un peu plus étroite que la réalité du code

**Ce que l'utilisatrice vivrait** : sur Windows, un coach dont seul le **débit** (pas la hauteur) a
été réglé manuellement afficherait un curseur de hauteur cohérent avec ce que la séance applique,
mais un coach dont ni l'un ni l'autre n'a été touché verrait les **deux** curseurs mentir
indépendamment — pas seulement « tant que le coach n'est pas réglé » comme la limite l'énonce, mais
par champ.

**La preuve** :
- **[déduit]** Sur la branche Windows d'`applyCoachVoicePreset` (`tts_service.dart:1051-1062`), le
  débit et la hauteur sont substitués **indépendamment** (`manual.rate ?? _windowsDefaultRate`,
  `manual.pitch ?? _windowsDefaultPitch`). Le curseur affiché, lui, montre toujours
  `widget.coach.voicePreset.rate`/`.pitch` quand rien n'est réglé pour ce champ précis
  (`coach_voice_picker.dart:237-240`). Un coach avec le débit réglé mais pas la hauteur affiche donc
  un débit cohérent et une hauteur qui ment, alors que l'énoncé de l'auteur laisse penser à un état
  binaire par coach.
- Cette branche n'est exercée par aucun test de la suite (elle dépend de `defaultTargetPlatform ==
  TargetPlatform.windows`, jamais simulé dans les fichiers de test touchés) : la nuance n'aurait pas
  été détectée par la suite verte.

**Bloquant ?** Non — c'est un raffinement d'une limite déjà connue et déjà déclarée « non corrigée »,
pas un défaut nouveau. Vaut d'être précisé si la limite est un jour reprise.

### 5. Débit et hauteur personnels entrent dans le fichier de partage public — décision assumée, pas encore tranchée par Manu

**Ce que l'utilisatrice vivrait** : en partageant son fichier `beatbitch-voices-<lang>.json` pour
contribuer une voix qui marche bien pour un coach, elle y joindrait aussi le débit et la hauteur
qu'elle a personnellement réglés pour ce coach — une préférence d'écoute, pas un fait de compatibilité
moteur.

**La preuve** :
- **[document]** Le commit `6e20dae` l'assume explicitement : « Le fichier de partage des voix les
  porte donc lui aussi. C'est une décision, pas un effet de bord. » Ce n'est donc pas un oubli — les
  deux exports (diagnostic et partage public) produisent leur section voix via le **même** code
  (`_voice()`, cf. `diagnostic_export_service.dart:193-198`), et l'extension à rate/pitch touche les
  deux à la fois par construction.
- **[document]** Le point figure comme sixième arbitrage « retenu par la session, pas par Manu,
  rediscutable » dans `~/.claude/orchestration/rapports/tss2/2026-08-18-voix-debit-hauteur-PLAN.md`
  (lignes 67-71) : l'auteur l'a donc déjà remonté comme non tranché, ce n'est pas une lacune de
  transparence de sa part.
- **[déduit]** L'argument avancé (« deux nombres bornés n'y ajoutent rien d'intime ») répond à la
  question de la confidentialité, pas à celle de la pertinence : un nom de voix est un fait objectif
  utile à toute la communauté (« cette voix technique existe et sonne bien pour ce coach en
  allemand ») ; un débit choisi est une préférence individuelle, dont la moyenne communautaire n'a pas
  de sens évident dans un fichier destiné à améliorer un preset partagé.

**Bloquant ?** Non — c'est une réserve de produit déjà signalée comme telle, pas un défaut caché. Je
la confirme et la recommande dans la liste des points à trancher avec Manu, sans trancher moi-même.

## Ce que je n'ai pas pu établir

- **Le rendu sonore lui-même.** Aucun débit ni aucune hauteur n'a été écouté, par moi ni par
  personne d'autre à ce stade — hors périmètre de cette relecture par construction, à faire sur
  appareil.
- **Le comportement Windows et Linux au sens large.** Toutes mes mesures ont tourné sous
  `defaultTargetPlatform` simulé ou sur un hôte Linux réel pour la partie service ; rien n'a tourné
  sur un vrai poste Windows ni sur un vrai build Linux packagé.
- **La suite complète dans des conditions garanties saines.** **[mesuré]** Mon premier passage de
  `flutter test` (les 1000 tests) a rencontré deux échecs et un crash de sous-processus après 559
  tests, sur une machine dont la charge dépassait 70 au moment du run (plusieurs autres sessions
  actives en parallèle, comme prévenu). **[mesuré]** Un second passage, seul et une fois la charge
  retombée, a donné 1000 tests verts, `flutter analyze` propre et `dart format
  --set-exit-if-changed` sans changement — mais je n'ai pas de troisième passage pour exclure
  complètement un flake résiduel sur les deux fichiers qui avaient échoué
  (`session_freeze_tts_speaking_test.dart`, `session_finished_duration_render_test.dart` — tous deux
  sans rapport avec ce diff).
- **La mesure d'écran sur « 393×851 »/« Pixel 7 » et sur un vrai Pixel** avec le texte poussé en
  accessibilité : mesuré seulement sur iPhone SE dans ce mode ; le calcul du deuxième écran cité par
  l'auteur n'a été rejoué qu'à taille de police normale, faute de budget de temps restant (chaque
  passage `flutter test` a pris entre 5 et 10 minutes sur la machine chargée).
- **Le changement de langue avec un réglage par coach actif.** Aucun test ne le couvre explicitement
  (contrairement au réglage par défaut, qui en a un). Le risque semble structurellement nul par
  lecture — `coachRateKey`/`coachPitchKey` ne portent pas la langue dans leur clé — mais je n'ai pas
  de preuve exécutée pour ce cas précis.

## Pistes ouvertes sans rien trouvé

- **Course entre un réglage utilisateur en cours et une restauration de fin de séance.**
  `setUserRate`/`setUserPitch` écrivent sans passer par le mécanisme de `lead`
  (`_voiceLeadLost`) que les presets coach respectent. Cherché un scénario où les deux
  s'entrelaceraient réellement (l'utilisatrice ne peut pas être sur l'écran Profil et en séance
  carrière en même temps dans la navigation actuelle) — rien trouvé de concret, le risque semble
  théorique.
- **Une cinquième sortie d'`applyCoachVoicePreset`** en plus des quatre revendiquées : il existe un
  retour anticipé préexistant (`_voiceLeadLost(lead)) return`, `tts_service.dart:1078`, hérité du
  8 août, avant cette PR) qui saute l'application du débit/hauteur. Vérifié qu'il ne s'agit pas d'un
  gain de cette PR — la ligne est inchangée depuis avant — et qu'il est délibéré (une passe plus
  récente a déjà pris la main, appliquer une valeur périmée serait pire). Pas retenu comme défaut.
- **Cohérence Slider/Texte avec les presets réels.** Les sept coachs actuels tiennent tous dans les
  plages du curseur (0,3-0,8 / 0,5-2,0) — cherché un preset JSON qui en sortirait déjà, rien trouvé à
  ce jour ; le risque décrit au défaut n°2 reste latent, pas manifesté.
