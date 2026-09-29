import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../design/components/alerts.dart';
import '../design/components/rolling_numerals.dart';
import '../design/icons/icons.dart';
import '../design/motion/numeral_source.dart';
import '../design/render/glyph_atlas.dart';
import '../design/render/render_kit.dart';
import '../design/theme/palette.dart' show TapeMode;
import '../design/theme/tape_theme.dart';
import '../design/tokens/colors.dart';
import '../design/tokens/hud.dart';
import '../design/tokens/livery.dart';
import '../design/tokens/spacing.dart';
import '../design/tokens/strokes.dart';
import '../design/tokens/typography.dart';
import '../pages/drive/drive_signals.dart';
import 'alignment_pattern.dart';
import 'hud_settings.dart';

/// The windshield HUD (DESIGN.md 8): pure black, one user-chosen colour, huge
/// bold numerals, mirrored so the windshield shows them true.
///
/// It is one component of the product, not its design language: it inherits
/// the typography and the smoothed signals, and drops everything windshield
/// optics cannot carry -- no halos, no trails, no etch, no panels. It draws
/// under its own [TapeTheme] (the HUD livery: the user's colour, Bold
/// numerals, no halo), so the numeral components work unchanged.
///
/// The layout, colour, flips, position and scale come from [settings]; the
/// widget rebuilds for a setting and never for data (the numerals and the bar
/// repaint from their own signals). The mirror is one [Transform] over the
/// whole layout, so the alignment pattern, drawn inside it, is flipped exactly
/// as the HUD is.
///
/// **Money is not here yet, on purpose:** the trip cost and the cost per km
/// come from `money/`, which is phase 4. [tripCost] and [costPerKm] are
/// null until then, and the two layouts that lead with money say so plainly
/// (a dash and "MONEY UNAVAILABLE") instead of showing a number that has no
/// source (CLAUDE.md 1).
class HudView extends StatelessWidget {
  const HudView({
    super.key,
    required this.signals,
    required this.settings,
    required this.width,
    required this.height,
    this.tripCost,
    this.costPerKm,
    this.alert,
    this.alertIcon = TapeIcon.checkEngine,
    this.moneyNote = 'MONEY UNAVAILABLE',
  });

  final DriveSignals signals;
  final HudSettings settings;
  final double width;
  final double height;

  /// ₹ this trip, whole rupees. Null until phase 4.
  final NumeralSource? tripCost;

  /// ₹ per km, one decimal. Null until phase 4.
  final NumeralSource? costPerKm;

  /// The alert slot's level. Null is no alert.
  final ValueListenable<AlertLevel>? alert;
  final TapeIcon alertIcon;

  /// What the money layouts say in place of a figure: that money is unavailable
  /// (the car gives no fuel figure), or that a price is needed.
  final String moneyNote;

  /// The matrix the HUD's content is drawn through: the scale, the two flips,
  /// and the vertical position, which moves the content up (positive) in its
  /// own, unflipped space so the slider moves what the driver sees whichever
  /// flips are on. Exposed for a direct test.
  static Matrix4 transformFor(HudSettings s, double height) {
    final sx = s.scale * (s.flipHorizontal ? -1 : 1);
    final sy = s.scale * (s.flipVertical ? -1 : 1);
    return Matrix4.diagonal3Values(sx, sy, 1)..multiply(
      Matrix4.translationValues(
        0,
        -s.verticalPosition * TapeHud.positionReach * height,
        0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ambient = TapeTheme.of(context);
    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) => TapeTheme(
        data: ambient.copyWith(
          livery: Liveries.hud(settings.color),
          mode: TapeMode.normal,
        ),
        child: SizedBox(
          width: width,
          height: height,
          child: ColoredBox(
            color: TapeColors.hudBlack,
            child: Transform(
              alignment: Alignment.center,
              transform: transformFor(settings, height),
              child: SizedBox(
                width: width,
                height: height,
                child: settings.showAlignment
                    ? AlignmentPattern(
                        color: settings.color.color,
                        width: width,
                        height: height,
                      )
                    : _layout(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _layout() => switch (settings.layout) {
    HudLayout.drive => _DriveHud(
      signals: signals,
      width: width,
      height: height,
      alert: alert,
      alertIcon: alertIcon,
      color: settings.color.color,
    ),
    HudLayout.driveMoney => _DriveMoneyHud(
      signals: signals,
      width: width,
      height: height,
      tripCost: tripCost,
      note: moneyNote,
      color: settings.color.color,
    ),
    HudLayout.money => _MoneyHud(
      width: width,
      height: height,
      tripCost: tripCost,
      costPerKm: costPerKm,
      note: moneyNote,
      color: settings.color.color,
    ),
  };
}

/// Puts a numeral of [size] so that the middle of its *ink* is at [centre],
/// horizontally centred on [centreX]: the numeral's box is much taller than its
/// ink (the detent and roll room, DESIGN.md 5.6), so a layout laid out by box
/// would sit the digits well off where they are meant to be.
Positioned _atInk({
  required double centreX,
  required double centreY,
  required double size,
  required double boxWidth,
  required Widget child,
}) {
  final m = NumeralMetrics(size);
  final inkMiddle = m.inkTop + m.inkHeight / 2;
  return Positioned(
    left: centreX - boxWidth / 2,
    width: boxWidth,
    top: centreY - inkMiddle,
    // The child is centred in a box as tall as a numeral's own, so that a
    // dash or a ₹ sits on the same middle as the digits beside it.
    child: SizedBox(
      height: m.boxHeight,
      child: Center(child: child),
    ),
  );
}

/// A HUD label: UPPERCASE Barlow Semi Condensed, at least 0.06H, in the HUD
/// colour (a dim label would vanish in the glass).
Widget _label(String text, double height, Color color) => Text(
  text,
  style: TapeType.label(size: height * TapeHud.labelShare, color: color),
  maxLines: 1,
  softWrap: false,
);

/// The HUD's numerals: Bold Saira from the glyph atlas, in the HUD colour, no
/// halo, [typical] integer digits wide and centred on them.
///
/// [CenteredNumeral] centres on an *estimate* of a digit's width (its own doc
/// comment says so), which at the HUD's huge sizes is a whole digit-width
/// wide of the atlas's real one: a measured 54 lp of drift on a 198 lp "64".
/// The HUD's numerals are the largest on any screen and sit alone, so this
/// reads the real advance from the same atlas the numerals draw from.
class _HudNumerals extends StatelessWidget {
  const _HudNumerals({
    required this.source,
    required this.format,
    required this.size,
    required this.typical,
  });

  final NumeralSource source;
  final NumeralFormat format;
  final double size;
  final int typical;

  @override
  Widget build(BuildContext context) {
    final theme = TapeTheme.of(context);
    final atlas = TapeRenderScope.of(context).atlases.get(
      GlyphAtlasSpec(
        sizeLp: size,
        devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
        weight: theme.livery.numeralWeight,
      ),
    );
    final metrics = NumeralMetrics(size);
    final numeral = RollingNumerals(
      source: source,
      format: format,
      size: size,
      role: NumeralRole.accent,
    );
    // The typical digits, plus the format's separators and decimals, at their
    // real advances: the width the lit part of the readout occupies.
    final lit = typical + format.decimals;
    var width = lit * atlas.digitAdvance;
    if (format.grouping != DigitGrouping.none) {
      final commas = format.grouping == DigitGrouping.indian
          ? (typical - 1) ~/ 2
          : (typical - 1) ~/ 3;
      width += commas * (atlas.glyph(0x2C)?.advance ?? 0);
    }
    if (format.decimals > 0) width += atlas.glyph(0x2E)?.advance ?? 0;
    final full =
        (format.integerDigits + format.decimals) * atlas.digitAdvance * 2;
    return SizedBox(
      width: width,
      height: metrics.boxHeight,
      child: OverflowBox(
        minWidth: 0,
        maxWidth: full,
        maxHeight: metrics.boxHeight * 1.5,
        alignment: Alignment.centerRight,
        child: numeral,
      ),
    );
  }
}

/// What a money readout shows with no source: a Bold dash, in the HUD colour.
Widget _dash(double size, Color color) => Text(
  '—',
  style: TapeType.numeral(
    size: size,
    weight: TapeHud.numeralWeight,
    color: color,
  ),
  maxLines: 1,
  softWrap: false,
);

/// The ₹ sign, Bold, at [size].
Widget _rupee(double size, Color color) => Text(
  '₹',
  style: TapeType.numeral(
    size: size,
    weight: TapeHud.numeralWeight,
    color: color,
  ),
  maxLines: 1,
  softWrap: false,
);

class _DriveHud extends StatelessWidget {
  const _DriveHud({
    required this.signals,
    required this.width,
    required this.height,
    required this.alert,
    required this.alertIcon,
    required this.color,
  });

  final DriveSignals signals;
  final double width;
  final double height;
  final ValueListenable<AlertLevel>? alert;
  final TapeIcon alertIcon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final size = height * TapeHud.heroShare;
    final barThickness = _barThickness(height);
    final ink = NumeralMetrics(size).inkHeight;
    final speedY = height * 0.44;
    final labelTop = speedY + ink / 2 + height * 0.02;
    final barTop = height * 0.86;
    return Stack(
      children: [
        _atInk(
          centreX: width / 2,
          centreY: speedY,
          size: size,
          boxWidth: width,
          child: _HudNumerals(
            source: signals.speed,
            format: const NumeralFormat(integerDigits: 3),
            size: size,
            typical: 2,
          ),
        ),
        Positioned(
          top: labelTop,
          left: 0,
          right: 0,
          child: Center(child: _label('KM/H', height, color)),
        ),
        // The alert slot: centre-top, out of the way of the speed, nothing at
        // all with no alert.
        Positioned(
          top: height * 0.03,
          left: 0,
          right: 0,
          child: Center(
            child: alert == null
                ? const SizedBox.shrink()
                : ValueListenableBuilder<AlertLevel>(
                    valueListenable: alert!,
                    builder: (_, level, _) =>
                        AlertSlot(level: level, icon: alertIcon),
                  ),
          ),
        ),
        Positioned(
          top: barTop,
          left: (width - width * TapeHud.rpmBarWidthShare) / 2,
          width: width * TapeHud.rpmBarWidthShare,
          height: barThickness * TapeHud.rpmRedlineRise,
          child: RepaintBoundary(
            child: CustomPaint(
              painter: HudRpmBarPainter(
                rpm: signals.rpm,
                color: color,
                critical: TapeColors.critical,
                thickness: barThickness,
              ),
            ),
          ),
        ),
      ],
    );
  }

  static double _barThickness(double height) =>
      (height * TapeHud.rpmBarShare).clamp(TapeStroke.hud, double.infinity);
}

/// The thin RPM bar under the speed: one lit bar from the left, two bold end
/// caps so the scale reads without a track (a track is etch, and etch is not
/// on the glass), and a red zone that stands taller as well as red, so it is
/// not told by colour alone (DESIGN.md 11).
class HudRpmBarPainter extends CustomPainter {
  HudRpmBarPainter({
    required this.rpm,
    required this.color,
    required this.critical,
    required this.thickness,
  }) : super(repaint: rpm);

  final NumeralSource rpm;
  final Color color;
  final Color critical;
  final double thickness;

  final Paint _paint = Paint();

  /// The lit extent as a share of the bar's width. Exposed for a direct test.
  static double litShare(double rpm) => (rpm / TapeHud.rpmMax).clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size size) {
    final capWidth = TapeStroke.hud;
    final rise = size.height;
    final midY = size.height / 2;
    final barTop = midY - thickness / 2;
    final w = size.width;
    final lit = rpm.hasValue ? litShare(rpm.value) * w : 0.0;
    final redStart = TapeHud.rpmRedline / TapeHud.rpmMax * w;

    _paint.color = color;
    canvas.drawRect(Rect.fromLTWH(0, 0, capWidth, rise), _paint);
    canvas.drawRect(Rect.fromLTWH(w - capWidth, 0, capWidth, rise), _paint);
    final normalEnd = lit < redStart ? lit : redStart;
    if (normalEnd > 0) {
      canvas.drawRect(Rect.fromLTWH(0, barTop, normalEnd, thickness), _paint);
    }
    if (lit > redStart) {
      _paint.color = critical;
      canvas.drawRect(Rect.fromLTWH(redStart, 0, lit - redStart, rise), _paint);
    }
  }

  @override
  bool shouldRepaint(HudRpmBarPainter old) =>
      old.color != color ||
      old.critical != critical ||
      old.thickness != thickness ||
      !identical(old.rpm, rpm);
}

class _DriveMoneyHud extends StatelessWidget {
  const _DriveMoneyHud({
    required this.signals,
    required this.width,
    required this.height,
    required this.tripCost,
    required this.note,
    required this.color,
  });

  final DriveSignals signals;
  final double width;
  final double height;
  final NumeralSource? tripCost;
  final String note;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final size = height * TapeHud.halfShare;
    final ink = NumeralMetrics(size).inkHeight;
    final y = height * 0.44;
    final labelTop = y + ink / 2 + height * 0.02;
    final half = width / 2;
    return Stack(
      children: [
        _atInk(
          centreX: half / 2,
          centreY: y,
          size: size,
          boxWidth: half,
          child: _HudNumerals(
            source: signals.speed,
            format: const NumeralFormat(integerDigits: 3),
            size: size,
            typical: 2,
          ),
        ),
        Positioned(
          top: labelTop,
          left: 0,
          width: half,
          child: Center(child: _label('KM/H', height, color)),
        ),
        _moneyHalf(size: size, y: y, half: half, labelTop: labelTop),
      ],
    );
  }

  Widget _moneyHalf({
    required double size,
    required double y,
    required double half,
    required double labelTop,
  }) {
    final source = tripCost;
    return Stack(
      children: [
        if (source == null)
          _atInk(
            centreX: half + half / 2,
            centreY: y,
            size: size,
            boxWidth: half,
            child: _dash(size * 0.8, color),
          )
        else
          _atInk(
            centreX: half + half / 2,
            centreY: y,
            size: size,
            boxWidth: half,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _rupee(size * 0.5, color),
                const SizedBox(width: TapeSpace.s2),
                _HudNumerals(
                  source: source,
                  format: const NumeralFormat(
                    integerDigits: 5,
                    grouping: DigitGrouping.indian,
                  ),
                  size: size,
                  typical: 3,
                ),
              ],
            ),
          ),
        Positioned(
          top: labelTop,
          left: half,
          width: half,
          child: Center(
            child: _label(source == null ? note : 'THIS TRIP', height, color),
          ),
        ),
      ],
    );
  }
}

class _MoneyHud extends StatelessWidget {
  const _MoneyHud({
    required this.width,
    required this.height,
    required this.tripCost,
    required this.costPerKm,
    required this.note,
    required this.color,
  });

  final double width;
  final double height;
  final NumeralSource? tripCost;
  final NumeralSource? costPerKm;
  final String note;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final size = height * TapeHud.heroShare;
    final small = height * TapeHud.secondaryShare;
    final trip = tripCost;
    final perKm = costPerKm;
    final ink = NumeralMetrics(size).inkHeight;
    final y = height * 0.38;
    final perKmY = y + ink / 2 + height * 0.16;
    return Stack(
      children: [
        _atInk(
          centreX: width / 2,
          centreY: y,
          size: size,
          boxWidth: width,
          child: trip == null
              ? _dash(size * 0.8, color)
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _rupee(size * 0.5, color),
                    const SizedBox(width: TapeSpace.s2),
                    _HudNumerals(
                      source: trip,
                      format: const NumeralFormat(
                        integerDigits: 5,
                        grouping: DigitGrouping.indian,
                      ),
                      size: size,
                      typical: 3,
                    ),
                  ],
                ),
        ),
        if (perKm != null)
          _atInk(
            centreX: width / 2,
            centreY: perKmY,
            size: small,
            boxWidth: width,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _rupee(small * 0.6, color),
                const SizedBox(width: TapeSpace.s1),
                _HudNumerals(
                  source: perKm,
                  format: const NumeralFormat(integerDigits: 2, decimals: 1),
                  size: small,
                  typical: 1,
                ),
                const SizedBox(width: TapeSpace.s2),
                _label('/KM', height, color),
              ],
            ),
          ),
        Positioned(
          top: height * 0.86,
          left: 0,
          right: 0,
          child: Center(
            child: _label(trip == null ? note : 'THIS TRIP', height, color),
          ),
        ),
      ],
    );
  }
}
