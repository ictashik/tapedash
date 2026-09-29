import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../design/components/money.dart';
import '../../design/components/rolling_numerals.dart';
import '../../design/components/tape_label.dart';
import '../../design/motion/numeral_source.dart';
import '../../design/theme/tape_theme.dart';
import '../../design/tokens/spacing.dart';
import '../../design/tokens/typography.dart';
import 'money_signals.dart';

/// Whole rupees, Indian grouping (DESIGN.md 10): up to ₹9,99,999 a trip.
const NumeralFormat rupeeFormat = NumeralFormat(
  integerDigits: 6,
  grouping: DigitGrouping.indian,
);

/// One decimal, for ₹/km and km/L (DESIGN.md 10).
const NumeralFormat rateFormat = NumeralFormat(integerDigits: 3, decimals: 1);

/// A money figure that says what it can (CLAUDE.md 8.5, DESIGN.md 7.4): rupees
/// with the confidence pips once there is a price; litres, with "L", while there
/// is fuel and no price; and a plain dash when the car gives no fuel figure at
/// all.
///
/// The figure repaints from its own signal; this widget rebuilds only when the
/// kind of thing it shows changes (a price is set, the pips gain one), which is
/// rare.
class MoneyFigure extends StatelessWidget {
  const MoneyFigure({
    super.key,
    required this.money,
    required this.size,
    this.approximate = false,
    this.integerDigits = 6,
  });

  final MoneySignals money;

  /// How many integer digits to reserve: a flank has little room, and a trip
  /// past ₹9,999 in one drive is rare.
  final int integerDigits;

  /// The digit size.
  final double size;

  /// Prefix "≈" (DESIGN.md 6.8: parked detail views only).
  final bool approximate;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<MoneyView>(
      valueListenable: money.view,
      builder: (context, view, _) => switch (view) {
        MoneyView.rupees => ValueListenableBuilder<MoneyConfidence>(
          valueListenable: money.confidence,
          builder: (context, confidence, _) => FittedNumerals(
            source: money.cost,
            maxDigits: integerDigits,
            builder: (context, digits) => MoneyReadout(
              value: money.cost,
              format: NumeralFormat(
                integerDigits: digits,
                grouping: DigitGrouping.indian,
              ),
              confidence: confidence,
              approximate: approximate,
              size: size,
            ),
          ),
        ),
        MoneyView.litres => LabeledNumeral(
          source: money.litres,
          format: rateFormat,
          size: size,
          unit: 'L',
          role: NumeralRole.money,
        ),
        MoneyView.unavailable => Text(
          noValue,
          style: TapeType.numeral(
            size: size,
            weight: TapeTheme.of(context).livery.numeralWeight,
            color: TapeTheme.of(context).palette.inkDim,
          ),
        ),
      },
    );
  }
}

/// Rolling numerals as wide as the digits they show and no wider: the mark before
/// them (the ₹) sits against the first digit, not out at the edge of the room
/// reserved for a number a hundred times bigger. The room changes when the
/// number of digits does (9 to 10, 99 to 100), which is rare, and the ones digit
/// never moves (DESIGN.md 4.5: digits are anchored by the ones column).
class FittedNumerals extends StatefulWidget {
  const FittedNumerals({
    super.key,
    required this.source,
    required this.builder,
    this.maxDigits = 6,
  });

  final NumeralSource source;
  final int maxDigits;

  /// Builds the readout for the number of integer digits to reserve now.
  final Widget Function(BuildContext context, int integerDigits) builder;

  @override
  State<FittedNumerals> createState() => _FittedNumeralsState();
}

class _FittedNumeralsState extends State<FittedNumerals> {
  late int _digits = _digitsOf(widget.source.value);

  static int _digitsOf(double v) {
    final whole = v.abs().round();
    return whole < 10 ? 1 : whole.toString().length;
  }

  @override
  void initState() {
    super.initState();
    widget.source.addListener(_onValue);
  }

  @override
  void didUpdateWidget(FittedNumerals old) {
    super.didUpdateWidget(old);
    if (!identical(old.source, widget.source)) {
      old.source.removeListener(_onValue);
      widget.source.addListener(_onValue);
    }
  }

  @override
  void dispose() {
    widget.source.removeListener(_onValue);
    super.dispose();
  }

  void _onValue() {
    final d = _digitsOf(widget.source.value);
    if (d != _digits) setState(() => _digits = d);
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _digits.clamp(1, widget.maxDigits));
}

/// The dash for a value that is not there (DESIGN.md 10 keeps money and rates
/// from showing false precision or a zero that is a lie).
const String noValue = '—';

/// A rolling numeral with its unit beside it, baseline-aligned: the unit small and
/// dim, never the size of the value (DESIGN.md 4.5).
class LabeledNumeral extends StatelessWidget {
  const LabeledNumeral({
    super.key,
    required this.source,
    required this.format,
    required this.size,
    this.unit,
    this.prefix,
    this.role = NumeralRole.bright,
  });

  final NumeralSource source;
  final NumeralFormat format;
  final double size;
  final String? unit;

  /// A small mark before the digits (the ₹ of ₹/km), in the unit's style.
  final String? prefix;
  final NumeralRole role;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        if (prefix != null) ...[
          TapeLabel(prefix!, size: (size * 0.5).clamp(11.0, 22.0)),
          const SizedBox(width: 2),
        ],
        FittedNumerals(
          source: source,
          maxDigits: format.integerDigits,
          builder: (context, digits) => RollingNumerals(
            source: source,
            format: NumeralFormat(
              integerDigits: digits,
              decimals: format.decimals,
              grouping: format.grouping,
              signed: format.signed,
            ),
            size: size,
            role: role,
          ),
        ),
        if (unit != null) ...[
          const SizedBox(width: TapeSpace.s1),
          TapeLabel(unit!, size: (size * 0.36).clamp(11.0, 16.0)),
        ],
      ],
    );
  }
}

/// A [ValueListenable] read through [map], so that a screen can show 1 - x of a
/// share (the eco bar hides as the car parks) without a second animation.
class MappedShare extends ChangeNotifier implements ValueListenable<double> {
  MappedShare(this._source, this._map) {
    _source.addListener(notifyListeners);
  }

  final ValueListenable<double> _source;
  final double Function(double) _map;

  @override
  double get value => _map(_source.value);

  @override
  void dispose() {
    _source.removeListener(notifyListeners);
    super.dispose();
  }
}
