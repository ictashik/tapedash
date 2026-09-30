import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../theme/tape_theme.dart';
import '../tokens/strokes.dart';

/// One mark in an icon, on the 24-unit grid.
sealed class IconOp {
  const IconOp();
}

/// A run of straight lines, stroked; closed if it says so.
class IconLine extends IconOp {
  const IconLine(this.points, {this.closed = false});

  /// x0, y0, x1, y1, ...
  final List<double> points;
  final bool closed;
}

/// A circle. Circles are the one curve the icon language allows (DESIGN.md 4.8).
class IconCircle extends IconOp {
  const IconCircle(this.x, this.y, this.radius, {this.filled = false});

  final double x;
  final double y;
  final double radius;
  final bool filled;
}

/// A filled square: a dot.
class IconDot extends IconOp {
  const IconDot(this.x, this.y, this.size);

  /// The top-left corner.
  final double x;
  final double y;
  final double size;
}

/// The icon set (DESIGN.md 4.8): drawn in code on a 24-unit grid, stroke 1.75,
/// square caps, 45 degree chamfers, and no free curves except circles. No icon
/// font, and no Material icons.
///
/// Each icon is written as a short path: `M x y` starts a line, `L x y` adds a
/// point, `Z` closes it, `O x y r` is a circle, `D x y r` a filled disc and
/// `Q x y s` a filled square with its top-left at x, y. Every line runs along an
/// axis or at 45 degrees; the tests check that.
enum TapeIcon {
  adapter('M3 7 L14 7 L16 9 L16 15 L14 17 L3 17 Z M16 10 L21 10 M16 14 L21 14'),
  bluetooth('M7 6 L17 16 L12 21 L12 3 L17 8 L7 18'),
  wifi('M3 11 L12 2 L21 11 M6 14 L12 8 L18 14 M9 17 L12 14 L15 17 Q 11 19.5 2'),
  gps(
    'O 12 12 6 M12 2 L12 6 M12 18 L12 22 M2 12 L6 12 M18 12 L22 12 D 12 12 1.5',
  ),
  checkEngine(
    'M3 10 L6 10 L6 8 L9 8 L9 6 L13 6 L13 8 L16 8 L16 10 L18 10 L18 8 L21 8 '
    'L21 16 L18 16 L18 14 L16 14 L16 18 L7 18 L5 16 L3 16 Z',
  ),
  coolant(
    'M10 14 L10 4 L14 4 L14 14 M12 8 L12 14 M16 6 L19 6 M16 10 L19 10 '
    'O 12 17.5 3.5',
  ),
  voltage(
    'M3 7 L21 7 L21 19 L3 19 Z M5 7 L5 4 L9 4 L9 7 M15 7 L15 4 L19 4 L19 7 '
    'M6 13 L10 13 M8 11 L8 15 M14 13 L18 13',
  ),
  fuelPump(
    'M4 21 L4 4 L13 4 L13 21 Z M3 21 L14 21 M6 7 L11 7 L11 11 L6 11 Z '
    'M13 8 L16 8 L19 11 L19 17 L21 17',
  ),
  clock('O 12 12 9 M12 6 L12 12 L16 16'),
  lock(
    'M5 11 L19 11 L19 19 L17 21 L7 21 L5 19 Z M8 11 L8 7 L10 5 L14 5 L16 7 L16 11',
  ),
  back('M10 6 L4 12 L10 18 M4 12 L20 12'),
  close('M6 6 L18 18 M18 6 L6 18'),
  chevron('M9 5 L16 12 L9 19'),
  garage(
    'M3 12 L12 3 L21 12 M3 12 L3 21 M21 12 L21 21 M7 21 L7 14 L17 14 L17 21 '
    'M7 17.5 L17 17.5',
  ),
  history('M7 7 L20 7 M7 12 L20 12 M7 17 L20 17 Q 3 6 2 Q 3 11 2 Q 3 16 2'),
  coach('O 12 12 9 O 12 12 2 M3 12 L10 12 M14 12 L21 12 M12 14 L12 21'),
  review('M4 19 L9 14 L13 18 L20 11 O 4 19 2 Q 19 9 3'),
  rupee('M6 4 L12 4 L15 7 L15 9 L12 12 L7 12 L16 21 M6 8 L18 8 M6 4 L18 4'),
  idle('M5 5 L19 5 L19 19 L5 19 Z D 12 12 2'),
  hardAccel('M5 12 L12 5 L19 12 M5 19 L12 12 L19 19'),
  hardBrake('M5 8 L19 8 M5 16 L19 16'),
  speed(
    'O 12 12 9 M12 12 L17 7 D 12 12 1.5 M12 3 L12 5 M3 12 L5 12 M21 12 L19 12',
  ),
  phoneHot('M7 4 L17 4 L17 20 L7 20 Z M10 17 L14 17 M19 6 L21 8 L19 10 L21 12'),
  demo('M6 5 L14 5 L18 9 L18 15 L14 19 L6 19 Z'),
  hud('M3 17 L3 9 L6 6 L18 6 L21 9 L21 17 Z M8 12 L16 12 M8 15 L16 15'),
  flip(
    'M4 12 L20 12 M8 8 L4 12 L8 16 M16 8 L20 12 L16 16 M12 3 L12 6 M12 18 L12 21',
  ),
  pitStop('M12 3 L19 10 L19 15 L14 20 L10 20 L5 15 L5 10 Z M9 15 L9 13'),
  endTrip('M6 21 L6 3 M6 4 L19 4 L15 8 L19 12 L6 12');

  const TapeIcon(this.path);

  /// The icon as a path (see the class documentation).
  final String path;

  /// The marks, parsed once.
  List<IconOp> get ops => _parsed.putIfAbsent(this, () => parsePath(path));

  static final Map<TapeIcon, List<IconOp>> _parsed = {};

  /// The name as a hyphenated word, for the Lab and for tests.
  String get label => name.replaceAllMapped(
    RegExp(r'[A-Z]'),
    (m) => '-${m.group(0)!.toLowerCase()}',
  );

  /// Parses an icon path into its marks. It throws a [FormatException] on a
  /// command it does not know, so that a typo is an error and not a missing line.
  static List<IconOp> parsePath(String path) {
    final matches = RegExp(r'[A-Za-z]|-?\d+(?:\.\d+)?').allMatches(path);
    final tokens = [for (final m in matches) m.group(0)!];
    if (path
        .replaceAll(RegExp(r'[A-Za-z]|-?\d+(?:\.\d+)?|[\s,]'), '')
        .isNotEmpty) {
      throw FormatException('Unexpected characters in icon path $path');
    }
    final ops = <IconOp>[];
    var line = <double>[];
    void flush({bool closed = false}) {
      if (line.isNotEmpty) ops.add(IconLine(line, closed: closed));
      line = <double>[];
    }

    var i = 0;
    double num() => double.parse(tokens[i++]);
    while (i < tokens.length) {
      final command = tokens[i++];
      switch (command) {
        case 'M':
          flush();
          line = [num(), num()];
        case 'L':
          line.addAll([num(), num()]);
        case 'Z':
          flush(closed: true);
        case 'O':
          flush();
          ops.add(IconCircle(num(), num(), num()));
        case 'D':
          flush();
          ops.add(IconCircle(num(), num(), num(), filled: true));
        case 'Q':
          flush();
          ops.add(IconDot(num(), num(), num()));
        default:
          throw FormatException('Unknown icon command $command in $path');
      }
    }
    flush();
    return ops;
  }
}

/// The side of the grid icons are drawn on.
const double tapeIconGrid = 24;

/// Draws [icon] with its top-left corner at [origin], [size] logical pixels on a
/// side, in [color]. [strokeScale] thickens the stroke in Daylight.
void paintTapeIcon(
  Canvas canvas,
  TapeIcon icon,
  Offset origin,
  double size,
  Color color, {
  double strokeScale = 1,
  Paint? paint,
}) {
  final scale = size / tapeIconGrid;
  final stroke = paint ?? Paint();
  stroke
    ..color = color
    ..style = ui.PaintingStyle.stroke
    ..strokeWidth = TapeStroke.icon * scale * strokeScale
    ..strokeCap = ui.StrokeCap.square
    ..strokeJoin = ui.StrokeJoin.miter
    ..isAntiAlias = true;
  final fill = Paint()
    ..color = color
    ..style = ui.PaintingStyle.fill
    ..isAntiAlias = true;

  Offset at(double x, double y) => origin + Offset(x * scale, y * scale);

  for (final op in icon.ops) {
    switch (op) {
      case IconLine():
        final path = Path();
        for (var i = 0; i < op.points.length; i += 2) {
          final p = at(op.points[i], op.points[i + 1]);
          if (i == 0) {
            path.moveTo(p.dx, p.dy);
          } else {
            path.lineTo(p.dx, p.dy);
          }
        }
        if (op.closed) path.close();
        canvas.drawPath(path, stroke);
      case IconCircle():
        canvas.drawCircle(
          at(op.x, op.y),
          op.radius * scale,
          op.filled ? fill : stroke,
        );
      case IconDot():
        canvas.drawRect(
          Rect.fromLTWH(
            origin.dx + op.x * scale,
            origin.dy + op.y * scale,
            op.size * scale,
            op.size * scale,
          ),
          fill,
        );
    }
  }
}

/// An icon of the set, at [size], in [color] (or the label colour of the theme).
class TapeIconView extends StatelessWidget {
  const TapeIconView(this.icon, {super.key, this.size = 24, this.color});

  final TapeIcon icon;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = TapeTheme.of(context);
    final palette = theme.palette;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _IconPainter(
          icon,
          color ?? palette.label,
          palette.strokeScale,
        ),
      ),
    );
  }
}

class _IconPainter extends CustomPainter {
  _IconPainter(this.icon, this.color, this.strokeScale);

  final TapeIcon icon;
  final Color color;
  final double strokeScale;

  @override
  void paint(Canvas canvas, Size size) => paintTapeIcon(
    canvas,
    icon,
    Offset.zero,
    size.shortestSide,
    color,
    strokeScale: strokeScale,
  );

  @override
  bool shouldRepaint(_IconPainter old) =>
      old.icon != icon || old.color != color || old.strokeScale != strokeScale;
}
