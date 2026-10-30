import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// Joue une image animée (WebP, GIF) une seule fois, puis reste sur la
/// dernière image et appelle [onDone]. `Image.asset` rejouerait en boucle :
/// les WebP du pack sont écrits avec une boucle infinie.
class PlayOnceImage extends StatefulWidget {
  final String path;
  final VoidCallback onDone;

  const PlayOnceImage({super.key, required this.path, required this.onDone});

  @override
  State<PlayOnceImage> createState() => _PlayOnceImageState();
}

class _PlayOnceImageState extends State<PlayOnceImage> {
  ui.Image? _frame;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _play(DefaultAssetBundle.of(context));
  }

  @override
  void dispose() {
    _frame?.dispose();
    super.dispose();
  }

  Future<void> _play(AssetBundle bundle) async {
    final data = await bundle.load(widget.path);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    try {
      for (var i = 0; i < codec.frameCount; i++) {
        final next = await codec.getNextFrame();
        if (!mounted) {
          next.image.dispose();
          return;
        }
        final previous = _frame;
        setState(() => _frame = next.image);
        WidgetsBinding.instance
            .addPostFrameCallback((_) => previous?.dispose());
        await Future<void>.delayed(next.duration);
        if (!mounted) return;
      }
      widget.onDone();
    } finally {
      codec.dispose();
    }
  }

  @override
  Widget build(BuildContext context) =>
      RawImage(image: _frame, fit: BoxFit.cover);
}
