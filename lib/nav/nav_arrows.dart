import 'dart:math' as math;
import 'dart:typed_data';

import 'nav_arrow.dart';

/// The kinds of manoeuvre the simulated Maps draws an arrow for.
enum NavTurn { straight, left, right, uturn, arrive }

/// Arrows drawn in code, for the simulator and for tests: white-on-transparent
/// masks of the size Google Maps' own are (126 px), so that the HUD is shown
/// something of the real shape. They are not Google's pictures.
class NavArrows {
  const NavArrows._();

  static const size = 126;

  static final Map<NavTurn, NavArrow> _cache = {};

  static NavArrow forTurn(NavTurn turn) =>
      _cache.putIfAbsent(turn, () => _draw(turn));

  // Each turn as lines in a unit square, y down. The stroke is 0.11 of it, as
  // thick as Google's.
  static const _stroke = 0.11;

  static const _right = <List<math.Point<double>>>[
    [math.Point(0.3, 0.9), math.Point(0.3, 0.5), math.Point(0.72, 0.5)],
    [math.Point(0.55, 0.3), math.Point(0.74, 0.5), math.Point(0.55, 0.7)],
  ];

  static List<List<math.Point<double>>> _mirror(
    List<List<math.Point<double>>> lines,
  ) => [
    for (final line in lines) [for (final p in line) math.Point(1 - p.x, p.y)],
  ];

  static final _paths = <NavTurn, List<List<math.Point<double>>>>{
    NavTurn.straight: [
      [math.Point(0.5, 0.92), math.Point(0.5, 0.2)],
      [math.Point(0.27, 0.42), math.Point(0.5, 0.17), math.Point(0.73, 0.42)],
    ],
    NavTurn.right: _right,
    NavTurn.left: _mirror(_right),
    NavTurn.uturn: [
      [
        math.Point(0.7, 0.92),
        math.Point(0.7, 0.4),
        math.Point(0.66, 0.27),
        math.Point(0.56, 0.18),
        math.Point(0.44, 0.18),
        math.Point(0.34, 0.27),
        math.Point(0.3, 0.4),
        math.Point(0.3, 0.64),
      ],
      [math.Point(0.17, 0.5), math.Point(0.3, 0.68), math.Point(0.43, 0.5)],
    ],
  };

  static NavArrow _draw(NavTurn turn) {
    final alpha = Uint8List(size * size);
    if (turn == NavTurn.arrive) {
      // A ring with a dot: somewhere to arrive at.
      for (var y = 0; y < size; y++) {
        for (var x = 0; x < size; x++) {
          final d = math.sqrt(
            math.pow((x + 0.5) / size - 0.5, 2) +
                math.pow((y + 0.5) / size - 0.5, 2),
          );
          final ring = (_stroke / 2 - (d - 0.3).abs()) * size;
          final dot = (0.1 - d) * size;
          alpha[y * size + x] = _coverage(math.max(ring, dot));
        }
      }
    } else {
      for (final line in _paths[turn]!) {
        for (var i = 0; i + 1 < line.length; i++) {
          _segment(alpha, line[i], line[i + 1]);
        }
      }
    }
    return NavArrow(
      id: 'sim-${turn.name}-${_hash(alpha)}',
      width: size,
      height: size,
      alpha: alpha,
    );
  }

  /// Strokes the segment from [a] to [b] with round ends, adding to [alpha].
  static void _segment(
    Uint8List alpha,
    math.Point<double> a,
    math.Point<double> b,
  ) {
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    final lengthSquared = dx * dx + dy * dy;
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        final px = (x + 0.5) / size;
        final py = (y + 0.5) / size;
        final t = lengthSquared == 0
            ? 0.0
            : (((px - a.x) * dx + (py - a.y) * dy) / lengthSquared).clamp(
                0.0,
                1.0,
              );
        final d = math.sqrt(
          math.pow(px - (a.x + t * dx), 2) + math.pow(py - (a.y + t * dy), 2),
        );
        final c = _coverage((_stroke / 2 - d) * size);
        final i = y * size + x;
        if (c > alpha[i]) alpha[i] = c;
      }
    }
  }

  /// Anti-aliased coverage from how far inside the shape a pixel's middle is, in
  /// pixels: one pixel from outside to inside.
  static int _coverage(double insidePixels) =>
      ((insidePixels + 0.5).clamp(0.0, 1.0) * 255).round();

  /// FNV-1a over the pixels: the same pixels, the same name.
  static String _hash(Uint8List bytes) {
    var h = 0x811C9DC5;
    for (final b in bytes) {
      h = ((h ^ b) * 0x01000193) & 0xFFFFFFFF;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }
}
