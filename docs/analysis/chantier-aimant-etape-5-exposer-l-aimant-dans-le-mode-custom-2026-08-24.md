---
type: analyse
sujet: chantier-aimant-etape-5-exposer-l-aimant-dans-le-mode-custom
ecrit_le: 2026-08-24T23:20:14+02:00
auteur: session tss2-etape5-ancrage-custom · claude-opus-5
revision: 09397fe
branche: feat/aimant-battement-inegal
porte_sur:
  - rhythm_coach/lib/career/models/career_generation_inputs.dart
  - rhythm_coach/lib/career/models/custom_session_config.dart
  - rhythm_coach/lib/career/screens/custom_config_editor_screen.dart
  - rhythm_coach/lib/career/screens/custom_mode_screen.dart
  - rhythm_coach/lib/career/services/career_level_gates.dart
  - rhythm_coach/lib/career/services/generation/career_session_generator.dart
  - rhythm_coach/lib/career/services/generation/finish_phase.dart
  - rhythm_coach/lib/career/services/generation/session_config.dart
  - rhythm_coach/lib/services/beep_engine.dart
provenance:
  mesure: 11
  deduit: 15
  document: 2
  sans_marqueur: 0
sources_citees: []
relu_contre:
  - rhythm_coach/lib/career/services/career_level_gates.dart:118
  - rhythm_coach/lib/career/services/career_level_gates.dart:143
  - rhythm_coach/lib/career/services/generation/finish_phase.dart:391
  - rhythm_coach/lib/services/beep_engine.dart:464
  - rhythm_coach/lib/services/beep_engine.dart:601
---

## Ce qui est livré

Trois réglages arrivent dans l'éditeur de configuration Custom — l'aimant allumé ou éteint, sa force
en trois crans nommés, et la position qu'il retient — et voyagent jusqu'aux steps que le mode Custom
produit. [mesuré] `flutter analyze` rend « No issues found! », `dart format --set-exit-if-changed`
0 fichier modifié, et `flutter test` 1160 tests verts.

[mesuré] La branche était à 1142 tests avant le travail ; l'écart de +18 est exactement le contenu
des trois fichiers de test ajoutés — 7 sur le chemin config → steps, 7 sur la sérialisation et la
compatibilité, 4 sur l'éditeur monté pour de vrai. Aucun test préexistant n'a changé de statut.

## Le constat qui a décidé de la forme du réglage

[mesuré] Une séance Custom **posait déjà des ancres avant ce travail**. Relevé sur le commit
`65d47a7`, aimant inexistant, sur douze séances — les quatre difficultés × trois graines :

| difficulté | niveau virtuel | ancres observées [mesuré] |
| --- | --- | --- |
| facile | 2 | 1 à 3 steps `rhythm`, ancre `from`, ratio 3 |
| normal | 6 | 3 à 6 steps `rhythm`, ancre `from`, ratio 3 |
| difficile | 11 | 3 à 7 steps `rhythm` ancre `to` ratio 3, plus le final `hold` ancré `to` ratio 9 |
| extreme | 18 | idem difficile |

[déduit] Ces ancres viennent des étapes 3 et 4 du chantier : le niveau virtuel de la config Custom
(2 / 6 / 11 / 18 selon la difficulté) traverse `CareerLevelGates.rhythmAnchorFor`, et à partir du
niveau 10 le final `hold` reçoit l'aimant très dur. Le mode Custom n'a jamais été à l'écart de ces
deux règles.

[document] Le prompt de mission supposait qu'une séance Custom sans aimant ne portait aucune ancre.
La mesure ci-dessus le réfute. Deux contraintes de la mission tranchent alors dans le même sens —
« une config déjà enregistrée doit jouer pareil » et « aimant éteint produit exactement les mêmes
steps qu'avant » : le réglage est une **surcharge additive**. Éteint, rien ne bouge, y compris ces
ancres-là. Allumé, le point et la force choisis priment.

L'alternative — éteindre veut dire zéro ancre — aurait fait rejouer autrement toutes les séances
Custom déjà enregistrées. Elle est écartée.

## Le chemin, d'un bout à l'autre

[déduit] Le réglage suit exactement la route des bornes BPM et des durées de tenue, déjà en place :

1. [déduit] `CustomSessionConfig` porte `anchorEnabled` (faux par défaut), `anchorStrength` et `anchorPoint` ;
   `resolveAnchor()` rend `(point, ratio)` ou `null` quand l'aimant est éteint.
2. `CustomOverrides.anchor` transporte ce couple depuis `custom_mode_screen`.
3. `SessionConfig.customAnchor` le fige pour la durée de la génération.
4. `_draftToStep` du générateur l'applique — et seulement à `rhythm` et `hold`.

[déduit] Hors Custom, `custom.anchor` reste `null` : la carrière ne traverse jamais la nouvelle
branche. Les deux points d'appel du mode Custom — la séance et « Termine-moi » — poussent le réglage.

## Ce que l'aimant fait, et ce qu'il ne fait pas

[déduit] Allumé, tout step `rhythm` du corps de séance reçoit le point et le ratio choisis, qu'il
soit sur un passage qui monte ou non. C'est le sens du réglage : la joueuse l'allume pour l'entendre
sur sa séance, pas sur trois steps.

[déduit] Un step `hold` n'est ancré que sur l'arrivée et si la position tenue n'est pas `tip` :
`BeepEngine` n'ouvre son aller-retour que sur `to`, et à `tip` il n'existe pas de position plus
aiguë. Ancré, il reçoit le bpm qui le cadence — sans lui, le moteur n'aurait aucune cadence à jouer.
Choisir « départ » laisse donc les tenues inchangées ; seuls les steps rythmés bougent.

[déduit] Aucun autre mode n'est touché : ni `lick`, ni `hand`, ni `beg`, ni `biffle`, ni `suckle`,
ni `freestyle`, ni `breath`. La condition d'entrée de la branche est `isRhythm || isHold`, et rien
d'autre.

[déduit] **La phase finish garde sa propre décision.** Les boosts et le final passent par le
`_draftToStep` dupliqué de `finish_phase.dart`, que la mission interdisait de toucher. Concrètement :
en difficulté « difficile » ou « extreme », le final `hold` reste ancré `to` ratio 9 même aimant
éteint, et garde ce 9 même aimant allumé sur un autre cran. C'est une frontière, pas un oubli — elle
est nommée en question ouverte plus bas.

## Les crans, et d'où viennent leurs valeurs

[déduit] La joueuse ne voit jamais un ratio. Trois crans nommés, traduits dans le code :

| cran | libellé FR | ratio [déduit] |
| --- | --- | --- |
| `light` | Léger | 2 |
| `medium` | Moyen | 3 |
| `hard` | Dur | 5 |

[document] `medium` reprend `CareerLevelGates.rhythmAnchorDefaultRatio`, le schéma 3:1 de Manu, seule
valeur du chantier passée devant lui pour le geste rythmé. [déduit] `light` à 2 est le premier ratio
qui produise encore une inégalité — à 1, `BeepEngine._intervalAfter` retombe sur l'intervalle
régulier. `hard` à 5 tient au milieu entre le 3 connu et le 9 du final « très dur », qu'il ne devait
pas atteindre. **Ces trois valeurs n'ont jamais été entendues par Manu.**

## Comment la compatibilité est prouvée

[mesuré] Un JSON de config Custom sans aucune des trois clés `anchor_*` — le schéma exact d'avant le
chantier — s'ouvre avec l'aimant éteint et `resolveAnchor()` à `null`, tous ses autres réglages
intacts. Le défaut est écrit explicitement dans `fromJson`, qui construit chaque champ et n'hérite
pas de celui du constructeur.

[mesuré] Une valeur illisible retombe sur le défaut : un cran inconnu donne `medium`, un point
`none` — qui ne veut rien dire ici, l'extinction passant par l'interrupteur — donne `from`.

[déduit] Le type ne se construit qu'en quatre endroits, tous dans son propre fichier : le
constructeur, `defaults()`, `copyWith()` et `fromJson()`. Les trois derniers portent les nouveaux
champs. Le service de persistance et l'export de diagnostic passent par `toJson` ou recopient le JSON
brut — aucune recopie champ à champ ailleurs, donc aucun site où le champ neuf puisse se perdre.

## Ce que les sondes attrapent — vérifié par mutation, pas supposé

[mesuré] Trois mutations posées et retirées, chacune relancée sur la suite des sondes :

| mutation | attendu | observé [mesuré] |
| --- | --- | --- |
| `customAnchor: null` — le câblage overrides → génération coupé | rouge | 3 rouges |
| `resolveAnchor()` rendant toujours `null` | rouge | 4 rouges |
| `_build()` de l'éditeur ne reportant plus les trois réglages | rouge | 1 rouge |
| `maxHoldDurationLimit` 120 → 110, borne de curseur hors sujet | vert | 14 verts |

[mesuré] Les rouges tombent sur les bonnes assertions, message lu : « aucun step rhythm piloté », « a
value greater than 12 / Actual 12 », « aucun hold ancré observé ». Pas un compteur générique.

[mesuré] Une première tentative de la deuxième mutation est passée **verte à tort** : `dart format`
avait replié la ligne visée, la substitution n'avait rien remplacé et le fichier était intact. La
mutation a été reposée après vérification du contenu du fichier — c'est cette seconde passe qui donne
les 4 rouges.

[déduit] La sonde d'invariance ne compare pas à « zéro ancre » mais à l'empreinte réellement relevée
sur le code d'avant, difficulté par difficulté et graine par graine. C'est ce qui la rend capable de
voir une régression : un « attendu vide » aurait été vert sur du code cassé.

## L'écran

[déduit] Un interrupteur, et les deux sélecteurs n'apparaissent que s'il est allumé — mêmes
`ChoiceChip` que la difficulté et les dosages voisins. [mesuré] L'éditeur est monté pour de vrai dans
les tests : une config neuve en ressort l'aimant éteint, une config allumée rouvre sur ses réglages,
et allumer puis choisir « Dur » et « Arrivée » ressort bien dans la config enregistrée.

[déduit] Neuf clés de traduction, écrites dans les quatre langues à la première écriture, puis
`flutter gen-l10n`. Le vocabulaire des consignes de tenue est évité : le réglage s'appelle « Aimant »
et sa position « Départ » / « Arrivée ».

## Questions ouvertes pour Manu

1. **Les trois ratios — 2 / 3 / 5 — n'ont jamais été entendus.** Seul le 3 vient de vous. Le 5 est
   posé au milieu entre le 3 et le 9 du final. À écouter et à corriger : ils tiennent dans une seule
   table du modèle.
2. **La phase finish échappe au réglage.** Aimant allumé sur « Léger », le final d'une séance
   difficile reste au 9 très dur, et les boosts gardent le ratio 3. Faut-il que le réglage Custom
   prenne aussi la main sur eux ? La mission l'interdisait pour cette étape.
3. **Une séance Custom porte déjà des ancres, aimant éteint** — voir le tableau du début. C'est
   l'héritage des étapes 3 et 4 via le niveau virtuel. Est-ce voulu, ou l'aimant éteint devrait-il
   vouloir dire « métronome régulier partout » ? Ce second choix ferait rejouer autrement vos
   configs déjà enregistrées ; c'est pour ça qu'il n'a pas été pris ici.
4. **« Départ » ne change rien aux tenues.** Le moteur ne sait faire l'aller-retour d'un `hold` que
   vers l'arrivée. Faut-il le dire à l'écran, ou laisser le réglage silencieux sur ce point ?
5. **Rien n'a été entendu.** Aucun APK n'a été construit — une seule tâche lourde à la fois sur la
   machine. Tout ce rapport est du code et des sondes, jamais de l'oreille.

## Ce que je n'ai pas pu établir

- **Comment ça sonne.** Aucun APK, aucune écoute. Les trois crans sont des chiffres justifiés par
  leur voisinage dans le code, pas par une oreille.
- **Si « Dur » se distingue de « Moyen » à l'usage.** 5 contre 3 est un écart lisible sur le papier ;
  rien ne dit qu'il s'entend sur une séance réelle, ni que « Léger » à 2 s'entend du tout.
- **Ce que donne l'aimant allumé sur une séance non-stop de plusieurs cycles.** Les sondes tirent des
  séances simples ; le non-stop monte le niveau virtuel de cycle en cycle, donc croise l'ancrage
  hérité de la carrière d'une façon qui n'a pas été mesurée.
- **Si le réglage devrait couvrir la phase finish.** La mission l'interdisait ; je constate la
  frontière, je ne sais pas si elle est la bonne.
