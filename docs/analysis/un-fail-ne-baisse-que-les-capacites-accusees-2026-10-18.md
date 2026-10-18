---
type: analyse
sujet: un-fail-ne-baisse-que-les-capacites-accusees
ecrit_le: 2026-10-18T17:55:47+02:00
auteur: session tss2-softcap · claude-opus-5-5
revision: 994076a
branche: fix/fail-soft-cap
porte_sur:
  - rhythm_coach/lib/services/capability_service.dart
  - rhythm_coach/lib/services/capability_tracker.dart
  - rhythm_coach/test/capability_fail_soft_cap_test.dart
provenance:
  mesure: 3
  deduit: 6
  document: 5
  sans_marqueur: 1
sources_citees: []
relu_contre:
  - rhythm_coach/lib/services/capability_service.dart:112
  - rhythm_coach/lib/services/capability_service.dart:221
  - rhythm_coach/lib/services/capability_service.dart:346
  - rhythm_coach/lib/services/capability_service.dart:92
  - rhythm_coach/lib/services/capability_tracker.dart:216
---

> ⚠️ AVERTISSEMENTS DU CONTRÔLE
> - 1 paragraphe porte un chiffre sans marqueur de provenance
> Pour en lever un, écrire dans ce document : `Waiver doc: <ce qui est levé> — <raison courte>`

## Constat

[mesuré] Sur `develop` (`c57bdcd`), un FAIL non imputé recopiait dans le confort la valeur figée à l'instant de l'abandon :
motion 90 → 2 s, engagement 60 → 12 s, effort sans souffle 120 → 12 s sur un tap-out imputé au BPM ; BPM gorge 100 → 50 et
motion 90 → 6 s sur un FAIL à 50 BPM (test `rhythm_coach/test/capability_fail_soft_cap_test.dart`, commit `f60a8cb`).

[document] Cause : la branche soft-cap de `CapabilityRegulator.regulate` posait `comfort = sessionCeiling` sans plancher, alors
que `CapabilityTracker.onFail` fige chaque streak vivant et les réglages du step quelle que soit leur valeur : un streak commencé
deux secondes plus tôt, ou le BPM d'un step lent.

## Décision de Manu (18/10)

[document] Mot pour mot : « je dirai LES vrais causes uniquement (sur un rythme profond on ne sait pas si c'est la profondeur ou
la vitesse, donc on baisse les 2) ».

## Correctif

[document] Règle appliquée, d'après la décision de Manu :
- Un axe non accusé garde son confort ; seul son taux de réussite baisse doucement, et le plafond de séance du tracker reste.
- L'axe accusé reste le plus dépassé (`attributeTapOut`, inchangé, toujours utilisé seul par la phrase coach). S'il appartient au
  rythme profond (profondeur figée au moins `throat`), la profondeur, le BPM de bande et le BPM franchissant de cette profondeur
  sont accusés ensemble (`CapabilityRegulator.accusedAxes`). Sur un rythme peu profond, la vitesse seule est accusée.
- [document] Commits : `641835e` (correctif), `988fbca` (test quickie qui figeait l'ancienne règle), `994076a` (commentaires seulement).

## Preuves

[mesuré] Quatre scénarios verts (rythme profond vitesse sondée, rythme profond profondeur sondée, rythme peu profond, FAIL sans
axe surchargé). Trois mutations rouges sur la bonne assertion : soft-cap rétabli (motion 90 → 2), couple retiré (profondeur 3 au
lieu de 2, BPM full 80 au lieu de moins de 80), couplage peu profond ajouté. `flutter analyze` sans remarque, `dart format` à 0.

[mesuré] Suite complète sur `994076a` : 1104 verts, 1 rouge, `challenge_timeline_forecast_test.dart`, vert seul trois fois
sur trois et déjà consigné comme instable en suite complète (fiche `tss2-008`).

## Effet sur les profils déjà faussés

[déduit] Le correctif ne touche que les séances avec FAIL : il ne remonte pas un profil déjà effondré. Sans FAIL, la remontée reste
celle mesurée au tri sur `82e3a7f` (BPM gorge bloqué à 51 pendant 8 séances), non rejouée ici. La réparation est une décision de Manu.

## Chantier futur non cadré : l'endurance

[document] Idée de Manu, laissée telle quelle, rien n'est fait. Le 18/10 : « fait en sorte aussi de géré l'endurance par exemple.
Si ca fait 40s qu'on fait un tip/full en 200 bpm, jusquà 39s ca "passait", donc ca serait vraiment un facteur reliant les
différentes compétences. Hold throat après 1m c'est le fait qu'on retienne plus sa respiration. » Puis : « Ouai cest plus complexe
que ca, y a plusieurs parametres qui rentrent en jeu. Le facteur durée, cest plutot en fonction de la durée ou la gorge est engagée
non-stop (on va rarement faille sur quelque chose de "standard") dans le doute on laisse comme ca ».

## Ce que je n'ai pas pu établir

[déduit] Points restés ouverts :
- [déduit] Séance réelle : rien n'a tourné dans `SessionController`, seulement le vrai tracker et le vrai `commit`.
- [déduit] Une vitesse accusée par couplage alors qu'elle était sous son confort perd plus de 15 % : `min(80, 70) × 0,85 = 59,5`.
- [déduit] Séance à plusieurs FAIL : les plafonds gardent le minimum de chaque axe, donc le couple lit la profondeur la plus faible.
- Les autres lecteurs du confort (calibration des défis) n'ont pas été mesurés.
- [déduit] Un FAIL pendant une interdiction d'avaler accuse encore `noswallow` comme un débordement (fiche `tss2-043` au sas).
