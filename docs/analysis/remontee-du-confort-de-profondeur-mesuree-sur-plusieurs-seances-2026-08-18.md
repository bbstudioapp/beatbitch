---
type: analyse
sujet: remontee-du-confort-de-profondeur-mesuree-sur-plusieurs-seances
ecrit_le: 2026-08-18T21:06:13+02:00
auteur: session tss2-profondeur-passe2 · claude-opus-5
revision: 9b6b6d17
branche: develop
porte_sur:
  - /home/emmanuel/perso/git/tss2-w2/rhythm_coach/lib/career/services/career_level_gates.dart
  - /home/emmanuel/perso/git/tss2-w2/rhythm_coach/lib/career/services/generation/capability_clamps.dart
  - /home/emmanuel/perso/git/tss2-w2/rhythm_coach/lib/services/capability_service.dart
  - /home/emmanuel/perso/git/tss2-w2/rhythm_coach/lib/services/capability_tracker.dart
  - /home/emmanuel/perso/git/tss2-w2/rhythm_coach/lib/services/diagnostic_import_service.dart
  - /home/emmanuel/perso/git/tss2-w2/rhythm_coach/test/capability_depth_comfort_loop_test.dart
provenance:
  mesure: 21
  deduit: 3
  document: 5
  sans_marqueur: 0
sources_citees: []
relu_contre:
  - /home/emmanuel/perso/git/tss2-w2/rhythm_coach/lib/career/services/career_level_gates.dart:107
  - /home/emmanuel/perso/git/tss2-w2/rhythm_coach/lib/services/capability_service.dart:346
  - /home/emmanuel/perso/git/tss2-w2/rhythm_coach/lib/services/diagnostic_import_service.dart:107
---

> ⚠️ **L'en-tête ci-dessus décrit le dépôt AutoPump, pas celui-ci.** Ce document a été écrit le
> 2026-08-18 par une session tss2 avec `castor doc:ecrire`, un outil qui ne vivait alors que dans le
> dépôt AutoPump : la session a dû s'y placer pour l'exécuter, et l'outil y a lu la révision, la
> branche et le dossier de destination. Les champs `revision`, `branche` et les chemins `porte_sur`
> en `_bmad-output/` renvoient donc à AutoPump et **ne décrivent pas l'arbre analysé ici** — la vraie
> révision jugée est écrite dans le corps du document. Rapatrié le 2026-08-19, sujet AutoPump #358 ;
> l'outil a été sorti de ce dépôt le même jour, un document écrit depuis tss2 reste désormais chez
> tss2 avec sa vraie révision.

[mesuré] Deux réserves de la relecture adverse se ferment ici, sur `fix/depth-comfort-probe-2` (worktree
`tss2-w2`, base `origin/develop` = `25657d5`, tête `97312b1`, **non poussée**). Deux commits :
le harnais de boucle multi-séances, et le commentaire. [document] Les deux rapports antérieurs
(correctif du 2026-08-18, relecture adverse du même jour) ne sont pas rejoués ici : j'en reprends les
constats étiquetés `[document]` et je mesure le reste.

## Le chiffre : deux séances

[mesuré] Profil de départ `comfort=mid` / `best=throat`, `successRate=0.50` (sous
`kDepthCranGate=0.65`), la joueuse tient tout ce qu'on lui propose :

| séance — tout [mesuré] | profondeur rythmée proposée | `comfort` après régulation | `successRate` après |
| --- | --- | --- | --- |
| 1 | **throat** | mid (inchangé) | 0,650 |
| 2 | throat | **throat** | 0,755 |
| 3 → 20 | throat | throat (stable) | 0,755 |

[mesuré] Identique sur 5 bases de graines indépendantes (0, 100, 200, 300, 400) : même séance de
bascule, mêmes valeurs. La séance 1 ne rend pas le cran parce que le ratchet ↑ d'un axe `depthCran`
est gaté **en plus** par `successRate >= kDepthCranGate`, et que l'EMA (α = 0,30) porte exactement
0,50 → 0,65 en une séance — le seuil est atteint tout juste, ce qui coûte une séance et une seule.

[mesuré] Depuis une chute de **deux** crans (`comfort=head` / `best=throat`), il faut **trois**
séances : le `comfort` vaut encore head après la séance 1 (le seuil de confiance se paie là aussi),
mid après la séance 2, **throat** après la séance 3. Un cran par séance, jamais de retour direct au
`best`.

## La même simulation sur `origin/develop` : jamais

[mesuré] Même harnais, même profil de départ, rejoué sur un worktree détaché sur `origin/develop`
(`25657d5`) : sur **20 séances réussies d'affilée**, `comfort` reste à `mid` (2,000), `successRate`
reste à 0,500 au centième près, et la profondeur proposée plafonne à `mid` à chaque séance. Rien ne
dérive, rien ne remonte — le circuit est fermé sur lui-même, exactement comme le correctif le
décrivait.

[mesuré] Les 4 tests du harnais sont **verts sur la branche et rouges sur `origin/develop`**, chacun
sur le chiffre attendu (profondeur proposée 2 au lieu de 3 ; `[1.0, 2.0, 2.0]` au lieu de
`[1.0, 2.0, 3.0]` ; aucun tap-out déclenché ; `comfort` figé à 2,0 sur toute la boucle). C'est ce
qui prouve que le correctif sert à quelque chose : la remontée mesurée n'existe que de son fait.

[mesuré] Un cas intermédiaire sur `develop` mérite d'être noté parce qu'il ressemble à une remontée
sans en être une : depuis `comfort=head`, le `comfort` y monte quand même jusqu'à `mid` en deux
séances — non par la sonde, mais par le plancher `[mid, full]` de `maxDepthIndexForProfile`, seule
source de dépassement encore disponible. Arrivé à `mid`, il s'arrête définitivement. Lire cette
montée-là comme « ça remonte tout seul » serait une erreur : elle s'éteint au premier palier.

## En cas d'échec : elle redescend, elle n'est jamais coincée

[mesuré] Scénario « elle tape out dès qu'un step vise plus profond que son `comfort` », à chaque
séance (le pire cas construit, pas un profil observé) :

| séance — tout [mesuré] | proposé | tap-out | `comfort` après |
| --- | --- | --- | --- |
| 1 | throat | oui | head |
| 2 | mid | oui | tip (0) |
| 3 | head | oui | 0 (plancher) |
| 4 | head | oui | 0 |

[mesuré] Invariant vérifié à chaque séance des quatre : la profondeur proposée ne dépasse **jamais**
`comfort + 1 cran`. Ce qu'elle ne tient pas redescend dès la séance suivante — le correctif ne la
maintient pas en surplomb.

[mesuré] Scénario mixte, un seul tap-out puis des séances propres : head (s1, −1 cran), head (s2),
head (s3), mid (s4), **throat (s5)**. Soit **quatre séances** pour revenir au `best` après un
tap-out, contre deux sans. L'écart n'est pas dans les crans, il est dans la confiance : le tap-out
tire l'EMA vers 0 (0,50 → 0,35), et il faut deux séances propres pour repasser `kDepthCranGate` avant
que les crans recommencent à bouger.

[mesuré] Sur `origin/develop`, ces deux scénarios ne se déclenchent même pas : aucun step ne dépasse
son `comfort`, donc aucun tap-out imputable à la profondeur. Elle n'est jamais mise en difficulté —
ni jamais remise en progression.

⚠️ [déduit] Ces rythmes sont **mesurés, pas jugés**. Deux séances pour rendre un cran perdu, quatre
après un tap-out : je ne touche à aucun seuil, et je ne dis pas si c'est le bon tempo — c'est une
décision de Manu.

## Ce que le harnais fait, et ce qu'il ne fait pas

[mesuré] `test/capability_depth_comfort_loop_test.dart` referme le circuit que les sondes
précédentes laissaient ouvert : le profil **persisté** est relu par le générateur, la séance produite
est rejouée seconde par seconde dans le vrai `CapabilityTracker`, et son rapport repasse par le vrai
`CapabilityService.commit` avant la séance suivante. Aucun profil figé, aucune valeur injectée à la
main entre deux séances.

[document] Trois simplifications assumées, écrites dans l'en-tête du fichier : le `SessionController`
n'est pas instancié (les `chainAction` ne sont pas déroulées), après un tap-out la séance s'arrête là
où l'app régénère la suite bornée par les `sessionCeilings`, et le temps avance d'une seconde exacte
par tick, sans TTS ni différé.

## Le commentaire corrigé

[document] La relecture reprochait au correctif de présenter
`best.round() > rounded ? rounded + 1 : rounded` comme « équivalent au `min` d'origine ». [mesuré]
L'affirmation d'équivalence ne se trouve **pas** dans le code — elle est dans le rapport du
correctif ; `grep` sur les deux fichiers touchés ne rend rien. Ce qui manquait au code, c'est
l'inverse : la forme ternaire porte un garde-fou réel et **aucun commentaire ne le disait**.

[mesuré] Les deux formules divergent exactement quand `best < comfort` : `min(rounded+1, best)`
rabaisserait le cap **sous** le `comfort`, là où le ternaire le laisse en place. Le propre test
`cap(3, 2)` du correctif les sépare.

[mesuré] Cet état est atteignable : `DiagnosticImportService._capabilities`
(`lib/services/diagnostic_import_service.dart:107-118`) écrit `best` et `comfort` depuis le JSON,
clé par clé, sans contrôle de cohérence entre les deux ni passage par le régulateur. [mesuré]
`ProfileReconciliation` ne le répare pas non plus : elle ne touche que les axes BPM et le score
d'humiliation, jamais la relation `best`/`comfort` de `rhythm.depth_max`.

Le commentaire ajouté dit donc ce que la forme protège, contre quoi, et où est le test qui le
prouve — et il ne devient faux que si quelqu'un défait la décision, ce qui est précisément le signal
qu'on veut voir.

## Les profils déjà faussés : rien à reprendre

[déduit] La mesure change la conclusion du rapport de correctif sur ce point. Il y était écrit que
« corriger le calcul ne répare rien chez une joueuse dont le `comfort` est déjà descendu ». C'est
inexact au vu des chiffres : le profil persisté n'a pas besoin d'être réécrit, il se répare **de
lui-même en deux séances** (trois depuis une chute de deux crans), par le mécanisme normal du
régulateur. Une réconciliation au chargement n'apporterait qu'une chose — supprimer ces deux
séances — au prix d'un écrasement de valeurs sur preuve indirecte. [document] Je ne l'implémente pas
et je ne la recommande pas ; la décision reste à Manu.

## Vérifications

[mesuré] `flutter analyze` → « No issues found! » · `flutter test` → **993 tests verts** (989 avant
cette passe, +4 du harnais) · `dart format --set-exit-if-changed lib/ test/` → sortie 0, aucun
fichier reformaté.

## Ce que je n'ai pas pu établir

- **La proportion de profils réels concernés.** Mon profil de départ est construit à la main. Je ne
  sais pas combien de joueuses portent `comfort < best` sur cet axe, ni de combien de crans — donc
  pas combien de personnes ces deux séances concernent.
- **Le réalisme du modèle de joueuse.** « Elle tient tout » et « elle tape out à chaque cran
  au-dessus de son comfort » sont deux bornes, pas des comportements observés. Le vrai rythme de
  remontée dépend de la fréquence réelle des tap-outs, que rien ici ne mesure.
- **Les séances Encore, Utilise-moi, quickie et les défis dans la boucle.** Le harnais n'enchaîne que
  des séances normales complètes. Un `quickie` ne recalibre pas le `comfort` (branche dédiée du
  régulateur), un Encore change la génération : leur effet sur le nombre de séances n'est pas mesuré.
- **Le decay.** [mesuré] `kDecayAfterSessions` ne se déclenche jamais dans mes boucles, l'axe étant
  sollicité à chaque séance. [déduit] Une joueuse qui espace ses séances verrait le `comfort` dériver
  vers `kDecayTargetFracOfBest × best` en parallèle de la remontée — non simulé.
- **Ce qu'elle ressent.** Deux séances est un chiffre. Que ce soit vécu comme « la gorge revient
  vite » ou « on m'a repris ce que j'avais perdu trop tôt » ne se mesure pas en test.

## Hors périmètre, signalé et non fait

[mesuré] Dans le scénario d'échec systématique, le `comfort` descend à 0 et les steps rythmés visent
alors `head` — **sous le plancher `mid`** que `maxDepthIndexForProfile` documente et applique, parce
que le clamp aval (`capabilityCapFor`) n'a, lui, aucun plancher. L'écart préexiste au correctif.
Fiché dans le sas sous `tss2-001-plancher-mid-contourne-par-le-clamp.md`, non corrigé.
