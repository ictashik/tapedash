import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../design/components/eco_bar.dart';
import '../../design/components/numeral_format.dart';
import '../../design/components/presence.dart';
import '../../design/components/tape_label.dart';
import '../../design/motion/numeral_source.dart';
import '../../design/theme/tape_theme.dart';
import '../../design/tokens/spacing.dart';
import '../../design/tokens/typography.dart';
import '../money/money_figure.dart';
import '../money/money_signals.dart';

/// A numeral that is drawn as a dash when its value is not there yet (below
/// 5 km/h for an instant km/L, under 100 m for a ₹/km): a zero would be a lie
/// (CLAUDE.md 1).
class GatedNumeral extends StatelessWidget {
  const GatedNumeral({
    super.key,
    required this.available,
    required this.source,
    required this.format,
    required this.size,
    this.unit,
    this.prefix,
    this.role = NumeralRole.bright,
  });

  final ValueListenable<bool> available;
  final NumeralSource source;
  final NumeralFormat format;
  final double size;
  final String? unit;
  final String? prefix;
  final NumeralRole role;

  @override
  Widget build(BuildContext context) {
    final theme = TapeTheme.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: available,
      builder: (context, ok, _) => ok
          ? LabeledNumeral(
              source: source,
              format: format,
              size: size,
              unit: unit,
              prefix: prefix,
              role: role,
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                if (prefix != null) ...[
                  TapeLabel(prefix!, size: (size * 0.5).clamp(11.0, 22.0)),
                  const SizedBox(width: 2),
                ],
                Text(
                  noValue,
                  style: TapeType.numeral(
                    size: size,
                    weight: theme.livery.numeralWeight,
                    color: theme.palette.inkDim,
                  ),
                ),
                if (unit != null) ...[
                  const SizedBox(width: TapeSpace.s1),
                  TapeLabel(unit!, size: (size * 0.36).clamp(11.0, 16.0)),
                ],
              ],
            ),
    );
  }
}

/// The driver-side flank of Apex (DESIGN.md 7.3): ₹ THIS TRIP at primary size,
/// with ₹/KM beneath. Money that the car cannot give says so where it stands.
class DriverFlankMoney extends StatelessWidget {
  const DriverFlankMoney({
    super.key,
    required this.money,
    required this.height,
    this.figureSize,
    this.integerDigits = 4,
    this.alignEnd = true,
  });

  final MoneySignals money;
  final double height;

  /// Overrides the digit size (default: `secondary` 0.075H bumped to fit a flank).
  final double? figureSize;
  final int integerDigits;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final type = TypeScale.forHeight(height);
    final size = figureSize ?? type.secondary * 1.1;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        MoneyFigure(money: money, size: size, integerDigits: integerDigits),
        const SizedBox(height: TapeSpace.s1),
        ValueListenableBuilder<MoneyView>(
          valueListenable: money.view,
          builder: (context, view, _) => TapeLabel(switch (view) {
            MoneyView.rupees => '₹ this trip',
            MoneyView.litres => 'litres this trip',
            MoneyView.unavailable => 'no fuel data',
          }, size: type.label),
        ),
        const SizedBox(height: TapeSpace.s3),
        ValueListenableBuilder<MoneyView>(
          valueListenable: money.view,
          builder: (context, view, _) => view == MoneyView.rupees
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GatedNumeral(
                      available: money.costPerKmAvailable,
                      source: money.costPerKm,
                      format: rateFormat,
                      size: type.secondary * 0.8,
                      prefix: '₹',
                      unit: '/KM',
                      role: NumeralRole.money,
                    ),
                  ],
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

/// The other flank's instant km/L, under the coolant gauge (DESIGN.md 7.3).
class InstantEconomy extends StatelessWidget {
  const InstantEconomy({super.key, required this.money, required this.height});

  final MoneySignals money;
  final double height;

  @override
  Widget build(BuildContext context) {
    final type = TypeScale.forHeight(height);
    return ValueListenableBuilder<MoneyView>(
      valueListenable: money.view,
      builder: (context, view, _) => view == MoneyView.unavailable
          ? const SizedBox.shrink()
          : GatedNumeral(
              available: money.instantAvailable,
              source: money.instantKmPerLitre,
              format: rateFormat,
              size: type.secondary * 0.8,
              unit: 'KM/L',
            ),
    );
  }
}

/// The eco bar in the floor (DESIGN.md 6.7): hidden while parked and when the car
/// gives no fuel figure.
class EcoBarSlot extends StatelessWidget {
  const EcoBarSlot({
    super.key,
    required this.money,
    required this.motionShare,
    required this.width,
    required this.height,
  });

  final MoneySignals money;

  /// 1 in Motion, falling to 0 as the car parks (`DriveSignals.motionShare`).
  final ValueListenable<double> motionShare;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<MoneyView>(
      valueListenable: money.view,
      builder: (context, view, _) => view == MoneyView.unavailable
          ? const SizedBox.shrink()
          : Presence(
              share: motionShare,
              child: ValueListenableBuilder<double?>(
                valueListenable: money.ecoAverage,
                builder: (context, average, _) => EcoBar(
                  instantValue: money.instantKmPerLitre,
                  average: average,
                  width: width,
                  heightReference: height,
                ),
              ),
            ),
    );
  }
}

/// The floor's trip distance and the trip's average km/L (left) and trip time
/// (right), in `ink.mid` at secondary size (DESIGN.md 7.3). They give way to the dock while parked.
class TripFloor extends StatelessWidget {
  const TripFloor({
    super.key,
    required this.money,
    required this.motionShare,
    required this.width,
    required this.height,
  });

  final MoneySignals money;

  /// 1 in Motion, falling to 0 as the car parks (`DriveSignals.motionShare`).
  final ValueListenable<double> motionShare;
  final double width;
  final double height;

  /// "12:05" for an hour and five minutes, or "5:30" for five and a half
  /// minutes: hours and minutes past an hour, minutes and seconds under it.
  static String formatDuration(Duration d) {
    final s = d.inSeconds;
    if (s >= 3600) {
      final h = s ~/ 3600;
      final m = (s % 3600) ~/ 60;
      return '$h:${m.toString().padLeft(2, '0')}';
    }
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final type = TypeScale.forHeight(height);
    final theme = TapeTheme.of(context);
    final margin = TapeSpace.margin(height);
    final style = TapeType.numeral(
      size: type.secondary * 0.7,
      weight: theme.livery.numeralWeight,
      color: theme.palette.inkMid,
    );
    final bottom = TapeSpace.pageTapeHeight + TapeSpace.s3;
    final fade = motionShare;
    return Stack(
      children: [
        Positioned(
          left: margin,
          bottom: bottom,
          child: Presence(
            share: fade,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                LabeledNumeral(
                  source: money.distanceKm,
                  format: rateFormat,
                  size: type.secondary * 0.7,
                  unit: 'KM',
                  role: NumeralRole.mid,
                ),
                // The trip's average, right after its distance: a dash until
                // there is some distance to average over, and nothing at all
                // for a car that gives no fuel figure.
                ValueListenableBuilder<MoneyView>(
                  valueListenable: money.view,
                  builder: (context, view, _) => view == MoneyView.unavailable
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.only(left: TapeSpace.s4),
                          child: GatedNumeral(
                            available: money.kmPerLitreAvailable,
                            source: money.kmPerLitre,
                            format: rateFormat,
                            size: type.secondary * 0.7,
                            unit: 'KM/L',
                            role: NumeralRole.mid,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          right: margin,
          bottom: bottom,
          child: Presence(
            share: fade,
            child: ValueListenableBuilder<Duration>(
              valueListenable: money.tripTime,
              builder: (context, d, _) => Text(formatDuration(d), style: style),
            ),
          ),
        ),
      ],
    );
  }
}
