---
type: analyse
sujet: mesure-du-repli-des-curseurs-de-voix
ecrit_le: 2026-08-18T18:38:36+02:00
auteur: session tss2-mesure-repli · claude-sonnet-5
revision: e11271bc
branche: develop
porte_sur:
  - /home/emmanuel/perso/git/tss2-w1/rhythm_coach/lib/screens/profile_screen.dart
  - /home/emmanuel/perso/git/tss2-w1/rhythm_coach/lib/services/tts_service.dart
  - /home/emmanuel/perso/git/tss2-w1/rhythm_coach/lib/widgets/coach_voice_picker.dart
  - /home/emmanuel/perso/git/tss2-w1/rhythm_coach/lib/widgets/voice_settings_section.dart
  - /home/emmanuel/perso/git/tss2-w1/rhythm_coach/test/coach_voice_collapse_measure_test.dart
provenance:
  mesure: 13
  deduit: 0
  document: 1
  sans_marqueur: 8
sources_citees: []
relu_contre:
  - /home/emmanuel/perso/git/tss2-w1/rhythm_coach/lib/screens/profile_screen.dart:163
  - /home/emmanuel/perso/git/tss2-w1/rhythm_coach/lib/services/tts_service.dart:107-110
  - /home/emmanuel/perso/git/tss2-w1/rhythm_coach/lib/widgets/coach_voice_picker.dart:308-312
  - /home/emmanuel/perso/git/tss2-w1/rhythm_coach/test/coach_voice_collapse_measure_test.dart:1-320
---

> ⚠️ **L'en-tête ci-dessus décrit le dépôt AutoPump, pas celui-ci.** Ce document a été écrit le
> 2026-08-18 par une session tss2 avec `castor doc:ecrire`, un outil qui ne vivait alors que dans le
> dépôt AutoPump : la session a dû s'y placer pour l'exécuter, et l'outil y a lu la révision, la
> branche et le dossier de destination. Les champs `revision`, `branche` et les chemins `porte_sur`
> en `_bmad-output/` renvoient donc à AutoPump et **ne décrivent pas l'arbre analysé ici** — la vraie
> révision jugée est écrite dans le corps du document. Rapatrié le 2026-08-19, sujet AutoPump #358 ;
> l'outil a été sorti de ce dépôt le même jour, un document écrit depuis tss2 reste désormais chez
> tss2 avec sa vraie révision.

> ⚠️ AVERTISSEMENTS DU CONTRÔLE
> - 8 paragraphes portent un chiffre sans marqueur de provenance
> Pour en lever un, écrire dans ce document : `Waiver doc: <ce qui est levé> — <raison courte>`

**Révision jugée : dépôt `tss2-w1` (pas celui où cette commande s'exécute), branche `mesure/repli-curseurs`, dérivée de `feat/voice-rate-pitch` @ `9e7c7c5`.** L'en-tête fabriqué par cet outil porte la révision du dépôt courant (`auto-pump`) — sans rapport avec le code mesuré ici.

## Tableau — locale allemande, écran 320×568, feuille de réglage vocal d'un coach

| # | Disposition | Police | Débordement de la feuille | Voix entièrement visibles |
|---|---|---|---:|---:|
| 1 | Actuelle (curseurs visibles) | normale | **0 px** [mesuré] | **0 / 4** [mesuré] |
| 1 | Actuelle (curseurs visibles) | accessibilité ×2 | **693 px** [mesuré] | **0 / 4** [mesuré] |
| 2 | Repliée, fermée | normale | **0 px** [mesuré] | **3 / 4** [mesuré] |
| 2 | Repliée, fermée | accessibilité ×2 | **137 px** [mesuré] | **0 / 4** [mesuré] |
| 3 | Repliée, ouverte | normale | **0 px** [mesuré] | **0 / 4** [mesuré] |
| 3 | Repliée, ouverte | accessibilité ×2 | **789 px** [mesuré] | **0 / 4** [mesuré] |

Repère : avant `feat/voice-rate-pitch` (aucun curseur du tout), accessibilité ×2 → **28 px** de débordement. [document] — chiffre donné dans la commande de la tâche, non ré-exécuté dans cette session.

Les 4 voix comptées sont les voix allemandes déclarées « préférées » dans `tts_service.dart` (`deg`, `de2`, `nfh`, `deb`) — un jeu réel tiré du code, pas inventé. « Entièrement visible » = le rectangle du libellé de la voix tient dans les 568 px physiques de l'écran ; rien n'est déduit du plafond théorique de 70 % de la feuille, c'est la position réellement calculée par le moteur de layout de Flutter qui tranche.

## Ce qui disparaît, en accessibilité ×2 (build release : coupé sans exception ni bandeau)

- **Disposition 1 (actuelle).** Le curseur de hauteur, le bouton « remettre à l'origine » et le bouton « Aperçu » sont **entièrement hors écran** (à 625 px, 828 px, 1100 px de haut — l'écran s'arrête à 568). Seul le curseur de débit reste visible. Aucune voix visible.
- **Disposition 2 (repliée, fermée).** Les curseurs ne sont même pas construits (rien à couper de ce côté), mais le bouton « Aperçu » est déjà coupé de 137 px. Aucune voix visible non plus, malgré la place rendue par le repli.
- **Disposition 3 (repliée, ouverte).** Le curseur de débit lui-même est coupé de 109 px (donc partiellement visible, pas utilisable jusqu'au bout de sa piste) ; hauteur, bouton origine et bouton Aperçu sont entièrement hors écran. Aucune voix visible.

## Réponse à la question de Manu

**Non : replier les curseurs ne les fait pas « rentrer » une fois qu'on les ouvre — ça déborde davantage que l'état actuel** (789 px contre 693 px en accessibilité ×2), parce que le second geste ajoute une ligne de bascule qui reste affichée même une fois ouvert, sans jamais rendre l'espace qu'elle prend ; et même **fermé**, le repli ne retrouve pas l'état d'avant la fonctionnalité (137 px de débordement contre 28 px avant branche — 5× plus), même si à police normale il redonne 3 des 4 voix (contre 0 aujourd'hui).

## Méthode [mesuré]

Suite `flutter test` sur un widget test réel, écran forcé à 320×568 logiques (`tester.view.physicalSize`/`devicePixelRatio`), locale `de`, moteur TTS mocké avec les 4 voix allemandes ci-dessus, `MediaQuery.textScaler` pour la police (`TextScaler.linear(1.0)` puis `TextScaler.linear(2.0)`).

- Le débordement est celui que **Flutter calcule lui-même** au layout (`RenderFlex overflowed by N pixels`), intercepté via `tester.takeException()` — pas un recalcul manuel. La disposition 1 en accessibilité ×2 a reproduit très exactement le 693 px cité dans la tâche : la méthode est donc la même que celle de la relecture précédente, ou en tout cas produit le même résultat.
- « Voix visible » et « élément coupé » sont mesurés en comparant le rectangle réel de chaque widget (`tester.getRect`) aux 568 px physiques de l'écran — pas au plafond théorique de la feuille.
- Dispositions 2 et 3 : prototype jetable, un `InkWell` de bascule (icône + « Débit et hauteur » + chevron) devant les deux `LabeledVoiceSlider` déjà existants et le bouton de remise à l'origine, réutilisés tels quels depuis `voice_settings_section.dart`. Il vit uniquement dans `test/coach_voice_collapse_measure_test.dart` sur la branche jetable `mesure/repli-curseurs`, jamais dans `coach_voice_picker.dart`.
- Fichier de test : `/home/emmanuel/perso/git/tss2-w1/rhythm_coach/test/coach_voice_collapse_measure_test.dart` — 6 `testWidgets`, tous verts (`All tests passed!`), les mesures sont dans leurs sorties `print` (préfixe `MEASURE|`).

## Artefact du protocole (hors sujet, pas un bug de l'app)

En disposition 1, une **deuxième** exception de layout est apparue (43 px), sur `coach_voice_section.dart:110` — le `Column` de la carte « VOIX DES COACHS » du Profil, pas la feuille modale. Elle vient du harnais de test : `CoachVoiceSection` y est montée seule dans un `Scaffold.body` sans ancêtre scrollable, alors que l'écran Profil réel l'encapsule dans un `ListView` (`profile_screen.dart:163`). Vérifié [mesuré+déduit] — ce n'est pas un défaut de l'app, donc pas fiché au sas.

## Ce que je n'ai pas pu établir

- Le **28 px avant-branche** est repris de l'énoncé de la tâche, pas ré-exécuté : je n'ai pas rejoué un test sur le commit d'avant `feat/voice-rate-pitch` pour le vérifier moi-même (l'ancien `coach_voice_picker.dart` n'a pas la même structure, donc pas le même harnais de test — le vérifier proprement aurait demandé un worktree séparé, jugé hors budget pour reconfirmer un chiffre déjà donné).
- Aucun chiffre « avant-branche » à police normale n'est disponible (ni mesuré ni fourni) — impossible de dire si la disposition 2 (repliée, fermée, normale) reproduit *exactement* l'état d'avant-branche à cette taille de police, seulement qu'elle n'a ni débordement ni voix coupée.
- Rendu non vérifié à l'œil (pas de capture d'écran ni de build réel) — uniquement la géométrie calculée par le moteur de layout en test. Cohérent avec l'interdiction de compiler Android sur cette machine.
- Pas de mesure sur un écran autre que 320×568, ni sur une autre locale : la tâche demandait explicitement le même pire cas pour les trois dispositions, pas un balayage plus large.
