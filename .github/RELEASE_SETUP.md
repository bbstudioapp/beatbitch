# Setup CI/CD — Release Android automatique

Ce dépôt publie un APK release signé sur **GitHub Releases** à chaque
push sur `main` qui bumpe la `version:` du `rhythm_coach/pubspec.yaml`.

Le workflow vit dans [`workflows/release.yml`](workflows/release.yml).

## Logique

1. Trigger : `push` sur `main` (ou `workflow_dispatch` manuel).
2. Lecture de `version:` dans `rhythm_coach/pubspec.yaml`.
3. Si le tag `v<version>` existe déjà → no-op.
4. Sinon : checkout JDK 17 + Flutter stable + tests + build APK release
   signé + tag + Release GitHub avec l'APK et son SHA256.

Pour publier `v0.2.0`, il suffit de :
1. Bumper `version: 0.2.0+N` dans `pubspec.yaml`.
2. Commit + push sur `main`.

## Secrets GitHub à configurer

Repo → **Settings** → **Secrets and variables** → **Actions** → **New
repository secret**. Quatre secrets requis :

| Nom | Contenu |
|---|---|
| `KEYSTORE_BASE64` | Le keystore `~/.android/beatbitch-upload.jks` encodé en base64 |
| `KEYSTORE_PASSWORD` | Mot de passe du keystore (champ `storePassword` de `key.properties`) |
| `KEY_PASSWORD` | Mot de passe de la clé (champ `keyPassword` — souvent identique au précédent) |
| `KEY_ALIAS` | Alias de la clé (`upload` par défaut) |

### Comment encoder le keystore

```bash
# Option 1 : copie directe dans le presse-papiers (xclip requis)
base64 -w 0 ~/.android/beatbitch-upload.jks | xclip -selection clipboard

# Option 2 : sortie dans un fichier temporaire
base64 -w 0 ~/.android/beatbitch-upload.jks > /tmp/keystore.b64
# Puis : cat /tmp/keystore.b64 et copier-coller dans le secret
rm /tmp/keystore.b64
```

> ⚠ `-w 0` est critique : sans lui, base64 insère des sauts de ligne et
> le décodage côté CI échoue. Vérifie que la sortie est une **seule
> longue ligne** sans retour chariot.

## Vérification après premier push

1. Onglet **Actions** du repo → suivre l'exécution du workflow `Release Android APK`.
2. Si succès, onglet **Releases** → voir `BeatBitch <version>` avec l'APK + `.sha256`.
3. Télécharger l'APK et vérifier : `sha256sum -c BeatBitch-<version>.apk.sha256`.

## Limitations actuelles

- **Assets binaires externalisés non bundlés** : les `assets/backgrounds/*.gif`
  et `assets/audio/ambience/*.mp3` ne sont pas dans le repo (cf. CLAUDE.md
  → section *Assets binaires externalisés*). L'APK CI sera fonctionnel mais
  sans fonds média et avec ambiance silencieuse. Une étape de récupération
  depuis un canal externe (R2, Drive, S3 privé…) reste à concevoir, à
  insérer entre `flutter pub get` et `flutter build apk` dans le workflow.
- **Pas de signing v2/v3 explicite** : le build Gradle utilise les défauts
  Android — suffisant pour Android 7+, ce qui couvre la cible (Android 9+).
- **Pas d'app bundle (`.aab`)** : on ne distribue pas via Play Store, donc
  inutile. Si un jour publication Play, ajouter `flutter build appbundle`.

## Si tu perds le keystore

Tu ne pourras plus publier de mise à jour signée par la même identité.
Les utilisateurs Android refuseront l'install d'un nouveau keystore par-dessus
l'ancien (« package conflicts with existing package »). Sauvegarde le `.jks`
dans un coffre-fort (1Password, Bitwarden, KeePass) le jour de sa création.
