import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../tokens/tach.dart';
import '../../tokens/watch.dart';

/// The geometry of a round watch face of one [diameter] (DESIGN.md 16.3): where
/// the rim, the core and the zones are, and how wide the circle is at any height.
///
/// A round screen makes its corners invisible, so layout asks this rather than
/// guessing: a line of text is only placed where [chordAt] says it fits.
@immutable
class WatchFace {
  const WatchFace(this.diameter);

  /// A face that fills a [width] by [height] box: the shorter side.
  factory WatchFace.of(double width, double height) =>
      WatchFace(math.min(width, height));

  final double diameter;

  double get radius => diameter / 2;
  Offset get centre => Offset(radius, radius);

  /// The rim: the band the tach arc and the money ring are drawn in.
  double get rimOuter => TapeTach.rimOuterShare * diameter;
  double get rimDepth => TapeTach.rimDepthShare * diameter;
  double get rimInner => rimOuter - rimDepth;

  /// The radius of the middle of the rim's band.
  double get rimRadius => rimOuter - rimDepth / 2;

  /// The disc the hero and the readouts live in.
  double get coreRadius => TapeWatch.coreShare * diameter;

  /// Where a zone's centre is, down from the top of the face.
  double get crownY => TapeWatch.crownY * diameter;
  double get heroY => TapeWatch.heroY * diameter;
  double get footY => TapeWatch.footY * diameter;
  double get tapeY => TapeWatch.tapeY * diameter;

  /// The sizes of type on this face.
  WatchType get type => WatchType.forDiameter(diameter);

  /// How wide a circle of [circleRadius] is at [y] down from the top of the face
  /// (0 where it does not reach). With no radius given it is the face itself.
  double chordAt(double y, {double? circleRadius}) {
    final r = circleRadius ?? radius;
    final dy = y - radius;
    if (dy.abs() >= r) return 0;
    return 2 * math.sqrt(r * r - dy * dy);
  }

  /// The width available to a line [height] tall centred at [y]: the narrowest
  /// the core is across it, which is its top or its bottom edge.
  double roomAt(double y, double height) {
    final top = chordAt(y - height / 2, circleRadius: coreRadius);
    final bottom = chordAt(y + height / 2, circleRadius: coreRadius);
    return math.min(top, bottom);
  }

  /// The rim's tach geometry for this face.
  TachGeometry get tach => TachGeometry.rim(diameter);

  /// Whether [rect] (in the face's own coordinates) lies inside the face.
  bool contains(Rect rect) {
    for (final p in [
      rect.topLeft,
      rect.topRight,
      rect.bottomLeft,
      rect.bottomRight,
    ]) {
      if ((p - centre).distance > radius) return false;
    }
    return true;
  }

  @override
  bool operator ==(Object other) =>
      other is WatchFace && other.diameter == diameter;

  @override
  int get hashCode => diameter.hashCode;
}
