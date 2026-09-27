import 'dart:ui' show Picture, PictureRecorder;

import 'package:flutter/widgets.dart';

/// A layer that is drawn once into a `Picture` and replayed (DESIGN.md 4.2 and
/// 9.3): the void, the vignette and grain (L0), and the etched scales and frames
/// (L1). Nothing in it changes while driving.
///
/// [paint] draws the layer. It runs when the layer is first shown, when the size
/// changes, and when [cacheKey] changes: put the things it depends on into the key
/// (the livery, the mode, the tier). In between, the recorded picture is replayed,
/// inside a `RepaintBoundary` of its own, so no frame repaints it.
class StaticLayer extends StatefulWidget {
  const StaticLayer({
    super.key,
    required this.cacheKey,
    required this.paint,
    this.child,
  });

  /// Anything that compares with `==` and changes when the drawing should.
  final Object cacheKey;

  /// Draws the layer into a canvas of the given size.
  final void Function(Canvas canvas, Size size) paint;

  /// Something drawn over the layer, such as the live data.
  final Widget? child;

  @override
  State<StaticLayer> createState() => _StaticLayerState();
}

class _StaticLayerState extends State<StaticLayer> {
  Picture? _picture;
  Size? _size;
  Object? _key;

  /// How many times the layer has been recorded, for the tests.
  int recordings = 0;

  Picture _recordFor(Size size) {
    if (_picture != null && _size == size && _key == widget.cacheKey) {
      return _picture!;
    }
    _picture?.dispose();
    final recorder = PictureRecorder();
    widget.paint(Canvas(recorder), size);
    _picture = recorder.endRecording();
    _size = size;
    _key = widget.cacheKey;
    recordings++;
    return _picture!;
  }

  @override
  void dispose() {
    _picture?.dispose();
    _picture = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _PicturePainter(this, widget.cacheKey),
        child: widget.child,
      ),
    );
  }
}

class _PicturePainter extends CustomPainter {
  _PicturePainter(this._state, this._key);

  final _StaticLayerState _state;
  final Object _key;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPicture(_state._recordFor(size));
  }

  @override
  bool shouldRepaint(_PicturePainter oldDelegate) => oldDelegate._key != _key;
}

/// The number of times a [StaticLayer] recorded its picture, for tests.
@visibleForTesting
int recordingsOf(State<StaticLayer> state) =>
    (state as _StaticLayerState).recordings;
