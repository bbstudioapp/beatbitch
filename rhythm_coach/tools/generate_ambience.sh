#!/usr/bin/env bash
# Génère 5 drones d'ambiance synthétiques dans assets/audio/ambience/
# avec ffmpeg. Sinusoïdes harmoniques superposées + filtres pour un
# rendu chaleureux/tendu, loop propre (fade in/out symétriques).
#
# Pré-requis : ffmpeg installé (sudo apt install ffmpeg).
#
# Lancer : bash tools/generate_ambience.sh

set -euo pipefail

cd "$(dirname "$0")/.."
OUT="assets/audio/ambience"
mkdir -p "$OUT"

DUR=60        # secondes de loop
SR=44100
BR="96k"

# --- Helper : combine N sines en un MP3 mono avec fade et lowpass ---
# Args : <name> <lowpass_hz> <volume> <fade_s> "freq1 freq2 freq3..."
make_drone() {
  local name="$1" lp="$2" vol="$3" fade="$4" freqs="$5"
  local fadeStart
  fadeStart=$(awk "BEGIN { printf \"%.4f\", $DUR - $fade }")

  # Construit dynamiquement -i sine=... pour chaque fréquence
  local inputs=()
  local mixinputs=()
  local idx=0
  for f in $freqs; do
    inputs+=("-f" "lavfi" "-i" "sine=frequency=${f}:duration=${DUR}")
    mixinputs+=("[${idx}:a]")
    idx=$((idx + 1))
  done
  local n=$idx
  local mixstr
  mixstr="$(IFS=; echo "${mixinputs[*]}")amix=inputs=${n}:duration=longest:normalize=0,lowpass=f=${lp},volume=${vol},afade=t=in:d=${fade},afade=t=out:st=${fadeStart}:d=${fade}"

  ffmpeg -y -hide_banner -loglevel error \
    "${inputs[@]}" \
    -filter_complex "$mixstr" \
    -ar "$SR" -ac 1 -b:a "$BR" \
    "$OUT/${name}.mp3"
  echo "→ $OUT/${name}.mp3"
}

# --- Drones « intime » : harmonies graves et chaudes, peu d'aigus ---

# Rhythm : drone profond et présent, fondamentale + 5te + octave.
# Énergie continue qui soutient le rythme sans déconcentrer.
make_drone deep_drone 600 0.55 2.5 "55 82.5 110"

# Lick : variation plus aigüe et legèrement « brillante » pour
# matcher le mode plus léger / wet.
make_drone warm_drone 1200 0.45 2.5 "110 165 220 275"

# Biffle : pulse régulier, simule un cœur qui bat. On utilise un
# sine très grave modulé en amplitude par un autre sine très lent
# (≈60 BPM). Construit ici en deux temps : sine + tremolo via aeval.
ffmpeg -y -hide_banner -loglevel error \
  -f lavfi -i "sine=frequency=55:duration=${DUR}" \
  -af "tremolo=f=1.0:d=0.85,lowpass=f=500,volume=0.6,afade=t=in:d=2.5,afade=t=out:st=$(awk "BEGIN{printf \"%.4f\", $DUR-2.5}"):d=2.5" \
  -ar "$SR" -ac 1 -b:a "$BR" \
  "$OUT/heartbeat.mp3"
echo "→ $OUT/heartbeat.mp3"

# Hold : drone tendu, deux sines très proches pour créer un
# battement binaural (110Hz + 113Hz → battement à 3Hz). Sensation
# de tension lente.
make_drone tension_drone 800 0.50 2.5 "110 113 220"

# Breath : pad chaleureux pour la respiration. Sines plus aiguës
# avec lowpass plus ouvert, tremolo doux pour effet « inspiration ».
ffmpeg -y -hide_banner -loglevel error \
  -f lavfi -i "sine=frequency=165:duration=${DUR}" \
  -f lavfi -i "sine=frequency=220:duration=${DUR}" \
  -f lavfi -i "sine=frequency=330:duration=${DUR}" \
  -filter_complex "[0:a][1:a][2:a]amix=inputs=3:duration=longest:normalize=0,tremolo=f=0.25:d=0.4,lowpass=f=1500,volume=0.45,afade=t=in:d=3.0,afade=t=out:st=$(awk "BEGIN{printf \"%.4f\", $DUR-3.0}"):d=3.0" \
  -ar "$SR" -ac 1 -b:a "$BR" \
  "$OUT/warm_pad.mp3"
echo "→ $OUT/warm_pad.mp3"

echo
echo "✓ 5 fichiers générés dans $OUT/"
echo "  deep_drone.mp3      — rythme : drone grave et présent"
echo "  warm_drone.mp3      — lick : drone plus chaud, médium"
echo "  heartbeat.mp3       — biffle : pulse cardiaque"
echo "  tension_drone.mp3   — hold : battement binaural tendu"
echo "  warm_pad.mp3        — breath : pad respirant"
