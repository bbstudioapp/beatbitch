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
# Balls : zone latérale, plus grave que full (180 vs 280 Hz) pour évoquer
# une zone "en-dessous" anatomiquement, sample un peu plus long avec un
# fade-out marqué pour rendre le côté sourd/mou de la zone (vs l'attaque
# nette des positions verge).
beep balls_beep   180 0.30 0.110 1.00

# Hold : overlay grave et long, joué EN PLUS du beep position
beep hold_beep    320 0.45 0.150 0.90

# Biffle : percutant, médium, un peu plus long pour qu'on l'entende au loop
beep biffle_beep  900 0.14 0.040 1.00

# Breath : grave, long, soft attack et fade-out long pour effet « libérateur »
beep breath_beep  500 0.40 0.180 0.85

# Suckle : sample wet pulsé toutes ~1.2 s, fade-out mou pour évoquer
# l'aspiration (geste actif-statique). Fréquence médium (~580 Hz) hors du
# pool position pour rester acoustiquement distinct des bips bouche. Durée
# courte (~0.20 s) avec fade-out long (~0.10 s) → on entend le « slurp »
# bref puis le fondu doux d'aspiration.
beep suckle_beep    580 0.22 0.110 0.85

# Hand : 2 samples alternés down/up pour évoquer le va-et-vient de la main.
# Fréquences placées hors du pool position (tip=1400 ... full=280) pour rester
# acoustiquement distinct des bips bouche → en combo hand+rhythm/lick on doit
# pouvoir parser les 2 pistes à l'oreille.
# - down : coup descendant (la main slamme vers la base), grave + un peu plus
#   long. Le volume sera modulé live par BeepEngine selon la profondeur de
#   `to` (tip × 0.7 → full × 1.0) → l'amplitude du stroke s'entend.
# - up : coup remontant (la main décroche vers le gland), bref et clair.
beep hand_down_beep  360 0.09 0.040 0.95
beep hand_up_beep    560 0.06 0.025 0.75

# Freestyle markers : montant pour le départ, descendant grave pour la fin
beep freestyle_start 600 0.20 0.080 0.75
beep freestyle_end   400 0.30 0.150 0.75

# Finale chime : son long et résonant joué à la fin de session avant les
# annonces de badges. Placeholder cloche médium → à remplacer par un vrai
# sample percussif (gong, clap final…).
beep finale_chime    520 1.40 0.700 0.95

echo
echo "✓ 15 fichiers générés dans $OUT/"
echo "Ce sont des sinusoïdes simples — remplace-les par tes propres samples"
echo "(coups secs, claps, slurps, etc.) en gardant les mêmes noms de fichiers."
