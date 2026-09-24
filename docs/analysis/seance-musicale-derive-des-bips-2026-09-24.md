---
type: analyse
sujet: seance-musicale-derive-des-bips
ecrit_le: 2026-09-24T13:43:46+02:00
auteur: session tss2-derive-bips · claude-sonnet-5
revision: 3ce7608
branche: feat/seance-musicale
porte_sur:
  - rhythm_coach/lib/models/session_music.dart
  - rhythm_coach/lib/services/beep_engine.dart
  - rhythm_coach/lib/services/music_clock.dart
  - rhythm_coach/lib/services/music_engine.dart
provenance:
  mesure: 8
  deduit: 7
  document: 5
  sans_marqueur: 0
sources_citees: []
relu_contre:
  - rhythm_coach/lib/models/session_music.dart:31
  - rhythm_coach/lib/services/beep_engine.dart:590
  - rhythm_coach/lib/services/music_clock.dart:37
---

## Verdict : H1 infirmée, rien codé

[mesuré] La grille de l'app est juste à quelques ms près sur tout le morceau. Pente de l'écart (attaque − grille) : +0,03 à +0,14 ms/s selon la méthode et la plage, soit +5 à +25 ms sur 178 s. Manu entend 40 à 60 ms de dérive dans l'autre sens (bips de plus en plus en retard). Le signe est opposé : une attaque qui glisse *après* la grille rend les bips *moins* en retard. L'ordre de grandeur est aussi trop petit. Ni tempo ni temps n°0 modifiés ; aucune ligne de code touchée.

## Ce que l'app lit

[document] `montee_en_puissance` : `bpm: 121.96`, `first_beat: 16.934` dans les 4 JSON de séance (`assets/sessions/session_montee_puissance*.json`). `SessionMusic.beatTime(i)` = `round(first_beat·1e6 + i·60e6/bpm)` µs (`session_music.dart:31`) : calculé depuis l'index, aucun arrondi de période qui s'accumule. La grille mesurée ci-dessous est exactement celle-là.

## La mesure (H1)

[mesuré] Méthode : `ffmpeg` → PCM mono 48 kHz ; passe-bas < 150 Hz (zéro phase) ; enveloppe (|x| lissée 8 ms, décimée à 1 kHz) ; fonction d'attaque = dérivée positive de √enveloppe. Pour chaque temps k de la grille de l'app (aussi avant `first_beat`), on cherche le maximum d'attaque dans ±60 ms (interpolation parabolique) : écart = attaque − grille.

[mesuré] Écartés : les temps dont la force d'attaque est sous la moitié de la médiane (sections sans grosse caisse : 280 → 274 temps gardés) ; puis moindres carrés itérés en rejetant les résidus au-delà de 3 σ robustes (MAD) : 262 temps retenus sur 274.

| [mesuré] Réglage | Pente (ms/s) | Ordonnée | Résidu σ | Écart à 178 s |
|---|---|---|---|---|
| App, fenêtre ±60 ms, tout le morceau | +0,095 ± 0,011 (Theil-Sen +0,042) | −13,1 ms | 7,7 ms | +3,8 ms |
| App, temps forts seulement (seuil 0,9 × médiane) | +0,045 ± 0,009 (Theil-Sen +0,001) | −8,9 ms | 5,7 ms | −0,9 ms |
| App, t < 140 s | −0,031 ± 0,008 (Theil-Sen −0,051) | −4,9 ms | 3,9 ms | −10,5 ms |
| Sans grille : pics détectés seuls, rattachés au temps entier le plus proche | +0,144 (t < 140 s : +0,029) | −16,8 ms | 11,0 ms | (période directe 0,492035 s = 121,94 BPM ; temps n°0 = 16,920 s) |

[mesuré] Par blocs de 20 s, l'écart médian va de −17 ms (0–20 s) à −3, −3, −10, −11, −11, −7 ms, puis +34 ms (160–180 s, 13 temps seulement, tenue finale où la grosse caisse est rare). Ce n'est pas une droite : la « pente » sur tout le morceau vient en partie de la queue. La pente est donc sensible à la plage, ce que dit l'écart entre les lignes ; elle ne dépasse jamais 0,15 ms/s.

[mesuré] Témoin : grille volontairement fausse, mêmes réglages. BPM 122,01 (+0,05) : pente +0,429 ms/s (attendu +0,41 + 0,09) ; BPM 121,91 (−0,05) : −0,315 ms/s (attendu −0,41 + 0,09). Avec +0,1 BPM : +0,74 ms/s (attendu ~+0,9, écrêté parce que l'écart sort de la fenêtre de recherche). La mesure discrimine donc un décalage de tempo de 0,05 BPM, et la dérive de Manu (0,25 à 0,37 ms/s) aurait été vue nettement, avec un rapport de 3 à 8 sur le bruit de pente (± 0,011).

[déduit] Le tempo réel du morceau est entre 121,94 et 121,96 BPM ; l'erreur de la grille est ≤ 0,02 BPM, soit ≤ 25 ms sur 178 s, dans le sens qui *réduit* le retard des bips. Le point de départ (ordonnée −5 à −17 ms selon la méthode) dépend de la définition de « l'attaque » (max de dérivée) : il ne compte pas comme retard absolu, mais il dit que le temps n°0 n'est pas à 90 ms de la grosse caisse.

## Matière pour H2

[mesuré] `ffprobe` et lecture des en-têtes : MP3 à **débit constant**, 192 kb/s, 48 kHz, 7452 trames toutes à 192 kb/s, ni en-tête Xing/Info ni VBRI (comptage sur le fichier). 7452 × 1152 / 48000 = 178,848 s = la durée annoncée par `ffprobe`. Pas de tag de retard d'encodeur non plus : le décodeur ne peut pas recaler à l'insu de l'app, mais cela relève d'un décalage fixe, pas d'une dérive. Un MP3 à débit variable sans table est le cas classique de position de lecture fausse ; ce n'est pas le nôtre.

[document] `MusicClock` (`music_clock.dart`) : position = dernier rapport du lecteur + temps écoulé au chronomètre depuis la *réception* du rapport. Chaque rapport ré-ancre : « aucune erreur ne s'accumule » (le code le dit). Il n'y a ni lissage ni filtre. `MusicEngine` relaie tel quel `onPositionChanged` d'`audioplayers`.

[déduit] Conséquences pour la dérive entendue :
- [déduit] Un retard de *transport* du rapport (canal plateforme, isolat Dart chargé) ajoute un retard, qui vaut la latence de livraison du rapport, à chaque intervalle. Il varie avec la charge : ce serait une gigue, pas une pente. Il s'ajoute à la latence de sortie audio du bip et du morceau, qui est fixe.
- [document] La grille (`_startGridLoop`) rappelle la position à chaque bip : elle ne dérive pas par construction (commentaire « Anti-drift » relu, et le code fait ce qu'il dit).
- [déduit] Ce que le code ne permet pas d'exclure : une horloge audio du téléphone qui ne tourne pas à la vitesse du chronomètre Dart entre deux rapports (extrapolation sur au plus l'intervalle entre deux rapports, [document] `audioplayers` Android : 200 ms) ; à 300 ppm cela fait 0,06 ms par intervalle, invisible. Une dérive de 50 ms en 160 s demanderait un écart d'horloge de 300 ppm *permanent et non recalé* : le ré-ancrage à chaque rapport l'interdit.
- [déduit] Reste que « entre 90 et 130 ms, voire 150 » peut être de la gigue (rapports en retard, ordonnancement du timer de la grille, calage sur des grosses caisses à des moments différents du morceau) plutôt qu'une pente, ce que l'écoute à l'œil ne sépare pas.

## L'essai qui trancherait (à faire sur le S21)

[déduit] Une phrase pour Manu : lance la séance, à environ 20 s règle l'avance jusqu'à ce que le bip colle à la grosse caisse et note la valeur ; sans plus rien changer, à environ 60 s, puis à 120 s, puis à 160 s, appuie sur + ou − jusqu'à ce que ça recolle et note à chaque fois la valeur : si les quatre notes sont à 10 ms l'une de l'autre, le retard est fixe (à ± la gigue) et l'avance fixe suffit ; si elles montent régulièrement de 20 ms ou plus, c'est une vraie dérive de la position du lecteur, et il faudra enregistrer les rapports de position (horodatés) pendant la séance pour les comparer au chronomètre.

## Ce que je n'ai pas pu établir

- [déduit] Que la dérive de 40–60 ms existe : c'est une perception à l'oreille, et la mesure hors ligne ne dit rien de ce que fait le téléphone.
- Ce que Manu compare exactement : le bip ou l'orbe à l'image, en « voyant », ce qui ajoute la latence d'affichage.
- [mesuré] La pente sur la queue du morceau (160–180 s) : peu de grosses caisses, 13 temps ; l'écart de +34 ms y est le moins sûr.
- Le comportement du lecteur Android sur l'appareil : aucun son, aucun téléphone dans cette session.
- La forme réelle de l'attaque de la grosse caisse : le max de la dérivée du passe-bas est un repère, pas la perception d'un clic.

[document] Script de mesure (hors dépôt, 6d337abb…) : `/tmp/claude-1000/-home-emmanuel-perso-git-tss2-musique/6d337abb-ad3e-4fe9-bddc-366c7f7e4eb5/scratchpad/` (`mesure.py`, `reg.py`, `blocs.py`, `sansgrille.py`).
