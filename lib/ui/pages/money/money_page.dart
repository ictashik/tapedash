import 'package:flutter/widgets.dart';

import '../../../vehicle/vehicle_state.dart' show DrivingMode;
import '../../design/components/centered_numeral.dart';
import '../../design/components/controls/tape_button.dart';
import '../../design/components/money.dart';
import '../../design/components/numeral_format.dart';
import '../../design/components/presence.dart';
import '../../design/components/shared_element_end.dart';
import '../../design/components/tape_label.dart';
import '../../design/icons/icons.dart';
import '../../design/motion/shared_elements.dart';
import '../../design/theme/palette.dart';
import '../../design/theme/tape_theme.dart';
import '../../design/tokens/spacing.dart';
import '../../design/tokens/typography.dart';
import '../drive/drive_signals.dart';
import '../drive/money_slots.dart';
import '../strip/the_strip.dart';
import 'bucket_breakdown.dart';
import 'money_figure.dart';
import 'money_signals.dart';

/// The Money page (DESIGN.md 7.4): where the money goes.
///
/// **Motion:** ₹ THIS TRIP in the centre at display size, ₹/KM and KM/L beneath;
/// on the driver-side flank the idle cost; on the other the Money Tape; in the
/// floor the fuel left as ₹ and km. **Parked:** the flanks make way for the
/// breakdown of where it went, the price per litre and the date of the last
/// fill-up, and the Pit Stop button. With no price set, litres are shown and one
/// champagne SET FUEL PRICE button asks for it, parked only.
///
/// The controls exist only while parked (`DrivingMode`), not merely faded out: a
/// button that cannot be seen must not be tappable while driving (CLAUDE.md 1).
///
/// The speed in the status corner is real and is where the Drive page's hero
/// speed lands (DESIGN.md 7.1's shared element).
class MoneyPage extends StatelessWidget {
  const MoneyPage({
    super.key,
    required this.signals,
    required this.width,
    required this.height,
    this.onPitStop,
    this.onSetPrice,
  });

  final DriveSignals signals;
  final double width;
  final double height;

  /// Opens Pit Stop (DESIGN.md 7.9).
  final VoidCallback? onPitStop;

  /// Opens the price entry.
  final VoidCallback? onSetPrice;

  @override
  Widget build(BuildContext context) {
    final type = TypeScale.forHeight(height);
    final toShare = SharedElementsScope.maybeOf(
      context,
    )?.ownShareOf(SharedElementIds.speed, SharedElementEndKind.to);
    final money = signals.money;
    final margin = TapeSpace.margin(height);
    final driverRight = TapeTheme.of(context).driverSide == DriverSide.right;

    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        children: [
          if (money == null)
            const _NoTripComputer()
          else ...[
            // The centre: ₹ THIS TRIP, and the rates beneath.
            Positioned(
              top: height * 0.2,
              left: 0,
              right: 0,
              child: Center(
                child: _Centre(money: money, height: height),
              ),
            ),

            // Motion: the idle cost on the driver's flank, the Money Tape on the
            // other. They fade out as the car parks, and the breakdown in.
            Positioned(
              top: height * 0.22,
              bottom: height * 0.2,
              left: driverRight ? null : margin,
              right: driverRight ? margin : null,
              child: Presence(
                share: signals.motionShare,
                child: _IdleFlank(money: money, height: height),
              ),
            ),
            Positioned(
              top: height * 0.16,
              bottom: height * 0.2,
              left: driverRight ? margin : null,
              right: driverRight ? null : margin,
              child: Presence(
                share: signals.motionShare,
                child: _TapeFlank(money: money, width: width, height: height),
              ),
            ),

            // The floor: the fuel left, as ₹ and km, when the car reports its
            // level (DESIGN.md 7.4).
            Positioned(
              left: 0,
              right: 0,
              bottom: TapeSpace.pageTapeHeight + TapeSpace.s3,
              child: Center(
                child: Presence(
                  share: signals.motionShare,
                  child: _FuelLeft(money: money, height: height),
                ),
              ),
            ),

            // Parked: the breakdown, the price, the buttons.
            ValueListenableBuilder<DrivingMode>(
              valueListenable: signals.mode,
              builder: (context, mode, _) => mode == DrivingMode.parked
                  ? _ParkedPanel(
                      money: money,
                      signals: signals,
                      width: width,
                      height: height,
                      onPitStop: onPitStop,
                      onSetPrice: onSetPrice,
                    )
                  : const SizedBox.shrink(),
            ),
          ],

          // The status-corner speed readout (DESIGN.md 7.1 shared-element
          // landing). Real data, registered as the to-end of the speed flight.
          Positioned(
            top: TapeSpace.s4,
            right: TapeSpace.s4,
            child: SharedElementEnd(
              id: SharedElementIds.speed,
              end: SharedElementEndKind.to,
              page: TheStrip.moneyPage,
              size: type.secondary,
              source: signals.speed,
              format: const NumeralFormat(integerDigits: 3),
              typicalIntegerDigits: 2,
              role: NumeralRole.bright,
              child: CenteredNumeral(
                source: signals.speed,
                format: const NumeralFormat(integerDigits: 3),
                typicalIntegerDigits: 2,
                size: type.secondary,
                role: NumeralRole.bright,
                presence: toShare,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoTripComputer extends StatelessWidget {
  const _NoTripComputer();

  @override
  Widget build(BuildContext context) {
    final palette = TapeTheme.of(context).palette;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const TapeLabel('MONEY', size: 14),
          const SizedBox(height: TapeSpace.s2),
          TapeText('No trip is being recorded.', color: palette.inkMid),
        ],
      ),
    );
  }
}

/// ₹ THIS TRIP at display size, with ₹/KM and KM/L beneath.
class _Centre extends StatelessWidget {
  const _Centre({required this.money, required this.height});

  final MoneySignals money;
  final double height;

  @override
  Widget build(BuildContext context) {
    final type = TypeScale.forHeight(height);
    final palette = TapeTheme.of(context).palette;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // The numeral's own box is far taller than its ink; this row is the
        // ink's height and lets the box overflow it.
        SizedBox(
          height: type.display * 0.9,
          child: OverflowBox(
            maxHeight: type.display * 2.2,
            child: MoneyFigure(
              money: money,
              size: type.display,
              integerDigits: 6,
            ),
          ),
        ),
        const SizedBox(height: TapeSpace.s1),
        ValueListenableBuilder<MoneyView>(
          valueListenable: money.view,
          builder: (context, view, _) => switch (view) {
            MoneyView.rupees => TapeLabel('₹ this trip', size: type.label),
            MoneyView.litres => TapeLabel(
              'Litres this trip · set a fuel price for ₹',
              size: type.label,
            ),
            MoneyView.unavailable => TapeText(
              'Your car does not report fuel use, so money is unavailable.',
              color: palette.inkMid,
            ),
          },
        ),
        const SizedBox(height: TapeSpace.s3),
        ValueListenableBuilder<MoneyView>(
          valueListenable: money.view,
          builder: (context, view, _) => view == MoneyView.unavailable
              ? const SizedBox.shrink()
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (view == MoneyView.rupees) ...[
                      GatedNumeral(
                        available: money.costPerKmAvailable,
                        source: money.costPerKm,
                        format: rateFormat,
                        size: type.secondary,
                        prefix: '₹',
                        unit: '/KM',
                        role: NumeralRole.money,
                      ),
                      const SizedBox(width: TapeSpace.s8),
                    ],
                    GatedNumeral(
                      available: money.kmPerLitreAvailable,
                      source: money.kmPerLitre,
                      format: rateFormat,
                      size: type.secondary,
                      unit: 'KM/L',
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// The idle cost, with the hollow idle glyph (DESIGN.md 7.4).
class _IdleFlank extends StatelessWidget {
  const _IdleFlank({required this.money, required this.height});

  final MoneySignals money;
  final double height;

  @override
  Widget build(BuildContext context) {
    final type = TypeScale.forHeight(height);
    final palette = TapeTheme.of(context).palette;
    return ValueListenableBuilder<MoneyView>(
      valueListenable: money.view,
      builder: (context, view, _) => view != MoneyView.rupees
          ? const SizedBox.shrink()
          : Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TapeIconView(TapeIcon.idle, size: 24, color: palette.caution),
                const SizedBox(height: TapeSpace.s2),
                LabeledNumeral(
                  source: money.idleCost,
                  format: const NumeralFormat(
                    integerDigits: 4,
                    grouping: DigitGrouping.indian,
                  ),
                  size: type.secondary,
                  prefix: '₹',
                  role: NumeralRole.caution,
                ),
                const SizedBox(height: TapeSpace.s1),
                TapeLabel('Idle', size: type.label),
              ],
            ),
    );
  }
}

class _TapeFlank extends StatelessWidget {
  const _TapeFlank({
    required this.money,
    required this.width,
    required this.height,
  });

  final MoneySignals money;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<MoneyBlock>>(
      valueListenable: money.blocks,
      builder: (context, blocks, _) => MoneyTape(
        blocks: blocks,
        length: height * 0.56,
        thickness: (width * 0.06).clamp(18.0, 40.0),
      ),
    );
  }
}

/// The fuel left, as ₹ and km, when the car reports its level.
class _FuelLeft extends StatelessWidget {
  const _FuelLeft({required this.money, required this.height});

  final MoneySignals money;
  final double height;

  @override
  Widget build(BuildContext context) {
    final type = TypeScale.forHeight(height);
    return ValueListenableBuilder<bool>(
      valueListenable: money.hasRemaining,
      builder: (context, has, _) => !has
          ? const SizedBox.shrink()
          : ValueListenableBuilder<MoneyView>(
              valueListenable: money.view,
              builder: (context, view, _) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (view == MoneyView.rupees) ...[
                    LabeledNumeral(
                      source: money.remainingCost,
                      format: const NumeralFormat(
                        integerDigits: 4,
                        grouping: DigitGrouping.indian,
                      ),
                      size: type.secondary * 0.7,
                      prefix: '₹',
                      unit: 'LEFT',
                      role: NumeralRole.money,
                    ),
                    const SizedBox(width: TapeSpace.s6),
                  ],
                  LabeledNumeral(
                    source: money.remainingKm,
                    format: const NumeralFormat(integerDigits: 4),
                    size: type.secondary * 0.7,
                    unit: 'KM LEFT',
                    role: NumeralRole.mid,
                  ),
                ],
              ),
            ),
    );
  }
}

/// The parked panel: the breakdown on one side, the price and the buttons on the
/// other (DESIGN.md 7.4).
class _ParkedPanel extends StatelessWidget {
  const _ParkedPanel({
    required this.money,
    required this.signals,
    required this.width,
    required this.height,
    required this.onPitStop,
    required this.onSetPrice,
  });

  final MoneySignals money;
  final DriveSignals signals;
  final double width;
  final double height;
  final VoidCallback? onPitStop;
  final VoidCallback? onSetPrice;

  @override
  Widget build(BuildContext context) {
    final margin = TapeSpace.margin(height);
    final palette = TapeTheme.of(context).palette;
    final panelWidth = (width * 0.4).clamp(180.0, 300.0);
    return Presence(
      share: signals.parkedShare,
      child: Stack(
        children: [
          Positioned(
            left: margin,
            top: height * 0.3,
            child: ValueListenableBuilder<MoneyView>(
              valueListenable: money.view,
              builder: (context, view, _) => view == MoneyView.rupees
                  ? BucketBreakdown(
                      cost: money.bucketCost,
                      percent: money.bucketPercent,
                      width: panelWidth,
                    )
                  : const SizedBox.shrink(),
            ),
          ),
          Positioned(
            right: margin,
            top: height * 0.4,
            child: SizedBox(
              width: panelWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ValueListenableBuilder<double?>(
                    valueListenable: money.pricePerLitre,
                    builder: (context, price, _) => price == null
                        ? TapeButton(
                            label: 'Set fuel price',
                            tone: ButtonTone.money,
                            onPressed: onSetPrice,
                          )
                        : _PriceChip(money: money, price: price),
                  ),
                  const SizedBox(height: TapeSpace.s3),
                  TapeButton(
                    label: 'Pit stop',
                    icon: TapeIcon.pitStop,
                    onPressed: onPitStop,
                  ),
                  const SizedBox(height: TapeSpace.s2),
                  TapeText(
                    'Estimates, from what your car reports.',
                    style: TapeTextStyle.caption,
                    color: palette.inkDim,
                    textAlign: TextAlign.end,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PriceChip extends StatelessWidget {
  const _PriceChip({required this.money, required this.price});

  final MoneySignals money;
  final double price;

  static const List<String> _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  @override
  Widget build(BuildContext context) {
    final palette = TapeTheme.of(context).palette;
    return ValueListenableBuilder(
      valueListenable: money.lastFill,
      builder: (context, fill, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          TapeText(
            '${formatPricePerLitre(price)} a litre',
            style: TapeTextStyle.title,
            color: palette.money,
          ),
          if (fill != null)
            TapeText(
              'Last filled ${fill.at.day} ${_months[fill.at.month - 1]}',
              style: TapeTextStyle.small,
              color: palette.inkMid,
            ),
        ],
      ),
    );
  }
}

/// "₹102.50": a price is written to the paise (DESIGN.md 10 keeps whole rupees
/// for a trip's cost, and a price is not a cost).
String formatPricePerLitre(double price) => '₹${price.toStringAsFixed(2)}';
