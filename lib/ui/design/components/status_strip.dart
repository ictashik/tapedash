import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';

import '../icons/icons.dart';
import '../motion/motion_clock.dart';
import '../motion/motion_scope.dart';
import '../render/chamfer.dart';
import '../theme/palette.dart';
import '../theme/tape_theme.dart';
import '../tokens/motion_tokens.dart';
import '../tokens/opacity.dart';
import '../tokens/status_strip.dart';
import '../tokens/strokes.dart';
import '../tokens/typography.dart';

/// The adapter link's state, as the status strip presents it (DESIGN.md 6.9).
///
/// A small presentational vocabulary, not `obd/transport/transport.dart`'s
/// own `TransportState`: the page composing this strip translates one into
/// the other, the same way every other `ui/design/` component takes plain
/// values rather than a service's own types.
enum AdapterLinkState {
  /// Data is flowing: the glyph is lit.
  flowing,

  /// Trying to connect, or waiting on the first reply: the glyph pulses.
  searching,

  /// Was connected and dropped, or never reached: the glyph is `caution`.
  lost,
}

/// The status strip's left flank (DESIGN.md 6.9): the adapter glyph, then the
/// GPS glyph. Glyphs only in Motion mode; a caption fades in under each one
/// as the parked share rises (the Parked choreography's "glyph labels become
/// text", DESIGN.md 7.2), and the column widens to fit it on the same share.
///
/// GPS has no elaborated states in DESIGN.md beyond being grouped here, and
/// unlike the adapter it is only ever a fallback (CLAUDE.md 8.6): no fix is
/// treated as merely dim, not `caution` -- it is not an error needing
/// attention the way a dropped adapter link is.
class StatusStripLeft extends StatefulWidget {
  const StatusStripLeft({
    super.key,
    required this.adapter,
    required this.gpsHasFix,
    required this.parkedShare,
  });

  final ValueListenable<AdapterLinkState> adapter;
  final ValueListenable<bool> gpsHasFix;

  /// The parked share (DESIGN.md 7.2), 0 in Motion and 1 parked: the
  /// captions fade in on it and the columns widen with them, so the strip's
  /// glyphs-to-text move is part of the screen's own choreography, not a
  /// hard switch of its own.
  final ValueListenable<double> parkedShare;

  @override
  State<StatusStripLeft> createState() => StatusStripLeftState();
}

class StatusStripLeftState extends State<StatusStripLeft>
    implements MotionDriven {
  late MotionClock _motion;
  bool _attached = false;
  double _phase = 0;
  final StatusStripRepaintPing repaint = StatusStripRepaintPing();

  @override
  void initState() {
    super.initState();
    widget.adapter.addListener(_onAdapter);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motion = MotionScope.of(context);
    _onAdapter();
  }

  @override
  void didUpdateWidget(StatusStripLeft oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.adapter, widget.adapter)) {
      oldWidget.adapter.removeListener(_onAdapter);
      widget.adapter.addListener(_onAdapter);
    }
    _onAdapter();
  }

  void _onAdapter() {
    final searching = widget.adapter.value == AdapterLinkState.searching;
    if (searching && !_attached) {
      _attached = true;
      _phase = 0;
      _motion.attach(this);
    } else if (!searching && _attached) {
      _attached = false;
      _motion.detach(this);
      repaint.ping(); // one more frame, to settle back to full alpha.
    }
  }

  @override
  bool advance(double dt, Duration time) {
    _phase += dt;
    repaint.ping();
    return true;
  }

  /// The pulse's current alpha share, 0 to 1 (DESIGN.md 6.9's 0.5 Hz).
  /// Exposed so the waveform has a direct test, since sampling it back out
  /// of rendered pixels is the fragile way to check it.
  double pulseAlpha() => pulseAlphaAt(_phase);

  static double pulseAlphaAt(double phaseSeconds) {
    final t = TapeMotion.pulseShare(
      phaseSeconds,
      TapeStatusStrip.searchPulseHz,
    );
    return TapeStatusStrip.searchPulseAlphaMin +
        (TapeStatusStrip.searchPulseAlphaMax -
                TapeStatusStrip.searchPulseAlphaMin) *
            t;
  }

  @override
  void dispose() {
    widget.adapter.removeListener(_onAdapter);
    if (_attached) _motion.detach(this);
    repaint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = TapeTheme.of(context).palette;
    final share = widget.parkedShare;
    return ListenableBuilder(
      listenable: share,
      builder: (context, _) {
        final parked = share.value.clamp(0.0, 1.0);
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: glyphColumnWidth(parked),
              height: _glyphColumnHeight(parked),
              child: CustomPaint(
                painter: AdapterGlyphPainter(
                  listenable: Listenable.merge([
                    widget.adapter,
                    repaint,
                    share,
                  ]),
                  state: this,
                  palette: palette,
                  parkedShare: share,
                ),
              ),
            ),
            SizedBox(width: TapeStatusStrip.gap * 2),
            SizedBox(
              width: glyphColumnWidth(parked),
              height: _glyphColumnHeight(parked),
              child: CustomPaint(
                painter: GpsGlyphPainter(
                  listenable: Listenable.merge([widget.gpsHasFix, share]),
                  hasFix: widget.gpsHasFix,
                  palette: palette,
                  parkedShare: share,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

double _glyphColumnHeight(double parked) =>
    TapeStatusStrip.glyphSize +
    parked * (TapeStatusStrip.gap + TapeStatusStrip.captionSize + 2);

/// A ping with no value attached, for a motion-driven painter's own repaint
/// trigger (there is nothing else for its `Listenable` to merge in).
class StatusStripRepaintPing extends ChangeNotifier {
  void ping() => notifyListeners();
}

/// The width a glyph column needs at the parked share it is at: just the
/// icon in Motion, widening to fit its caption as the share rises, so two
/// neighbouring columns part smoothly (DESIGN.md 6.9's captions can be wider
/// than the 20 lp icon they sit under -- "SEARCHING", "PHONE HOT" -- so a
/// column narrower than its own caption would run into its neighbour).
/// Exposed for a direct test.
double glyphColumnWidth(double parked) => ui.lerpDouble(
  TapeStatusStrip.glyphSize,
  TapeStatusStrip.captionColumnWidth,
  parked.clamp(0.0, 1.0),
)!;

/// Draws the icon centred at the top of its box, and -- at the parked share
/// it is given -- the caption fading in underneath, both read live in
/// [paint] rather than cached at build time (DESIGN.md 9.3), since the
/// adapter and GPS states can each change without the page around this
/// strip rebuilding.
void _paintGlyphColumn(
  Canvas canvas,
  Size size,
  TapeIcon icon,
  Color color,
  double strokeScale,
  double parked,
  String caption,
  Color captionColor,
) {
  paintTapeIcon(
    canvas,
    icon,
    Offset((size.width - TapeStatusStrip.glyphSize) / 2, 0),
    TapeStatusStrip.glyphSize,
    color,
    strokeScale: strokeScale,
  );
  final alpha = parked.clamp(0.0, 1.0);
  if (alpha <= 0) return;
  final painter = TextPainter(
    text: TextSpan(
      text: caption.toUpperCase(),
      style: TapeType.label(
        size: TapeStatusStrip.captionSize,
        color: captionColor.withValues(alpha: captionColor.a * alpha),
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  painter.paint(
    canvas,
    Offset(
      (size.width - painter.width) / 2,
      TapeStatusStrip.glyphSize + TapeStatusStrip.gap,
    ),
  );
}

class AdapterGlyphPainter extends CustomPainter {
  AdapterGlyphPainter({
    required Listenable listenable,
    required this.state,
    required this.palette,
    required this.parkedShare,
  }) : super(repaint: listenable);

  final StatusStripLeftState state;
  final TapePalette palette;
  final ValueListenable<double> parkedShare;

  @override
  void paint(Canvas canvas, Size size) {
    final (color, caption) = switch (state.widget.adapter.value) {
      AdapterLinkState.flowing => (palette.label, 'linked'),
      AdapterLinkState.searching => (
        palette.label.withValues(alpha: state.pulseAlpha()),
        'searching',
      ),
      AdapterLinkState.lost => (palette.caution, 'lost'),
    };
    _paintGlyphColumn(
      canvas,
      size,
      TapeIcon.adapter,
      color,
      palette.strokeScale,
      parkedShare.value,
      caption,
      palette.label,
    );
  }

  @override
  bool shouldRepaint(AdapterGlyphPainter old) =>
      old.palette != palette ||
      !identical(old.parkedShare, parkedShare) ||
      !identical(old.state.widget.adapter, state.widget.adapter);
}

class GpsGlyphPainter extends CustomPainter {
  GpsGlyphPainter({
    required Listenable listenable,
    required this.hasFix,
    required this.palette,
    required this.parkedShare,
  }) : super(repaint: listenable);

  final ValueListenable<bool> hasFix;
  final TapePalette palette;
  final ValueListenable<double> parkedShare;

  @override
  void paint(Canvas canvas, Size size) {
    final fix = hasFix.value;
    final color = fix
        ? palette.label
        : palette.label.withValues(alpha: TapeOpacity.disabled);
    _paintGlyphColumn(
      canvas,
      size,
      TapeIcon.gps,
      color,
      palette.strokeScale,
      parkedShare.value,
      fix ? 'gps' : 'no fix',
      palette.label,
    );
  }

  @override
  bool shouldRepaint(GpsGlyphPainter old) =>
      old.palette != palette ||
      !identical(old.parkedShare, parkedShare) ||
      !identical(old.hasFix, hasFix);
}

/// The status strip's right flank (DESIGN.md 6.9): the clock, then the
/// phone-hot glyph when warm, then the DEMO badge whenever Demo Mode is on.
///
/// The DEMO badge is not gated by Motion/Parked -- CLAUDE.md 7.6 is explicit
/// that it "is always visible" -- and neither is the clock, which is already
/// textual in both modes; only the phone-hot glyph's caption follows the
/// glyphs-to-text rule, on the same parked share the left flank runs on
/// (DESIGN.md 7.2), so both flanks move as one choreography.
class StatusStripRight extends StatelessWidget {
  const StatusStripRight({
    super.key,
    required this.time,
    required this.use24Hour,
    required this.phoneHot,
    required this.parkedShare,
    this.demoMode = false,
  });

  final ValueListenable<DateTime> time;
  final bool use24Hour;
  final ValueListenable<bool> phoneHot;
  final ValueListenable<double> parkedShare;
  final bool demoMode;

  @override
  Widget build(BuildContext context) {
    final theme = TapeTheme.of(context);
    final palette = theme.palette;
    return ListenableBuilder(
      listenable: parkedShare,
      builder: (context, _) {
        final parked = parkedShare.value.clamp(0.0, 1.0);
        return SizedBox(
          width: TapeStatusStrip.rightReserve,
          height: _glyphColumnHeight(parked),
          child: CustomPaint(
            painter: StatusStripRightPainter(
              listenable: Listenable.merge([time, phoneHot, parkedShare]),
              right: this,
              palette: palette,
              numeralWeight: theme.livery.numeralWeight,
            ),
          ),
        );
      },
    );
  }
}

class StatusStripRightPainter extends CustomPainter {
  StatusStripRightPainter({
    required Listenable listenable,
    required this.right,
    required this.palette,
    required this.numeralWeight,
  }) : super(repaint: listenable);

  final StatusStripRight right;
  final TapePalette palette;
  final double numeralWeight;

  @override
  void paint(Canvas canvas, Size size) {
    final parked = right.parkedShare.value.clamp(0.0, 1.0);

    final clock = TextPainter(
      text: TextSpan(
        text: formatClock(right.time.value, use24Hour: right.use24Hour),
        style: TapeType.numeral(
          size: TapeStatusStrip.clockSize,
          weight: numeralWeight,
          color: palette.label,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final hot = right.phoneHot.value;
    final columnWidth = glyphColumnWidth(parked);
    final badge = right.demoMode
        ? (TextPainter(
            text: TextSpan(
              text: 'DEMO',
              style: TapeType.label(
                size: TapeStatusStrip.captionSize,
                color: palette.accentCore,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout())
        : null;

    // Measured first, so the flank ends against the margin (it is laid out
    // right-aligned in its reserve, not from the left).
    var total = clock.width;
    if (hot) total += TapeStatusStrip.gap * 2 + columnWidth;
    if (badge != null) {
      total +=
          TapeStatusStrip.gap * 2 +
          badge.width +
          TapeStatusStrip.badgePaddingH * 2;
    }
    var x = size.width - total;

    clock.paint(canvas, Offset(x, 0));
    x += clock.width;

    if (hot) {
      x += TapeStatusStrip.gap * 2;
      canvas.save();
      canvas.translate(x, 0);
      _paintGlyphColumn(
        canvas,
        Size(columnWidth, size.height),
        TapeIcon.phoneHot,
        palette.caution,
        palette.strokeScale,
        parked,
        'phone hot',
        palette.label,
      );
      canvas.restore();
      x += columnWidth;
    }

    if (badge != null) {
      x += TapeStatusStrip.gap * 2;
      canvas.save();
      canvas.translate(x, 0);
      _paintDemoBadge(canvas, badge);
      canvas.restore();
    }
  }

  void _paintDemoBadge(Canvas canvas, TextPainter text) {
    final rect = Rect.fromLTWH(
      0,
      0,
      text.width + TapeStatusStrip.badgePaddingH * 2,
      text.height + TapeStatusStrip.badgePaddingV * 2,
    );
    canvas.drawPath(
      Chamfer.all(rect, TapeStatusStrip.badgeChamfer),
      Paint()
        ..color = palette.accentCore
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = TapeStroke.fine * palette.strokeScale,
    );
    text.paint(
      canvas,
      Offset(TapeStatusStrip.badgePaddingH, TapeStatusStrip.badgePaddingV),
    );
  }

  @override
  bool shouldRepaint(StatusStripRightPainter old) =>
      old.palette != palette ||
      old.right.use24Hour != right.use24Hour ||
      old.right.demoMode != right.demoMode ||
      !identical(old.right.parkedShare, right.parkedShare) ||
      !identical(old.right.time, right.time) ||
      !identical(old.right.phoneHot, right.phoneHot);
}

/// "HH:MM" (24-hour) or "H:MM AM/PM" (12-hour), tabular (DESIGN.md 6.9).
/// Exposed so the formatting has a direct test.
String formatClock(DateTime time, {required bool use24Hour}) {
  final minute = time.minute.toString().padLeft(2, '0');
  if (use24Hour) {
    final hour = time.hour.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
  final hour12 = time.hour % 12 == 0 ? 12 : time.hour % 12;
  final suffix = time.hour < 12 ? 'AM' : 'PM';
  return '$hour12:$minute $suffix';
}
