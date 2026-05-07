import 'package:flutter/material.dart';

import '../services/backgrounds_loader.dart';
import '../services/backgrounds_service.dart';
import '../theme/app_theme.dart';

/// Arrière-plan de `SessionScreen`. Affiche soit un média (image / GIF)
/// fourni par `BackgroundsService.instance.current`, soit le placeholder
/// animé (dégradé radial qui pulse) si aucun fond n'est posé.
///
/// **Source des médias** : catalogue `assets/backgrounds.json` chargé au
/// démarrage par `BackgroundsLoader` et injecté dans le service. Un step
/// peut imposer un fond précis via `step.background = "<id>"` ; sinon le
/// service rotate aléatoirement à chaque changement de mode.
///
/// **Vidéo** : pas livré en V1 (cf. CLAUDE.md backlog). Pour ajouter,
/// installer `video_player ^2.x` et étendre `BackgroundMediaType` avec
/// un cas `video` + un sous-widget dédié dans le switch ci-dessous.
///
/// **Opacité** : plafonnée à 0.55 pour que les badges, jauges et
/// l'animation principale restent lisibles par-dessus. À ajuster si les
/// médias livrés sont déjà sombres / désaturés.
class SessionBackground extends StatelessWidget {
  /// Quand false, ignore complètement `BackgroundsService.current` et
  /// rend uniquement le dégradé animé. Permet à l'utilisatrice de
  /// désactiver les médias visuels (toggle dans la page SONS) sans
  /// vider le `assets/backgrounds.json` ni perdre la rotation côté
  /// service (qui continue son cycle, juste pas affichée).
  final bool mediaEnabled;

  const SessionBackground({super.key, this.mediaEnabled = true});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      // Pas d'interaction : le fond ne doit jamais bouffer un tap qui
      // appartient à l'UI au-dessus.
      child: !mediaEnabled
          ? const _AmbientGradient()
          : ValueListenableBuilder<BackgroundEntry?>(
              valueListenable: BackgroundsService.instance.current,
              builder: (context, entry, _) {
                // AnimatedSwitcher avec une key par id → fade-cross entre
                // 2 médias. La key fallback `__placeholder__` est partagée
                // par tout le monde quand entry == null, donc on évite un
                // re-fadein si le service repasse à null entre 2 médias.
                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 600),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  child: entry == null
                      ? const _AmbientGradient(
                          key: ValueKey('__placeholder__'))
                      : _MediaBackground(
                          entry: entry, key: ValueKey(entry.id)),
                );
              },
            ),
    );
  }
}

/// Rendu d'une entrée du catalogue. Le `path` peut être :
/// - un asset local (`assets/backgrounds/foo.gif`) → `Image.asset`.
/// - une URL HTTP/HTTPS (`https://.../foo.gif`) → `Image.network`.
///
/// Détection par préfixe `http`. Permet de mélanger des médias bundlés
/// dans l'APK et des liens externes dans le même `backgrounds.json` sans
/// changer le schéma. Trade-off URL : pas de cache disque (cache mémoire
/// seulement par `Image.network`), donc re-DL au cold start. Si ça pose
/// problème, ajouter `cached_network_image ^3.x` à pubspec et remplacer
/// `Image.network` par `CachedNetworkImage` ici.
///
/// Switch sur `type` parce que l'API d'`Image.*` couvre déjà jpg/png/gif
/// (Flutter joue les GIF nativement) — `gif` et `image` partagent donc
/// le même rendu en V1. Garder le switch ouvert facilite l'ajout d'un
/// cas `video` plus tard.
class _MediaBackground extends StatelessWidget {
  final BackgroundEntry entry;

  const _MediaBackground({required this.entry, super.key});

  bool get _isRemote =>
      entry.path.startsWith('http://') || entry.path.startsWith('https://');

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        switch (entry.type) {
          BackgroundMediaType.image ||
          BackgroundMediaType.gif =>
            _isRemote
                ? Image.network(
                    entry.path,
                    fit: BoxFit.cover,
                    // Pendant le DL : afficher le placeholder animé pour
                    // ne pas trouer l'écran de noir le temps du fetch.
                    loadingBuilder: (_, child, progress) =>
                        progress == null ? child : const _AmbientGradient(),
                    // Erreur réseau / 404 : fallback placeholder, pas
                    // d'icône d'erreur Flutter par-dessus la séance.
                    errorBuilder: (_, __, ___) => const _AmbientGradient(),
                  )
                : Image.asset(
                    entry.path,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const _AmbientGradient(),
                  ),
        },
        // Voile sombre pour garder l'UI lisible quel que soit le média
        // fourni. Préférable au paramètre `opacity` d'Image.* qui baisse
        // uniformément (les pixels clairs deviennent transparents tout
        // autant que les sombres).
        const DecoratedBox(
          decoration: BoxDecoration(
            color: Color(0x73000000), // ~0.45 alpha
          ),
          child: SizedBox.expand(),
        ),
      ],
    );
  }
}

class _AmbientGradient extends StatefulWidget {
  const _AmbientGradient({super.key});

  @override
  State<_AmbientGradient> createState() => _AmbientGradientState();
}

class _AmbientGradientState extends State<_AmbientGradient>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(_ctrl.value);
        // Centre du dégradé qui flotte légèrement pour éviter l'effet
        // « fond figé ». Amplitude faible (±0.12) pour rester subtil.
        final centerX = -0.12 + 0.24 * t;
        final centerY = -0.18 + 0.36 * t;
        // Couleurs : on glisse de l'ambre du theme (chaud) vers un
        // violet sombre (froid) — palette cohérente avec les modes du
        // badge sans copier une couleur de mode en particulier.
        final warm = Color.lerp(
          AppTheme.accent.withValues(alpha: 0.18),
          const Color(0xFF7E57C2).withValues(alpha: 0.16),
          t,
        )!;
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(centerX, centerY),
              radius: 1.2,
              colors: [
                warm,
                AppTheme.background,
              ],
              stops: const [0.0, 0.85],
            ),
          ),
          child: const SizedBox.expand(),
        );
      },
    );
  }
}
