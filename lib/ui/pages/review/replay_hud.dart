import 'package:flutter/widgets.dart';

import '../../../coach/sample_events.dart';
import '../../design/components/bar_gauge.dart';
import '../../design/components/rolling_numerals.dart';
import '../../design/components/tape_label.dart';
import '../../design/icons/icons.dart';
import '../../design/motion/playback_channel.dart';
import '../../design/motion/trip_player.dart';
import '../../design/theme/tape_theme.dart';
import '../../design/tokens/spacing.dart';
import '../../design/tokens/typography.dart';
import '../money/money_figure.dart';

/// The instruments of a trip replay (DESIGN.md 6.12), in the place of the receipt
/// while a replay runs: the speed large, the revs and the throttle as bars, the ₹
/// so far (or the litres, with no price), the distance, the time, and the marked
/// moment (a hard acceleration, a hard braking, a long idle) for a few seconds as
/// the car passes it.
///
/// Every reading is a [PlaybackChannel]: the numerals and bars repaint from the
/// play head and nothing rebuilds for it. Only the marked moment rebuilds, and only
/// when it changes.
class ReplayHud extends StatefulWidget {
  const ReplayHud({
    super.key,
    required this.player,
    required this.events,
    required this.price,
    required this.maxRpm,
    required this.width,
    required this.height,
  });

  final TripPlayer player;
  final ReplayEvents events;

  /// The price the trip was costed at, or null: the litres are shown instead.
  final double? price;

  /// The top of the rev bar: what the trip reached, rounded up to 1000.
  final double maxRpm;

  final double width;
  final double height;

  /// The room the moment's caption keeps whether it has one or not, so that nothing
  /// below it moves.
  static const double eventHeight = 20;

  @override
  State<ReplayHud> createState() => _ReplayHudState();
}

class _ReplayHudState extends State<ReplayHud> {
  // Each on the grain it is shown at: whole km/h, revs to 10, whole percent, whole
  // rupees, tenths of a litre, of a km and of a minute: a number that moved every
  // frame would be part-way through a roll nearly all the time.
  late final PlaybackChannel _speed = PlaybackChannel(
    widget.player,
    (f) => f.speedKmh,
    step: 1,
  );
  late final PlaybackChannel _rpm = PlaybackChannel(
    widget.player,
    (f) => f.rpm,
    step: 10,
  );
  late final PlaybackChannel _throttle = PlaybackChannel(
    widget.player,
    (f) => f.throttle,
    step: 1,
  );
  late final PlaybackChannel _cost = PlaybackChannel(
    widget.player,
    (f) => f.cost,
    step: 1,
  );
  late final PlaybackChannel _litres = PlaybackChannel(
    widget.player,
    (f) => f.litres,
    step: 0.1,
  );
  late final PlaybackChannel _km = PlaybackChannel(
    widget.player,
    (f) => f.distanceKm,
    step: 0.1,
  );
  late final PlaybackChannel _minutes = PlaybackChannel(
    widget.player,
    (f) => f.seconds / 60,
    step: 0.1,
  );

  @override
  void dispose() {
    for (final c in [_speed, _rpm, _throttle, _cost, _litres, _km, _minutes]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = TapeTheme.of(context);
    final palette = theme.palette;
    final heroSize = (widget.height * 0.2).clamp(40.0, 72.0);
    final barLength = (widget.width - 130).clamp(70.0, 180.0);
    final hasPrice = widget.price != null;
    const minutesFormat = NumeralFormat(integerDigits: 3, decimals: 1);

    Widget stat(String label, Widget value) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TapeLabel(label, size: 10),
          SizedBox(
            height: 22,
            child: OverflowBox(
              maxHeight: NumeralMetrics(18).boxHeight,
              alignment: Alignment.centerLeft,
              child: value,
            ),
          ),
        ],
      ),
    );

    // The column is as tall as it is and scales down to the room it is given: a
    // few lp of overflow at 360 lp high would otherwise clip the moment's caption.
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: widget.width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The speed.
              SizedBox(
                height: heroSize * 0.95,
                child: OverflowBox(
                  maxHeight: heroSize * 2.2,
                  alignment: Alignment.centerLeft,
                  child: LabeledNumeral(
                    source: _speed,
                    format: const NumeralFormat(integerDigits: 3),
                    size: heroSize,
                    unit: 'KM/H',
                    role: NumeralRole.accent,
                  ),
                ),
              ),
              const SizedBox(height: TapeSpace.s2),
              BarGauge(
                value: _rpm,
                min: 0,
                max: widget.maxRpm,
                length: barLength,
                thickness: 10,
                label: 'RPM',
              ),
              const SizedBox(height: TapeSpace.s2),
              BarGauge(
                value: _throttle,
                min: 0,
                max: 100,
                length: barLength,
                thickness: 10,
                label: '% THR',
              ),
              const SizedBox(height: TapeSpace.s3),
              Row(
                children: [
                  if (hasPrice)
                    stat(
                      'Spent',
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            '≈₹',
                            style: TapeType.numeral(
                              size: 11,
                              weight: theme.livery.numeralWeight,
                              color: palette.rupee,
                            ),
                          ),
                          FittedNumerals(
                            source: _cost,
                            maxDigits: 5,
                            builder: (context, digits) => RollingNumerals(
                              source: _cost,
                              format: NumeralFormat(
                                integerDigits: digits,
                                grouping: DigitGrouping.indian,
                              ),
                              size: 18,
                              role: NumeralRole.money,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    stat(
                      'Fuel',
                      LabeledNumeral(
                        source: _litres,
                        format: rateFormat,
                        size: 18,
                        unit: 'L',
                        role: NumeralRole.money,
                      ),
                    ),
                  stat(
                    'Distance',
                    LabeledNumeral(
                      source: _km,
                      format: rateFormat,
                      size: 18,
                      unit: 'KM',
                    ),
                  ),
                  stat(
                    'Time',
                    LabeledNumeral(
                      source: _minutes,
                      format: minutesFormat,
                      size: 18,
                      unit: 'MIN',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: TapeSpace.s2),
              SizedBox(
                height: ReplayHud.eventHeight,
                child: ListenableBuilder(
                  listenable: widget.events,
                  builder: (context, _) =>
                      _EventCaption(type: widget.events.current),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The marked moment being passed: its glyph and its name, in the colour its marker
/// has on the route. Nothing when there is none. The wording is the coach's
/// (DESIGN.md 10): what happened, never a judgement.
class _EventCaption extends StatelessWidget {
  const _EventCaption({required this.type});

  final SampleEventType? type;

  static String nameOf(SampleEventType t) => switch (t) {
    SampleEventType.hardAcceleration => 'Hard acceleration',
    SampleEventType.hardBraking => 'Hard braking',
    SampleEventType.longIdle => 'Long idle',
  };

  @override
  Widget build(BuildContext context) {
    final t = type;
    if (t == null) return const SizedBox.shrink();
    final palette = TapeTheme.of(context).palette;
    final color = t == SampleEventType.longIdle
        ? palette.caution
        : palette.critical;
    final icon = switch (t) {
      SampleEventType.hardAcceleration => TapeIcon.hardAccel,
      SampleEventType.hardBraking => TapeIcon.hardBrake,
      SampleEventType.longIdle => TapeIcon.idle,
    };
    return Row(
      children: [
        TapeIconView(icon, size: 16, color: color),
        const SizedBox(width: TapeSpace.s2),
        TapeLabel(nameOf(t), size: 12, color: color),
      ],
    );
  }
}
