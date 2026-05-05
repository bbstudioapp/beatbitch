# Coachs — format des fichiers

Chaque coach est défini par **deux fichiers** dans ce dossier :

| Fichier                          | Contenu                                                              | Dépend de la langue ? |
|----------------------------------|----------------------------------------------------------------------|:---------------------:|
| `coach_<id>.json`                | Préférences gameplay (archetype, tier, isPrincipal, requirements…)   | non                   |
| `coach_<id>_<lang>.json`         | Contenu localisé : title, publicBio, phrases, nicknames              | oui                   |

Exemple :
- `coach_03_jade.json` — préférences globales de Jade (mêmes pour FR/EN/…)
- `coach_03_jade_fr.json` — phrases françaises de Jade

L'`id` du fichier doit correspondre à un coach déclaré dans `lib/career/models/coach_catalog.dart` (qui sert de **défauts** : si un fichier manque, l'app retombe sur les valeurs codées).

---

## Fichier global `coach_<id>.json` — préférences gameplay

```jsonc
{
  "id":          "coach_03_jade",         // documentaire (résolu par nom de fichier)
  "name":        "Jade",                  // prénom du coach (pas localisé)
  "archetype":   "taquinSadique",         // bienveillant | strict | taquinSadique | brutal | hautain | sansPitie
  "specialties": ["rythmeBiffle", "sloppy"],  // 0..N branches : endurance | profondeur | rythmeBiffle | obeissance | sloppy | resilience

  "tier":        3,                       // palier de coach (1..6) — détermine le déblocage
  "isPrincipal": true,                    // si true, c'est le Coach Principal du palier

  "requirements": {
    "requiresHands":            true,                          // toggle « inclure la main » actif
    "minPlayerLevel":           13,                            // niveau global minimum requis
    "mustHaveUnlockedBranches": ["profondeur"],                // 0..N branches à avoir investies (≥ 1 point)
    "requiredBranchPoints":     { "resilience": 3, "sloppy": 2 }  // seuils par branche (AND)
  }
}
```

Tous les champs sont **optionnels** : un champ absent = la valeur par défaut codée est conservée. Tu peux donc créer un fichier `coach_xx.json` ne contenant que `{ "tier": 4 }` pour ne changer que ça.

### Différence `mustHaveUnlockedBranches` vs `requiredBranchPoints`

- `mustHaveUnlockedBranches: ["profondeur"]` → "il faut **au moins 1 point** dans profondeur". Check binaire, simple.
- `requiredBranchPoints: { "profondeur": 3 }` → "il faut **au moins 3 points** dans profondeur". Pour des coachs qui n'apparaissent que quand le joueur a réellement spécialisé. Si une branche est dans les deux, c'est `requiredBranchPoints` qui gagne (seuil plus strict).

**Convention** : ne rédige dans le JSON que ce qui **diffère** du défaut. Réécrire `requiresHands: false` ou `mustHaveUnlockedBranches: []` partout est du bruit (ce sont les défauts de `CoachRequirement`). Pareil pour `requirements: {}` complètement vide → omettre la clé.

Défauts à ne pas répéter :
- `requirements.requiresHands` → `false`
- `requirements.minPlayerLevel` → `1`
- `requirements.mustHaveUnlockedBranches` → `[]`

> ⚠ **Ne jamais renommer un `id`** : il sert de clé pour la sélection persistée des joueurs ET de nom de fichier asset. Le renommer = perdre toutes les sélections existantes.

---

## Fichier localisé `coach_<id>_<lang>.json` — contenu affiché et phrases

```jsonc
{
  "lang":      "fr",                      // documentaire — n'est pas relu par le code
  "id":        "coach_03_jade",           // documentaire — la résolution se fait par le nom de fichier

  "title":     "Coach taquine",           // sous-titre affiché dans le picker (override si présent)
  "publicBio": "Joueuse, ironique...",    // bio affichée dans le picker (override si présent)

  // Phrases déclenchées en fonction du mode de step en cours et de
  // l'intensité demandée par le générateur.
  "phrases": {
    "rhythm":    { "soft": [], "medium": [], "hard": [] },
    "lick":      { "soft": [], "medium": [], "hard": [] },
    "biffle":    { "soft": [], "medium": [], "hard": [] },
    "hold":      { "soft": [], "medium": [], "hard": [], "finale": [] },
    "breath":    { "soft": [], "medium": [], "hard": [] },
    "beg":       { "soft": [], "medium": [], "hard": [], "insistent": [] },
    "freestyle": { "soft": [], "medium": [], "hard": [] },
    "hand":      { "soft": [], "medium": [], "hard": [] }
  },

  // Phrases transverses — pas liées à un mode particulier.
  "intros":   [],   // une phrase tirée à l'ouverture d'une séance carrière
  "congrats": [],   // une phrase tirée à la fin d'une séance complétée
  "encore":   [],   // une phrase tirée à l'ouverture d'une session « encore »

  // Phrases déclenchées au franchissement d'un seuil de la jauge d'excitation.
  "excitation": {
    "25": [],
    "50": [],
    "75": [],
    "90": []
  },

  // Surnoms utilisés par ce coach pour substituer {name} dans les phrases.
  "nicknames": {
    "pool":               [],     // surnoms propres au coach (toujours utilisés)
    "use_user_prenom":    false,  // si true, ajoute le prénom user au pool
    "use_user_nicknames": false   // si true, fusionne aussi avec le pool user
  }
}
```

---

## Détail des clés

### `lang` et `id`
Documentaires. Le code ne les relit pas — il déduit la langue et l'id du **nom de fichier**. Les laisser cohérents reste utile pour la maintenance.

### `phrases`
Map indexée par **mode de session**, puis par **tier d'intensité**.

#### Modes disponibles
Identiques à l'enum `SessionMode` :

| Mode        | Quand le générateur le tire                                       |
|-------------|-------------------------------------------------------------------|
| `rhythm`    | Loop BPM standard (alternance de positions)                       |
| `lick`      | Loop BPM léger / wet                                              |
| `biffle`    | Coups de queue rythmés (réservé aux coachs autorisant les mains)  |
| `hold`      | Maintien d'une position                                           |
| `breath`    | Pause respiration (souvent post-effort ou post-fail)              |
| `beg`       | Phase de supplique vocale                                         |
| `freestyle` | Plage libre entre 2 marqueurs sonores                             |
| `hand`      | Stimulation à la main (alternative douce)                         |

#### Tiers d'intensité
La clé est une chaîne libre. Conventions consommées par le code actuel :

| Tier         | Sens                                                          | Utilisé par                              |
|--------------|---------------------------------------------------------------|------------------------------------------|
| `soft`       | Début de séance, jauge d'excitation basse, ton doux           | Tous les modes                           |
| `medium`     | Milieu de séance, intensité moyenne                           | Tous les modes (et fallback de `pickFor`)|
| `hard`       | Fin de séance / pic d'intensité                               | Tous les modes                           |
| `finale`     | Phrases pour les holds finaux les plus longs                  | `hold` uniquement                        |
| `insistent`  | Beg du Supplier (boost de niveau en cours de séance)          | `beg` uniquement                         |
| `any`        | Filet de secours utilisé si le tier demandé est introuvable   | Tous les modes — rarement nécessaire     |

Tu peux ajouter d'autres tiers — ils seront ignorés tant que le générateur ne les demande pas.

#### Règle de fallback à l'intérieur d'un mode
`PhraseBank.pickFor(mode, tier)` :
1. Cherche `phrases[mode][tier]`.
2. Sinon `phrases[mode]['medium']`.
3. Sinon `phrases[mode]['any']`.
4. Sinon la première liste non-vide du mode.
5. Sinon → fallback **global** (cf. plus bas).

### `intros`
Phrase TTS jouée au démarrage d'une séance carrière classique (avant le décompte). Vide → tirage dans la banque globale (`assets/career/phrases.json` → `intros`).

### `congrats`
Phrase de fin de séance, jouée juste avant l'écran « finished ».

### `encore`
Phrase d'ouverture pour les sessions « encore » (relance immédiate après une séance terminée). Pas de décompte d'intro, donc cette phrase est jointe directement au tout premier step.

### `excitation`
Indexée par seuil de la jauge d'excitation (0–100 ou plus en mode encore). Chaque seuil n'est franchi **qu'une fois par séance** — la phrase est lue une fois, pas en boucle.

Seuils canoniques : `25`, `50`, `75`, `90`. Tu peux en ajouter d'autres, mais le `ExcitationEngine` ne les déclenchera que s'ils sont câblés côté code.

### `nicknames`
Pilote la résolution du placeholder `{name}` dans **toutes** les phrases du coach (pack coach + fallback global). Tirage aléatoire à chaque occurrence — deux `{name}` dans la même phrase peuvent renvoyer deux surnoms différents.

| Clé                   | Type        | Effet                                                                              |
|-----------------------|-------------|------------------------------------------------------------------------------------|
| `pool`                | `string[]`  | Surnoms propres au coach. Toujours dans le pool effectif.                          |
| `use_user_prenom`     | `bool`      | Si true, ajoute `UserProfileService.prenom` (s'il est défini) au pool effectif.    |
| `use_user_nicknames`  | `bool`      | Si true, fusionne avec le pool user complet (defaults activés + customs).          |

**Règle de fallback** :
1. Pool effectif = `pool` + (prénom user si `use_user_prenom`) + (pool user si `use_user_nicknames`).
2. Si vide → fallback sur le pool user complet (`UserProfileService.activePool`).
3. Si vide même là → `'salope'` (alignement sur le fallback historique).

**Cas d'usage typiques** :
- Coach bienveillant (Lina) : `use_user_prenom: true`, pool vide → appelle l'utilisatrice par son prénom (et fallback discret si pas défini).
- Coach humiliant (Nyx) : pool perso bien rempli, `use_user_prenom: false` → tirage exclusivement dans le pool coach, le prénom user est ignoré.
- Coach « variable » : pool perso + `use_user_nicknames: true` → mix des surnoms du coach et de ceux configurés par le user.
- Coach « neutre » : tout vide / tout false → fallback complet sur le pool user, comme le mode Scénario.

> Le pool user reste **toujours** la source de vérité pour le mode Scénario et les sessions hors-Carrière. Les overrides coach ne s'appliquent qu'à la session Carrière en cours et sont retirés automatiquement au retour de la séance.

---

## Règle de fallback inter-coach / global

Tout vide (clé absente, liste vide, mode entièrement omis) **retombe automatiquement** sur la banque globale `assets/career/phrases.json` (FR) ou `assets/career/phrases_<lang>.json`.

Conséquence pratique : tu peux ne rédiger pour un coach que **les phrases qui définissent sa voix**. Exemple typique pour Jade (taquine / sloppy / biffle) :

```jsonc
{
  "phrases": {
    "biffle": { "soft": ["..."], "medium": ["..."], "hard": ["..."] },
    "lick":   { "soft": ["..."], "medium": ["..."], "hard": ["..."] }
  },
  "intros":   ["..."],
  "congrats": ["..."]
}
```

Tous les autres modes (rhythm, hold, breath…) restent tirés dans la banque globale, ton neutre. Pas besoin de tout réécrire.

---

## Ajouter une langue

Pour livrer le coach Jade en anglais :

1. Créer `coach_03_jade_en.json` avec la même structure (peut être incomplet — fallback sur le `_fr.json` puis sur la globale).
2. S'assurer que `Locale('en')` est listée dans `kSupportedLocales` (`lib/services/locale_service.dart`).
3. Créer la banque globale anglaise `assets/career/phrases_en.json` si elle n'existe pas (sinon le fallback final tombera sur des phrases françaises).

> Le fichier global `coach_03_jade.json` n'est **pas** à dupliquer par langue — c'est tout son intérêt.

---

## Ajouter un coach

1. Ajouter une entrée minimale à `CoachCatalog.defaults` dans `lib/career/models/coach_catalog.dart` (au moins l'`id` — le reste peut venir du JSON).
2. Créer `coach_<id>.json` (préférences gameplay).
3. Créer `coach_<id>_fr.json` (contenu localisé) à partir d'un squelette existant.
4. (Optionnel) Si c'est un nouveau Coach Principal d'un nouveau palier, vérifier que `CoachTierMap` couvre bien le palier visé.

Aucun autre code à modifier — le `CoachService` détecte automatiquement les nouvelles entrées.

### Pourquoi conserver le code Dart ?

`CoachCatalog.defaults` agit comme **fallback de sécurité** : si tous les fichiers JSON disparaissent, l'app reste fonctionnelle avec les valeurs codées. Et l'`id` doit y être déclaré pour que le loader sache quels fichiers chercher (le dossier `coaches/` n'est pas scanné automatiquement, par sécurité).

---

## Validation au démarrage

Au boot, `CoachCatalogValidator.validate(coaches)` vérifie deux règles structurelles :

1. **Séquence de paliers complète** : pour chaque tier de 1 à max(tier), il existe **exactement un Principal**. Pas de trou (palier 2 absent), pas de doublon.
2. **`minPlayerLevel` strictement croissant** entre Principals consécutifs. Hélène (tier 2) ne peut pas avoir un `minPlayerLevel` ≤ celui de Lina (tier 1).

Comportement en cas d'incohérence :
- **debug** (`flutter run`) : `assert` qui pète au boot, message clair pointant le problème.
- **release** : log warning via `debugPrint` mais l'app continue (mode dégradé, pour ne pas crasher en prod).

Concrètement : si tu changes un `tier` ou un `minPlayerLevel` et que la séquence devient incohérente, tu le sauras au prochain `flutter run`.

---

## Diagnostic rapide

| Symptôme                                  | Cause probable                                                                |
|-------------------------------------------|-------------------------------------------------------------------------------|
| Le coach ne dit jamais de phrase perso    | Fichier mal nommé (id ou langue erronée), ou JSON invalide → check `flutter run` logs |
| La phrase tirée n'est pas la bonne tier   | Tier absent ou liste vide → `PhraseBank` retombe sur `medium` puis fallback   |
| Les seuils d'excitation ne se déclenchent | `ExcitationEngine` doit être actif (mode Carrière), seuils 25/50/75/90 attendus |
| Coach absent du picker                    | Pas dans `CoachCatalog.defaults`, ou tier > tier courant du joueur            |
