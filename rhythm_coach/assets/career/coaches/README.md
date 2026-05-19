# Coachs — format des fichiers

Chaque coach est défini par **deux fichiers** dans ce dossier :

| Fichier                          | Contenu                                                              | Dépend de la langue ? |
|----------------------------------|----------------------------------------------------------------------|:---------------------:|
| `coach_<id>.json`                | Préférences gameplay (archetype, tier, isPrincipal, requirements…)   | non                   |
| `coach_<id>_<lang>.json`         | Contenu localisé : title, publicBio, phrases, nicknames              | oui                   |

Exemple :
- `coach_03_jade.json` — préférences globales de Jade (mêmes pour FR/EN/…)
- `coach_03_jade_fr.json` — phrases françaises de Jade
- `portraits/coach_03_jade.png` — portrait de Jade (ratio source 2:3, voir plus bas)

L'`id` du fichier doit correspondre à un coach déclaré dans `lib/career/models/coach_catalog.dart` (qui sert de **défauts** : si un fichier manque, l'app retombe sur les valeurs codées).

Les **portraits** des coachs vivent dans le sous-dossier `portraits/` (cf. la section [Portraits des coachs](#portraits-des-coachs)).

---

## Fichier global `coach_<id>.json` — préférences gameplay

```jsonc
{
  "id":          "coach_03_jade",         // documentaire (résolu par nom de fichier)
  "name":        "Jade",                  // prénom du coach (pas localisé)
  "archetype":   "taquinSadique",         // bienveillant | strict | taquinSadique | brutal | hautain | sansPitie
  "specialties": ["rythmeBiffle", "sloppy"],  // 0..N branches : endurance | profondeur | rythmeBiffle | obeissance | sloppy

  "tier":        3,                       // palier de coach (1..6) — détermine le déblocage
  "isPrincipal": true,                    // si true, c'est le Coach Principal du palier

  "portrait":    "assets/career/coaches/portraits/coach_03_jade.png",  // chemin du portrait (override ; défaut codé)

  "requirements": {
    "requiresHands":            true,                          // toggle « inclure la main » actif
    "minPlayerLevel":           13                             // niveau global minimum requis
  }
}
```

Tous les champs sont **optionnels** : un champ absent = la valeur par défaut codée est conservée. Tu peux donc créer un fichier `coach_xx.json` ne contenant que `{ "tier": 4 }` pour ne changer que ça.

**Convention** : ne rédige dans le JSON que ce qui **diffère** du défaut. Réécrire `requiresHands: false` partout est du bruit (c'est le défaut de `CoachRequirement`). Pareil pour `requirements: {}` complètement vide → omettre la clé.

Défauts à ne pas répéter :
- `requirements.requiresHands` → `false`
- `requirements.minPlayerLevel` → `1`
- `portrait` → le chemin codé dans `CoachCatalog.defaults` (par convention `assets/career/coaches/portraits/<id>.png` pour les 6 coachs livrés). N'écrire la clé que pour pointer ailleurs.

> ⚠ **Ne jamais renommer un `id`** : il sert de clé pour la sélection persistée des joueurs ET de nom de fichier asset. Le renommer = perdre toutes les sélections existantes.

---

## Portraits des coachs

Chaque coach a un **portrait** affiché dans le sélecteur de coach (carrière + mode Custom) et sur la carte du coach actif de l'écran Carrière.

- **Emplacement** : `assets/career/coaches/portraits/<id>.png` — co-localisé avec les JSON, sous le sous-dossier `portraits/` (déclaré dans `pubspec.yaml` pour que Flutter bundle ce qu'il y trouve).
- **Assets externalisés** (comme `assets/backgrounds/` et `assets/audio/ambience/`) : les `.png`/`.jpg`/`.jpeg`/`.webp` du dossier sont **gitignorés**, pas versionnés. Seul un `.gitkeep` est suivi (pour que le dossier existe au build). La CI les rapatrie depuis le bucket R2 (préfixe `coach-portraits/v1/`, cf. `.github/workflows/release.yml`) ; un build sans accès R2 part avec le dossier vide → repli stylisé en jeu (cf. ci-dessous). Voir aussi `CLAUDE.md` → « Assets binaires externalisés ».
- **Format** : PNG (ou tout format géré par `Image.asset`), ratio source **2:3** (les portraits actuels font 512×768). L'UI recadre en `BoxFit.cover`, donc un autre ratio fonctionne mais sera rogné.
- **Mapping** : le chemin attendu est codé dans `CoachCatalog.defaults` (champ `portraitAsset`, par convention `'$_portraitDir/<id>.png'`). Pour pointer ailleurs, ajouter la clé `"portrait": "..."` au `coach_<id>.json` (langue-indépendant — un portrait ne se traduit pas). Un coach sans portrait (`portraitAsset == null`, **ou** asset déclaré mais absent du bundle) affiche un **repli stylisé** : l'initiale du nom sur un cadre teinté (cf. `CoachPortrait` dans `lib/career/widgets/coach_portrait.dart`). La feature ne casse jamais si l'image manque — même esprit que `SessionBackground`.

> ⚠ **NSFW** : ces portraits sont des images explicites, au même titre que les `assets/backgrounds/`. À garder à l'esprit pour les captures marketing / stores.

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

  // Phrases déclenchées au franchissement d'un seuil de progression de la
  // séance (ratio elapsedSeconds / durationSeconds × 100).
  "progress": {
    "25": [],
    "50": [],
    "75": [],
    "90": []
  },

  // Phrases du « profil de capacités » — annonces parcimonieuses liées à
  // l'axe poussé exprès dans la séance (cf. section dédiée plus bas).
  // Clé = storageKey de l'axe (ex. "gorge.apnee_streak"), 3 tiers.
  "progressPhrases": {
    // "gorge.apnee_streak": { "attempt": [], "record": [], "tapout": [] }
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
| `soft`       | Début de séance, ton doux                                     | Tous les modes                           |
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

### `progress`
Indexée par seuil de progression de la séance, en pourcent (`elapsedSeconds / durationSeconds × 100`). Chaque seuil n'est franchi **qu'une fois par séance** — la phrase est lue une fois, pas en boucle.

Seuils canoniques : `25`, `50`, `75`, `90`. Tu peux en ajouter d'autres, mais le `SessionController` ne les déclenchera que s'ils sont câblés côté code.

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

### `progressPhrases` — coach audible sur le profil de capacités

Section **optionnelle** qui donne une voix à la 2ᵉ enveloppe de difficulté carrière (le « profil de capacités » : compteurs par pratique — profondeur, apnée, vitesse, salive…). Le générateur choisit un **axe à pousser exprès** à chaque séance (la « surcharge » — un seul axe par séance, pour que tout ratage soit attribuable) ; ces phrases racontent cette intention au joueur.

**Carrière uniquement.** Hors carrière (Custom, scénarios JSON), le profil n'est pas suivi → ces phrases ne sont jamais déclenchées, peu importe ce qu'il y a dans le JSON.

#### Format

```jsonc
"progressPhrases": {
  "<axe.storageKey>": {
    "attempt": [ "phrase 1", "phrase 2", ... ],
    "record":  [ "phrase 1", "phrase 2", ... ],
    "tapout":  [ "phrase 1", "phrase 2", ... ]
  }
}
```

La clé d'axe est la **storageKey** brute de l'enum `CapabilityAxis` (cf. `lib/services/capability_axis.dart`). Une clé inconnue est conservée silencieusement mais ne sera jamais consultée. Un tier absent / liste vide → silence (l'appelant ne dit rien). Les `{name}` / `{coach}` sont supportés comme partout ailleurs.

#### Les trois tiers — semantique et déclenchement

| Tier      | Quand                                                                                                    | Qui le prononce                                          | Effet de bord                                                                                  |
|-----------|----------------------------------------------------------------------------------------------------------|----------------------------------------------------------|-----------------------------------------------------------------------------------------------|
| `attempt` | Tout début de séance, **à la place** de l'ouverture générique du step #0. Annonce l'intention.           | **Générateur** (`CareerSessionGenerator`)                | Aucun (remplace juste le texte du step #0).                                                   |
| `record`  | **Fin** de séance (post-bascule `finished`), seulement si la joueuse a battu son `best` pré-séance sur l'axe poussé. | **`SessionController`** (`_finish`)                      | Bump permanent +2 humiliation career et +2 obéissance, posé **dès qu'un record est détecté** (indépendant du dé de l'annonce). |
| `tapout`  | **Sur un FAIL** (« je peux pas »), **à la place** de la phrase de fail standard, si le ratage est imputable à un axe vraiment poussé hors zone de confort. | **`SessionController`** (`triggerFail`)                  | Aucun — la phrase de fail standard est juste remplacée par une variante DOUCE « limite reconnue ».    |

**`tapout` n'est jamais une phrase humiliante.** C'est l'inverse : on dit « ok, c'était une vraie limite, on la respecte, on retravaillera ». L'humiliation du fail-flemme reste dans le pool `failPhrases` standard. Cf. les phrases existantes pour le ton.

#### Fréquence — quasi-muet aux premiers paliers

À chaque déclenchement potentiel, un dé `progressPhraseChanceForLevel(level)` est tiré :

| Niveau   | 1-4 | 5    | 6    | 7    | 8    | 9    | 10   | 11   | 12+   |
|----------|-----|------|------|------|------|------|------|------|-------|
| Chance   | 0 % | 5 %  | 10 % | 15 % | 20 % | 25 % | 30 % | 35 % | 40 %  |

Formule : `clamp((level − 4) × 0,05, 0, 0,40)` (cf. `CapabilityRegulator` dans `capability_service.dart`).

Et de toute façon, **rien ne se déclenche tant qu'aucun axe n'est consolidé** (~3-5 sessions par axe pour que le profil ait des données exploitables). Donc une joueuse débutante n'entendra rien, peu importe le niveau.

#### Axes disponibles

Seuls les axes « **pilotants** + utilisables pour la surcharge » peuvent déclencher des phrases. Les autres (floors BPM, `breath.min_dose`, `gorge.crossings_lifetime`, `lick.*`, `hand.streak`) sont enregistrés à titre de télémétrie / classement, mais le générateur ne les pousse jamais → mettre des phrases pour eux ne sert à rien.

| `storageKey`                  | Unité     | Sens du record (axe « j'ai prouvé que… »)                                              |
|-------------------------------|-----------|----------------------------------------------------------------------------------------|
| `gorge.apnee_streak`          | secondes  | apnée totale (zéro fenêtre d'air, hold/beg ≥ throat ou rhythm `from ≥ throat`)         |
| `gorge.engagement_streak`     | secondes  | gorge en jeu en continu (les fenêtres d'air entre coups sont OK)                       |
| `gorge.crossings_pm.throat`   | BPM       | vitesse soutenue d'allers-retours franchissants jusqu'à `throat`                       |
| `gorge.crossings_pm.full`     | BPM       | idem, jusqu'à `full`                                                                   |
| `rhythm.bpm_ceil.shallow`     | BPM       | tempo rythme max tenu sur `to ≤ mid`                                                   |
| `rhythm.bpm_ceil.throat`      | BPM       | tempo rythme max tenu sur `to = throat`                                                |
| `rhythm.bpm_ceil.full`        | BPM       | tempo rythme max tenu sur `to = full`                                                  |
| `rhythm.depth_max`            | cran      | cran de profondeur max tenu en rythme (`tip` < `head` < `mid` < `throat` < `full`)     |
| `rhythm.motion_streak`        | secondes  | mouvement rythmé ininterrompu (rhythm OU lick, hand exclu)                             |
| `hold.throat.streak`          | secondes  | hold/beg tenu exactement à `throat`                                                    |
| `hold.full.streak`            | secondes  | hold/beg tenu exactement à `full`                                                      |
| `noswallow.streak`            | secondes  | `swallowMode = forbidden` en continu, sans débordement                                 |
| `biffle.streak`               | secondes  | step `biffle` en continu                                                               |
| `biffle.bpm_max`              | BPM       | tempo biffle max                                                                       |
| `effort.no_breath_streak`     | secondes  | temps d'effort sans step `breath` de récup                                             |

> **Ne pas écrire de phrases pour `hand.streak`.** Hand est par convention « jamais un levier de difficulté ou d'humiliation » — un hold ou un rythme à la main ne doit jamais sonner comme un défi. Le compteur existe pour éventuellement *rallonger* les phases hand, pas pour les durcir.

#### Conseils éditoriaux

- **Choisis les axes qui collent à l'archétype.** Un coach « profondeur » (Victoria) parle de `rhythm.depth_max` / `gorge.apnee_streak` / `gorge.crossings_pm.full`. Un coach « endurance / sloppy » (Lina) parle de `gorge.engagement_streak` / `hold.throat.streak` / `noswallow.streak` / `effort.no_breath_streak`. Inutile de couvrir tous les axes : ce que tu n'écris pas → silence, c'est très bien.
- **Reste contextuel.** Ces phrases sont prononcées *pendant* la pipe, pas dans un débrief sportif. Vocabulaire concret (« la garder au fond », « bouche pleine », « sans respirer »…), pas « tu as battu ton record d'apnée ».
- **`tapout` reste doux, toujours.** Même chez un coach très dur (Victoria), le tapout dit « limite reconnue, on y reviendra ». L'humiliation appartient au pool `failPhrases` (fail-flemme), pas ici.
- **Petit volume suffit.** 2-3 phrases par tier par axe couvre largement (déclenchement rare ∝ niveau, donc peu de répétition perçue).

#### Exemple condensé

```jsonc
"progressPhrases": {
  "gorge.apnee_streak": {
    "attempt": [
      "Ce soir on coupe l'air plus longtemps {name}. Apprends à ne plus en avoir besoin."
    ],
    "record": [
      "Record d'apnée {name}. Ta gorge sait maintenant qui décide quand elle respire."
    ],
    "tapout": [
      "Tu as eu besoin d'air {name}, ok — c'est la vraie limite. On la repousse la prochaine fois."
    ]
  }
}
```

Aucune phrase écrite ailleurs → tous les autres axes restent silencieux pour ce coach, et le fail standard continue de tirer dans `failPhrases` global.

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

1. Ajouter une entrée minimale à `CoachCatalog.defaults` dans `lib/career/models/coach_catalog.dart` (au moins l'`id` — le reste peut venir du JSON). Renseigner `portraitAsset` (par convention `'$_portraitDir/<id>.png'`).
2. Portrait : déposer `portraits/<id>.png` en local (ratio 2:3) **et** l'uploader sur R2 (`coach-portraits/v1/<id>.png`) pour qu'il soit bundlé par la CI — c'est un asset externalisé, pas versionné. Optionnel : sans portrait, l'UI montre le repli initiale.
3. Créer `coach_<id>.json` (préférences gameplay).
4. Créer `coach_<id>_fr.json` (contenu localisé) à partir d'un squelette existant.
5. (Optionnel) Si c'est un nouveau Coach Principal d'un nouveau palier, vérifier que `CoachTierMap` couvre bien le palier visé.

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

| Symptôme                                              | Cause probable                                                                                                |
|-------------------------------------------------------|---------------------------------------------------------------------------------------------------------------|
| Le coach ne dit jamais de phrase perso                | Fichier mal nommé (id ou langue erronée), ou JSON invalide → check `flutter run` logs                          |
| La phrase tirée n'est pas la bonne tier               | Tier absent ou liste vide → `PhraseBank` retombe sur `medium` puis fallback                                    |
| Les seuils `progress` ne se déclenchent               | Mode Carrière requis (PhraseBank fournie), seuils 25/50/75/90 attendus                                         |
| Coach absent du picker                                | Pas dans `CoachCatalog.defaults`, ou tier > tier courant du joueur                                            |
| `progressPhrases` jamais entendues                    | Bas niveau (chance 0 % aux niv ≤ 4) ; profil neuf (aucun axe consolidé) ; hors carrière (Custom/scénario) ; clé d'axe mal orthographiée (cf. `storageKey` exactes du tableau plus haut) |
| Phrase `tapout` jouée alors qu'on visait fail-flemme  | Le fail a été imputé à l'axe poussé (ratio figé/comfort > 1). C'est attendu — le pool `failPhrases` standard ne sort que sur fail dans la zone de confort. |
