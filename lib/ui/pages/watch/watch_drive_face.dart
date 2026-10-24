import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../design/components/centered_numeral.dart';
import '../../design/components/numeral_format.dart';
import '../../design/components/parked_scale.dart';
import '../../design/components/presence.dart';
import '../../design/components/tach_arc.dart';
import '../../design/components/tape_label.dart';
import '../../design/components/watch/eco_arc.dart';
import '../../design/components/watch/watch_face.dart';
import '../drive/drive_signals.dart';
import '../drive/money_slots.dart';
import '../money/money_figure.dart';
import '../money/money_signals.dart';

/// The watch's Drive face (DESIGN.md 16.5): the revs round the rim, the speed in
/// the core, the ₹ of this trip in the foot, the eco arc in the rim's opening.
///
/// Three values and a cue, and nothing a driver has to read: the lit length of the
/// ring is the revs, seen without looking at it. Parked, the ring thins and dims,
/// the speed shrinks, and the trip's distance and time come up beneath it.
class WatchDriveFace extends StatelessWidget {
  const WatchDriveFace({
    super.key,
    required this.signals,
    required this.face,
    this.unit = 'KM/H',
  });

  final DriveSignals signals;
  final WatchFace face;

  /// What is under the speed.
  final String unit;

  /// How much of its size the speed keeps when the car is parked.
  static const double parkedHeroShare = 0.6;

  @override
  Widget build(BuildContext context) {
    final type = face.type;
    final money = signals.money;
    final hero = type.hero;
    final metrics = NumeralMetrics(hero);
    const format = NumeralFormat(integerDigits: 3);
    return SizedBox.square(
      dimension: face.diameter,
      child: Stack(
        children: [
          Positioned.fill(
            child: Center(
              child: TachArc(
                rpm: signals.rpm,
                heightReference: face.diameter,
                geometry: face.tach,
                rpmPerSegment: 200,
                parkedShare: signals.parkedShare,
                litShare: signals.arcWave,
              ),
            ),
          ),
          // The speed, with its unit under the ink.
          Positioned(
            left: 0,
            right: 0,
            top: face.heroY - metrics.boxHeight / 2,
            height: metrics.boxHeight,
            child: Center(
              child: ParkedScale(
                share: signals.parkedShare,
                parkedScaleShare: parkedHeroShare,
                child: CenteredNumeral(
                  source: signals.speed,
                  format: format,
                  typicalIntegerDigits: 2,
                  size: hero,
                  role: NumeralRole.bright,
                ),
              ),
            ),
          ),
          if (money != null) ...[
            // The foot: ₹ THIS TRIP.
            Positioned(
              left: 0,
              right: 0,
              top: face.footY - NumeralMetrics(type.primary).boxHeight / 2,
              height: NumeralMetrics(type.primary).boxHeight,
              child: Presence(
                share: signals.flankDriver,
                child: Center(
                  child: MoneyFigure(
                    money: money,
                    size: type.primary,
                    integerDigits: 4,
                  ),
                ),
              ),
            ),
            // The eco arc, in the rim's opening: Motion only.
            Positioned.fill(
              child: _EcoSlot(
                money: money,
                motionShare: signals.motionShare,
                face: face,
              ),
            ),
            // Parked: the trip's distance and time over the speed, where the
            // shrunk speed has left room.
            Positioned(
              left: 0,
              right: 0,
              top:
                  face.diameter * 0.305 -
                  NumeralMetrics(type.secondary).boxHeight / 2,
              height: NumeralMetrics(type.secondary).boxHeight,
              child: Presence(
                share: signals.parkedShare,
                child: Center(
                  child: _TripLine(money: money, face: face),
                ),
              ),
            ),
          ],
          // The unit goes over the foot's neighbouring digit, not under it.
          Positioned(
            left: 0,
            right: 0,
            top: face.heroY + metrics.inkHeight / 2 + type.label * 0.35,
            child: Center(child: TapeLabel(unit, size: type.label)),
          ),
        ],
      ),
    );
  }
}

class _EcoSlot extends StatelessWidget {
  const _EcoSlot({
    required this.money,
    required this.motionShare,
    required this.face,
  });

  final MoneySignals money;
  final ValueListenable<double> motionShare;
  final WatchFace face;

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
                builder: (context, average, _) => EcoArc(
                  instantValue: money.instantKmPerLitre,
                  average: average,
                  face: face,
                ),
              ),
            ),
    );
  }
}

/// "12.4 KM  32:10", at secondary size.
class _TripLine extends StatelessWidget {
  const _TripLine({required this.money, required this.face});

  final MoneySignals money;
  final WatchFace face;

  @override
  Widget build(BuildContext context) {
    final size = face.type.secondary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        LabeledNumeral(
          source: money.distanceKm,
          format: rateFormat,
          size: size,
          unit: 'KM',
          role: NumeralRole.mid,
        ),
        SizedBox(width: size * 0.6),
        ValueListenableBuilder<Duration>(
          valueListenable: money.tripTime,
          builder: (context, d, _) =>
              TapeLabel(TripFloor.formatDuration(d), size: face.type.label),
        ),
      ],
    );
  }
}
