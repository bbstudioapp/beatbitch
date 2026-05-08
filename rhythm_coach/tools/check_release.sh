#!/usr/bin/env bash
#
# BeatBitch — vérification d'un build APK release signé.
#
# Workflow :
#   1. flutter build apk --release
#   2. apksigner verify --print-certs sur l'APK produit
#   3. SHA256 du fichier (à coller dans la GitHub Release)
#
# Pré-requis :
#   - `android/key.properties` rempli avec un keystore valide
#     (cf. android/key.properties.example).
#   - `apksigner` dans le PATH (livré avec Android build-tools ;
#     ex: ~/Android/Sdk/build-tools/<version>/apksigner).
#
# À runner depuis la racine `rhythm_coach/`.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
APK_PATH="${PROJECT_DIR}/build/app/outputs/flutter-apk/app-release.apk"
KEY_PROPS="${PROJECT_DIR}/android/key.properties"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
red()  { printf '\033[31m%s\033[0m\n' "$*" >&2; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }

cd "${PROJECT_DIR}"

if [[ ! -f "${KEY_PROPS}" ]]; then
  red "✗ android/key.properties absent."
  red "  Copier android/key.properties.example, remplir avec le vrai keystore"
  red "  et relancer."
  exit 1
fi

bold "▶ flutter build apk --release"
flutter build apk --release

if [[ ! -f "${APK_PATH}" ]]; then
  red "✗ APK introuvable à ${APK_PATH}"
  exit 1
fi

bold "▶ apksigner verify --print-certs"
APKSIGNER=""
if command -v apksigner >/dev/null 2>&1; then
  APKSIGNER="$(command -v apksigner)"
else
  # Fallback : on cherche dans le SDK Android. `local.properties`
  # déclare `sdk.dir=...`, sinon on regarde les emplacements usuels.
  SDK_DIR=""
  if [[ -f "${PROJECT_DIR}/android/local.properties" ]]; then
    SDK_DIR="$(grep -E '^sdk.dir=' "${PROJECT_DIR}/android/local.properties" | cut -d= -f2- || true)"
  fi
  for candidate in "${SDK_DIR}" "${ANDROID_SDK_ROOT:-}" "${ANDROID_HOME:-}" "${HOME}/Android/Sdk" "/opt/android-sdk"; do
    [[ -z "${candidate}" ]] && continue
    # Plus haute version disponible (tri version-aware).
    found="$(ls -1 "${candidate}/build-tools" 2>/dev/null | sort -V | tail -1)"
    if [[ -n "${found}" && -x "${candidate}/build-tools/${found}/apksigner" ]]; then
      APKSIGNER="${candidate}/build-tools/${found}/apksigner"
      break
    fi
  done
fi

if [[ -z "${APKSIGNER}" ]]; then
  red "✗ apksigner introuvable."
  red "  Ajouter \$ANDROID_SDK_ROOT/build-tools/<version>/ au PATH"
  red "  ou installer build-tools via \`sdkmanager\`."
  exit 1
fi

"${APKSIGNER}" verify --print-certs "${APK_PATH}"
green "✓ Signature valide"

bold "▶ SHA256"
sha256sum "${APK_PATH}"

bold "▶ Taille"
du -h "${APK_PATH}" | awk '{print $1}'

green "✓ APK release prêt : ${APK_PATH}"
