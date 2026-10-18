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
  mesure: 16
  deduit: 19
  document: 9
  sans_marqueur: 0
sources_citees: []
relu_contre:
  - rhythm_coach/lib/services/capability_service.dart:112
  - rhythm_coach/lib/services/capability_service.dart:221
  - rhythm_coach/lib/services/capability_service.dart:346
  - rhythm_coach/lib/services/capability_service.dart:92
  - rhythm_coach/lib/services/capability_tracker.dart:216
---

## Constat

[mesuré] Sur `develop` (`c57bdcd`), un FAIL non imputé recopiait dans le confort la valeur figée à l'instant de l'abandon :
motion 90 → 2 s, engagement 60 → 12 s, effort sans souffle 120 → 12 s sur un tap-out imputé au BPM ; BPM gorge 100 → 50 et
motion 90 → 6 s sur un FAIL à 50 BPM (test `rhythm_coach/test/capability_fail_soft_cap_test.dart`, commit `f60a8cb`).

[document] Cause : la branche soft-cap de `CapabilityRegulator.regulate` posait `comfort = sessionCeiling` sans plancher, alors
que `CapabilityTracker.onFail` fige chaque streak vivant et les réglages du step quelle que soit leur valeur : un streak commencé
deux secondes plus tôt, ou le BPM d'un step lent.

## Décision de Manu

[document] Le 18/10, mot pour mot : « je dirai LES vrais causes uniquement (sur un rythme profond on ne sait pas si c'est la profondeur ou
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

## 2ᵉ passe : réserves de la relecture et fiche du sas

[document] Le 18/10, reprise des quatre réserves de la relecture adverse (`relecture/fail-soft-cap`, `95167f6`) et de la fiche `tss2-043`
(confirmée grave). Règle donnée pour cette passe, d'après Manu : une vraie cause perd 15 % (ou un cran de profondeur), jamais plus ;
le reste ne bouge pas. Pour D4, Manu : « Oui, elles montent normalement ». Chaque point a un commit de test rouge puis un commit
de correctif.

### D1 : la baisse d'un axe accusé est bornée

[mesuré] Test `055496e`, rouge sur `71f7f40` : une sonde de profondeur lente (`throat→full` à 40 BPM) faisait tomber le BPM
`full` accusé avec elle de 80 à 34 au lieu de 68. Les valeurs attendues sont écrites en dur (85, 68, 119, 102, cran 2) : l'oracle
ne rappelle plus `regulate`.

[document] Correctif `aabb859` : le ratchet dur part du confort seul (×0,85 ; ÷0,85 pour un plancher ; −1 cran pour la profondeur).
Il ne lit plus la valeur figée au FAIL, qui pouvait venir d'un step qui ne sondait pas l'axe.

[déduit] À faire trancher par Manu : la même règle vaut pour un vrai débordement de salive, qui ne retombe plus à la durée du
débordement (confort 120 s, débordement à 60 s : 102 s au lieu de 51 s). Deux tests qui figeaient l'ancienne valeur sont réécrits
(`capability_regulation_test` : « signal négatif imputé » et « débordement de salive »). Manu ne s'est pas prononcé sur le
débordement ; c'est la lecture de « jamais plus ».

### D4 : un axe non accusé garde son taux de réussite

[mesuré] Test `3ba903e`, rouge sur `aabb859` : chaque axe figé mais non accusé passait de 0,5 à 0,425. Correctif `0136dff` : plus
de baisse du taux de réussite hors accusation ; le confort ne bouge pas ; la montée reste bloquée pour la seule séance du FAIL,
comme avant.

[déduit] « Elles montent normalement » est lu ainsi : rien ne freine leur remontée aux séances suivantes. Si Manu voulait aussi
qu'un axe non accusé puisse monter dans la séance même de son FAIL, c'est une ligne de plus, non faite.

### D2 : chaque FAIL d'une séance garde ses accusés

[mesuré] Test `71e16f2`, rouge sur `0136dff` : un 2ᵉ FAIL sur un `tip→head` laissait la profondeur à 3 au lieu de 2 ; deux FAIL
de causes différentes (vitesse gorge puis vitesse peu profonde) n'en accusaient qu'une (BPM peu profond 140 au lieu de 119).

[document] Correctif `3fd7b72` : le tracker garde les valeurs figées de chaque FAIL (`SessionCapabilityReport.failCeilings`) à côté
du plafond de séance ; `commit` accuse FAIL par FAIL contre le profil d'avant séance. Un axe accusé par deux FAIL perd 15 % une
seule fois. Le retour de `commit` ne change pas (attribution sur le plafond de séance, ignorée par `SessionController`).

[mesuré] D1 et D2 se tiennent : avec l'accusation par FAIL, le plafond de séance passé à `regulate` peut être bien plus bas que la
valeur du FAIL qui accuse. Remettre le rabattement de la profondeur sur ce plafond la fait tomber de 3 à 1 (−2 crans) dans le test
à deux FAIL.

### Sans avaler : seul un vrai débordement accuse cet axe

[mesuré] Fiche `tss2-043`. Test `24b0fbd`, rouge sur `3fd7b72` : un FAIL après 10 s d'interdiction d'avaler, sans débordement ni dépassement,
baissait `noswallow` de 120 à 102 (à 8,5 sur `71f7f40`). Correctif `ff178ff` : le tracker signale le débordement à part
(`salivaOverflowed`) ; un plafond `noswallow` posé par un FAIL suit la règle commune. Témoins verts : vrai débordement (120 → 102),
FAIL où `noswallow` est le plus au-delà de son confort (130 s sur 120 : accusé, 102).

### D3 : angles morts bouchés

[mesuré] Commit `eaeda51` : confort semé sur `gorge.crossings_bpm.throat` et `full`, nouveau scénario `mid→full` ; le taux de
réussite est vérifié pour chaque axe figé (0,35 si accusé, inchangé sinon). La mutation `successRate` de la relecture porte sur
une ligne supprimée par D4 ; son pendant (baisse remise sur un axe non accusé) est la mutation 10 ci-dessous.

### Mutations rejouées

| Mutation [mesuré] | Tests rouges |
|---|---|
| 1. soft-cap rétabli (`comfort = sessionCeiling`) | 11 |
| 2. groupe du rythme profond retiré | 5 |
| 3. couplage ajouté sur un rythme peu profond | 1 |
| 4. D1 : minimum entre valeur figée et confort | 5 |
| 5. D1 : profondeur rabattue sur le plafond | 1 |
| 6. D2 : accusation sur le plafond de séance | 2 |
| 7. tss2-043 : tout plafond `noswallow` accusé | 1 |
| 8. D3 : `gorge.crossings_bpm.full` retiré du groupe | 1 |
| 9. D3 : `gorge.crossings_bpm.throat` retiré du groupe | 3 |
| 10. D4 : baisse du taux remise hors accusation | 10 |
| 11. tss2-043 : débordement ignoré par `commit` | 2 |
| 12. D2 : le tracker garde le plafond de séance au lieu du FAIL | 1 |
| 13. tss2-043 : le tracker oublie le débordement | 1 |
| 14. taux d'un axe accusé non baissé | 9 |

[mesuré] Une mutation à la fois, fichier restauré par copie, `git diff` vide vérifié après chacune ; chaque rouge lu sur
l'assertion visée (profondeur 3 → 1 pour la 5, `noswallow` 120 → 102 pour la 7, etc.). Témoin non muté : 55 verts sur les quatre
fichiers de capacités.

### Commentaires seulement et contrôles

[mesuré] Commit `c02db97` : 108 lignes de commentaires retirées de `capability_tracker.dart` (le quoi, les renvois §, le récit) ;
code identique hors commentaires, vérifié par comparaison. `flutter analyze` : « No issues found! » ; `dart format
--set-exit-if-changed .` à 0. Suite complète sur `c02db97` : 1111 verts, aucun rouge
(`challenge_timeline_forecast_test`, instable connu `tss2-008`, vert cette fois).

### 2ᵉ passe : ce que je n'ai pas pu établir

- [déduit] Séance réelle : rien n'a tourné dans `SessionController`, seulement le vrai tracker et le vrai `commit`.
- [déduit] Le commentaire de `session_controller.dart` au-dessus de l'appel à `commit` dit que l'attribution de `commit` sert au
  ratchet ↓ : ce n'est plus le cas (fichier non touché, signalé ici).
- [déduit] La phrase coach « limite reconnue » lit encore le plafond de séance : au 2ᵉ FAIL elle peut viser un axe du 1ᵉʳ
  (fiche `tss2-044` au sas, non mesurée).
- [déduit] Le débordement réel à −15 % et la lecture de « montent normalement » sont des interprétations, à confirmer par Manu.
- [déduit] La calibration des défis et la fréquence réelle d'un 2ᵉ FAIL ou d'un FAIL en « sans avaler » ne sont pas mesurées.

## 3ᵉ passe : déborder est le but, avaler est l'échec

[document] Décision de Manu le 18/10, mot pour mot : « Cest justement le but de faire deborder. Cest si on avale qu'on fail ».
Elle remplace la règle tss2-043 de la 2ᵉ passe (`ff178ff`).

[mesuré] Débordement : test `9b60215`, rouge sur `9ce5a24` (plafond `noswallow` posé à 10 s, streak coupé à 20 au lieu de 25).
Correctif `2eecd6b` : le tracker ne reçoit plus le débordement (`onSalivaOverflow`, `salivaOverflowed` et le drapeau de streak
retirés) ; `noswallow` reste à 120, le streak compte en entier. Le bump d'humiliation n'est pas touché.

[mesuré] FAIL pendant un « sans avaler » : test `2be3680`, rouge sur `2eecd6b` (`noswallow` resté à 120 au lieu de 102 ; quand
`noswallow` dépasse le plus, la tenue gorge restait à 22 au lieu de 18,7). Correctif `ff63cb2` :
`CapabilityRegulator.failAccused` accuse `noswallow` dès qu'il est figé au FAIL, et la règle commune désigne en plus l'axe le
plus dépassé parmi les autres valeurs figées.

| Mutation [mesuré] | Tests rouges |
|---|---|
| A. `noswallow` figé mais pas accusé | 4 |
| B. règle commune appliquée avec `noswallow` dans le lot | 1 |
| C. `noswallow` non figé au FAIL | 4 |
| D. soft-cap rétabli | 14 |
| E. groupe du rythme profond retiré | 5 |
| F. streak sans avaler oublié en fin de séance | 1 (après `f0de139`, verte avant) |

[mesuré] `flutter analyze` : « No issues found! » ; `dart format --set-exit-if-changed .` à 0 ; suite complète : 1112 verts.

### 3ᵉ passe : ce que je n'ai pas pu établir

- [déduit] Lire « les autres causes » comme l'axe le plus dépassé hors `noswallow` est une interprétation (mutation B).
- [déduit] Le débordement compté comme succès (streak entier) suit le mot « succès » de la consigne ; non confirmé par Manu.
- [déduit] Aucun test ne garde l'absence de lien débordement → tracker au niveau `SessionController` : le lien n'existe plus.
- [déduit] Un FAIL dans la seconde qui suit un « avale » coaché accuserait encore `noswallow` (streak non remis à zéro avant le
  tick suivant) ; non mesuré.
- [déduit] Un débordement peut aussi survenir quand avaler est permis (seuil 90, auto-déglutition à 75 avec délai) ; il n'a
  jamais touché les capacités.
- [déduit] Commentaires de `capability_service.dart` et `session_controller.dart` non nettoyés (plafond de jetons).
