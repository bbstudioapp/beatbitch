# BeatBitch — Guide des formats éditoriaux

> Doc destinée aux **contributeurs humains** et **assistants IA** (ChatGPT,
> Claude, etc.) qui veulent produire du contenu pour BeatBitch : phrases
> coach, scénarios, surnoms, packs d'ambiance, milestones, traductions.

L'objectif est qu'une IA puisse, à partir de ce seul fichier, produire un JSON
**directement consommable** par le générateur sans modification de code. Si tu
es l'IA et qu'on te demande de générer du contenu : lis ce fichier en entier
avant de proposer quoi que ce soit.

---

## 1. Contexte du projet

BeatBitch est un coach vocal rythmique pour Android — l'utilisatrice pose son
téléphone à plat à côté d'elle et suit la voix + les bips de guidage pour
des séances d'entraînement à la fellation. Tout est local (TTS hors-ligne,
zéro réseau).

**Ton dominant** : voix féminine ferme, registre cru, rapport de domination
soft à hard selon le contexte. Le tutoiement est par défaut. Le coach
s'adresse à l'utilisatrice à la 2e personne, jamais à un homme générique.

**Langues actuelles** : français (livré), anglais (en cours). L'infrastructure
accepte n'importe quelle langue par ajout de fichiers `<asset>_<lang>.json`.

---

## 2. Règles éditoriales — à respecter strictement

### À faire

- **Tutoiement** systématique en FR. En EN, ton direct sans formule de politesse.
- **Voix de coach féminine**. La coach parle d'elle au féminin (« je suis fière
  de toi », « ma chienne »).
- **Adresse à la 2e personne** : « tu », « toi », « your ». Jamais « il », « elle ».
- **Cohérence de tier** : une phrase rangée en `soft` ne doit pas être hard,
  et inversement. Le générateur tire selon l'intensité demandée — un soft
  qui contient « salope » va casser la dramaturgie d'un échauffement.
- **Placeholders bien orthographiés** : `{name}` (avec accolades, en minuscules,
  sans espace). `{coach}` pour l'auto-référence.
- **Verbes à l'impératif** ou à l'indicatif présent. Évite le futur.
- **Phrases courtes**. Ce qui passe vite à l'oreille passe bien — 4 à 12 mots
  pour les soft/medium, jusqu'à 20 pour les boost/finale.
- **Variété**. Si tu produis 20 phrases d'un coup, vérifie qu'il n'y en a pas
  3 qui commencent par le même mot.

### À ne pas faire

- ❌ **Le mode `hand` n'est jamais humiliant.** Quel que soit le BPM, la
  profondeur, ou le tier, les phrases du mode hand restent neutres ou
  encourageantes — c'est un mode pour entretenir l'excitation et l'endurance,
  jamais un levier d'humiliation. Pas de « pauvre fille qui n'arrive même
  pas à sucer », pas de « tu n'es bonne qu'à branler ».
- ❌ **Pas de mention de mineurs**, jamais, sous aucune forme indirecte.
- ❌ **Pas de scénarios non-consensuels** (kidnapping, viol scénarisé, etc.).
  L'app est un outil de jeu solo, le cadre reste consensuel.
- ❌ **Pas de pronoms masculins pour l'utilisatrice**. Le contenu cible des
  utilisatrices ; même si l'app est ouverte à tout le monde, le casting
  textuel reste « elle ».
- ❌ **Pas de noms de marques** (Apple, Tesla, etc.) — vieillit mal.
- ❌ **Pas d'émojis dans les phrases** — elles passent par le TTS, l'émoji
  est lu comme du symbole.
- ❌ **Pas de URLs, mentions Reddit, hashtags** dans les phrases coach.

### Patterns à éviter

- Phrases trop longues qui font drifter le tempo : « Je voudrais que tu
  songes à ralentir un peu si tu sens que… » → coupe.
- Méta-phrases : « bienvenue dans cette séance d'entraînement » — la coach
  *est* dans la séance, elle ne la commente pas.
- Phrases interchangeables entre coachs : si tu écris pour Lina (douce) et
  que la phrase pourrait sortir de la bouche de Nyx (sadique), le tier
  est probablement faux.

---

## 3. Vocabulaire commun

### 3.1 Modes de session (8)

| Mode | Description | Champs typiques |
|---|---|---|
| `rhythm` | Loop BPM standard, alterne `from`/`to` à chaque beat | `from`, `to`, `bpm` |
| `lick` | Comme rhythm mais volume réduit (effet léger, mouillé) | `from`, `to`, `bpm` |
| `biffle` | Coups de queue rythmés sur le visage (sample dédié) | `bpm` (pas de from/to) |
| `hold` | Maintien d'une position pendant `duration` secondes | `to`, `duration` |
| `breath` | Pause respiration | `duration` |
| `beg` | Phase de supplique vocale | `duration`, optionnellement `from` |
| `freestyle` | Plage libre entre 2 marqueurs | `duration` |
| `hand` | Stimulation à la main (alternance descendant/remontant) | `from`, `to`, `bpm` |

### 3.2 Positions (5 niveaux du plus aigu au plus profond)

```
tip → head → mid → throat → full
```

Règle de step : **`from` doit toujours être plus aigu que `to`**. Pas
d'égalité (`head → head` interdit), pas d'inversion (`throat → tip`
interdit). Quand tu écris une amplitude, la convention est « du plus haut
vers le plus profond ».

### 3.3 Tiers de phrases

| Tier | Sens | Modes concernés |
|---|---|---|
| `soft` | Début de séance, ton doux | tous |
| `medium` | Milieu de séance, intensité moyenne | tous (et fallback) |
| `hard` | Fin de séance, pic d'intensité | tous |
| `boost` | Transition montée d'intensité (avant le finale) | rhythm, lick, biffle, hold |
| `finale` | Apothéose / climax | tous (pour finals scriptés) |
| `insistent` | Beg du Supplier (boost en cours de séance) | `beg` uniquement |
| `any` | Filet de secours si tier introuvable | tous (rarement utilisé) |

### 3.4 BPM — fourchettes typiques

| Mode | Fourchette confortable | Plafond pratique |
|---|---|---|
| `rhythm` | 50–140 | 180 max |
| `lick` | 50–90 | 120 max |
| `biffle` | 90–135 | 160 max |
| `hand` | 50–130 | 170 max |

`hold` / `breath` / `beg` / `freestyle` : pas de BPM (ce ne sont pas des
loops rythmés).

### 3.5 Placeholders

| Placeholder | Substitution | Où l'utiliser |
|---|---|---|
| `{name}` | Surnom tiré du pool actif | partout — surnom de l'utilisatrice |
| `{coach}` | Nom du coach (« Lina », « Nyx », etc.) | dans les `beg` / `intros` / phrases d'auto-référence |
| `{seconds}` | Substitution numérique | uniquement dans `coach_<lang>.json > system.prep_countdown` |

⚠ Deux occurrences de `{name}` dans la même phrase peuvent renvoyer **deux
surnoms différents** (tirage indépendant). Si tu veux un seul surnom répété,
écris-le une fois.

---

## 4. Tableau des fichiers éditoriaux

| Fichier | Rôle | Doc dédiée |
|---|---|---|
| `assets/sessions/<id>.json` | Scénario complet jouable en mode Scénario | §5 |
| `assets/punishments.json` | Phrases de fail + mini-séquences de punition | §6 |
| `assets/random_comments.json` | Commentaires intercalés en cours de séance | §7 |
| `assets/nicknames.json` | Pool de surnoms par défaut | §8 |
| `assets/ambience_packs.json` | Packs ambiance MP3 par mode | §9 |
| `assets/career/phrases.json` | Banque globale de phrases coach (carrière) | §10 |
| `assets/career/coaches/coach_<id>_<lang>.json` | Phrases d'un coach spécifique | §11 (renvoie au README dédié) |
| `assets/career/milestones.json` | Séquences pédagogiques d'apprentissage | §12 |
| `assets/coach/coach_<lang>.json` | Phrases système (caméra, countdown, test voix) | §13 |

**Règle de nommage par langue** : pour le français, le fichier garde son
nom historique sans suffixe (`punishments.json`). Pour toute autre langue,
le suffixe `_<code>` est ajouté (`punishments_en.json`, `nicknames_de.json`).
Tous les fichiers déclarent leur langue dans une clé top-level `"lang": "fr"`.

---

## 5. Sessions — `assets/sessions/<id>.json`

Une session = un scénario scripté avec une durée fixe et une timeline de
steps. Joué dans le mode Scénario (différent du mode Carrière qui est
généré).

### Schéma

```jsonc
{
  "lang": "fr",
  "id": "ma_session",                       // unique, kebab_case
  "name": "Nom affiché",                    // 2-4 mots
  "description": "Phrase courte de pitch.", // 1-2 phrases, vue dans le picker
  "duration_seconds": 480,                  // durée totale (8 min ici)
  "mode": "rhythm",                         // mode par défaut si un step ne le précise pas
  "intro": "Phrase parlée au démarrage.",   // optionnel — sinon le décompte direct
  "steps": [
    {"time": 0, "text": "Phrase parlée.", "mode": "rhythm", "from": "tip", "to": "head", "bpm": 50},
    {"time": 30, "text": "Commentaire intercalé sans changer le rythme."},
    {"time": 60, "mode": "rhythm", "from": "head", "to": "mid", "bpm": 75},
    {"time": 240, "text": "Pause respiration.", "mode": "breath", "duration": 8},
    {"time": 248, "mode": "hold", "to": "throat", "duration": 12}
  ]
}
```

### Règles importantes

- `time` est en **secondes depuis le début de la session**. Strictement croissant.
- Un step **sans** `mode/from/to/bpm/duration` est un `text-only` : il parle
  une phrase mais **ne change pas le loop courant**. Idéal pour intercaler
  des commentaires sans casser le rythme.
- Pour `rhythm` / `lick` / `hand` : `from` + `to` + `bpm` requis.
- Pour `hold` : `to` + `duration` requis.
- Pour `breath` / `freestyle` : `duration` requis.
- Pour `biffle` : `bpm` requis (pas de from/to).
- Pour `beg` : `duration` requis ; `from` optionnel (pour ancrer une position
  pendant la supplique — si absent, supplique « libre »).
- Le **dernier** step doit faire sens comme « fin » — souvent un step de
  décélération vers `tip→head` puis un text-only « terminé ».
- Penser à **inscrire la session dans `lib/services/session_loader.dart` →
  `_assetPaths`** (sinon elle ne sera pas chargée). Cette étape est faite
  par les développeurs après merge ; un contributeur éditorial n'a pas à
  toucher au code.

### Bonnes pratiques de scénario

- **Courbe d'intensité** : monter progressivement (BPM + profondeur), placer
  un creux à mi-séance, repartir, finir sur un sprint.
- **Pas plus de 60 s de loop identique** sans phrase intercalée — l'oreille
  se déconnecte.
- **Synchroniser la phrase avec le changement** : la phrase qui dit « plus
  vite » est sur le step qui change le BPM, pas 30 s plus tard.

---

## 6. Punitions — `assets/punishments.json`

Joué quand l'utilisatrice appuie sur **Je peux pas** pendant une séance.

### Schéma

```jsonc
{
  "lang": "fr",
  "fail_phrases": [
    "Phrases tirées en premier après l'appui sur le bouton.",
    "Tu abandonnes déjà ?"
  ],
  "fail_phrases_swallow": [
    "Variante : tirée si l'utilisatrice a violé une règle de no-swallow.",
    "Tu as avalé. On va corriger ça."
  ],
  "punishments": [
    {
      "id": "extra_throat",
      "name": "Extra Throat",
      "duration_seconds": 45,
      "steps": [
        {"time": 0, "text": "Punition.", "mode": "rhythm", "from": "throat", "to": "full", "bpm": 100},
        {"time": 20, "text": "Plus profond."},
        {"time": 35, "text": "Hold final.", "mode": "hold", "to": "full", "duration": 8}
      ]
    }
  ]
}
```

### Règles

- `fail_phrases[]` : phrases courtes (8-15 mots), tirées au hasard. Tier
  implicite **hard** — ce sont des reproches.
- `fail_phrases_swallow[]` : optionnel, version « tu as désobéi à la consigne
  no-swallow ».
- Chaque `punishment` a une timeline interne en time **relatif** (`time: 0`
  = début de la punition). Mêmes règles de step que pour les sessions.
- Durée 25-60 s typique. Plus court = peu satisfaisant ; plus long = casse
  le rythme de la séance principale.
- Une bonne punition combine au moins 2 modes (rhythm + hold, biffle + lick,
  etc.) pour ne pas être un simple « plus vite, plus profond ».

---

## 7. Random comments — `assets/random_comments.json`

Phrases tirées aléatoirement pendant la séance, sans casser les phrases
scriptées des steps.

### Schéma

```jsonc
{
  "lang": "fr",
  "min_interval_seconds": 15,
  "max_interval_seconds": 40,
  "scripted_cooldown_seconds": 4,
  "comments": [
    "Continue {name}.",
    "Plus fort.",
    {"text": "Bave bien {name}.", "requires_unlock": "sloppy_drool_basic"},
    {"text": "Va plus profond.", "modes": ["rhythm", "lick"], "min_depth": "throat"},
    {"text": "Plus vite avec la main {name}.", "modes": ["hand"], "min_bpm": 120},
    {"text": "Doucement, prends ton temps.", "modes": ["lick"], "max_bpm": 70}
  ]
}
```

### Règles

- `comments[]` accepte deux formats par entrée :
  - **String simple** : phrase universelle, peut tomber n'importe quand.
  - **Objet avec filtres** : ne sortira que si le contexte courant
    correspond à tous les filtres présents.

| Filtre | Effet |
|---|---|
| `modes: ["rhythm", "lick"]` | ne sort que si le mode courant est dans la liste |
| `min_bpm: 120` | ne sort que si BPM courant ≥ 120 |
| `max_bpm: 70` | ne sort que si BPM courant ≤ 70 |
| `min_depth: "throat"` | ne sort que si profondeur courante (`to ?? from`) ≥ throat |
| `max_depth: "mid"` | ne sort que si profondeur courante ≤ mid |
| `requires_unlock: "key"` ou `["k1", "k2"]` | ne sort que si toutes les clés d'unlock sont acquises (carrière uniquement — voir `UnlockKey` dans le code Dart pour la liste exacte) |

- `min_interval_seconds` / `max_interval_seconds` : fenêtre aléatoire entre
  deux random comments (cadence). 15-40 s convient pour la plupart des
  séances.
- `scripted_cooldown_seconds` : délai après une phrase scriptée (texte d'un
  step) avant qu'un random puisse parler. 4 s par défaut.
- **Les phrases hand** dans random_comments doivent rester non-humiliantes
  (cf. règle générale §2). Si une phrase a `modes: ["hand"]`, son ton doit
  rester encourageant ou neutre.

---

## 8. Nicknames — `assets/nicknames.json`

Pool de surnoms par défaut (substitués dans `{name}` quand le coach ne
fournit pas son propre pool).

### Schéma

```jsonc
{
  "lang": "fr",
  "default_nicknames": [
    "salope",
    "petite salope",
    "petite pute",
    "jouet",
    "ma chienne"
  ]
}
```

### Règles

- Liste plate, 8-20 entrées idéalement.
- Tous **substituables** dans une phrase neutre — un surnom doit fonctionner
  derrière n'importe quelle phrase qui contient `{name}`. Évite les surnoms
  trop spécifiques (« ma queen sloppy »).
- L'utilisatrice peut activer/désactiver chaque surnom et en ajouter dans
  l'écran Profil. Le pool éditorial est un **point de départ**.

---

## 9. Ambience packs — `assets/ambience_packs.json`

Mappings « mode de session → MP3 d'ambiance d'arrière-plan ». Les MP3
eux-mêmes sont **gitignorés** (distribution hors-repo) ; le JSON ne fait
que pointer.

### Schéma

```jsonc
{
  "lang": "fr",
  "packs": [
    {
      "id": "intime",
      "name": "Intime",
      "description": "Drones harmoniques chauds, pulse cardiaque.",
      "tracks": {
        "rhythm": "audio/ambience/deep_drone.mp3",
        "lick": "audio/ambience/warm_drone.mp3",
        "biffle": "audio/ambience/heartbeat.mp3",
        "hold": "audio/ambience/tension_drone.mp3",
        "breath": "audio/ambience/warm_pad.mp3",
        "beg": null,
        "freestyle": null,
        "hand": "audio/ambience/warm_drone.mp3"
      }
    }
  ]
}
```

### Règles

- `id` unique, kebab_case.
- `name` court (1-2 mots), `description` 1 phrase qui dit *l'ambiance audio*,
  pas le scénario fictionnel.
- `tracks.<mode>` : chemin **relatif à `assets/`** vers un MP3, ou `null` =
  silence pour ce mode.
- Tous les modes ne doivent pas être présents — un mode absent = silence.
- Si un fichier référencé est manquant à la build, le pack reste utilisable
  (silence sur ce mode).

---

## 10. Banque globale de phrases carrière — `assets/career/phrases.json`

Phrases de fallback utilisées par le mode Carrière quand un coach n'a pas
de phrase pour un mode/tier donné.

### Schéma

```jsonc
{
  "lang": "fr",
  "rhythm": {
    "soft":   ["...", "..."],
    "medium": ["...", {"text": "Plus profond.", "min_depth": "mid"}],
    "hard":   ["..."],
    "boost":  ["..."],
    "finale": ["..."]
  },
  "lick":    { "soft": [], "medium": [], "hard": [], "finale": [] },
  "biffle":  { "soft": [], "medium": [], "hard": [], "finale": [] },
  "hold":    { "soft": [], "medium": [], "hard": [], "finale": [] },
  "breath":  { "soft": [], "medium": [], "hard": [] },
  "beg":     { "soft": [], "medium": [], "hard": [], "insistent": [] },
  "freestyle": { "soft": [], "medium": [], "hard": [] },
  "hand":    { "soft": [], "medium": [], "hard": [] },

  "intros":   ["..."],
  "congrats": ["..."],
  "encore":   ["..."],
  "progress": {
    "25": ["..."],
    "50": ["..."],
    "75": ["..."],
    "90": ["..."]
  }
}
```

### Règles

- Chaque phrase peut être une **string simple** ou un objet avec filtres
  (mêmes filtres que random_comments §7 — `min_depth`, `max_depth`,
  `min_bpm`, `max_bpm`, `requires_unlock`).
- `progress.25/50/75/90` : phrases déclenchées **une seule fois** quand la
  séance franchit ces seuils de progression (en pourcent).
- `intros` : tirée au démarrage d'une séance carrière classique.
- `congrats` : tirée à la fin d'une séance complétée.
- `encore` : tirée à l'ouverture d'un encore enchaîné.
- `boost` : tier dédié pour les transitions « ça monte ! » avant le finale.
  Phrases courtes et énergiques.
- `finale` : tier de l'apothéose. Le « je viens », « décharge », « avale ».

---

## 11. Coach individuel — `assets/career/coaches/coach_<id>_<lang>.json`

**Doc complète et exhaustive** : voir
[`assets/career/coaches/README.md`](../rhythm_coach/assets/career/coaches/README.md).

Résumé pour les contributeurs éditoriaux :

- Chaque coach a deux fichiers : un **global** (`coach_<id>.json` avec ses
  préférences gameplay : archetype, specialties, tier) et un **localisé**
  (`coach_<id>_<lang>.json` avec ses phrases).
- Le format des phrases du coach est **identique** au schéma de
  `phrases.json` (§10), avec en plus :
  - `randomComments[]` : remplace la liste globale pour ce coach (cadence
    héritée du fichier global).
  - `intros[]`, `congrats[]`, `encore[]`, `progress.{25,50,75,90}[]`.
  - `branchPhrases.{branche}.{tier}[]` : phrases colorées par branche de
    spécialisation (endurance, profondeur, rythmeBiffle, obeissance,
    sloppy, resilience). Tirées 30% du temps quand l'utilisatrice a une
    branche dominante (≥ 3 pts).
  - `nicknames.{pool, use_user_prenom, use_user_nicknames}` : pool de
    surnoms du coach + flags pour fusionner avec le prénom user.
  - `coachNicknames[]` : noms du coach (utilisés pour `{coach}`).
- **Tout est optionnel** sauf le minimum vital (au moins 1 mode avec 1 tier
  rempli). Tous les vides retombent sur la banque globale (§10).

**Pour un nouveau coach** : copie le squelette d'un coach existant
(`coach_01_lina_fr.json` est le plus complet) et remplis les phrases dans
le ton du nouveau coach.

---

## 12. Milestones — `assets/career/milestones.json`

Mini-scénarios pédagogiques insérés dans une séance carrière pour
**apprendre une nouvelle compétence** (lick full, hold throat, beg libre,
etc.).

### Schéma

```jsonc
{
  "lang": "fr",
  "milestones": [
    {
      "id": "intro_basics",                  // unique, kebab_case
      "level": 1,                            // niveau global minimum requis
      "displayLabel": "Première séance — apprends les bases",
      "unlocks": [                           // clés débloquées si milestone réussie
        "hand_basic",
        "lick_tip_basic",
        "rhythm_tip_head"
      ],
      "requires": [],                        // unlocks pré-requis (vide = aucun)
      "branches": ["profondeur"],            // optionnel — branches concernées
      "insertAtMinSeconds": 0,               // optionnel — fenêtre d'insertion
      "insertAtMaxSeconds": 0,
      "maxRetry": 2,                         // optionnel — nb de retries après fail
      "requiresHands": true,                 // optionnel — milestone hand-dépendante
      "sequence": [
        {"time": 0,  "text": "...", "mode": "breath", "duration": 8},
        {"time": 8,  "mode": "hand", "from": "tip", "to": "head", "bpm": 60, "duration": 10},
        {"time": 18, "text": "...", "mode": "rhythm", "from": "tip", "to": "head", "bpm": 70, "duration": 14}
      ]
    }
  ]
}
```

### Règles

- **`sequence`** est une mini-timeline (mêmes règles de step que les
  sessions). `time` en secondes relatives au début de la milestone.
- Chaque step de la séquence peut avoir un `text` (phrase coach scriptée,
  écrite en dur dans le JSON pour cette V1).
- Les `unlocks` sont des `UnlockKey` (cf. liste dans `lib/career/models/
  unlock_key.dart`). Les noms doivent matcher exactement.
- Une milestone est **insérée automatiquement** dans la séance carrière du
  niveau correspondant (sauf si déjà acquittée). Si l'utilisatrice fail
  pendant la fenêtre milestone, retry au prochain start (jusqu'à
  `maxRetry`).
- Une bonne séquence milestone fait **30-150 s**, alterne 3-6 steps, et
  finit sur un step doux (breath ou rhythm tip→head lent) pour la
  transition vers le reste de la séance.

---

## 13. Phrases système coach — `assets/coach/coach_<lang>.json`

Phrases hors-séance utilisées par les fonctions techniques (vérif caméra
des holds, décompte de prep, test de voix dans l'écran SONS).

### Schéma

```jsonc
{
  "lang": "fr",
  "hold_nudges": {
    "go_deeper": ["descends", "plus bas", "plus profond", "encore"],
    "go_up":     ["remonte", "moins profond", "remonte un peu"],
    "lost":      ["où es-tu", "reste dans le cadre", "remets-toi en place"]
  },
  "system": {
    "prep_countdown": "En place. Ça commence dans {seconds} secondes.",
    "encore_fallback": "Encore. On y retourne."
  },
  "test_phrases": {
    "voice":    "Allez, montre-moi ce que tu as. Plus profond, plus lent.",
    "identity": "Continue {name}. Tu vas y arriver {name}."
  }
}
```

### Règles

- `hold_nudges` : phrases **très courtes** (1-4 mots) — elles sont
  prononcées en cours de hold, l'utilisatrice n'a pas le temps d'écouter
  une phrase longue.
- `prep_countdown` : doit contenir `{seconds}` exactement (substitué par le
  nombre de secondes restantes avant le start).
- `test_phrases.voice` : phrase prononcée quand l'utilisatrice teste sa voix
  dans l'écran SONS — choisis une phrase représentative du ton de l'app.
- `test_phrases.identity` : phrase prononcée quand l'utilisatrice teste son
  prénom / surnom — doit contenir `{name}`.

---

## 14. Checklist avant de livrer une contribution

Si tu es une IA et qu'on te demande de produire un fichier complet, vérifie
ces points avant de retourner le JSON :

- [ ] **JSON valide** (parsable). Pas de virgule en trop, pas de commentaire
      `//` (sauf dans cette doc — les vrais fichiers sont du JSON pur).
- [ ] **Clé `"lang"`** présente au top-level avec le code langue correct.
- [ ] **Placeholders bien orthographiés** : `{name}` et `{coach}` exactement,
      pas `{Name}`, `{username}`, `${name}`, etc.
- [ ] **Tier cohérent avec le contenu** : aucune phrase mal rangée
      (soft qui contient « salope », hard sans intensité).
- [ ] **Mode `hand` non humiliant** (cf. règle stricte §2).
- [ ] **Pas d'occurrence répétée** : si tu produis 20 phrases, vérifie
      qu'aucune n'est doublée.
- [ ] **Filtres conditionnels valides** : `min_depth` est bien dans
      {tip, head, mid, throat, full}, `min_bpm` est un nombre, `modes`
      est un tableau de modes valides.
- [ ] **Pour les sessions/punitions/milestones** : pas de step `from→from`
      (égalité interdite), pas d'inversion `to` aigu vs `from` profond,
      `time` strictement croissant, `bpm` dans les fourchettes du §3.4.

### Format de livraison

- **Un fichier complet** plutôt que des fragments éparpillés. L'humain qui
  reçoit ta production doit pouvoir le copier tel quel dans
  `assets/<chemin>` et committer.
- **Pas de prose autour du JSON**. Si tu veux commenter, fais-le **avant**
  le bloc de code, pas dedans (le JSON pur ne supporte pas les commentaires).
- **Indentation cohérente** (2 ou 4 espaces, pas de mix).

---

## 15. Pour aller plus loin

- Architecture interne du générateur, du moteur d'excitation, des
  spécialisations : [`rhythm_coach/CLAUDE.md`](../rhythm_coach/CLAUDE.md).
- Format coach détaillé : [`assets/career/coaches/README.md`](../rhythm_coach/assets/career/coaches/README.md).
- Liste exhaustive des `UnlockKey` : `lib/career/models/unlock_key.dart`
  (à consulter si tu écris des `requires_unlock` ou `unlocks` de
  milestone).
- Branches de spécialisation : `lib/career/models/specialization.dart`.
