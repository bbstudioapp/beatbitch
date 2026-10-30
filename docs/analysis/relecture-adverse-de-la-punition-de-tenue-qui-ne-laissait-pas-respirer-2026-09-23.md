---
type: analyse
sujet: relecture-adverse-de-la-punition-de-tenue-qui-ne-laissait-pas-respirer
ecrit_le: 2026-09-23T20:56:59+02:00
auteur: session tss2-relecture-punition · claude-opus-5-5
revision: fe7f136
branche: fix/punition-tenue-respiration
porte_sur:
  - rhythm_coach/assets/punishments.json
  - rhythm_coach/lib/career/services/generation/punishment_builder.dart
  - rhythm_coach/lib/controllers/session_controller.dart
  - rhythm_coach/lib/controllers/session_controller_fail_flow.dart
  - rhythm_coach/lib/screens/session_screen.dart
  - rhythm_coach/lib/services/beep_engine.dart
  - rhythm_coach/lib/widgets/movement_animation.dart
  - rhythm_coach/test/session_punishment_breath_screen_test.dart
provenance:
  mesure: 13
  deduit: 20
  document: 0
  sans_marqueur: 0
sources_citees: []
relu_contre:
  - rhythm_coach/lib/career/services/generation/punishment_builder.dart:280
  - rhythm_coach/lib/controllers/session_controller.dart:2385
  - rhythm_coach/lib/controllers/session_controller.dart:961
  - rhythm_coach/lib/controllers/session_controller_fail_flow.dart:307
  - rhythm_coach/lib/controllers/session_controller_fail_flow.dart:458
  - rhythm_coach/lib/screens/session_screen.dart:1118
  - rhythm_coach/lib/screens/session_screen.dart:1305
  - rhythm_coach/lib/services/beep_engine.dart:417
  - rhythm_coach/lib/widgets/movement_animation.dart:310
  - rhythm_coach/lib/widgets/movement_animation.dart:438
  - rhythm_coach/test/session_punishment_breath_screen_test.dart:294
---

## Verdict : publiable avec réserves

- [mesuré] Le correctif `9db389f` est juste et suffisant pour ce qu'il vise : la cause est la bonne, le test rouge tombe sur la bonne assertion, la mutation qui retire le `_notify()` le refait tomber, et je n'ai trouvé aucun état incohérent introduit à l'écran.
- **Réserve gênante — le repère proposé à Manu ne discrimine pas.** [mesuré] La respiration de récupération qui précède la punition met déjà le curseur vert tout en haut, sur le code d'avant correctif comme après. Un « monte » peut donc être rapporté sur un build encore cassé. Repère corrigé plus bas. Le code n'est pas en cause, mais il ne faut pas faire tester Manu avec le repère d'origine.
- Réserve non gênante : le rapport d'origine surestime l'effet sur les punitions rythmées et en oublie une (détail plus bas). Ça ne change ni le correctif ni son test.
- Réserve non gênante, défaut préexistant hors correctif : à la reprise après une punition, l'écran garde la punition pendant le délai de transition du moteur. Déposé au sas (fiche `tss2-011`). Lien plausible avec les sauts d'une demi-seconde signalés par Manu, non établi.

## La cause, rejouée

- [mesuré] `git diff 8b2d029 fe7f136 -- rhythm_coach/` ne contient que les deux lignes du correctif : retirer le `_notify()` reproduit exactement le code d'avant. Mutation posée par suppression de la seule ligne `_notify();` (le commentaire laissé en place), vérifiée par `git diff` avant de lancer le test, puis restaurée par `git checkout` et revérifiée propre.
- [mesuré] Code muté : les deux tests rouges, pour les deux routes, sur l'assertion de `session_punishment_breath_screen_test.dart:185`, avec le message « Moteur : {breath}, mode reçu par MovementAnimation : {hold}, y : {0.20} ». Les assertions précédentes (enchaînement du moteur, curseur bas pendant la 1re tenue) passent. Code corrigé : les deux tests verts (41 s au total).
- [mesuré] Sonde jetable, non commitée, qui compte les notifications du contrôleur et lit le curseur réellement dessiné (l'`Align` parent de `_CursorVisual`, et sa couleur). Sur le code d'avant, pendant toute la punition carrière `deep_hold_chain`, le contrôleur ne notifie qu'une fois : le passage en phase `punishment`. L'écran reste sur `hold/throat`, y = 0,2, jaune, du début à la fin de la punition, pendant que le moteur passe par `breath` puis `hold/full`. C'est la cause décrite, et dans ce banc elle est la seule.
- [déduit] Aucun autre chemin ne redessine l'écran pendant une punition : `SessionScreen` n'a pas de `setState` périodique en jeu (seul le décompte de mise en place en a un), `_handleBeat` ne notifie pas, et `MovementAnimation._onBeatEvent` fait avancer le curseur entre les `from`/`to` qu'il a reçus, jamais ceux du moteur.

## Ce que Manu vivait vraiment, mesuré

- [mesuré] Code d'avant, `deep_hold_chain` carrière (tenues de 3 s) : vert en haut pendant la respiration de récupération (avant la punition), puis jaune à la rangée `throat` pendant toute la punition, environ 10 s, sans aucun mouvement. La respiration entre les tenues et la descente plus profonde de la 2e tenue (`full`) n'apparaissent jamais.
- [mesuré] Code corrigé, même punition : vert en haut (récupération), jaune `throat` (y = 0,2), vert en haut pendant 4 s (remontée en 0,7 s environ), jaune `full` (y = 0,6), puis reprise en orange.
- [mesuré] Punition synthétique de même forme que `throat_relentless`, `slow_torture` et `extra_throat` (rythme `throat`→`full` à 100 BPM pendant 6 s, puis tenue `full`), code d'avant : **la partie rythmée s'affiche correctement et bouge** (orange, alternance entre y = 0,2 et 0,6, le premier step étant notifié par le changement de phase). Seule la tenue finale est fausse : l'écran garde le rythme, curseur orange figé à y = 0,5, au lieu d'une tenue jaune à `full`. Le rapport d'origine dit ces punitions « laissées figées » : c'est vrai de leur tenue finale seulement.
- [déduit] Punitions touchées = celles qui ont au moins deux steps de configuration : `deep_hold_chain`, `slow_torture`, `throat_relentless` (carrière) et `deep_hold_chain`, `slow_torture`, `extra_throat` (`punishments.json`). Le rapport d'origine oublie `extra_throat`. Jamais touchées (un seul step de configuration) : `biffle_burst`, `crossings_burst`, `last_resort_rhythm`, `hand_fallback`, `lick_humiliation`, `rapid_full`.

## Ce que le correctif pourrait casser

- [mesuré] Nombre de notifications du flow FAIL, punition carrière `deep_hold_chain` : 3 avant, 6 après (une par step de configuration). [déduit] Au démarrage de la punition, le `_notify()` de phase et celui du 1er step tombent dans la même image. Coût de rebuild négligeable.
- [déduit] Les deux seuls écouteurs directs du contrôleur (`_onCareerStateChanged`, `_maybeAutoChain`) ne font rien tant que la séance n'est pas finie. Pas de notification après `dispose` : `dispose()` et `stop()` annulent `_punishmentTicker` et remettent `_failActive` à faux, et `tick()` sort avant d'appliquer quoi que ce soit.
- [déduit] En production, le moteur est initialisé et `applyStep` pose mode, positions, BPM et `stepSerial` de façon synchrone, avant sa première attente : l'image qui suit le `_notify()` lit l'état neuf. Dans le banc, où `init()` est remplacé, l'état est posé une micro-tâche plus tard mais toujours avant l'image, et le résultat mesuré est le même.
- [déduit] FAIL pendant une punition (abandon) : le ticker est annulé, aucun step n'est appliqué ensuite, l'écran garde le dernier step affiché jusqu'au `_notify()` du `finally`, comme avant. Défi : `triggerFail` ne fait rien pendant un défi, le ticker principal (seul à faire avancer un défi) est coupé pendant la punition, les deux ne se chevauchent pas. Mini-punition : même `_runPunishment`, donc couverte, mais elle ne se déclenche jamais (fiche `tss2-010`).
- [déduit] Texte affiché : pendant un FAIL, `currentDisplayText` rend la phrase de fail, que le correctif ne change pas. Les textes des steps de punition, prononcés, ne s'affichaient pas avant et ne s'affichent toujours pas.
- [déduit] Pendant la punition, `MovementAnimation` reçoit désormais le mode de chaque step, avec des `upcomingSteps` tirés de la séance principale et une horloge gelée. C'était déjà le cas pour le 1er step avant le correctif, et je n'ai vu aucune image fausse dans les mesures ci-dessus.

## Les sauts d'une demi-seconde après un défi ou une punition

- [déduit] Aucun lien avec ce correctif : Manu les voyait sur un build qui ne l'avait pas, un défi ne passe jamais par `_runPunishment`, et la séquence mesurée à la reprise est identique avant et après.
- [mesuré] Défaut préexistant voisin, sur le chemin `_restorePreviousLoop` (séance sans section suivante) : le moteur repasse en rythme à t = 17,0 s, l'écran reste sur la tenue de la punition jusqu'à t = 17,7 s ; même chose sur la punition rythme → tenue (17,8 s → 18,7 s), avant comme après le correctif. [déduit] `_restorePreviousLoop` attend `applyStep`, qui attend le délai de transition (600 ms ici) avant de rendre la main au `_notify()` du `finally`. L'écran lance ensuite son propre pont visuel alors que les bips ont déjà repris.
- [déduit] Lien plausible par l'ordre de grandeur (délai de 600 ms) et le moment (juste après une punition). Non établi : chemin `_skipToNextSection` et sortie de défi non mesurés, et ce retard arrive une fois par punition, il n'explique pas des sauts en boucle. Fiche `tss2-011` au sas.

## Le repère proposé à Manu

- [mesuré] Couleurs vérifiées dans le code et sur le curseur dessiné : tenue `#FFD54F` (jaune, `movement_animation.dart:438`), respiration `#81C784` (vert, `:440`), rythme `#FFA726` (orange, `AppTheme.accent`). Le rapport d'origine a raison sur ces couleurs.
- [mesuré] Mais le vert en haut apparaît **avant** la punition, pendant la respiration de récupération (bandeau « Respiration »), sur le code d'avant comme après. Le mot « monte » ne dit pas quelle respiration Manu a vue : il peut valider un build cassé.
- [déduit] Repère qui discrimine : **pendant que le bandeau affiche « Punition » (nom `deep_hold_chain`), combien de fois le curseur jaune descend ?** Un mot : « une » = défaut toujours là, « deux » = corrigé (trois si le bandeau affiche « Chaîne de Holds », version `punishments.json`). Indice de confirmation : la 2e descente va plus bas que la 1re (`full` sous `throat`).
- [déduit] Prérequis : le toggle debug « chronomètre » doit être éteint (défaut), sinon le chronomètre remplace le curseur.

## Réserves sur le test, non gênantes

- [déduit] `_cursorY` prend le dernier `Align` de tout l'arbre dont `x` n'est ni 0 ni 0,92. Il lit bien le curseur aujourd'hui (mes lectures ciblées donnent les mêmes valeurs), mais un widget ajouté plus tard sous le curseur, avec un `Align` excentré, changerait silencieusement ce qu'il lit. Le chercher sous `MovementAnimation` serait plus sûr.
- [déduit] Le test ne couvre pas la tenue finale des punitions rythme → tenue ; la même ligne la répare, et ma sonde l'a montré, mais aucun test commité ne la garde.

## Vérification

- [mesuré] Depuis `rhythm_coach/` du worktree, sonde supprimée, arbre propre : `flutter analyze` rend « No issues found! », `dart format --set-exit-if-changed .` ne change aucun des 315 fichiers, `flutter test` rend 1103 tests passés, sortie 0. `challenge_timeline_forecast_test.dart` n'a pas échoué.

## Ce que je n'ai pas pu établir

- [déduit] Rien de ce qui sort du haut-parleur ni le rendu sur téléphone : moteur sans échantillons, lecture de l'arbre de widgets.
- [déduit] La version `punishments.json` complète (trois tenues) n'a pas été rejouée jusqu'au bout par ma sonde ; le test commité s'arrête à la 2e tenue.
- [déduit] L'abandon par FAIL pendant la punition n'est exercé que par la sortie du test, sans assertion sur l'écran.
- [déduit] Le retard de reprise sur le chemin `_skipToNextSection` et après un défi, et donc si c'est bien ce que Manu appelle des sauts d'une demi-seconde.
- [déduit] Quelle punition Manu a jouée le 23/09 et ce qu'il a entendu : le son de respiration jouait peut-être déjà, seul l'écran était faux.
