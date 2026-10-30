import 'package:flutter/services.dart' show AssetManifest, rootBundle;

Set<String>? _manifestKeys;

/// [assetKey] est la clé complète (`assets/...`). Interroge l'`AssetManifest` :
/// lire le fichier lui-même chargerait un morceau entier pour un test de
/// présence.
Future<bool> isAssetBundled(String assetKey) async {
  try {
    _manifestKeys ??= (await AssetManifest.loadFromAssetBundle(rootBundle))
        .listAssets()
        .toSet();
    return _manifestKeys!.contains(assetKey);
  } catch (_) {
    return false;
  }
}
