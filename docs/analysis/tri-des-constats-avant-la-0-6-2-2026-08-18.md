---
type: analyse
sujet: tri-des-constats-avant-la-0-6-2
ecrit_le: 2026-08-18T16:03:27+02:00
auteur: session tss2-tri-constats · claude-opus-5
revision: 7f119dcb
branche: develop
porte_sur:
  - docs/analysis/2026-08-07-challenge-bpm-target-runaway.md
  - docs/analysis/2026-08-07-session-freeze-and-coach-unlock.md
provenance:
  mesure: 20
  deduit: 12
  document: 5
  sans_marqueur: 0
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

# Tri des constats BeatBitch avant la 0.6.2

Arbre jugé : `origin/develop` à la révision `25657d5`, soit la 0.6.1 publiée plus vingt-six
corrections fusionnées et non publiées. Worktree `tss2-w2`, lecture seule, aucun fichier du dépôt
modifié.

**Un seul constat grave** : le verrou de profondeur du profil de capacités. Tout le reste est
gênant, cosmétique, déjà corrigé, ou obsolète.

---

## Le grave

### La profondeur prouvée redevient inaccessible et n'y revient plus toute seule

**Ce que la joueuse vit** : elle a déjà tenu la gorge, l'app le sait — et pourtant ses séances
s'arrêtent au palier du dessous, séance après séance, sans jamais lui reproposer ce qu'elle a
prouvé savoir faire. Sa progression sur cet axe est bloquée vers le bas, sauf si elle réclame
elle-même une escalade.

Le générateur cible le `comfort` de l'axe `rhythm.depth_max`, pas le `best`. Quand un abandon
imputé ou l'usure fait descendre le `comfort` sous le `best`, la profondeur générée en séance
normale est bornée au `comfort` — donc aucun dépassement n'est possible, donc le régulateur n'a
jamais de raison de faire remonter le `comfort` **[déduit]**.

Mesure sur `origin/develop`, profil `comfort = mid` / `best = throat`, format moyen, trois cents
graines par cas : un step de rythme visant la gorge sort dans zéro séance sur trois cents dès que
le taux de succès de l'axe passe sous le seuil de cran, et dans seize séances sur trois cents
au-dessus de ce seuil **[mesuré]**.

L'échappatoire existe et elle est systématique : en séance d'escalade — « Utilise-moi » ou
« Encore » — la gorge sort dans trois cents séances sur trois cents, quel que soit le taux de
succès **[mesuré]**. Le blocage se lève donc dès que la joueuse pousse d'elle-même ; il ne se lève
jamais si elle joue normalement.

Le correctif existe et n'a jamais été livré : la branche `feat/depth-comfort-probe` fait viser un
cran au-dessus du `comfort`, borné par le `best` déjà prouvé, dans les deux endroits qui plafonnent
la profondeur **[déduit]**. Elle est restée en arrière de `origin/develop` de cent un commits
**[mesuré]**.

Nuance à porter au dossier : la mémoire projet décrit ce défaut comme un verrou total
(« aucun overshoot possible, le comfort ne peut plus jamais remonter ») **[document]**. La mesure
ci-dessus le contredit sur `origin/develop` — la voie d'escalade est ouverte, et la voie normale
l'est aussi tant que le taux de succès de l'axe reste au-dessus du seuil. Le défaut est réel, son
ampleur est plus faible que ce qui est écrit.

---

## Le reste, par ordre de sévérité décroissante

| Constat | Où il est écrit | Classement | Preuve | Ce qui n'a pas pu être établi |
|---|---|---|---|---|
| Le bouton pause peut mettre longtemps à répondre : chaque joueur audio du pool est borné à 300 ms, mais la pause les arrête **en série** sur une soixantaine de joueurs | mémoire `project_audio_mediaplayer_saturation` | gênant, le plus proche du seuil | Pool de quatre joueurs par échantillon, quinze échantillons, borne individuelle de 300 ms, boucle séquentielle **[déduit]** | Le pire cas cumulé (~18 s) n'a jamais été observé en séance : il faudrait un appareil et un moteur audio engorgé |
| Un « Utilise-moi » en cours de séance efface les défis restants, les pauses restantes et la posture imposée | rapports de relecture (passes 2, 3, 4) | gênant | Sonde exécutée : deux défis en attente sur deux perdus, une pause sur une perdue, posture ramenée à « libre » ; la régénération d'après-défi, elle, garde les défis **[mesuré]** | Rien : le constat est reproduit et élargi. La perte des pauses est assumée par un commentaire du code, celle des défis est silencieuse |
| L'annonce d'un défi tombe dans les treize secondes qui suivent la fin d'une pause scénarisée | rapport d'intégration du 11/08 | gênant | Quatre collisions sur cinq cents graines, uniquement en format long avec quatre défis au plafond ; zéro sur tous les autres couples format × nombre de défis **[mesuré]** | Rien : les quatre cas du rapport sont retrouvés à l'identique |
| Une séance sans le moindre défi produit un enchaînement de rythme continu plus long que le plafond qu'un défi aurait eu | rapport de relecture (passe 4) | gênant | Cent quatre-vingt-trois secondes contre un plafond de cent quatre-vingts en format bâclé, cent quatre-vingt-treize en format court ; zéro dépassement en moyen et long, sur cinq cents graines par format **[mesuré]** | L'effet réel sur la calibration : la valeur reflète un exploit que la joueuse a vraiment accompli, elle n'est pas fabriquée |
| Un défi prolongé n'a aucune fin imposée, et l'horloge de séance est gelée pendant ce temps | rapport de relecture (passe 4) | gênant, assumé | Le code dit « Aucun timeout auto » au-dessus de la boucle de prolongation ; aucun garde-fou de séance ne la borne **[déduit]** | Combien de joueuses prolongent réellement, et jusqu'où |
| Le bouton « Utilise-moi » apparaît dès le début de la séance qui enseigne la supplique, au lieu d'attendre la fin de la leçon | `bugs.md` (« bouton Supplier visible dès le début ») | gênant | La garde d'affichage lit un déblocage qui inclut les déblocages provisoires de la séance en cours **[déduit]** | Le correctif dort sur `fix/marc-voice-usemi-gating`, jamais fusionné |
| L'icône des notifications surprise reste absente tant que sa leçon n'est pas jouée | issue #76, marquée `wontfix` | gênant, déjà tranché | La garde d'affichage est toujours là, aucune reprise au démarrage n'existe **[déduit]** ; la leçon n'exige plus que la supplique, acquise tôt **[déduit]** | Combien de séances il faut en pratique pour que la leçon tombe |
| Le pas de respiration du tutoriel n'a pas de durée déclarée, dans les quatre langues | branche `fix/tutorial-breath-duration` | cosmétique | Le fichier de séance du tutoriel ne porte toujours pas la durée que la branche ajoute **[mesuré]** | L'effet perçu — « le défi tuto se termine trop vite » — n'a pas été rejoué |
| Compte à rebours optionnel sur les tenues et fondu entre modes, jamais livrés | branche `feat/screen-polish` | cosmétique | Le drapeau d'affichage du compte à rebours est introuvable dans l'arbre jugé **[mesuré]** | Si Manu veut encore cette finition : la branche a sept cent cinquante-cinq commits de retard |
| Une leçon du catalogue enchaîne une lèche de « tête » vers « tête » | croisé en lisant `milestones.json` | cosmétique, hors sujet | Le pas existe tel quel dans le catalogue **[mesuré]** ; l'amplitude nulle contredit la règle d'amplitude stricte **[document]** | Signalé, pas corrigé — hors périmètre de ce tri |
| Bips manquants sur cinq à dix pour cent des frappes | `bugs.md` | non établi | — | Rien de rejouable sans appareil : la mesure d'origine vient d'un journal Android |
| Le défi « pousse ta limite » n'offre pas d'arrêt assez tôt | `bugs.md` | non établi | — | Le nombre de franchissements avant l'arrêt n'a pas été remesuré sur l'arbre jugé |
| Blocage de progression de carrière, séance figée à une seconde de la fin | issue #317 | corrigé | Le report d'un pas parlé est borné à cinq secondes, l'arrêt du son en fin de séance est borné à deux **[déduit]** ; le rapporteur a lui-même signalé que sa situation s'est débloquée **[document]** | Pourquoi le moteur vocal se taisait sur son appareil : la cause première reste inconnue |
| Cible de vitesse qui s'emballe jusqu'à des milliers de battements | `docs/analysis/2026-08-07-challenge-bpm-target-runaway.md` | corrigé | Les trois correctifs proposés sont en place : cible bornée au maximum du moteur, plancher d'humiliation borné, réconciliation des profils déjà dérivés au démarrage **[déduit]** | — |
| Coach masculin introuvable chez les profils avancés | `docs/analysis/2026-08-07-session-freeze-and-coach-unlock.md` | corrigé | Le catalogue est désormais réconcilié en entier à chaque synchronisation, pas seulement au-dessus du palier atteint **[déduit]** | — |
| Postures imposées et pauses scénarisées annoncées mais éteintes | issue #77 | corrigé — c'est la matière de la 0.6.2 | La préférence est allumée par défaut, sous une clé neuve pour que l'ancien « éteint » ne colle pas **[déduit]** ; un test verrouille la chaîne complète **[mesuré]** | — |
| Le temps des défis mangeait le contenu de la séance | `bugs.md` (« les douze minutes incluent le défi ») | corrigé | Le plafond par format est en place et la suite complète passe **[mesuré]** | — |
| Compilation cassée par le décalage des textes espagnols | `bugs.md` | obsolète | L'analyse statique ne remonte aucun problème sur l'arbre jugé **[mesuré]** | — |
| Blocage sur ancre en mode Music, motifs mal calés sur la musique | `bugs.md`, mémoire `project_music_mode` | obsolète | Le mode est retiré de l'accueil et aucun chemin de l'app n'y mène plus **[mesuré]** | — |
| Défis qui n'apparaissent jamais | issue #294 | non établi | Les quatre formats visent au moins un défi, l'interrupteur est allumé par défaut, et un défi exploratoire prend le relais quand aucun axe n'est prouvé **[déduit]** | Le cas du rapporteur : son export est au premier format de schéma, et **aucun export — ni le sien ni celui d'aujourd'hui — ne contient l'état de l'interrupteur des défis** **[mesuré]**. Rien ne permet de dire s'il les avait coupés |
| File de mise en vitrine d'un point de spécialisation | branche `feat/specialization-showcase-queue` | obsolète | La fonctionnalité est dans l'arbre jugé, livrée par un autre chemin **[mesuré]** | — |
| Détection du tempo au micro | branche `feat/music-mic` | obsolète | Le mode Music est inaccessible dans l'arbre jugé **[mesuré]** ; la mémoire projet acte l'abandon du micro au profit de la frappe à l'écran **[document]** | — |
| Voix française forcée pour le coach masculin | branche `fix/marc-voice-usemi-gating` | obsolète | Le réglage de voix par coach, livré en 0.6.1, couvre le besoin **[document]** | — |

---

## L'état de l'arbre jugé

Suite complète : neuf cent soixante-dix-huit tests, tous verts. Analyse statique : aucun problème.
Les deux relancées par moi sur `origin/develop`, pas recopiées d'un rapport **[mesuré]**.

Les six branches jamais fusionnées se répartissent ainsi : deux portent un correctif encore utile
et jamais livré — `feat/depth-comfort-probe` (le grave ci-dessus) et la moitié « bouton » de
`fix/marc-voice-usemi-gating` ; une porte une correction cosmétique jamais livrée
(`fix/tutorial-breath-duration`) ; une porte une finition d'affichage jamais livrée
(`feat/screen-polish`) ; deux sont obsolètes (`feat/music-mic`, déjà livrée autrement pour
`feat/specialization-showcase-queue`) **[mesuré]**.

Point de sortie de version, sans rapport avec les défauts : la section « Non publié » du journal
des modifications est vide alors que vingt-six corrections y attendent leur ligne **[mesuré]**.

---

## Ce que je n'ai pas pu établir

- **Pourquoi les défis n'apparaissaient pas chez le rapporteur de l'issue #294.** Rien dans le
  code ne peut les supprimer tous ; l'export joint ne dit pas si l'interrupteur était coupé, et
  l'export d'aujourd'hui ne le dirait pas davantage **[mesuré]**. Tant que l'état de cet
  interrupteur n'entre pas dans l'export diagnostic, ce constat restera indécidable.
- **Le pire cas de la pause audio.** Le calcul se tient, l'observation manque : il faut un
  appareil et une séance longue pour voir si la soixantaine d'arrêts en série se paie vraiment.
- **Les bips manquants et le défi « pousse ta limite ».** Les deux viennent d'observations sur
  appareil, et aucune compilation Android n'était autorisée ici.
- **L'effet réel du dépassement passif de rythme sur la calibration.** La valeur produite
  correspond à un effort authentique ; savoir si elle fausse la mesure ou si elle la reflète
  demande un arbitrage de conception, pas une mesure.
- **La fréquence en jeu des situations mesurées.** Toutes les proportions données ici portent sur
  des séances générées, pas sur des séances jouées : je ne sais pas combien de joueuses ont un
  profil au taux de succès bas sur la profondeur, ni combien jouent le format long avec quatre
  défis au plafond.
