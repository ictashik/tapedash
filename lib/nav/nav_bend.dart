import 'nav_arrow.dart';

/// Which way a manoeuvre turns, read from its arrow.
enum NavBend {
  left,
  right,

  /// Straight on: one stroke up the middle.
  straight,

  /// Anything else (a U-turn, a roundabout), or an arrow too faint or too odd to
  /// read. The HUD then draws no bend, and Google's own arrow says the rest.
  unknown,
}

/// Reads [NavBend] out of the arrow Google Maps drew.
///
/// Maps' turn arrows are a stem that comes up from the bottom and bends to one
/// side, the head at the side: the ink at the top is on the side it turns to, and
/// the ink at the bottom is on the other. A capture of Maps 25.33 gives a
/// difference of 0.37 of the picture's width for a left turn (-) and a right turn
/// (+), and nothing for straight ahead; Maps 26.42's 135 px arrows give the same.
/// A U-turn has ink on both sides and no difference, and is told from straight by
/// being wider. An arrow that is none of these (a sharp turn, a roundabout) is
/// `unknown`, and the HUD then draws no bend (docs/NAV.md): a line that leans
/// the wrong way would be worse than one that does not lean.
class NavBendReader {
  const NavBendReader._();

  /// Coverage above this counts as ink.
  static const _ink = 40;

  /// How far the top's middle must be from the bottom's, as a share of the
  /// picture's width, for a turn; and how near for a straight line.
  static const _turnShare = 0.12;

  /// How far off the picture's middle the stem (the ink's bottom) must be, as a
  /// share of its width, for a turn. Every turn arrow's stem rises from one side.
  /// Maps 26.42's "Sharp right" is a hairpin: ink on both sides at the bottom, a
  /// stem 0.00 off the middle, and a top-to-bottom difference of 0.12 that sat on
  /// [_turnShare] and was read as a LEFT turn. Real turns are 0.28 to 0.35 here.
  static const _stemShare = 0.12;
  static const _straightShare = 0.08;

  /// Wider than this share of the picture and with no difference: not straight.
  static const _straightWidthShare = 0.58;

  static final Map<String, NavBend> _cache = {};

  static NavBend of(NavArrow arrow) =>
      _cache.putIfAbsent(arrow.id, () => _read(arrow));

  static NavBend _read(NavArrow arrow) {
    final w = arrow.width;
    final h = arrow.height;
    final a = arrow.alpha;

    var top = h;
    var bottom = -1;
    var left = w;
    var right = -1;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (a[y * w + x] > _ink) {
          if (y < top) top = y;
          if (y > bottom) bottom = y;
          if (x < left) left = x;
          if (x > right) right = x;
        }
      }
    }
    if (bottom < 0) return NavBend.unknown;
    final span = bottom - top + 1;
    // Too small to be an arrow.
    if (span < h * 0.25) return NavBend.unknown;

    final band = (span * 0.4).round().clamp(1, span);
    final upper = _middle(a, w, top, top + band);
    final lower = _middle(a, w, bottom + 1 - band, bottom + 1);
    if (upper == null || lower == null) return NavBend.unknown;

    final difference = (upper - lower) / w;
    final stem = (lower - w / 2).abs() / w;
    if (stem >= _stemShare) {
      if (difference <= -_turnShare) return NavBend.left;
      if (difference >= _turnShare) return NavBend.right;
    }
    final widthShare = (right - left + 1) / w;
    if (difference.abs() <= _straightShare &&
        widthShare < _straightWidthShare) {
      return NavBend.straight;
    }
    return NavBend.unknown;
  }

  /// The ink's middle, by coverage, across rows [from] to [to).
  static double? _middle(List<int> a, int w, int from, int to) {
    var sum = 0.0;
    var weight = 0;
    for (var y = from; y < to; y++) {
      for (var x = 0; x < w; x++) {
        final v = a[y * w + x];
        sum += x * v;
        weight += v;
      }
    }
    return weight == 0 ? null : sum / weight;
  }
}
