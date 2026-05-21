# `tools/simulate_career.dart`

Simulateur de progression carrière BeatBitch. Rejoue N sessions sous
plusieurs profils de joueuse pour valider que les paliers (milestones,
unlocks, niveau, capability gating, défis intra-séance) tombent dans le
bon ordre — sans avoir à jouer 50 séances à la main après chaque
changement de mécanique.

## Lancer

Depuis `rhythm_coach/` :

```sh
dart run tools/simulate_career.dart           # tous les profils
dart run tools/simulate_career.dart --profile debutante
dart run tools/simulate_career.dart --profile avance,experte
dart run tools/simulate_career.dart --sessions 50 --seed 7
dart run tools/simulate_career.dart --format tsv --out /tmp/sim.tsv
```

Options :
- `--profile <a,b,...>` — limite aux profils nommés
- `--sessions <N>` — override du nombre de sessions par profil
- `--seed <n>` — seed RNG (défaut 42, déterministe)
- `--format markdown|tsv` — markdown (défaut, lecture humaine) ou TSV
  (post-traitement)
- `--out <path>` — fichier de sortie (défaut : stdout)

Le script n'a aucune dépendance Flutter et ne touche pas aux assets ;
il lit `assets/career/milestones.json` directement et réimplémente en
standalone la sélection des milestones (logique de
`MilestoneService.allPendingFor`), les deltas humil/obed de fin de
session, **et la mécanique des défis intra-séance** (calibration,
résolution outcome pondérée par la difficulté, acquittement implicite
de milestones avec cascade transitive holds).

## Profils embarqués

**4 tiers** (skillLevel croissant — pilote `P(fail défi)` et le nombre
d'extensions) :

| nom | skill | allocation | description |
|---|---:|---|---|
| `debutante` | 0.20 | 0 pt | Découvre la mécanique. Fail ambiant 20 %, milestones 65 %, peut PASSE pendant le breath (10 %). |
| `moyen` | 0.50 | 1-1-1-1-1 (L10) | Hybride confirmé. Fail 8 %, milestones 90 %, encore 30 %. |
| `avance` | 0.75 | 3 end + 2 obé (L10) | Spé soumise endurante. Fail 4 %, milestones 94 %, encore 45 %. |
| `experte` | 0.95 | 4 prof + 3 end + 2 rythme (L18+) | Fin de carrière. Fail 1 %, milestones 98 %, encore 60 %. |

**2 spé pathologiques** (cas extrêmes pour les détecteurs de
régression) :

| nom | skill | description |
|---|---:|---|
| `fail_prone` | 0.35 | Fail ambiant 25 %, milestones échouées 1/3, abandons fréquents. |
| `quickie_spammer` | 0.60 | Sessions bâclées 90 %. Pas de level-up. Pas de défi (parité prod : `!quickie`). |

Chaque profil porte :
- une allocation par branche de spécialisation,
- des probas (fail ambiant, encore, quickie, milestone clean, skip défi),
- un `skillLevel ∈ [0,1]` qui pilote la résolution du défi,
- une carte « axes capacité poussés par session » (cibles fonction du
  niveau + de l'allocation).

## Lire la sortie

Pour chaque profil, 3-4 sections :

### 1. Timeline

Une ligne par session :
`n° | level | humil | obed | milestone (body / final) | challenge | outcome | unlocks | axes touchés`.

- `↑` à côté du level signale un level-up à cette session.
- `challenge` au format `axis × outcome[×N]` :
  - `tut` — défi tutoriel (hold throat 5 s).
  - `net` — succès net (seuil atteint, JE M'ARRÊTE ou timeout).
  - `ext×N` — succès étendu avec N prolongations « JE TIENS ENCORE ».
  - `fail` — abandon avant le seuil.
  - `skip` — PASSE pressé pendant le breath.
  - `?` après l'axe signale un défi **exploratoire** (axe vierge).

### 2. Récap

- Sessions pour atteindre L5 / L10 / L15 / L20.
- Niveau / humil / obed finaux.
- Liste des unlocks acquis dans l'ordre (avec milestone d'origine ;
  ceux marqués `(challenge)` ou `(challenge:transitive)` sont issus de
  l'acquittement implicite via défi).
- Milestones jamais déclenchées en N sessions, avec la raison (level,
  humil, prérequis, capability gating manquant).

### 3. Défis intra-séance (si au moins 1 défi joué)

- Total et skill du profil.
- Distribution par outcome (tut / net / ext / fail / skip).
- Axes records poussés via défi (vs alimentés par milestone ou
  `axisTargets`) — utile pour voir si la surcharge cible bien l'axe
  voulu.
- Unlocks gagnés via défi (cascade transitive holds incluse).

### 4. Rapport de cohérence

Détecte automatiquement :

- `CAP-NEVER` — une milestone demande un axe capacité que le profil ne
  pousse jamais → milestone injouable pour ce style de jeu.
- `HUMIL-INV` — une milestone à `humilRequired` faible acquise *après*
  une milestone plus dure (gap > 5). Souvent un signal informationnel :
  le tri par branchScore peut volontairement retarder un palier facile
  dont la branche n'est pas investie. Vérifier au cas par cas.
- `LEVEL-STUCK` — niveau bloqué ≥ 5 sessions consécutives (typique du
  `quickie_spammer` ou d'une joueuse qui collectionne les fails).
- `FEATURE-MISSED` — une *feature-milestone* (`intro_surprise_notifs`,
  `intro_fake_breath`, `intro_freestyle`, `intro_encore`) reste pending
  alors que la joueuse est éligible (level, requires, capability OK).
  Signal qu'une feature peut rester invisible pour ce profil.
- `AXIS-IDLE` / `AXIS-DECAY` — un axe lié à une branche très investie
  (≥ 2 pts) qui n'a jamais été touché, ou qui est resté inactif ≥ 4
  sessions (au-delà de `CapabilityRegulator.kDecayAfterSessions`,
  `comfort` pourrait dériver vers 0,7 × best).

## Modélisation du défi

Réplique simplifiée de `ChallengeService.buildForSession` + résolution
mécanique de l'outcome (pas un % en dur).

### Sélection d'axe

- Session #1 (tutoriel) → `holdThroatStreak 5 s` scripté.
- Sinon → axe pilotant le plus ancien `lastSeen` parmi
  `_overloadableSimAxes` (réplique de `CapabilityClamps.overloadableAxes`),
  excluant ceux des milestones insérées cette session.
- Profil vide / tous axes exclus → axe vierge tiré au hasard
  (exploratoire, marqué `?` dans la timeline).

### Calibration

Aligné sur `fix/challenges-calibration-by-axis` :
- `kChallengeOverloadFactor = 1.30` (durée/BPM)
- durée nominale du step par axe (table `_challengeDurationFor` :
  shallow 25 s, throat/full 7-8 s, biffle BPM 20 s, depthCran 12 s)
- inversion `minimize` (division au lieu de multiplication, plancher
  BPM à 18) — défensif tant qu'aucun `minimize` n'est dans
  `overloadableAxes`.

### Difficulté

`d ∈ [0.20, 0.95]` calculé par axe + profondeur :

```
d = w_axis + 0.20 × depthFactor
```

| Catégorie axe | `w_axis` |
|---|---:|
| lick, biffle streak | 0.30 |
| rhythm shallow, biffle BPM | 0.45 |
| rhythm/gorge throat, motion, engagement, noswallow | 0.60 |
| rhythm/gorge full, hold throat, gorge apnée | 0.75 |
| hold full, depth_max, effortNoBreath | 0.90 |

`depthFactor = max(from.index, to.index) / (Position.values.length - 1)`.

Tutoriel forcé à `d = 0.30`. Exploratoire : `d - 0.15` (seuil initial
bas, pas de surcharge × 1.30).

### Outcome

```dart
P(skip)   = profile.challengeSkipProba             // 0.10 pour débutante, 0 ailleurs
P(fail)   = clamp((d − skill) × 1.6 + 0.05, 0.02, 0.95)
N_extens  = round(clamp((skill − d) × 8, 0, 5) + gauss(0, 0.5))
outcome   = N == 0 ? net : extended  (sauf si fail/skip déjà tirés)
```

### Effets

- **net** : `best[axis] = max(best, threshold)` (plafonné par
  `_axisChallengeCap` — le sim ne modélise pas le comfort, donc
  compounding 1.30^N borné manuellement), +2 humil career,
  `raiseCareerFloor` via `HumiliationScale.requiredFor` (palier humil
  de l'action prouvée), +2 obed.
- **extended ×N** : net + N × (+1 humil, +1 obed). `best` étendu pour
  les axes durée (`threshold + N × extensionSeconds`).
- **fail** : pas de malus career/obed (parité prod : fail défi est doux,
  juste soft-cap × 0.92 sur comfort, non simulé).
- **skip** : -3 obed.

### Acquittement implicite milestone

Parité avec `MilestoneService.milestonesAcquittableByChallenge` :
- Milestones dont `requiresCapability` matche l'axe (avec seuil
  atteint) + autres caps satisfaits + `requires` OK → marquées
  completed.
- Cascade transitive holds : un défi `hold.throat ≥ 3 s` acquitte aussi
  `holdHead`, `holdMidShort`, `finalHoldTip/Head/Mid`. Un défi
  `hold.full ≥ 3 s` ajoute `throatHoldShort` + `finalHoldThroat`.

## Quand le relancer

Après chaque modification de :
- la liste / les critères des milestones (`assets/career/milestones.json`,
  `MilestoneLoader`),
- la sélection des milestones (`MilestoneService.allPendingFor`,
  branchScore, branchAdvance, lowestBranch),
- les deltas humil/obed (`HumiliationEngine.applyEndOfSessionDelta`,
  tick rates, bumps),
- la règle de level-up (`CareerProgressService.recordSessionCompleted`),
- les seuils d'humil (`HumiliationScale.requiredFor`),
- la calibration des défis (`ChallengeService.thresholdFor`,
  `_kChallengeOverloadFactor`, table `_challengeDurationFor`),
- l'acquittement implicite via défi
  (`milestonesAcquittableByChallenge`, `_impliedHoldUnlocksByAxis`).

Le simulateur ne reproduit **pas** exactement le générateur de session
(`CareerSessionGenerator.generate`) ni l'autorégulation
(`CapabilityRegulator`) — il approxime les axes touchés par session via
les cibles de profil et la séquence des milestones insérées. Il est
suffisant pour repérer les **régressions d'ordre** (un palier qui se
bloque, une feature qui n'apparaît jamais, un gating capability sans
producteur d'axe), pas pour valider les valeurs précises de comfort.

Pour les valeurs exactes d'humil par milestone, garder
`tools/dump_milestone_humil.dart`.

## Limites connues

- Le `comfort` (boucle d'autorégulation Phase 3) n'est pas simulé — on
  ne tient que `best` monotone et `lastSeen` (assez pour flagger un
  decay potentiel). Conséquence côté défi : le ratchet `comfort × 1.30`
  par défi compounde à chaque session — borné par `_axisChallengeCap`
  pour rester réaliste.
- Le simulateur n'évalue pas la qualité musicale / dramaturgique d'une
  séance — seulement la mécanique de progression.
- Les heuristiques de « cibles d'axes par profil » sont éditoriales :
  un profil qui pousse `holdThroatStreak` à `1.5 + 0.6 × level` ne
  reflète pas exactement ce qu'une vraie joueuse atteindrait — c'est
  une approximation suffisante pour les comparaisons inter-profils.
- L'humiliation `session` est approximée à l'agrégat ; pas de modèle
  step-par-step du tick rate.
- La **difficulté du défi** dépend de (axe, profondeur) mais
  **pas de la valeur absolue du seuil**. Un hold throat 1 s sur
  débutante a la même `difficulty` qu'un hold throat 30 s sur experte.
  Conséquence : la débutante échoue souvent sur des défis dont le seuil
  absolu est trivial. À raffiner si nécessaire (intégrer `threshold`
  dans `_challengeDifficulty`).
