#!/usr/bin/env bash
# Génère 7 bips placeholder dans assets/audio/ avec ffmpeg.
# Tonalités décroissantes du tip (très aigu) au full (très grave),
# plus un overlay hold sustainé et un biffle agressif.
#
# Pré-requis : ffmpeg installé (sudo apt install ffmpeg).
#
# Lancer : bash tools/generate_beeps.sh

set -euo pipefail

cd "$(dirname "$0")/.."
OUT="assets/audio"
mkdir -p "$OUT"

# beep <name> <freq> <duration_s> <fade_out_s> <volume>
beep() {
  local name="$1" freq="$2" dur="$3" fade="$4" vol="$5"
  local fadeStart
  fadeStart=$(awk "BEGIN { printf \"%.4f\", $dur - $fade }")
  ffmpeg -y -hide_banner -loglevel error \
    -f lavfi -i "sine=frequency=${freq}:duration=${dur}" \
    -af "volume=${vol},afade=t=in:d=0.005,afade=t=out:st=${fadeStart}:d=${fade}" \
    -ar 44100 -ac 1 -b:a 96k \
    "$OUT/${name}.mp3"
  echo "→ $OUT/${name}.mp3"
}

# Position beeps : courts, attaque franche, ton selon profondeur
# Durées rallongées (~+45 %) pour réduire les "skips" sur Android — sous
# 100 ms certains bips étaient avalés ou coupés en court de route.
beep tip_beep    1400 0.11 0.035 0.85
beep head_beep   1000 0.13 0.040 0.90
beep mid_beep     680 0.16 0.050 0.95
beep throat_beep  450 0.20 0.065 1.00
beep full_beep    280 0.26 0.085 1.00

# Hold : overlay grave et long, joué EN PLUS du beep position
beep hold_beep    320 0.45 0.150 0.90

# Biffle : percutant, médium, un peu plus long pour qu'on l'entende au loop
beep biffle_beep  900 0.14 0.040 1.00

# Breath : grave, long, soft attack et fade-out long pour effet « libérateur »
beep breath_beep  500 0.40 0.180 0.85

# Hand : médium-aigu, plus mat que rhythm pour différencier la stimulation main
beep hand_beep    780 0.12 0.040 0.85

# Freestyle markers : montant pour le départ, descendant grave pour la fin
beep freestyle_start 600 0.20 0.080 0.75
beep freestyle_end   400 0.30 0.150 0.75

# Finale chime : son long et résonant joué à la fin de session avant les
# annonces de badges. Placeholder cloche médium → à remplacer par un vrai
# sample percussif (gong, clap final…).
beep finale_chime    520 1.40 0.700 0.95

echo
echo "✓ 12 fichiers générés dans $OUT/"
echo "Ce sont des sinusoïdes simples — remplace-les par tes propres samples"
echo "(coups secs, claps, slurps, etc.) en gardant les mêmes noms de fichiers."
