---
type: analyse
sujet: relecture-adverse-etape-6-de-la-timeline-mini-points-de-trajectoire-hors-debug
ecrit_le: 2026-08-21T23:42:22+02:00
auteur: session tss2-relecture-etape6 · claude-sonnet-5
revision: 3f80a9c
branche: fix/courbe-continuite-visuelle
porte_sur:
  - rhythm_coach/android/app/build.gradle.kts
  - rhythm_coach/lib/career/services/debug_settings_service.dart
  - rhythm_coach/lib/screens/session_screen.dart
  - rhythm_coach/lib/screens/sound_demo_screen.dart
  - rhythm_coach/lib/widgets/movement_animation.dart
  - rhythm_coach/test/debug_settings_trajectory_dots_default_test.dart
  - rhythm_coach/test/movement_trajectory_dots_visibility_test.dart
provenance:
  mesure: 13
  deduit: 4
  document: 0
  sans_marqueur: 0
sources_citees: []
relu_contre:
  - rhythm_coach/android/app/build.gradle.kts:41
  - rhythm_coach/lib/career/services/debug_settings_service.dart:188
  - rhythm_coach/lib/screens/session_screen.dart:1128
  - rhythm_coach/lib/widgets/movement_animation.dart:1386
  - rhythm_coach/lib/widgets/movement_animation.dart:1405
---

*Relecture par `claude-sonnet-5` du travail de `claude-opus-5`. Consigne : chercher à réfuter, pas à
valider. Périmètre strict : le commit `67aa2c3` (`feat(animation): masquer les mini-points de
trajectoire hors debug`), `git diff 5f30d62..67aa2c3`. Choix esthétique tranché par Manu (« c'est
carrément plus joli », APK testé) — non rediscuté.*

## Verdict

**Publiable avec réserves.** Aucun bug fonctionnel trouvé dans le périmètre : le défaut `kDebugMode`
est correctement appliqué, la courbe et le curseur restent intacts dans les deux réglages, les 5
mutations annoncées par l'auteur tombent bien rouges sur la bonne assertion, et les traductions sont
complètes et cohérentes. Les réserves portent uniquement sur la couverture de test : le défaut
`kDebugMode` — seul de tout le service à ne pas être un littéral fixe — n'était verrouillé par aucune
sonde (corrigé dans cette relecture), et deux maillons de câblage restent non gardés avec un coût de
sonde jugé disproportionné (détail § 5).

## 1. Le défaut de la clé

**[mesuré]** `getShowTrajectoryDots()` (`debug_settings_service.dart:188-191`) fait
`prefs.getBool(_kShowTrajectoryDots) ?? kDebugMode` — ce n'est pas un `fromJson` ni un value-object
figé au parse, c'est un getter qui réévalue le fallback à chaque appel. Le piège du projet
(`feedback_fromjson_bypasses_constructor_default`) ne s'applique pas ici : il n'y a pas de
constructeur intermédiaire à contourner.

**[mesuré]** Sonde manuelle (écrite, exécutée, puis retirée avant tout commit) : sous `flutter test`,
`kDebugMode == true` et `getShowTrajectoryDots()` avec préférences vierges renvoie bien `true`. Une
clé écrite explicitement à `true` prime toujours sur `kDebugMode`, y compris quand celui-ci vaudrait
`false` (comportement normal d'un toggle persisté, pas un bug).

**[mesuré]** `android/app/build.gradle.kts` ne déclare aucun `applicationIdSuffix` pour `debug` — les
builds debug et release partagent le même `applicationId` (`com.beatbitch.app`). Une donnée
`SharedPreferences` écrite en debug (ex. via le switch de `sound_demo_screen.dart`) peut donc
survivre à une réinstallation en release.

**[déduit]** Ce n'est pas une régression introduite par ce commit : c'est le comportement de **tous**
les 12 autres toggles `debug.*`/`pref.*` du service — tous accessibles et modifiables en tout temps
depuis la section Debug de l'écran SONS, quel que soit le build type, comme documenté dans le
`CLAUDE.md` du projet (« Toggles d'affichage debug… exposés dans la section Debug de l'écran SONS »).
Le seul écart réel avec les 12 autres est le défaut *conditionnel* — les autres ont tous un défaut
fixe (`false` ou `true` en dur).

**[mesuré → corrigé]** Cet écart n'était verrouillé par aucun test, alors que le pattern de test
existe déjà pour un getter voisin du même service (`scripted_breaks_enabled_test.dart`, sur
`getScriptedBreaks`). Sonde rouge d'abord : j'ai muté `?? kDebugMode` en `?? false`, écrit
`test/debug_settings_trajectory_dots_default_test.dart` (3 cas : défaut vierge, valeur explicite
prioritaire, setter écrit sous la bonne clé), confirmé le rouge sur la bonne assertion (`Expected:
<true> / Actual: <false>`), puis restauré le code de production et confirmé le vert. Commit
`3f80a9c`.

## 2. La courbe est-elle bien tracée dans les deux cas ?

**[mesuré]** Lecture de `_TrajectoryPainter.paint()` en entier (`movement_animation.dart:1348-1394`) :
après `if (!showDots) return;`, il ne reste que la boucle des pastilles jusqu'à la fin de la méthode
— rien d'autre n'est dessiné après ce point, donc rien d'autre ne peut disparaître avec lui.

**[mesuré]** Un seul `CustomPaint`/`CustomPainter` existe dans tout le fichier
(`grep -n "CustomPaint\|class _.*Painter"` → une seule occurrence, `_TrajectoryPainter`). Le curseur
(`_CursorVisual`) est un `Align` + widget positionné séparément (`movement_animation.dart:1018-1021`,
`cursorAlignment` calculé indépendamment) — il n'est **pas** peint par ce `CustomPainter` et ne peut
donc pas être affecté par son early return. Confirmé par le test existant (« séance : le curseur
reste visible », `find.byType(Align)`), rejoué en vert (§4).

**[réfuté]** Aucun repère de frontière ni point fusionné de tête n'est peint par `_TrajectoryPainter`
au-delà de `drawPath` — je n'ai trouvé aucun élément additionnel dans ce fichier qui serait rendu par
ce painter après la ligne du early return.

## 3. `shouldRepaint`

**[mesuré]** `old.showDots != showDots` a bien été ajouté à la condition (`movement_animation.dart:
1405`). Mutation : je l'ai retiré, relancé `test/movement_trajectory_dots_visibility_test.dart` →
**les 3 tests passent quand même** (vert, non détecté). Restauré immédiatement.

**[déduit]** Ce n'est pas un bug du code actuel — la ligne est présente et correcte à HEAD. C'est un
trou de couverture : la sonde du commit construit le widget via `pumpWidget` à chaque cas (deux
montages indépendants, jamais un update en place du même painter), donc `shouldRepaint` n'est jamais
exercé par un flip du toggle en cours de vie du widget. Aucun cas de repaint bloqué ni de repaint
permanent trouvé — juste une ligne non atteinte par la suite actuelle.

## 4. La sonde prouve-t-elle la chaîne ?

**[mesuré]** Les 5 mutations rejouées moi-même sur le code réel (chacune : mutation → run ciblé →
lecture du message d'échec → restauration → re-run vert) :
| Mutation | Résultat | Assertion qui tombe |
|---|---|---|
| `showDots: widget.showTrajectoryDots` → `showDots: false` (peintre, ligne 992) | 🔴 | `plusieurs beats à venir portent une pastille` — `Expected: >1 / Actual: 0` |
| `showTrajectoryDots: widget.showTrajectoryDots` → `showTrajectoryDots: false` (ladder, ligne 430) | 🔴 | même assertion, même message |
| `if (!showDots) return;` → `if (showDots) return;` (garde inversée) | 🔴 | les 2 tests de visibilité tombent, chacun sur son assertion propre (0 pastille attendu en séance → 3 offsets rendus ; >1 attendu en debug → 0) |
| `old.showDots != showDots` retiré de `shouldRepaint` | 🟢 non détecté | — (cf. §3) |
| `?? kDebugMode` → `?? false` | 🔴 sur la sonde ajoutée cette session, 🟢 sur le reste de la suite avant cet ajout | cf. §1 |

Les 3 premières mutations tombent bien sur l'assertion pertinente (pas un artefact de setup) : la
sonde teste réellement le fil `showTrajectoryDots` → `showDots` → rendu, pas seulement la logique
interne du peintre isolée de son câblage — exactement le risque que ce projet a payé plusieurs fois
(`feedback_probe_must_be_red_for_the_right_reason`).

Restauré après chaque mutation ; `git diff -- lib/` confirmé vide avant tout commit.

## 5. Le dernier maillon non gardé — inventaire des réglages `session_screen.dart` non gardés

**[mesuré]** Mutation de `showTrajectoryDots: _showTrajectoryDots` → `showTrajectoryDots: false`
(`session_screen.dart:1128`) : `flutter analyze` remonte un `unused_field` sur `_showTrajectoryDots`
(signal fragile — n'aurait rien dit si la mutation avait pointé vers une variable existante ailleurs
plutôt que de figer un littéral), et **la suite complète (1088 tests) passe intégralement**. Confirmé
puis restauré (`git diff` vide, aucune trace).

**[déduit]** Une sonde de bout en bout pour ce maillon précis existe en gabarit
(`session_finished_duration_render_test.dart`) mais c'est un harness lourd : mocks de canaux audio
(`audioplayers`), wakelock, TTS, `SessionController` réel avec `Stopwatch` non simulé
(`runAsync` + attente d'horloge murale), `_SilentBeepEngine`/`_SilentAmbienceEngine` dédiés — 264
lignes pour un seul scénario. Reproduire ce harness pour vérifier un simple flag transmis est
disproportionné par rapport au coût de la lacune (un flag d'affichage esthétique, pas un calcul
métier) — à la différence du défaut `kDebugMode` (§1), testable en 15 lignes sans aucun widget.

**[mesuré] Inventaire demandé.** Sur les 11 champs `_show*`/`_skip*` de `session_screen.dart`, deux
familles :

- **Gates de visibilité d'un widget entier** (`if (_showX) Widget(...)`) : `_showTimer`,
  `_showHumiliationBar`, `_showObedienceBar`, `_showSalivaBar`, `_showSessionControls`,
  `_showStaminaBar`. Testables par `find.byType` présent/absent sans lire de paramètre interne —
  raisonnablement atteignables par un futur test de bout en bout s'il en naît un.
- **[mesuré]** **Paramètres transmis à un widget déjà affiché** (le widget existe dans les deux réglages, seul
  son rendu interne change) — **les 3 seuls cas de ce type, aucun gardé de bout en bout** :
  - `showTrajectoryDots: _showTrajectoryDots` → `MovementAnimation` (`session_screen.dart:1128`) —
    sujet de cette relecture.
  - `mediaEnabled: _showBackgroundMedia` → `SessionBackground` (`session_screen.dart:928`) —
    `grep -rl "mediaEnabled\|SessionBackground" test/` : aucun résultat.
  - `showDetails: _showModeBadge` → `ModeBadgeRow` (`session_screen.dart:1073`) —
    `grep -rl "showDetails" test/` : aucun résultat.

  **[déduit]** Cette 2ᵉ famille est structurellement plus difficile à garder que la 1ʳᵉ : le test doit descendre
  dans les paramètres du widget enfant plutôt que constater sa présence, ce qui exige soit le
  harness lourd ci-dessus, soit un refactor (extraire la lecture du paramètre dans un point testable
  isolément). **Aucun des 3 n'a de sonde de bout en bout à ce jour** — ni ceux des commits
  précédents, ni celui de ce commit. Pas un défaut spécifique à `67aa2c3` : un point aveugle
  structurel de `session_screen.dart`, déjà signalé deux fois cette semaine sur d'autres fils
  (`feedback_new_field_lost_at_copy_sites`, `feedback_pure_function_tested_wiring_not`) — je ne rouvre
  pas de fiche sas, je consigne l'inventaire ici comme demandé.

## 6. Traductions

**[mesuré]** Les 2 clés (`soundsDebugShowTrajectoryDots`, `soundsDebugShowTrajectoryDotsSubtitle`)
sont présentes dans les 4 ARB (`app_fr.arb`, `app_en.arb`, `app_de.arb`, `app_es.arb`) et dans les 5
fichiers générés (`app_localizations.dart` + les 4 `app_localizations_<lang>.dart`) — aucune langue
manquante. `flutter analyze` propre et `flutter test` (1088 puis 1091 tests) tous verts confirment
qu'aucun drift `flutter gen-l10n` n'est resté (le piège `feedback_l10n_es_generated_drift` aurait
cassé la compilation, pas juste raté un test).

## Ce que je n'ai pas pu établir

- Je n'ai pas pu observer de **régression visuelle réelle** en dehors des mutations que j'ai moi-même
  provoquées — aucune piste du périmètre ne casse sur le code à HEAD.
- Je n'ai pas pu **mesurer le coût exact** d'une sonde de bout en bout pour le maillon `session_screen`
  (section précédente) autrement que par comparaison au harness existant le plus proche — je n'ai pas
  tenté de l'écrire pour chronométrer, jugement qualitatif seulement.
- Je n'ai pas cherché à savoir si `mediaEnabled`/`showDetails` cachent eux-mêmes un vrai bug — hors
  périmètre de ce commit, je me suis arrêté à constater leur absence de sonde pour l'inventaire.

## Vérifications

**[mesuré]** Depuis `rhythm_coach/` : `flutter pub get` (OK), `flutter analyze` (`No issues found!`, deux fois —
avant et après l'ajout de sonde), `flutter test` (1088 tests verts en baseline, 1091 après l'ajout de
la sonde de couverture — aucune régression), `dart format --set-exit-if-changed lib/ test/` (propre
après reformatage automatique du nouveau fichier). Tout redirigé vers fichier, jamais pipé.

## Ce qui a été corrigé

**[mesuré]** `test/debug_settings_trajectory_dots_default_test.dart` (30 lignes, 3 cas) — verrouille le défaut
`?? kDebugMode` de `getShowTrajectoryDots()`, seul comportement du périmètre trouvé sans aucune
garde et à coût de sonde négligeable. Commit `3f80a9c` sur `fix/courbe-continuite-visuelle`.
