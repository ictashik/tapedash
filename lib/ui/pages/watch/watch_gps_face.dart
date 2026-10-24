import 'package:flutter/widgets.dart';

import '../../../location/gps_drive.dart';
import '../../design/components/centered_numeral.dart';
import '../../design/components/numeral_format.dart';
import '../../design/components/parked_scale.dart';
import '../../design/components/presence.dart';
import '../../design/components/tach_arc.dart';
import '../../design/components/tape_label.dart';
import '../../design/components/watch/watch_face.dart';
import '../../design/theme/tape_theme.dart';
import '../drive/gps_signals.dart';
import '../money/money_figure.dart' show LabeledNumeral, rateFormat;

/// The watch's face for a drive on the GPS alone (DESIGN.md 16.5, 7.15): the speed
/// as the hero, a **speed arc** round the rim (0 to 140 km/h, lit as the revs are on
/// an adapter's face), the distance in the foot, and, parked, the moving time and
/// the fastest speed over the hero. No tach, money or coach: nothing reads them.
///
/// Before there is a speed the centre says why in a few words and never shows a
/// zero it does not have (DESIGN.md 7.15); after the first speed a lost fix dims the
/// number and keeps it.
class WatchGpsFace extends StatelessWidget {
  const WatchGpsFace({
    super.key,
    required this.signals,
    required this.face,
    this.onAllowLocation,
  });

  final GpsSignals signals;
  final WatchFace face;

  /// Asks the watch for its location (a tap on the words, when it is needed).
  final VoidCallback? onAllowLocation;

  /// The speed arc's range: 140 km/h in 35 segments of 4.
  static const double maxKmh = 140;
  static const int kmhPerSegment = 4;

  @override
  Widget build(BuildContext context) {
    final drive = signals.drive;
    final type = face.type;
    final metrics = NumeralMetrics(type.hero);
    return SizedBox.square(
      dimension: face.diameter,
      child: Stack(
        children: [
          Positioned.fill(
            child: Center(
              child: TachArc(
                rpm: drive.speed,
                maxRpm: maxKmh,
                redlineRpm: maxKmh * 100,
                heightReference: face.diameter,
                geometry: face.tach,
                rpmPerSegment: kmhPerSegment,
                parkedShare: drive.parkedShare,
              ),
            ),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: signals.hasSpeed,
            builder: (context, has, _) => has
                ? Stack(
                    children: [
                      Positioned(
                        left: 0,
                        right: 0,
                        top: face.heroY - metrics.boxHeight / 2,
                        height: metrics.boxHeight,
                        child: Center(
                          child: ParkedScale(
                            share: drive.parkedShare,
                            parkedScaleShare: 0.6,
                            child: CenteredNumeral(
                              source: drive.speed,
                              format: const NumeralFormat(integerDigits: 3),
                              typicalIntegerDigits: 2,
                              size: type.hero,
                              role: NumeralRole.bright,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        top:
                            face.heroY +
                            metrics.inkHeight / 2 +
                            type.label * 0.35,
                        child: Center(
                          child: TapeLabel('KM/H', size: type.label),
                        ),
                      ),
                    ],
                  )
                : _Waiting(
                    signals: signals,
                    face: face,
                    onAllow: onAllowLocation,
                  ),
          ),
          // The foot: the distance of this trip.
          Positioned(
            left: 0,
            right: 0,
            top: face.footY - NumeralMetrics(type.primary).boxHeight / 2,
            height: NumeralMetrics(type.primary).boxHeight,
            child: Center(
              child: LabeledNumeral(
                source: signals.distance,
                format: rateFormat,
                size: type.primary,
                unit: 'KM',
                role: NumeralRole.bright,
              ),
            ),
          ),
          // Parked: the time spent moving and the fastest, over the speed.
          Positioned(
            left: 0,
            right: 0,
            top:
                face.diameter * 0.305 -
                NumeralMetrics(type.secondary).boxHeight / 2,
            height: NumeralMetrics(type.secondary).boxHeight,
            child: Presence(
              share: drive.parkedShare,
              child: Center(
                child: _ParkedLine(signals: signals, face: face),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// What the centre says before there is a speed.
class _Waiting extends StatelessWidget {
  const _Waiting({
    required this.signals,
    required this.face,
    required this.onAllow,
  });

  final GpsSignals signals;
  final WatchFace face;
  final VoidCallback? onAllow;

  @override
  Widget build(BuildContext context) {
    final palette = TapeTheme.of(context).palette;
    return ValueListenableBuilder<GpsPhase>(
      valueListenable: signals.phase,
      builder: (context, phase, _) {
        final lines = switch (phase) {
          GpsPhase.starting => const ['Starting', 'GPS'],
          GpsPhase.needsPermission => const [
            'Location',
            'needed',
            'tap to allow',
          ],
          GpsPhase.unavailable => const ['No GPS'],
          GpsPhase.searching ||
          GpsPhase.tracking => const ['Looking for', 'GPS', 'sky view helps'],
        };
        return Positioned(
          left: 0,
          right: 0,
          top: face.heroY - face.type.label * 2.2,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: phase == GpsPhase.needsPermission ? onAllow : null,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (i, line) in lines.indexed)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: TapeLabel(
                      line,
                      size: face.type.label,
                      color: i == 0 ? palette.inkBright : palette.inkMid,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// "0:32  MAX 87", in the label size.
class _ParkedLine extends StatelessWidget {
  const _ParkedLine({required this.signals, required this.face});

  final GpsSignals signals;
  final WatchFace face;

  static String _time(Duration d) {
    final s = d.inSeconds;
    if (s >= 3600) {
      return '${s ~/ 3600}:${((s % 3600) ~/ 60).toString().padLeft(2, '0')}';
    }
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<GpsFigures>(
      valueListenable: signals.figures,
      builder: (context, f, _) => TapeLabel(
        '${_time(f.movingTime)}  ·  max ${f.maxKmh.round()}',
        size: face.type.label,
      ),
    );
  }
}
