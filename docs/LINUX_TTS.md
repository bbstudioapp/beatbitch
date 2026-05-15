# TTS sous Linux — voix neuronale via piper

Le plugin Flutter `flutter_tts` ne supporte pas Linux. BeatBitch contourne en
sélectionnant **au runtime** l'un de deux backends :

1. **piper** — TTS neuronal léger, voix très naturelle.
   Activé automatiquement si `piper` est dans le `PATH` *et* qu'au moins un
   fichier de voix `.onnx` est posé dans un dossier conventionnel.
2. **spd-say** — CLI de `speech-dispatcher`. Fallback toujours dispo
   (`speech-dispatcher` est listé comme dépendance Linux du paquet), mais
   par défaut il sort de l'`espeak-ng` très robotique.

L'app détecte le backend disponible au lancement et l'affiche dans
*Profil → VOIX* comme « piper (neuronal) » ou « spd-say (système) ».

---

## Installer piper

### 1. Binaire

```bash
sudo apt install pipx
pipx install piper-tts
pipx ensurepath   # ajoute ~/.local/bin au PATH si pas déjà
```

Vérifier :

```bash
which piper
piper --help
```

> Alternative : binaire pré-compilé sur la page Releases de
> [rhasspy/piper](https://github.com/rhasspy/piper/releases) — extrait dans
> `~/.local/bin/` ou `/usr/local/bin/`.

### 2. Une voix par langue

Les modèles sont hébergés sur HuggingFace :
<https://huggingface.co/rhasspy/piper-voices>

Conventions piper : `<lang>_<COUNTRY>-<name>-<quality>.onnx` + sidecar
`.onnx.json` (config du modèle, sample rate…). Les deux fichiers vont
toujours ensemble.

#### Français — `fr_FR-siwis-medium` (recommandé)

```bash
mkdir -p ~/.local/share/piper-voices
cd ~/.local/share/piper-voices
wget https://huggingface.co/rhasspy/piper-voices/resolve/main/fr/fr_FR/siwis/medium/fr_FR-siwis-medium.onnx
wget https://huggingface.co/rhasspy/piper-voices/resolve/main/fr/fr_FR/siwis/medium/fr_FR-siwis-medium.onnx.json
```

Autres voix FR : `fr_FR-upmc-medium`, `fr_FR-tom-medium`, `fr_FR-mls-medium`.

#### Anglais — `en_US-amy-medium`

```bash
cd ~/.local/share/piper-voices
wget https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/amy/medium/en_US-amy-medium.onnx
wget https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/amy/medium/en_US-amy-medium.onnx.json
```

Autres : `en_US-ryan-medium`, `en_GB-jenny_dioco-medium`.

#### Allemand — `de_DE-thorsten-medium`

```bash
cd ~/.local/share/piper-voices
wget https://huggingface.co/rhasspy/piper-voices/resolve/main/de/de_DE/thorsten/medium/de_DE-thorsten-medium.onnx
wget https://huggingface.co/rhasspy/piper-voices/resolve/main/de/de_DE/thorsten/medium/de_DE-thorsten-medium.onnx.json
```

Autre : `de_DE-eva_k-x_low` (femme, petit modèle).

### 3. Relancer l'app

La détection se fait au lancement. Après installation des voix, ferme et
relance BeatBitch. *Profil → VOIX* doit afficher « piper (neuronal) ».

---

## Conventions de chemin

L'app scanne les dossiers suivants, par ordre de priorité (le 1er match
par langue gagne) :

1. `$XDG_DATA_HOME/piper-voices`
2. `~/.local/share/piper-voices`
3. `/usr/local/share/piper-voices`
4. `/usr/share/piper-voices`

Le code langue est extrait du préfixe du nom de fichier avant le 1er `_`
ou `-` : `fr_FR-siwis-medium.onnx` → langue `fr`. Un seul `.onnx` par
langue est retenu — pour changer de voix, remplace le fichier (ou bouge
les autres dans un sous-dossier).

---

## Troubleshooting

### *Profil → VOIX* affiche « spd-say (système) » alors que piper est installé

- Vérifier `which piper` → doit retourner un chemin existant. Si vide,
  `pipx ensurepath` puis nouvelle session shell.
- Vérifier qu'au moins un `.onnx` est dans `~/.local/share/piper-voices/`
  (et que son `.onnx.json` est à côté).
- Le nom de fichier doit commencer par un code langue connu (`fr`, `en`,
  `de`…) — pas de fichier renommé sans préfixe langue.
- Relancer l'app (la détection est faite une seule fois au démarrage).

### Aucun son via piper

Piper produit du PCM brut envoyé à `aplay` (ALSA). Tester le pipeline
en standalone (utiliser un texte neutre, *pas* du contenu de l'app) :

```bash
echo "test un deux trois" | \
  piper --model ~/.local/share/piper-voices/fr_FR-siwis-medium.onnx --output_raw | \
  aplay -r 22050 -f S16_LE -t raw -c 1
```

Si `aplay` est absent : `sudo apt install alsa-utils`.

Si le système est full-PipeWire/PulseAudio sans backend ALSA, installer
le shim : `sudo apt install pipewire-alsa` (ou `pulseaudio-utils` selon
la stack).

### piper plante ou met longtemps à charger

- 1ʳᵉ inférence : ~1-3 s (chargement du modèle ONNX). Les suivantes sont
  ~100-300 ms.
- Si le modèle ne charge jamais : vérifier l'intégrité du `.onnx`
  (`sha256sum` vs page HuggingFace) — un téléchargement tronqué donne un
  fichier corrompu.

### Le slider rate/pitch de l'app n'a pas d'effet

Avec **piper**, ces sliders sont ignorés : la cadence et la hauteur sont
des propriétés du modèle. Pour changer le rendu, télécharger une autre
voix (qualités `low` / `medium` / `high` ont des timbres différents, et
chaque voix a sa propre cadence intrinsèque).

Avec **spd-say** (fallback), les sliders sont mappés sur `-r` / `-p`
(échelle `-100..100`) et fonctionnent.

---

## Limitations connues

- **Pas de sélection de voix dans l'UI** : une seule voix par langue,
  posée dans le dossier conventionnel. Pour proposer plusieurs voix
  alternatives dans l'écran Profil, il faudrait un sélecteur — pas livré
  en V1.
- **Pas de variation par coach** : les 6 coachs de carrière partagent
  la même voix piper. Sur Android, chaque coach a son preset `tts.voice`
  + rate + pitch ; sur Linux, c'est ignoré (cf. `applyCoachVoicePreset`).
  La distinction reste portée par le texte de chaque coach.
- **Latence d'init** : ~1-3 s à la 1ʳᵉ phrase d'une session (chargement
  du modèle ONNX). Acceptable, la session démarre par un countdown.
