import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../app/nav_service.dart';
import '../../nav/nav_bend.dart';
import '../../nav/nav_format.dart';
import '../../nav/nav_state.dart';
import '../../nav/nav_tracker.dart';
import '../design/components/rolling_numerals.dart';
import '../design/motion/observable_listenable.dart';
import '../design/tokens/hud.dart';
import '../design/tokens/strokes.dart';
import '../design/tokens/typography.dart';
import '../pages/drive/drive_signals.dart';
import 'hud_parts.dart';
import 'nav_arrow_images.dart';

/// The navigation layout of the HUD (DESIGN.md 8, docs/NAV.md): the speed on the
/// left, and what Google Maps says on the right: its arrow, the distance to the
/// turn, the instruction, and along the bottom the ETA, the time left and the
/// distance left. A bold line climbs to the junction, bending where the arrow
/// does, with a dot on it that counts down the distance to the turn.
///
/// The speed is the HUD's own numerals. Everything else is painted by one painter
/// that repaints when Maps posts something, never rebuilding a widget for data
/// (DESIGN.md 9.3). The line is a sketch of the next junction, not a map: Google
/// Maps does not give out its route.
class NavHud extends StatefulWidget {
  const NavHud({
    super.key,
    required this.signals,
    required this.nav,
    required this.width,
    required this.height,
    required this.color,
  });

  final DriveSignals signals;
  final NavService nav;
  final double width;
  final double height;
  final Color color;

  @override
  State<NavHud> createState() => _NavHudState();
}

class _NavHudState extends State<NavHud> {
  late final ObservableListenable<NavState> _state = ObservableListenable(
    widget.nav.tracker.state,
  );
  late final ObservableListenable<NavFreshness> _freshness =
      ObservableListenable(widget.nav.tracker.freshness);
  late final ObservableListenable<double?> _estimate = ObservableListenable(
    widget.nav.tracker.distanceToTurnEstimateM,
  );
  final NavArrowImages _images = NavArrowImages();

  @override
  void dispose() {
    _state.dispose();
    _freshness.dispose();
    _estimate.dispose();
    _images.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.width;
    final h = widget.height;
    final color = widget.color;
    final size = h * TapeHud.navSpeedShare;
    final ink = NumeralMetrics(size).inkHeight;
    final y = h * 0.40;
    final half = w / 2;
    return Stack(
      children: [
        hudAtInk(
          centreX: half / 2,
          centreY: y,
          size: size,
          boxWidth: half,
          child: HudNumerals(
            source: widget.signals.speed,
            format: const NumeralFormat(integerDigits: 3),
            size: size,
            typical: 2,
          ),
        ),
        Positioned(
          top: y + ink / 2 + h * 0.02,
          left: 0,
          width: half,
          child: Center(child: hudLabel('KM/H', h, color)),
        ),
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: NavHudPainter(
                state: _state,
                freshness: _freshness,
                estimate: _estimate,
                images: _images,
                color: color,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Where everything of the navigation layout goes, for a screen [width] by
/// [height], as shares of them (DESIGN.md 8). Pure, so a test can hold it to the
/// HUD's rules: nothing smaller than 0.06H, a stroke of at least 5 lp.
class NavHudGeometry {
  NavHudGeometry(this.width, this.height) {
    final w = width;
    final h = height;
    final right = w - w * 0.04;
    lineX = w * 0.5 + w * 0.035;
    lineTop = h * 0.10;
    lineBottom = h * 0.72;
    bendDx = w * 0.035;
    bendRise = h * 0.14;
    final contentLeft = w * 0.5 + w * 0.085;
    contentRight = right;
    final side = math.min(
      h * TapeHud.navArrowShare,
      (contentRight - contentLeft) * 0.42,
    );
    arrow = Rect.fromLTWH(
      contentLeft - side * TapeHud.navArrowInset,
      h * 0.07,
      side,
      side,
    );
    textLeft = contentLeft;
    distanceLeft = arrow.right - side * TapeHud.navArrowInset + h * 0.05;
    distanceMaxWidth = contentRight - distanceLeft;
    instructionTop = arrow.bottom + h * 0.03;
    instructionWidth = contentRight - contentLeft;
    instructionLines = TapeHud.navInstructionLines;
    figuresY = h * 0.88;
    figureCentres = [w * 0.2, w * 0.5, w * 0.8];
    strokeWidth = math.max(TapeStroke.hud, h * TapeHud.navLineShare);
    nodeRadius = h * TapeHud.navNodeShare;
    dotRadius = h * TapeHud.navDotShare;
    distanceSize = h * TapeHud.navDistanceShare;
    instructionSize = h * TapeHud.navInstructionShare;
    figureSize = h * TapeHud.navFigureShare;
    labelSize = h * TapeHud.labelShare;
  }

  final double width;
  final double height;

  // The approach line.
  late final double lineX;
  late final double lineTop;
  late final double lineBottom;
  late final double bendDx;
  late final double bendRise;
  late final double strokeWidth;
  late final double nodeRadius;
  late final double dotRadius;

  // The turn.
  late final Rect arrow;
  late final double distanceLeft;
  late final double distanceMaxWidth;
  late final double instructionTop;
  late final double instructionWidth;
  late final int instructionLines;

  /// Where the words start: the arrow's ink starts here too.
  late final double textLeft;
  late final double contentRight;

  // Along the bottom.
  late final double figuresY;
  late final List<double> figureCentres;

  // Sizes.
  late final double distanceSize;
  late final double instructionSize;
  late final double figureSize;
  late final double labelSize;

  /// The line from the car to the junction: straight up, or up and then leaning
  /// [bend] to the side the arrow turns.
  Path approach(NavBend bend) {
    final path = Path()..moveTo(lineX, lineBottom);
    final dx = switch (bend) {
      NavBend.left => -bendDx,
      NavBend.right => bendDx,
      _ => 0.0,
    };
    if (dx == 0) {
      path.lineTo(lineX, lineTop);
    } else {
      path
        ..lineTo(lineX, lineTop + bendRise)
        ..lineTo(lineX + dx, lineTop);
    }
    return path;
  }

  /// The junction at the top of the line, for [bend].
  Offset junction(NavBend bend) => Offset(
    lineX +
        switch (bend) {
          NavBend.left => -bendDx,
          NavBend.right => bendDx,
          _ => 0.0,
        },
    lineTop,
  );
}

/// Paints the right half and the bottom of the navigation layout.
class NavHudPainter extends CustomPainter {
  NavHudPainter({
    required this.state,
    required this.freshness,
    required this.estimate,
    required this.images,
    required this.color,
  }) : super(repaint: Listenable.merge([state, freshness, estimate, images]));

  final ValueListenable<NavState> state;
  final ValueListenable<NavFreshness> freshness;
  final ValueListenable<double?> estimate;
  final NavArrowImages images;
  final Color color;

  final Paint _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  final Paint _fill = Paint();
  final Paint _image = Paint()..filterQuality = FilterQuality.medium;

  final Map<String, TextPainter> _texts = {};
  NavHudGeometry? _geometry;
  Path? _path;
  Path? _drawn;
  ui.PathMetric? _metric;
  NavBend? _pathBend;

  @override
  void paint(Canvas canvas, Size size) {
    final g = _geometry?.width == size.width && _geometry?.height == size.height
        ? _geometry!
        : (_geometry = NavHudGeometry(size.width, size.height));
    final s = state.value;
    _stroke
      ..color = color
      ..strokeWidth = g.strokeWidth;
    _fill.color = color;
    _image.colorFilter = ColorFilter.mode(color, BlendMode.srcIn);

    if (freshness.value == NavFreshness.stale) {
      _stale(canvas, g);
      return;
    }
    switch (s.phase) {
      case NavPhase.idle:
        return;
      case NavPhase.starting:
      case NavPhase.rerouting:
        _message(canvas, g, s.message);
      case NavPhase.guiding:
        _turn(canvas, g, s);
        _figures(canvas, g, s);
    }
  }

  // ---- the turn --------------------------------------------------------------

  void _turn(Canvas canvas, NavHudGeometry g, NavState s) {
    final bend = s.arrow == null ? NavBend.unknown : NavBendReader.of(s.arrow!);
    _approachLine(canvas, g, bend, s);

    final image = images.imageFor(s.arrow);
    if (image != null) {
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        g.arrow,
        _image,
      );
    }

    final distance = NavFormat.distanceToTurn(s);
    if (distance != null) {
      _distance(canvas, g, distance, g.arrow.center.dy);
    }

    final instruction = s.instruction;
    if (instruction != null && instruction.isNotEmpty) {
      final text = _fitted(
        instruction.toUpperCase(),
        TapeType.button(size: g.instructionSize, color: color),
        g.instructionWidth,
        g.instructionLines,
      );
      text.paint(canvas, Offset(g.textLeft, g.instructionTop));
    }
  }

  /// The line to the junction and the dot that is the car on it.
  void _approachLine(
    Canvas canvas,
    NavHudGeometry g,
    NavBend bend,
    NavState s,
  ) {
    if (_pathBend != bend || _path == null) {
      _path = g.approach(bend);
      _metric = _path!.computeMetrics().first;
      // The line stops at the junction's ring, and does not run into it.
      _drawn = _metric!.extractPath(
        0,
        math.max(0, _metric!.length - g.nodeRadius),
      );
      _pathBend = bend;
    }
    canvas.drawPath(_drawn!, _stroke);
    canvas.drawCircle(g.junction(bend), g.nodeRadius, _stroke);

    // The car: at the foot while the turn is far, at the junction at the turn.
    // Maps leaves the distance out when the turn is a few metres away (a capture of
    // it counting down: 80 m, 70 m, 50 m, and then only the instruction), so a turn
    // with no distance is the turn itself. A line with no turn in it (`Head toward`)
    // has no dot.
    final toTurn =
        estimate.value ??
        s.distanceToTurnM ??
        (bend == NavBend.left || bend == NavBend.right ? 0.0 : null);
    if (toTurn == null) return;
    final t = 1 - (toTurn / TapeHud.navApproachMetres).clamp(0.0, 1.0);
    final metric = _metric!;
    final at = metric.getTangentForOffset(metric.length * t);
    if (at != null) canvas.drawCircle(at.position, g.dotRadius, _fill);
  }

  /// The distance to the turn, its number in the numeral face and its unit as a
  /// label, shrunk to fit if it is long (a unit Maps wrote that is not known is
  /// shown as it came).
  void _distance(Canvas canvas, NavHudGeometry g, NavFigure figure, double cy) {
    final number = _text(
      figure.value,
      TapeType.numeral(
        size: g.distanceSize,
        weight: TapeHud.numeralWeight,
        color: color,
      ),
    );
    final unit = figure.unit == null
        ? null
        : _text(figure.unit!, TapeType.label(size: g.labelSize, color: color));
    final gap = g.distanceSize * 0.12;
    final width = number.width + (unit == null ? 0 : gap + unit.width);
    final scale = width > g.distanceMaxWidth ? g.distanceMaxWidth / width : 1.0;

    canvas.save();
    canvas.translate(g.distanceLeft, cy);
    canvas.scale(scale);
    number.paint(canvas, Offset(0, -number.height / 2));
    if (unit != null) {
      // The unit sits on the numeral's baseline.
      final baseline = number.computeDistanceToActualBaseline(
        TextBaseline.alphabetic,
      );
      final unitBaseline = unit.computeDistanceToActualBaseline(
        TextBaseline.alphabetic,
      );
      unit.paint(
        canvas,
        Offset(
          number.width + gap,
          -number.height / 2 + baseline - unitBaseline,
        ),
      );
    }
    canvas.restore();
  }

  // ---- states with no turn ---------------------------------------------------

  /// `Starting navigation…` or `Rerouting...`, in Maps' own words.
  void _message(Canvas canvas, NavHudGeometry g, String? message) {
    if (message == null || message.isEmpty) return;
    final text = _text(
      message.toUpperCase(),
      TapeType.button(size: g.instructionSize * 1.3, color: color),
      maxWidth: g.contentRight - g.textLeft,
      maxLines: 2,
    );
    text.paint(canvas, Offset(g.textLeft, g.arrow.center.dy - text.height / 2));
  }

  /// Maps has gone quiet: no turn, no figures, and a plain sentence that says why.
  void _stale(Canvas canvas, NavHudGeometry g) {
    final dash = _text(
      '—',
      TapeType.numeral(
        size: g.distanceSize,
        weight: TapeHud.numeralWeight,
        color: color,
      ),
    );
    dash.paint(canvas, Offset(g.textLeft, g.arrow.center.dy - dash.height / 2));
    final label = _text(
      'NO UPDATE',
      TapeType.label(size: g.labelSize, color: color),
    );
    label.paint(canvas, Offset(g.textLeft, g.instructionTop));
  }

  // ---- along the bottom ------------------------------------------------------

  /// The ETA, the time left and the distance left, each a numeral and a label.
  void _figures(Canvas canvas, NavHudGeometry g, NavState s) {
    final figures = [
      NavFormat.eta(s),
      NavFormat.timeLeft(s),
      NavFormat.distanceLeft(s),
    ];
    for (var i = 0; i < figures.length; i++) {
      final figure = figures[i];
      if (figure == null) continue;
      final number = _text(
        figure.value,
        TapeType.numeral(
          size: g.figureSize,
          weight: TapeHud.numeralWeight,
          color: color,
        ),
      );
      final unit = figure.unit == null
          ? null
          : _text(
              figure.unit!,
              TapeType.label(size: g.labelSize, color: color),
            );
      final gap = g.figureSize * 0.18;
      final width = number.width + (unit == null ? 0 : gap + unit.width);
      final left = g.figureCentres[i] - width / 2;
      final top = g.figuresY - number.height / 2;
      number.paint(canvas, Offset(left, top));
      if (unit != null) {
        final baseline = number.computeDistanceToActualBaseline(
          TextBaseline.alphabetic,
        );
        final unitBaseline = unit.computeDistanceToActualBaseline(
          TextBaseline.alphabetic,
        );
        unit.paint(
          canvas,
          Offset(left + number.width + gap, top + baseline - unitBaseline),
        );
      }
    }
  }

  // ---- text ------------------------------------------------------------------

  /// A laid-out text, kept: the same words in the same style are made once.
  TextPainter _text(
    String text,
    TextStyle style, {
    double maxWidth = double.infinity,
    int maxLines = 1,
  }) {
    final key =
        '$text|${style.fontSize}|${style.fontFamily}|'
        '${style.fontWeight}|$maxWidth|$maxLines';
    return _texts.putIfAbsent(key, () {
      if (_texts.length > 40) _texts.clear();
      return TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: _directionOf(text),
        maxLines: maxLines,
        ellipsis: '…',
      )..layout(maxWidth: maxWidth);
    });
  }

  /// [text] in at most [maxLines] lines of [maxWidth], cut at a word and ended with
  /// an ellipsis when it is too long: never a word cut in half.
  TextPainter _fitted(
    String text,
    TextStyle style,
    double maxWidth,
    int maxLines,
  ) {
    final key =
        'fit|$text|${style.fontSize}|${style.fontFamily}|$maxWidth|$maxLines';
    return _texts.putIfAbsent(key, () {
      if (_texts.length > 40) _texts.clear();
      final direction = _directionOf(text);
      TextPainter make(String s, {bool ellipsis = false}) => TextPainter(
        text: TextSpan(text: s, style: style),
        textDirection: direction,
        maxLines: maxLines,
        ellipsis: ellipsis ? '\u2026' : null,
      )..layout(maxWidth: maxWidth);

      final words = text.split(RegExp(r'\s+'));
      var painter = make(text);
      while (painter.didExceedMaxLines && words.length > 1) {
        words.removeLast();
        painter = make('${words.join(' ')}\u2026');
      }
      // One word that is longer than the lines can hold: cut it, with an ellipsis.
      return painter.didExceedMaxLines
          ? make(words.first, ellipsis: true)
          : painter;
    });
  }

  /// Right to left for text in Arabic or Hebrew, which Maps writes for a phone in
  /// those languages.
  static TextDirection _directionOf(String text) {
    for (final unit in text.runes) {
      if ((unit >= 0x0590 && unit <= 0x08FF) ||
          (unit >= 0xFB1D && unit <= 0xFDFF) ||
          (unit >= 0xFE70 && unit <= 0xFEFF)) {
        return TextDirection.rtl;
      }
    }
    return TextDirection.ltr;
  }

  @override
  bool shouldRepaint(NavHudPainter old) =>
      old.color != color ||
      !identical(old.state, state) ||
      !identical(old.freshness, freshness) ||
      !identical(old.estimate, estimate) ||
      !identical(old.images, images);
}
