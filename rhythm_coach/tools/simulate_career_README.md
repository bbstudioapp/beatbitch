# `tools/simulate_career.dart`

Simulateur de progression carrière BeatBitch. Rejoue N sessions sous
plusieurs profils de joueuse pour valider que les paliers (milestones,
unlocks, niveau, capability gating) tombent dans le bon ordre — sans
avoir à jouer 50 séances à la main après chaque changement de
mécanique.

## Lancer

Depuis `rhythm_coach/` :

```sh
dart run tools/simulate_career.dart           # tous les profils
dart run tools/simulate_career.dart --profile purist_endurance
dart run tools/simulate_career.dart --profile profondeur_brutale,fail_prone
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
`MilestoneService.allPendingFor`) + les deltas humil/obed de fin de
session.

## Profils embarqués

| nom | description |
|---|---|
| `purist_endurance` | 5 pts endurance, zéro fail, holds throat/full longs |
| `profondeur_brutale` | 4 pts profondeur + 1 pt rythme, BPM throat + apnée |
| `sloppy_obeissante` | 3 pts sloppy + 2 pts obéissance, beg + lick humide |
| `hybride_prudente` | 1 pt par branche, valeurs modérées partout |
| `fail_prone` | fail ambiant 25 %, milestones échouées 1/3, abandons fréquents |
| `quickie_spammer` | sessions bâclées en permanence, pas de level-up |

Chaque profil porte :
- une allocation par branche de spécialisation,
- des probas (fail ambiant, encore, quickie, milestone clean),
- une carte « axes capacité poussés par session » (cibles fonction du
  niveau + de l'allocation).

## Lire la sortie

Pour chaque profil, 3 sections :

### 1. Timeline

Une ligne par session : `n° | level | humil career | obed | milestone
body / final inserted | outcome | unlocks gagnés | axes touchés`. La
flèche `↑` à côté du level signale un level-up à cette session.

### 2. Récap

- Sessions pour atteindre L5/L10/L15/L20.
- Niveau / humil / obed finaux.
- Liste des unlocks acquis dans l'ordre (avec milestone d'origine).
- Milestones jamais déclenchées en N sessions, avec la raison (level,
  humil, prérequis, capability gating manquant).

### 3. Rapport de cohérence

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

## Quand le relancer

Après chaque modification de :
- la liste / les critères des milestones (`assets/career/milestones.json`,
  `MilestoneLoader`),
- la sélection des milestones (`MilestoneService.allPendingFor`,
  branchScore, branchAdvance, lowestBranch),
- les deltas humil/obed (`HumiliationEngine.applyEndOfSessionDelta`,
  tick rates, bumps),
- la règle de level-up (`CareerProgressService.recordSessionCompleted`),
- les seuils d'humil (`HumiliationScale.requiredFor`).

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
  decay potentiel).
- Le simulateur n'évalue pas la qualité musicale / dramaturgique d'une
  séance — seulement la mécanique de progression.
- Les heuristiques de « cibles d'axes par profil » sont éditoriales :
  un profil qui pousse `holdThroatStreak` à `1.5 + 0.6 × level` ne
  reflète pas exactement ce qu'une vraie joueuse atteindrait — c'est
  une approximation suffisante pour les comparaisons inter-profils.
- L'humiliation `session` est approximée à l'agrégat ; pas de modèle
  step-par-step du tick rate.
