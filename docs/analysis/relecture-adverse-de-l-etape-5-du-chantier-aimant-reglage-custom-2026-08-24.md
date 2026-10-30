---
type: analyse
sujet: relecture-adverse-de-l-etape-5-du-chantier-aimant-reglage-custom
ecrit_le: 2026-08-24T23:37:23+02:00
auteur: session tss2-relecture-etape5 · claude-sonnet-5
revision: 0818615
branche: feat/aimant-battement-inegal
porte_sur:
  - rhythm_coach/lib/career/models/career_generation_inputs.dart
  - rhythm_coach/lib/career/models/custom_session_config.dart
  - rhythm_coach/lib/career/screens/custom_config_editor_screen.dart
  - rhythm_coach/lib/career/screens/custom_mode_screen.dart
  - rhythm_coach/lib/career/services/career_level_gates.dart
  - rhythm_coach/lib/career/services/generation/career_session_generator.dart
  - rhythm_coach/lib/career/services/generation/finish_phase.dart
  - rhythm_coach/lib/career/services/generation/session_config.dart
  - rhythm_coach/lib/models/session_step.dart
  - rhythm_coach/lib/services/beep_engine.dart
  - rhythm_coach/lib/services/custom_config_service.dart
  - rhythm_coach/lib/services/diagnostic_export_service.dart
provenance:
  mesure: 17
  deduit: 2
  document: 0
  sans_marqueur: 0
sources_citees: []
relu_contre:
  - rhythm_coach/lib/career/models/custom_session_config.dart:285
  - rhythm_coach/lib/career/models/custom_session_config.dart:452
  - rhythm_coach/lib/career/screens/custom_config_editor_screen.dart:134
  - rhythm_coach/lib/career/services/generation/career_session_generator.dart:2092
  - rhythm_coach/lib/career/services/generation/career_session_generator.dart:2100
  - rhythm_coach/lib/career/services/generation/finish_phase.dart:391
  - rhythm_coach/lib/models/session_step.dart:13
  - rhythm_coach/lib/services/beep_engine.dart:464
---

## Verdict

**Publiable avec réserves — aucune réserve bloquante sur le code.** Les six cibles de danger de la
mission ont été rejouées indépendamment (mesure fraîche, pas relecture du rapport) et aucune n'a
été réfutée. La seule réserve est celle que le rapport relu porte déjà lui-même : les trois ratios
(2/3/5) et le rendu à l'oreille n'ont jamais été entendus, par aucune des deux sessions. Ce n'est pas
un défaut de code, c'est un tuning non validé — à écouter avant de considérer le réglage fini pour
la joueuse.

## Ce qui a été rejoué, cible par cible

### 1. ⭐ Surcharge additive — confirmée par mesure indépendante fraîche

[mesuré] Le tableau des douze séances (quatre difficultés × trois graines) codé en dur dans
`custom_anchor_wiring_test.dart` a été recalculé à partir de zéro, sans lire ce tableau au
préalable : worktree Git dédié posé sur `65d47a7` (avant tout le chantier étape 5), harnais de test
reconstruit à la main avec la signature de `CustomOverrides` de ce commit (pas de champ `anchor`),
et impression brute des empreintes d'ancre. Les douze lignes obtenues sont identiques caractère pour
caractère à celles du fichier de test. La promesse « aimant éteint = ancres héritées des étapes 3/4,
inchangées » est donc vraie, pas seulement auto-cohérente avec HEAD.

### 2. ⭐ Compatibilité d'une config déjà enregistrée — confirmée par mutation

[mesuré] `fromJson` construit chaque champ explicitement plutôt que d'hériter du constructeur — le
défaut de `anchorEnabled` a été basculé de `false` à `true` dans le code, et le test « s'ouvre avec
l'aimant éteint » est tombé rouge sur la bonne assertion (`Expected: false / Actual: <true>`),
entraînant en cascade 6 autres échecs du même fichier. Mutation retirée, fichier revenu identique.

### 3. Recopies — confirmées par mutation et par grep

[mesuré] Deux mutations : retirer `anchorEnabled` de `copyWith` (7 rouges, dont l'écran qui
« rouvre sur ses réglages ») et retirer les trois champs de `_build()` dans l'éditeur (1 rouge
exact, sur le test qui bascule réellement les trois réglages). [mesuré] `grep` ne trouve aucune
construction de `CustomSessionConfig(` hors de son propre fichier, et les deux seuls `copyWith`
d'un `CustomSessionConfig` ailleurs dans le code (duplication de séance, `_build` de l'éditeur) ne
touchent jamais les champs d'ancre — ils héritent par le `?? this.champ` de `copyWith`. [mesuré]
Le service de persistance (`custom_config_service.dart`) et l'export diagnostic ne recopient jamais
les champs un par un : le premier passe exclusivement par `toJson`/`fromJson`, le second n'exporte
même pas le contenu des configs Custom (juste un compteur et le dernier id).

### 4. ⛔ Périmètre rhythm/hold — confirmé par un balayage nettement plus large que celui du rapport

Le test existant ne balayait que la difficulté « normal », 3 graines, cycle 0. [mesuré] Un balayage
propre à cette relecture a couvert les 4 difficultés × 2 points × 3 crans × 25 graines × 4 index de
cycle (pour couvrir aussi le non-stop, question que le rapport relu classait lui-même comme
« pas mesurée ») : **164 568 steps vérifiés, 0 avec une ancre ou un ratio ≠ 1 hors `rhythm`/`hold`.**
[mesuré] Une deuxième sonde ciblée a vérifié que le bpm d'un hold ancré vaut toujours exactement
`CareerLevelGates.holdFinalAnchorBpm` (60), jamais une valeur qui aurait fuité d'un draft antérieur
via le `bpm ??= …` du générateur — 18 420 holds ancrés vus, 0 suspects. [déduit] Ce risque était
réel sur le papier (`??=` ne pose la valeur que si `draft.bpm` était encore `null`) ; il ne se
matérialise dans aucun scénario balayé.

### 5. i18n — confirmée

[mesuré] `flutter gen-l10n` rejoué : aucun fichier généré ne change (`git status` vide après coup),
donc les fichiers `app_localizations_*.dart` commités sont bien à jour avec les quatre `.arb`.
[mesuré] Les 9 clés sont présentes dans `app_fr.arb`, `app_en.arb`, `app_es.arb`, `app_de.arb`
(36 entrées). [mesuré] `grep` sur les lignes ajoutées de l'écran éditeur ne trouve aucun `Text('…')`
littéral — tout passe par `AppLocalizations` ou `enum_labels.dart`.

### 6. Sondes ajoutées — déterminisme et mutations rejouées à l'identique

[mesuré] Les 18 tests (7 + 7 + 4, recomptés par `grep -c` des déclarations `test`/`testWidgets` dans
les trois fichiers) ont été rejoués trois fois de suite : 18 verts à chaque fois. [mesuré] Les
quatre mutations annoncées par le rapport relu ont été reposées indépendamment, avec les mêmes
comptes annoncés :

| mutation | attendu par le rapport | observé ici [mesuré] |
| --- | --- | --- |
| `customAnchor: null` (câblage overrides → génération coupé) | 3 rouges | 3 rouges, mêmes tests |
| `resolveAnchor()` rendant toujours `null` | 4 rouges | 4 rouges, mêmes tests |
| `_build()` de l'éditeur ne reportant plus les trois réglages | 1 rouge | 1 rouge, même test |
| `maxHoldDurationLimit` 120 → 110 (hors sujet) | vert | 18 verts (fichiers élargis) |

## Ce que j'ai corrigé moi-même

Rien. Aucune ligne exécutée n'a dû bouger — toutes les affirmations mesurables du rapport relu ont
résisté à une mesure indépendante.

## Rejeu des commandes obligatoires

[mesuré] `flutter analyze` → No issues found!. [mesuré] `dart format --set-exit-if-changed .` → 329
fichiers, 0 modifié. [mesuré] `flutter test` (rediriger vers fichier, jamais de pipe) → **1160
tests, tous verts**, en 1 min 30. [mesuré] L'écart de +18 s'explique fichier par fichier :
`custom_anchor_wiring_test.dart` (7) + `custom_session_config_anchor_compat_test.dart` (7) +
`custom_config_editor_anchor_test.dart` (4) = 18 ; [déduit] aucun fichier de test préexistant n'a
été modifié par ce chantier (confirmé par `git diff --stat` : les trois fichiers de test sont des
créations, rien d'autre sous `test/`), donc 1142 + 18 = 1160 sans ambiguïté.

## Ce que je n'ai pas pu établir

- **Comment ça sonne.** Aucun APK construit, aucune écoute — consigne de la mission. Les trois crans
  (2/3/5) restent des chiffres justifiés par leur position dans le code, jamais par une oreille.
- **Si « Dur » se distingue de « Moyen » à l'usage**, et si « Léger » s'entend du tout. Le balayage
  large confirme que le code fait ce qu'il dit ; il ne dit rien sur la perception.
- **Ce que le réglage donne sur une séance non-stop de plusieurs cycles, à l'oreille.** Le balayage
  large de cette relecture couvre le périmètre (rhythm/hold uniquement) et le bpm sur 4 index de
  cycle, mais seulement au niveau des steps produits — pas du ressenti d'un enchaînement réel.
- **Si le réglage devrait aussi couvrir la phase finish.** Confirmé que `finish_phase.dart` porte sa
  propre copie de `_draftToStep`, non modifiée, insensible à `customAnchor` — c'est une frontière
  volontaire du chantier, pas un oubli technique. Si elle est la bonne frontière reste une question
  pour Manu, pas une question de code.
