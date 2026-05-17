---
name: Bug report
about: Signaler un bug / Report a bug
title: '[Bug] '
labels: bug
assignees: ''
---

<!--
🇫🇷 Tu peux écrire en français ou en anglais.
🇬🇧 You can write in English or French.
-->

## Que s'est-il passé ? / What happened?

<!-- Décris brièvement le problème. / Briefly describe the issue. -->

## Reproduction

1.
2.
3.

## Comportement attendu / Expected behavior

<!-- Ce qui aurait dû se passer. / What should have happened. -->

## Environnement / Environment

- **Version BeatBitch** : <!-- ex: 0.4.1 (Profil → bas de page) -->
- **Plateforme / Platform** : <!-- coche / check : Android | Windows desktop | Linux desktop | autre / other -->
- **OS** : <!-- ex: Android 15 / Samsung Galaxy S21 — ou — Windows 11 23H2 — ou — Ubuntu 24.04 -->
- **Langue dans l'app / App language** : <!-- FR, EN, DE -->

## Export diagnostic / Diagnostic export

<!--
🇫🇷 Surtout utile pour les bugs de progression (niveau bloqué, milestone qui
ne valide pas, badge manquant, état carrière incohérent…) : un export
diagnostic permet de reproduire ton état côté maintenance.

  Profil → DIAGNOSTIC → Exporter mes données → Partager / Enregistrer.

Le toggle « Inclure mes surnoms personnalisés » reste OFF par défaut — laisse-le
off sauf si le bug concerne précisément le texte qui s'adresse à toi. Aucune
calibration caméra n'est exposée. Le fichier contient ton état de progression
(carrière, stats, capacités, badges, préférences) + un checksum d'intégrité
pour qu'on détecte une corruption pendant le transit.

Glisse-dépose le fichier .json dans ce ticket. Si GitHub refuse l'extension,
renomme-le en .txt ou zippe-le.

🇬🇧 Especially helpful for progression bugs (stuck level, milestone not
validating, missing badge, inconsistent career state…): a diagnostic export
lets us reproduce your state on our side.

  Profile → DIAGNOSTIC → Export my data → Share / Save.

The "Include my custom nicknames" toggle stays OFF by default — keep it off
unless the bug is specifically about the wording addressed to you. No camera
calibration is exposed. The file contains your progression state (career,
stats, capabilities, badges, preferences) plus an integrity checksum so we can
detect corruption during transit.

Drag & drop the .json file into this issue. If GitHub rejects the extension,
rename it to .txt or zip it.
-->

## Logs / Captures

<!--
Optionnel : captures d'écran, vidéo, logs si tu en as.
Optional: screenshots, video, logs if you have any.

Logs Android :
  adb logcat *:W | grep -i beatbitch

Logs Windows : lance `rhythm_coach.exe` depuis un terminal (cmd / PowerShell) →
les `debugPrint` et exceptions catchées s'affichent en stdout/stderr.

Logs Linux : lance `./BeatBitch-X.Y.Z-linux-x64/beat_bitch` depuis un terminal
→ les `debugPrint` et exceptions catchées s'affichent en stdout/stderr.
-->

## Notes

<!-- Tout autre détail utile. / Anything else worth knowing. -->
