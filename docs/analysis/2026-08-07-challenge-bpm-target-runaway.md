# Retour utilisateur 0.6.0 — la cible du défi de rythme s'emballe (« 956 BPM »)

**Date d'analyse** : 2026-08-07 · **Version concernée** : 0.6.0 (build 15) · **Base de code** : `develop` (identique à `release/0.6.0` sur `lib/`)

Troisième problème rapporté par le même utilisateur. Il est indépendant des deux
premiers, traités dans
[`2026-08-07-session-freeze-and-coach-unlock.md`](2026-08-07-session-freeze-and-coach-unlock.md).

Symptôme, tel que décrit :

> I also think the speed ramp ip challange has an issue, it is at max speed, but
> definitely not 956 bpm haha, this number gets higher every time i get this
> challange, even though the speed cannot get higher

Ce que montre la capture fournie : en-tête « Career — quickie », bannière de
consigne « **Shallow rhythm — ramp up to 956 BPM** », bouton **GIVE UP**, jauge
de profondeur avec `tip`/`head` allumés et `mid`/`throat`/`full` éteints.

Deux observations de l'utilisateur sont exactes, et ce sont les bonnes :

1. le nombre affiché est une **cible** (« ramp up to »), pas une mesure ;
2. la vitesse réelle est déjà au maximum et n'y arrivera jamais.

---

## Ce que la bannière affiche

`lib/controllers/session_controller_challenge.dart:233`

```dart
case CapabilityAxis.rhythmBpmCeilShallow:
  return l10n.challengeBannerRhythmShallow(t);   // t = ch.targetThreshold
```

`challengeBannerRhythmShallow` = « Shallow rhythm — ramp up to {bpm} BPM »
(`lib/l10n/app_en.arb:291`). Le `956` est donc `Challenge.targetThreshold`, et
l'axe concerné est `CapabilityAxis.rhythmBpmCeilShallow` — cohérent avec la jauge
de la capture (`head→mid`, bande « peu profonde »).

## Comment cette cible est calculée

`lib/career/services/challenge_service.dart:438-464`

```dart
final threshold = thresholdFor(kind, comfort, axis);
final bpm    = isBpm ? comfort.round() : null;   // départ de rampe
final bpmEnd = isBpm ? threshold      : null;    // arrivée de rampe
```

`lib/career/services/challenge_service.dart:654-659`

```dart
case ChallengeAxisKind.bpm:
  final raw = isMinimize
      ? comfort / kChallengeOverloadFactor
      : comfort * kChallengeOverloadFactor;      // 1.30
  final rounded = raw.round();
  return isMinimize ? (rounded < 18 ? 18 : rounded) : rounded;
```

Donc : **cible = `comfort` de l'axe × 1,30**, arrondi. Aucune borne haute sur la
branche `maximize` — le plancher à 18 ne concerne que les axes `minimize`.

`956 / 1,30 ≈ 735` : au moment de la capture, le `comfort` persisté de
`rhythm.bpm_ceil.shallow` valait ≈ **735 BPM**.

---

## Cause établie : on crédite la vitesse *demandée*, jamais la vitesse *jouée*

`lib/controllers/session_controller_challenge.dart:705-721` — à la clôture d'un
défi réussi :

```dart
final double reached;
switch (ch.kind) {
  case ChallengeAxisKind.duration:
    reached = reachedDuration.toDouble();
    break;
  case ChallengeAxisKind.bpm:
    reached = (ch.bpmEnd ?? ch.bpm ?? ch.targetThreshold).toDouble();
    break;
  ...
}
_capabilityTracker?.recordChallengeReached(ch.axis, reached);
```

`ch.bpmEnd` **est** la cible affichée. On enregistre donc au profil de capacités
la valeur qu'on a demandée, sans jamais vérifier qu'elle a été produite — ni même
qu'elle était produisible.

Puis, en fin de séance, `CapabilityRegulator.regulate`
(`lib/services/capability_service.dart:338-368`) :

```dart
final bool overshoot = reached >= comfort * kOvershootMargin;   // 1.02
if (overshoot) {
  final double gain = kRatchetUpGainMin +
      (kRatchetUpGainMax - kRatchetUpGainMin) * sr.clamp(0.0, 1.0);   // 0.12 → 0.35
  double next = comfort * (1.0 + gain);
  final double anchorCeil = reached * kRatchetAnchorHeadroom;         // × 1.15
  if (next > anchorCeil) next = anchorCeil;
  if (next > comfort) comfort = next;
  sr = _ema(sr, 1.0);
}
```

`reached = comfort × 1,30` est **toujours** un overshoot (1,30 ≥ 1,02). La boucle
se referme :

```
comfort ──(× 1,30)──► cible affichée ──(créditée telle quelle)──► reached
   ▲                                                                │
   └──────────────── comfort × (1 + gain) ◄─────────────────────────┘
```

`comfort_{n+1} = comfort_n × (1 + gain)`, avec `gain ∈ [0,12 ; 0,35]` piloté par
`successRate` — qui monte vers 1 à chaque succès (`_ema(sr, 1.0)`). **Croissance
géométrique de 12 % à 35 % par défi réussi.**

### Pourquoi aucun garde-fou ne l'arrête

Les deux plafonds du régulateur sont **relatifs à `reached`**, donc emportés par
la même dérive :

| Garde-fou | Valeur | Contraignant ? |
|---|---|---|
| `anchorCeil = reached × kRatchetAnchorHeadroom` (`:364`) | `comfort × 1,30 × 1,15 = comfort × 1,495` | non — `next` vaut au plus `comfort × 1,35` |
| `cap = bestRef × kSurchargeMax` (`:392-393`) | `best` vient d'être posé à `reached` → `comfort × 1,495` | non |
| `_absoluteFloor` (`:405-416`) | plancher uniquement | sans objet |

Il n'existe **aucune borne haute absolue** sur `comfort`, sur `best`, ni sur
`targetThreshold`.

### Trajectoire chiffrée

Simulation de la boucle réelle (`CapabilityRegulator.regulate` +
`ChallengeService.thresholdFor`), profil neuf → premier défi exploratoire à
60 BPM, puis succès consécutifs :

| Défi n° | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Cible affichée | 78 | 96 | 122 | 158 | 207 | **274** | 365 | 488 | 654 | 878 | 1181 |
| `comfort` après | 74 | 94 | 122 | 159 | 211 | 281 | 375 | 503 | 675 | 909 | 1224 |

Le **6ᵉ succès** sort de la zone jouable, le **10ᵉ-11ᵉ** encadre le 956 rapporté.
Les trajectoires depuis 90 ou 120 BPM y arrivent en 8-9 succès. L'ordre de
grandeur observé est donc exactement celui que produit le modèle.

---

## Bornes : le moteur en a une, la cible n'en a pas

`lib/services/beep_engine.dart:314` et `:324`

```dart
if (step.bpm != null) _bpm = step.bpm!.clamp(20, 300);
...
_bpmEnd = step.bpmEnd!.clamp(20, 300);
```

Le BPM **effectivement joué** est clampé à **300** — au-delà, la rampe est plate
et le bip tourne au maximum. C'est exactement ce que décrit l'utilisateur :
« it is at max speed, but definitely not 956 bpm ».

**Asymétrie confirmée** : borne haute côté moteur, aucune côté cible. Le nombre
affiché est décoratif dès qu'il dépasse 300.

---

## Le défi est-il impossible à réussir ? **Non.**

C'est le point qui compte pour l'utilisateur, et la réponse est rassurante : la
cible BPM **n'est pas une condition de succès**. Le défi se gagne au temps.

`lib/career/services/challenges/builders/rhythm_bpm_ceil_shallow_builder.dart:46-70` :
le builder émet **un seul** segment de la durée nominale, puis pose
`thresholdReached` au passage suivant. Le BPM n'entre nulle part dans la
condition.

- Durée nominale de l'axe `rhythmBpmCeilShallow` : **25 s**
  (`lib/career/models/challenge.dart:292-293`).
- L'axe n'est pas dans `kCrossingsChallengeAxes`
  (`lib/career/services/challenge_service.dart:68-73`) → pas de compteur de
  franchissements à atteindre non plus.
- Mode d'input : `tapToggle` (tout ce qui n'est pas un hold —
  `lib/career/models/challenge.dart:246-248`). En mode tap, l'UI **ne câble pas**
  `onChallengeHoldEnd` (`lib/screens/session_screen.dart:1594-1595`) : la
  tolérance de relâchement n'est jamais armée, donc aucun échec passif.

Concrètement : après le décompte, il suffit d'attendre 25 s sans toucher
**GIVE UP** pour que le défi bascule en « seuil atteint » et soit crédité en
succès. Le bouton GIVE UP est simplement le seul bouton affiché pendant la phase
live — ce n'est pas le signe d'une impasse.

Ce constat est aussi ce qui alimente la dérive : **chaque rencontre avec cet axe
est un succès quasi automatique**, donc un crédit de plus dans la boucle.

---

## Effet de bord : le plancher d'humiliation carrière prend la même valeur fictive

`lib/controllers/session_controller_challenge.dart:1167-1193` — sur tout succès
non exploratoire :

```dart
case ChallengeAxisKind.bpm:
  durationReached = ch.nominalDurationSeconds;
  bpmReached = ch.bpmEnd ?? ch.bpm;      // ← 956
  ...
_humiliation.raiseCareerFloor(floor);
```

Or `HumiliationScale._bpmExtra` est **quadratique**
(`lib/services/humiliation_engine.dart:139-143`) :

```dart
if (bpm == null || bpm <= 90) return 0.0;
final excess = (bpm - 90) / 30.0;
return excess * excess * 5.0;
```

| BPM passé | Plancher d'humiliation posé |
|---|---|
| 140 (rythme carrière normal) | ≈ 13 |
| 300 (borne réelle du moteur) | ≈ 245 |
| **956 (cible affichée)** | **≈ 4 166** |

`raiseCareerFloor` écrase le score carrière s'il est inférieur
(`lib/services/humiliation_engine.dart:398-402`), et ce score n'a pas de borne
haute ni de mécanisme de retour. À titre de repère, le code lui-même calibre
« career+session jusqu'à ~50 sur une session menée à terme par une débutante »
(`humiliation_engine.dart:146-148`).

Conséquence : le thermomètre d'humiliation, qui sert de première enveloppe de
difficulté, est **définitivement neutralisé** pour ce profil. Tout le contenu
qu'il gate est ouvert d'un coup. Ce n'est pas un blocage, c'est l'inverse — mais
c'est une perte irréversible de la progression telle qu'elle est conçue.

> ⚠️ Contrairement au crédit `comfort`, ce plancher est posé **aussi en séance
> bâclée** : `setHumiliationLevel` n'est conditionné que par `!session.noStats`
> (`lib/controllers/session_controller.dart:1730`).

---

## Reproduction

Reproduit de façon déterministe en test, sans appareil :
`rhythm_coach/test/challenge_bpm_target_runaway_test.dart`.

| Scénario | Résultat |
|---|---|
| 12 défis BPM réussis d'affilée depuis `comfort = 120` | cible strictement croissante, 156 → 3 182 |
| idem, recherche du franchissement de la borne moteur | la cible dépasse 300 BPM au **6ᵉ** défi |
| un succès avec `comfort = 400`, `successRate = 1` | cible 520, `comfort` → 540, `best` → 520 — aucun plafond n'intervient |
| plancher d'humiliation pour `bpm = 956` | > 4 000, écrase un score carrière de 40 |
| durée nominale / crossings de l'axe shallow | 25 s, `targetCrossings == null` — le succès ne dépend pas du BPM |

```
flutter test test/challenge_bpm_target_runaway_test.dart
00:00 +7: All tests passed!
```

> ⚠️ Ce sont des **tests de caractérisation** : ils décrivent le défaut tel qu'il
> existe aujourd'hui. Ils devront être inversés (assertions de non-régression)
> quand le correctif sera livré.

**Ce qui n'a pas été reproduit** : le parcours réel de l'utilisateur (nombre de
défis joués sur cet axe, part de séances normales vs bâclées). Un export
diagnostic trancherait — cf. plus bas.

---

## Est-ce une régression 0.6.0 ?

**Non.** Les trois maillons sont antérieurs :

| Maillon | Commit | Date | Première version |
|---|---|---|---|
| `bpmEnd = threshold` (rampe BPM) | `8de80a6` | 2026-05-19 | v0.4.2 |
| `recordChallengeReached(ch.bpmEnd)` | `1eaa5f7` | 2026-05-21 | v0.5.0 |
| `_raiseHumiliationFloorFromRecord` | `2fa2904` | 2026-05-21 | v0.5.0 |

La boucle est donc active depuis **v0.5.0** (2026-05-24). Cohérent avec « this
number gets higher every time » : c'est une accumulation lente sur plusieurs
versions, pas un défaut apparu avec la 0.6.0.

**Nuance sur les séances bâclées** : `CapabilityService.commit` est appelé avec
`quickie: _isQuickie` (`lib/controllers/session_controller.dart:1748-1749`), et
`regulate` ne recalibre pas le `comfort` en séance bâclée
(`capability_service.dart:303-310`). La capture montre un quickie, mais la
montée du `comfort` s'est faite lors de séances **normales** ; en quickie,
seuls `best` et le plancher d'humiliation bougent. La cible affichée dans un
quickie est donc le reflet d'un `comfort` gonflé ailleurs.

---

## Lien avec le coach verrouillé (problème 2) : **écarté**

Les deux problèmes ne se rejoignent pas, pour deux raisons indépendantes :

1. **Le déblocage des coachs ne dépend pas de la progression carrière.**
   `CoachService.syncFromTotalSeconds(totalSeconds)`
   (`lib/career/services/coach_service.dart:169-184`) ne lit que le **temps de
   jeu cumulé** (`stats.totalSeconds`). Ni le niveau, ni les milestones, ni les
   défis n'entrent dans le calcul. La cause du coach absent est celle déjà
   établie : la boucle de déblocage ne revisite jamais les tiers déjà franchis.
2. **Le défi n'est de toute façon pas bloquant** — il se réussit en attendant
   25 s (§ ci-dessus), et un défi raté n'empêche ni de terminer la séance, ni de
   valider une milestone (le défi ne fait qu'en *acquitter* en bonus,
   `_finalizeChallengeAcquittals`).

Le seul recouvrement entre les deux sujets est thématique — les deux touchent la
progression — pas causal.

**Non tranché (mineur)** : le `comfort` emballé rend l'axe
`rhythm.bpm_ceil.shallow` non contraignant en séance normale. Comme
`capabilityCapFor` n'est qu'un **plafond** (un `min`, jamais un boost —
`capability_clamps.dart:188-216`) et que le pacing carrière borne le rythme bien
en dessous (« le rythme carrière plafonne à 140 »,
`bpm_pacing.dart:35-36`), cela ne rend pas les séances plus rapides : cela retire
seulement à cet axe sa fonction de régulation. Aucun lien avec le gel de séance
du problème 1.

---

## Correctif proposé — non appliqué

Trois points, du plus sûr au plus structurel. Le premier suffit à stopper la
divergence.

1. **Créditer ce qui a été joué, pas ce qui a été demandé.**
   `session_controller_challenge.dart:714-715` : clamper la valeur créditée à la
   même borne que le moteur. Les bornes `20`/`300` sont aujourd'hui des
   littéraux dans `beep_engine.dart` — les extraire en constantes publiques
   plutôt que les redupliquer ici.

   ```dart
   case ChallengeAxisKind.bpm:
     final asked = ch.bpmEnd ?? ch.bpm ?? ch.targetThreshold;
     reached = asked.clamp(BeepEngine.kMinBpm, BeepEngine.kMaxBpm).toDouble();
     break;
   ```

   Effet : `reached ≤ 300` ⇒ `comfort` converge vers `300 × 1,15 ≈ 345` au lieu
   de diverger. Idempotent, sans effet sur les axes durée/profondeur.

2. **Borner la cible elle-même** dans `ChallengeService.thresholdFor` (branche
   `bpm`, cas `maximize`), symétrique du plancher 18 déjà présent pour
   `minimize`. Garantit qu'une bannière n'annonce jamais un nombre injouable,
   même si un `comfort` déjà corrompu est en base.

3. **Appliquer la même borne au plancher d'humiliation**
   (`_raiseHumiliationFloorFromRecord`, ligne 1179) — sinon un profil existant
   continue de propager un plancher à 4 chiffres à chaque succès sur l'axe.

**Non résolu par ces trois points, et à trancher côté produit** :

- Les profils **déjà corrompus** ne se réparent pas tout seuls : `comfort` ne
  redescend que sur signal négatif imputé (`× 0,85`,
  `capability_service.dart:314-327`), et le score d'humiliation carrière n'a
  aucun mécanisme de retour. Il faut décider d'une réconciliation au chargement
  (borner `comfort` et `best` des axes BPM à la limite moteur) — sinon
  l'utilisateur reste avec sa bannière absurde après mise à jour.
- **Faut-il créditer un succès obtenu en attendant 25 s ?** Le fond du défaut est
  là : la mécanique du défi BPM récompense la présence, pas la performance. Le
  borner rend le symptôme invisible sans traiter cette question. C'est un choix
  de design, pas un correctif.

---

## Ce qu'il manque — à demander à l'utilisateur

Rien n'est bloquant pour le diagnostic : la cause est établie et reproduite. Un
seul élément confirmerait l'état exact du profil :

- **Un export diagnostic** (Profil → DIAGNOSTIC → Exporter mes données). Les clés
  utiles : `cap.rhythm.bpm_ceil.shallow.comfort` / `.best` / `.sr`, et le score
  d'humiliation carrière. Cela dirait aussi si d'autres axes BPM
  (`throat`, `full`, `biffle.bpm_max`) ont dérivé de la même façon — ils
  partagent exactement le même chemin de code.
