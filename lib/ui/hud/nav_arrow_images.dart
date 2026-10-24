import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../../nav/nav_arrow.dart';

/// Keeps the picture of each manoeuvre as an image the HUD can paint
/// (docs/NAV.md).
///
/// Google Maps draws a handful of arrows, over and over, so each is made into an
/// image once and kept (a few at most). Making an image is asynchronous in
/// Flutter; until it is ready [imageFor] gives null and the HUD draws no arrow,
/// and this tells its listeners when there is one, so that the HUD repaints. The
/// image is white with Maps' coverage, a mask: the HUD paints it in its own
/// colour.
class NavArrowImages extends ChangeNotifier {
  /// The most arrows kept: a route has a few kinds of turn.
  static const _keep = 8;

  final Map<String, ui.Image> _images = {};
  final Set<String> _making = {};
  bool _disposed = false;

  /// The image of [arrow], or null while it is being made (or if there is none).
  ui.Image? imageFor(NavArrow? arrow) {
    if (arrow == null) return null;
    final image = _images[arrow.id];
    if (image != null) return image;
    if (_making.add(arrow.id)) _make(arrow);
    return null;
  }

  void _make(NavArrow arrow) {
    final pixels = Uint8List(arrow.width * arrow.height * 4);
    for (var i = 0; i < arrow.alpha.length; i++) {
      pixels[i * 4] = 255;
      pixels[i * 4 + 1] = 255;
      pixels[i * 4 + 2] = 255;
      pixels[i * 4 + 3] = arrow.alpha[i];
    }
    ui.decodeImageFromPixels(
      pixels,
      arrow.width,
      arrow.height,
      ui.PixelFormat.rgba8888,
      (image) {
        _making.remove(arrow.id);
        if (_disposed) {
          image.dispose();
          return;
        }
        if (_images.length >= _keep) {
          final oldest = _images.keys.first;
          _images.remove(oldest)?.dispose();
        }
        _images[arrow.id] = image;
        notifyListeners();
      },
    );
  }

  @override
  void dispose() {
    _disposed = true;
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
    super.dispose();
  }
}
