---
type: analyse
sujet: voix-debit-et-hauteur-reglables-et-persistants-0-6-2
ecrit_le: 2026-08-18T16:20:15+02:00
auteur: session tss2-voix-debit-hauteur · claude-opus-5
revision: 7f119dcb
branche: develop
porte_sur:
  - rhythm_coach/lib/services/tts_service.dart
  - rhythm_coach/lib/widgets/coach_voice_picker.dart
  - rhythm_coach/lib/widgets/voice_settings_section.dart
provenance:
  mesure: 8
  deduit: 4
  document: 1
  sans_marqueur: 1
sources_citees: []
relu_contre: ⚠️ NON RENSEIGNÉ
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
> - 1 paragraphe porte un chiffre sans marqueur de provenance
> Pour en lever un, écrire dans ce document : `Waiver doc: <ce qui est levé> — <raison courte>`

## Ce dont il s'agit

Réglage du débit et de la hauteur de la voix, en deux volets : les rendre persistants pour la voix
par défaut (défaut avéré, hérité de la 0.6.1), puis les rendre réglables par coach avec retour
possible à la couleur d'origine du personnage.

**Révision jugée** : branche `feat/voice-rate-pitch` du dépôt BeatBitch, worktree
`~/perso/git/tss2-w1`, base `origin/develop` = `25657d5`. Quatre commits, tête `9e7c7c5`. **Rien n'a
été poussé, aucune PR ouverte, aucune issue créée.** [document]

## Ce que j'ai mesuré (commandes exécutées)

Toutes depuis `rhythm_coach/`, toutes bornées en temps.

- `flutter analyze` → **No issues found!** sur la tête de branche. [mesuré]
- `timeout 900 flutter test` → **1000 tests passés, 0 échec**, sorties redirigées vers fichier (jamais
  de `| grep | head` : SIGPIPE tue le run avec un exit 0 trompeur). Point de départ : 984 sur
  `origin/develop` une fois mes 6 premiers tests ajoutés ; 999 après le volet 2 ; 1000 après l'export
  par coach. **Aucun test perdu en route.** [mesuré]
- `dart format --set-exit-if-changed lib/ test/` → exit 0. [mesuré]

### Les tests discriminent-ils vraiment ?

Un test vert sur du code corrigé ne prouve rien tant qu'il n'a pas été vu rouge sur le code d'avant.

- **Volet 1** : les 6 cas rejoués sur le code d'avant (service et écran remis par `git stash`) →
  **4 rouges, 2 verts**. Les deux verts sont les cas d'arbitrage (défaut plateforme conservé quand rien
  n'est réglé ; réglage insensible au changement de langue) : leur rôle est de tenir dans les deux
  états. [mesuré]
- Un de ces tests **ne discriminait pas** à la première écriture : Flutter réutilisait le `State` du
  premier montage, les curseurs gardaient leur valeur en mémoire et le test passait sans qu'aucune
  préférence ait été relue. Corrigé en vidant l'arbre entre les deux montages ; c'est ce qui l'a fait
  passer de vert à rouge sur le code d'avant. [mesuré]
- **Volet 2** : le test ne peut pas être rouge sur du code pristine, l'API n'y existe pas. À la place,
  contre-épreuve ciblée : `applyCoachVoicePreset` a **quatre sorties**, chacune poussant son propre
  couple débit/hauteur. J'ai cassé la sortie anticipée (celle empruntée quand une voix mémorisée est
  trouvée) et rien d'autre → **le test « une voix choisie pour le coach n'annule pas sa vitesse
  réglée » échoue, seul**. Restauré, il repasse. [mesuré]

### Le coût de « curseurs visibles », en pixels

Mesuré en montant la fiche réelle à trois tailles d'écran, avec un test jetable supprimé depuis. La
feuille est déjà plafonnée à 70 % de la hauteur d'écran : elle ne grandit pas, **c'est la liste de
voix qui perd 153 px**. [mesuré]

- iPhone SE (320×568) : liste 255 → 102 px, **5 → 2 options visibles sans défiler**
- Pixel 7 (393×851) : liste 453 → 300 px, **9 → 6**
- Écran de test (800×600) : liste 294 → 141 px, **6 → 2**

Sur le plus petit écran que la PWA ait à servir, la liste de voix devient une fenêtre de deux lignes.
Elle reste entièrement atteignable — elle défile. **Remonté comme demandé, sans contournement.**

Effet de bord constaté et traité : deux tests existants tapaient une voix devenue hors écran. Plutôt
que de corriger les deux qui cassaient, **tous** les taps de voix des deux fichiers concernés passent
désormais par un défilement explicite — sinon la prochaine voix ajoutée recasse un test au hasard.
[mesuré]

## Ce que j'ai déduit (lu, non exécuté)

- Le volet 1 était **exactement** le défaut corrigé en 0.6.1 sur le choix de voix : les curseurs
  poussaient au moteur (`setRate` / `setPitch`) sans jamais écrire de préférence, et
  `restoreDefaultVoicePreset` reposait les défauts plateforme en sortie de séance. Le correctif suit
  le même partage des rôles : `setUserRate` / `setUserPitch` mémorisent, `setRate` / `setPitch` non —
  comme `setUserVoice` face à `setVoiceByName`. [déduit]
- Sur **Linux**, le débit et la hauteur ont une prise réelle même sans sélection de voix : `spd-say`
  les lit à chaque énoncé. Le rechargement est donc posé **avant** le retour anticipé Linux de
  `init()`. Non vérifié à l'exécution — les tests tournent en cible Android. [déduit]
- Le réglage par coach est résolu **une seule fois en tête** de `applyCoachVoicePreset`, jamais au fil
  de ses quatre sorties : quatre résolutions seraient quatre occasions d'en oublier une. Deux de ces
  sorties (Linux, Windows) ne sont pas atteignables par les tests. [déduit]
- L'export et l'import diagnostic ont été étendus aux quatre nouvelles clés. Ce n'était pas demandé,
  mais l'import est l'inverse de l'export : reposer la voix d'un profil sans sa couleur vocale
  laisserait un état vocal mixte, et l'asymétrie aurait été de mon fait. [déduit]

## Ce que je n'ai pas pu établir

- **Rien de ce qui sort du haut-parleur.** Aucune écoute : ni le rendu d'un débit, ni celui d'une
  hauteur, ni la cohérence entre ce qu'affiche un curseur et ce qu'entend la joueuse. Tout ce qui est
  écrit ici porte sur des nombres poussés à un faux moteur. C'est Manu qui écoutera.
- **Aucune exécution sur appareil ni sur navigateur** : pas de compilation Android (interdite, machine
  partagée), pas de test Safari iOS. Le remappage web du débit (`×2` sur Web Speech API) est traversé
  par le code de persistance sans avoir été exercé.
- **Windows et Linux** ne sont couverts par aucun test : `defaultTargetPlatform` vaut Android sous
  `flutter_test`. Les deux sorties de `applyCoachVoicePreset` propres à ces plateformes sont donc
  relues, pas éprouvées.
- **Un décalage connu sur Windows, non corrigé** : tant que rien n'est réglé pour un coach, la séance
  y applique la calibration Microsoft Julie et non le preset du coach — alors que le curseur affiche
  le preset. La valeur montrée n'est donc pas celle qui sortira. Reproduire la cascade de plateforme
  dans l'écran dupliquerait la logique du service ; dès qu'un curseur est touché, l'écart disparaît.
  Assumé, écrit dans le document de plan.
- **La lisibilité réelle sur petit écran** : je mesure 2 options visibles sur un iPhone SE, je ne sais
  pas si c'est vivable à l'usage. Chiffre, pas jugement.

## Décisions et arbitrages

**Tranché par Manu**, 2026-08-18, mot pour mot : **« visible »**. Les curseurs sont posés à même la
fiche du coach, pas repliés derrière un second geste.

**Retenu par moi, rediscutable** — ces six-là ne viennent pas de Manu et sont listés en détail dans
`~/.claude/orchestration/rapports/tss2/2026-08-18-voix-debit-hauteur-PLAN.md` : réglage global plutôt
que par langue (voix par défaut comme coachs), un seul bouton de retour pour les deux valeurs, bouton
affiché en permanence mais inerte, écriture au relâchement du curseur, et entrée des deux nombres dans
l'export de voix partageable.

## État de reprise

Les quatre commits tiennent debout et la suite est verte. **Rien n'est poussé.** Ce qui resterait à
faire, si quelqu'un reprend : écouter le rendu sur appareil, décider si les 2 options visibles sur
iPhone SE demandent un ajustement, et trancher les six arbitrages ci-dessus.
