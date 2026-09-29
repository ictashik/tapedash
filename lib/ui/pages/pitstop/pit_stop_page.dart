import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../../money/pit_stop_form.dart';
import '../../../vehicle/vehicle_state.dart' show DrivingMode;
import '../../design/components/controls/tape_button.dart';
import '../../design/components/controls/tape_numpad.dart';
import '../../design/components/controls/tape_toggle.dart';
import '../../design/components/tape_label.dart';
import '../../design/icons/icons.dart';
import '../../design/motion/motion_scope.dart';
import '../../design/motion/timeline.dart';
import '../../design/theme/palette.dart';
import '../../design/theme/tape_theme.dart';
import '../../design/tokens/motion_tokens.dart';
import '../../design/tokens/spacing.dart';
import '../../design/tokens/strokes.dart';
import '../../design/tokens/typography.dart';
import '../money/money_page.dart' show formatPricePerLitre;

/// Pit Stop (DESIGN.md 7.9, CLAUDE.md 8.5): log a fill-up, or just set the price.
///
/// On the left the numpad; on the right the LITRES and AMOUNT fields (tap one to
/// point the numpad at it: the active one is lit), the live price per litre, a
/// FULL TANK switch and SAVE. On saving, a column fills with champagne from the
/// bottom and collapses into the new price, 900 ms in all, and the page closes.
///
/// **Parked only.** The page closes itself the moment the car moves ([mode]), and
/// the shell never opens it while it is moving: a form is not something to type
/// into at speed (CLAUDE.md 1).
///
/// With [priceOnly] there is one field, the price of a litre, and no fill-up is
/// logged (CLAUDE.md 8.5: "the user can also set the price directly").
class PitStopPage extends StatefulWidget {
  const PitStopPage({
    super.key,
    required this.width,
    required this.height,
    required this.mode,
    required this.onSave,
    required this.onClose,
    this.tankLitres = 40,
    this.priceOnly = false,
    this.currentPrice,
  });

  final double width;
  final double height;

  /// Parked or motion, from the vehicle state.
  final ValueListenable<DrivingMode> mode;

  /// Saves the form (the caller logs the fill-up or sets the price).
  final Future<void> Function(PitStopForm form) onSave;

  final VoidCallback onClose;
  final double tankLitres;
  final bool priceOnly;

  /// The price in force, shown as a hint.
  final double? currentPrice;

  @override
  State<PitStopPage> createState() => PitStopPageState();
}

class PitStopPageState extends State<PitStopPage> {
  late final PitStopForm form = PitStopForm(
    tankLitres: widget.tankLitres,
    priceOnly: widget.priceOnly,
  );
  Timeline? _saving;

  /// Whether the save animation is playing.
  bool get isSaving => _saving != null;

  @override
  void initState() {
    super.initState();
    widget.mode.addListener(_onMode);
  }

  @override
  void dispose() {
    widget.mode.removeListener(_onMode);
    _saving?.dispose();
    super.dispose();
  }

  void _onMode() {
    // Safety beats everything: the form goes the moment the car moves.
    if (widget.mode.value != DrivingMode.parked) widget.onClose();
  }

  void _key(String key) => setState(() => form.press(key));

  Future<void> _save() async {
    if (!form.canSave ||
        _saving != null ||
        widget.mode.value != DrivingMode.parked) {
      return;
    }
    await widget.onSave(form);
    if (!mounted) return;
    final clock = MotionScope.of(context);
    setState(() {
      _saving = Timeline(
        clock: clock,
        length: PitStopMotion.saveLength,
        onDone: () {
          if (mounted) widget.onClose();
        },
      )..start();
    });
  }

  static String issueText(PitStopIssue issue) => switch (issue) {
    PitStopIssue.litresMissing => 'Enter the litres.',
    PitStopIssue.amountMissing => 'Enter the amount paid.',
    PitStopIssue.litresTooMany => 'That is more than your tank holds.',
    PitStopIssue.priceImplausible => 'That price looks wrong.',
  };

  @override
  Widget build(BuildContext context) {
    final theme = TapeTheme.of(context);
    final palette = theme.palette;
    final margin = TapeSpace.margin(widget.height);
    final keySize = ((widget.height - 2 * margin - 3 * TapeSpace.s2) / 4).clamp(
      48.0,
      72.0,
    );
    final issues = form.issues();
    // Only what is wrong with what was typed is said: an empty form is not an error.
    final shown = issues.where(
      (i) =>
          i == PitStopIssue.litresTooMany || i == PitStopIssue.priceImplausible,
    );

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: Stack(
        children: [
          Positioned(
            left: margin,
            top: (widget.height - TapeNumpad.heightFor(keySize)) / 2,
            child: TapeNumpad(onKey: _key, keySize: keySize),
          ),
          Positioned(
            left: margin + TapeNumpad.widthFor(keySize) + TapeSpace.s8,
            right: margin,
            top: margin,
            bottom: margin,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TapeLabel(
                  widget.priceOnly ? 'Fuel price' : 'Pit stop',
                  size: 12,
                ),
                const SizedBox(height: TapeSpace.s1),
                if (!widget.priceOnly) ...[
                  _Field(
                    label: 'Litres',
                    text: form.litresText,
                    unit: 'L',
                    active: form.active == PitStopField.litres,
                    onTap: () =>
                        setState(() => form.active = PitStopField.litres),
                  ),
                  const SizedBox(height: TapeSpace.s2),
                ],
                _Field(
                  label: widget.priceOnly ? 'Price per litre' : 'Amount paid',
                  text: form.amountText,
                  unit: '₹',
                  unitFirst: true,
                  active: form.active == PitStopField.amount,
                  onTap: () =>
                      setState(() => form.active = PitStopField.amount),
                ),
                const SizedBox(height: TapeSpace.s2),
                // What is wrong, if anything, takes the place of the price line:
                // there is no room for both on a 360 lp screen.
                if (shown.isNotEmpty)
                  SizedBox(
                    height: 26,
                    child: TapeText(
                      issueText(shown.first),
                      style: TapeTextStyle.title,
                      color: palette.caution,
                    ),
                  )
                else
                  _PriceLine(
                    price: form.pricePerLitre,
                    hint: widget.currentPrice,
                    palette: palette,
                  ),
                const Spacer(),
                if (!widget.priceOnly) ...[
                  Row(
                    children: [
                      TapeToggle(
                        value: form.fullTank,
                        onChanged: (v) => setState(() => form.fullTank = v),
                      ),
                      const SizedBox(width: TapeSpace.s3),
                      const TapeLabel('Tank filled full', size: 12),
                    ],
                  ),
                  const SizedBox(height: TapeSpace.s2),
                ],
                Row(
                  children: [
                    TapeButton(
                      label: 'Save',
                      primary: true,
                      icon: TapeIcon.pitStop,
                      onPressed: form.canSave && _saving == null ? _save : null,
                    ),
                    const SizedBox(width: TapeSpace.s3),
                    TapeButton(
                      label: 'Close',
                      onPressed: _saving == null ? widget.onClose : null,
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_saving != null)
            Positioned.fill(
              child: CustomPaint(
                painter: FuelColumnPainter(
                  timeline: _saving!,
                  palette: palette,
                  price: form.pricePerLitre,
                  numeralWeight: theme.livery.numeralWeight,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The save animation's own numbers (DESIGN.md 7.9: 900 ms in all).
abstract final class PitStopMotion {
  static const Duration saveLength = TapeDurations.pitStopSave;

  /// The column fills over the first share, then collapses into the price chip.
  static const double fillShare = 0.62;
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.text,
    required this.unit,
    required this.active,
    required this.onTap,
    this.unitFirst = false,
  });

  final String label;
  final String text;
  final String unit;
  final bool unitFirst;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = TapeTheme.of(context);
    final palette = theme.palette;
    final numeral = TapeType.numeral(
      size: 30,
      weight: theme.livery.numeralWeight,
      color: text.isEmpty ? palette.inkDim : palette.inkBright,
    );
    final line = active ? palette.accentCore : palette.etchStrong;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: TapeSpace.touchTarget),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            TapeLabel(label, color: active ? palette.accentCore : null),
            const SizedBox(height: TapeSpace.s1),
            Row(
              children: [
                if (unitFirst) Text('$unit ', style: numeral),
                Text(text.isEmpty ? '0' : text, style: numeral),
                // The caret of the active field, in the accent.
                if (active)
                  Container(
                    width: 2,
                    height: 26,
                    margin: const EdgeInsets.only(left: 2),
                    color: palette.accentCore,
                  ),
                if (!unitFirst) ...[
                  const SizedBox(width: TapeSpace.s2),
                  Text(unit, style: numeral.copyWith(fontSize: 18)),
                ],
              ],
            ),
            const SizedBox(height: TapeSpace.s1),
            SizedBox(
              height: TapeStroke.regular,
              child: ColoredBox(color: line),
            ),
          ],
        ),
      ),
    );
  }
}

class _PriceLine extends StatelessWidget {
  const _PriceLine({
    required this.price,
    required this.hint,
    required this.palette,
  });

  final double? price;
  final double? hint;
  final TapePalette palette;

  @override
  Widget build(BuildContext context) {
    final p = price;
    final text = p != null
        ? '${formatPricePerLitre(p)} a litre'
        : hint != null
        ? 'Now ${formatPricePerLitre(hint!)} a litre'
        : 'Price per litre appears here.';
    return TapeText(
      text,
      style: TapeTextStyle.title,
      color: p != null ? palette.money : palette.inkMid,
    );
  }
}

/// The fuel column of the save animation: champagne fills from the bottom on
/// `spring.reveal`-like ease, then it collapses into the price (DESIGN.md 7.9).
class FuelColumnPainter extends CustomPainter {
  FuelColumnPainter({
    required this.timeline,
    required this.palette,
    required this.price,
    required this.numeralWeight,
  }) : super(repaint: timeline);

  final Timeline timeline;
  final TapePalette palette;
  final double? price;
  final double numeralWeight;

  /// The column's fill, 0 to 1, at [t] (0 to 1 over the animation): it rises over
  /// the first [PitStopMotion.fillShare] and holds full while it collapses.
  static double fillAt(double t) {
    final s = (t / PitStopMotion.fillShare).clamp(0.0, 1.0);
    return TapeCurves.enter.transform(s);
  }

  /// How much of the column is left at [t]: full until the fill is done, then
  /// collapsing to nothing.
  static double heightAt(double t) {
    if (t <= PitStopMotion.fillShare) return 1;
    final s = ((t - PitStopMotion.fillShare) / (1 - PitStopMotion.fillShare))
        .clamp(0.0, 1.0);
    return 1 - TapeCurves.exit.transform(s);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = timeline.progress;
    final columnHeight = size.height * 0.6 * heightAt(t);
    if (columnHeight <= 0.5) return;
    const width = 44.0;
    final rect = Rect.fromLTWH(
      size.width * 0.5 - width / 2,
      size.height * 0.8 - columnHeight,
      width,
      columnHeight,
    );
    final money = palette.money;
    canvas.drawRect(
      rect,
      Paint()..color = palette.canvas.withValues(alpha: 0.85),
    );
    canvas.drawRect(
      Rect.fromLTRB(
        rect.left,
        rect.bottom - rect.height * fillAt(t),
        rect.right,
        rect.bottom,
      ),
      Paint()..color = money,
    );
    canvas.drawRect(
      rect,
      Paint()
        ..color = money
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = TapeStroke.regular,
    );
  }

  @override
  bool shouldRepaint(FuelColumnPainter old) => old.palette != palette;
}
