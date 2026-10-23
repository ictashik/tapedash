import 'package:flutter/widgets.dart';

import '../../../location/gps_drive.dart';
import '../../design/components/centered_numeral.dart';
import '../../design/components/controls/tape_button.dart';
import '../../design/components/parked_scale.dart';
import '../../design/components/rolling_numerals.dart';
import '../../design/components/status_strip.dart';
import '../../design/components/tape_label.dart';
import '../../design/icons/icons.dart';
import '../../design/theme/tape_theme.dart';
import '../../design/tokens/spacing.dart';
import '../../design/tokens/typography.dart';
import '../money/money_figure.dart' show LabeledNumeral, noValue;
import 'gps_signals.dart';

/// The drive screen for a drive on the GPS alone: the speed as the hero, the
/// way the Minimal cluster has it, and under it what a GPS can honestly add up to
/// (distance, moving time, average, fastest, and the heading). There is no tach, no
/// money and no coach, because nothing reads them; the screen does not draw
/// empty places for them.
///
/// Until the phone has given a first speed the hero is a plain message in words
/// (looking for GPS, or asking for the location), and a button to allow the
/// location when that is what is missing. A fix lost later (a tunnel) keeps the
/// last speed on screen, dimmed as stale numbers are, and never swaps it for a
/// message.
class GpsCluster extends StatelessWidget {
  const GpsCluster({
    super.key,
    required this.signals,
    required this.width,
    required this.height,
    this.onAllowLocation,
  });

  final GpsSignals signals;
  final double width;
  final double height;

  /// Asks again for the location permission. Null leaves the button out.
  final VoidCallback? onAllowLocation;

  @override
  Widget build(BuildContext context) {
    final type = TypeScale.forHeight(height);
    final drive = signals.drive;
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        children: [
          Positioned(
            top: TapeSpace.s2,
            left: TapeSpace.s4,
            child: StatusStripLeft(
              gpsHasFix: drive.gpsHasFix,
              parkedShare: drive.parkedShare,
            ),
          ),
          Positioned(
            top: TapeSpace.s2,
            right: TapeSpace.s4,
            child: StatusStripRight(
              time: drive.wallClock,
              use24Hour: MediaQuery.alwaysUse24HourFormatOf(context),
              phoneHot: drive.phoneHot,
              parkedShare: drive.parkedShare,
            ),
          ),
          Positioned(
            top: height * TapeSpace.horizonShare,
            bottom: height * TapeSpace.clearOfDockShare,
            left: 0,
            right: 0,
            child: Center(
              child: OverflowBox(
                minHeight: 0,
                maxHeight: double.infinity,
                child: ValueListenableBuilder<bool>(
                  valueListenable: signals.hasSpeed,
                  builder: (context, has, _) =>
                      has ? _speed(context, type) : _waiting(context, type),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _speed(BuildContext context, TypeScale type) {
    final drive = signals.drive;
    final hero = NumeralMetrics(type.hero);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // The numeral's own box is far taller than its ink (the detent and roll
        // room), and the label would float far below it: this box is the ink's
        // height, and the numeral is centred in it and overflows both ways.
        SizedBox(
          height: hero.inkHeight,
          child: OverflowBox(
            minHeight: 0,
            maxHeight: hero.boxHeight * 1.5,
            child: ParkedScale(
              share: drive.parkedShare,
              parkedScaleShare: type.primary / type.hero,
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
        const SizedBox(height: TapeSpace.s3),
        const TapeLabel('km/h', size: 14),
        const SizedBox(height: TapeSpace.s3),
        _Readouts(signals: signals, size: type.secondary),
      ],
    );
  }

  Widget _waiting(BuildContext context, TypeScale type) {
    final palette = TapeTheme.of(context).palette;
    return ValueListenableBuilder<GpsPhase>(
      valueListenable: signals.phase,
      builder: (context, phase, _) {
        final (title, body) = switch (phase) {
          GpsPhase.starting => ('Starting GPS', ''),
          GpsPhase.needsPermission => (
            'Location needed',
            'TapeDash reads your speed from this phone\'s GPS. Allow location '
                'to begin. Nothing leaves the phone.',
          ),
          GpsPhase.unavailable => (
            'No GPS',
            'This phone would not start a GPS receiver.',
          ),
          GpsPhase.searching || GpsPhase.tracking => (
            'Looking for GPS',
            'Give the phone a clear view of the sky; the first fix can take a '
                'minute. Check that location is on in the phone\'s settings.',
          ),
        };
        return SizedBox(
          width: width * 0.62,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TapeLabel(title, size: 16, color: palette.inkBright),
              if (body.isNotEmpty) ...[
                const SizedBox(height: TapeSpace.s3),
                TapeText(
                  body,
                  style: TapeTextStyle.body,
                  color: palette.inkMid,
                  textAlign: TextAlign.center,
                  maxLines: 4,
                ),
              ],
              if (phase == GpsPhase.needsPermission &&
                  onAllowLocation != null) ...[
                const SizedBox(height: TapeSpace.s6),
                TapeButton(
                  label: 'Allow location',
                  icon: TapeIcon.gps,
                  primary: true,
                  onPressed: onAllowLocation,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// The trip's figures under the speed: distance, moving time, average and fastest
/// speed, and the heading. Each is a label over its number, and the number is
/// honest: an average before there is enough driving to have one is a dash, and a
/// heading at a standstill is a dash.
class _Readouts extends StatelessWidget {
  const _Readouts({required this.signals, required this.size});

  final GpsSignals signals;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Readout(
          label: 'Distance',
          child: LabeledNumeral(
            source: signals.distance,
            format: const NumeralFormat(integerDigits: 3, decimals: 1),
            size: size,
            unit: 'km',
            role: NumeralRole.mid,
          ),
        ),
        _Readout(
          label: 'Moving',
          child: _Text(
            listenable: signals.figures,
            size: size,
            text: () => formatMovingTime(signals.figures.value.movingTime),
          ),
        ),
        _Readout(
          label: 'Average',
          child: ListenableBuilder(
            listenable: signals.figures,
            builder: (context, _) => signals.figures.value.averageKmh == null
                ? _Dash(size: size)
                : LabeledNumeral(
                    source: signals.average,
                    format: const NumeralFormat(integerDigits: 3),
                    size: size,
                    unit: 'km/h',
                    role: NumeralRole.mid,
                  ),
          ),
        ),
        _Readout(
          label: 'Fastest',
          child: LabeledNumeral(
            source: signals.fastest,
            format: const NumeralFormat(integerDigits: 3),
            size: size,
            unit: 'km/h',
            role: NumeralRole.mid,
          ),
        ),
        _Readout(
          label: 'Heading',
          child: _Text(
            listenable: signals.heading,
            size: size,
            text: () => compassPoint(signals.heading.value) ?? noValue,
          ),
        ),
      ],
    );
  }
}

/// Minutes and seconds (`12:34`) up to an hour, then hours, minutes and seconds
/// (`1:05:09`). Seconds count from the first, so the figure moves while the car
/// does and is never `0:00` on a drive. Exposed for a direct test.
String formatMovingTime(Duration d) {
  final seconds = d.inSeconds;
  String two(int n) => n.toString().padLeft(2, '0');
  if (seconds < 3600) return '${seconds ~/ 60}:${two(seconds % 60)}';
  return '${seconds ~/ 3600}:${two(seconds ~/ 60 % 60)}:${two(seconds % 60)}';
}

/// The compass point of a heading in degrees (`N`, `NE`, `E` and so on), or null
/// when there is no heading. Exposed for a direct test.
String? compassPoint(double? degrees) {
  if (degrees == null) return null;
  const points = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
  final index = (((degrees % 360) + 360) % 360 / 45).round() % 8;
  return points[index];
}

class _Readout extends StatelessWidget {
  const _Readout({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: TapeSpace.s3),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TapeLabel(label, size: 10),
          const SizedBox(height: TapeSpace.s1),
          child,
        ],
      ),
    );
  }
}

/// A figure that is text and not a rolling number (a time, a compass point): set in
/// the numeral face and redrawn when its source changes, at most once a second.
class _Text extends StatelessWidget {
  const _Text({
    required this.listenable,
    required this.size,
    required this.text,
  });

  final Listenable listenable;
  final double size;
  final String Function() text;

  @override
  Widget build(BuildContext context) {
    final theme = TapeTheme.of(context);
    return ListenableBuilder(
      listenable: listenable,
      builder: (context, _) => SizedBox(
        // The height the rolling numerals beside it have, so the figures share a
        // baseline, and enough for the line the text sets (a shorter box clips it).
        height: NumeralMetrics(size).boxHeight,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            text(),
            maxLines: 1,
            style: TapeType.numeral(
              size: size,
              weight: theme.livery.numeralWeight,
              color: theme.palette.inkMid,
            ),
          ),
        ),
      ),
    );
  }
}

class _Dash extends StatelessWidget {
  const _Dash({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = TapeTheme.of(context);
    return SizedBox(
      height: NumeralMetrics(size).boxHeight,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          noValue,
          style: TapeType.numeral(
            size: size,
            weight: theme.livery.numeralWeight,
            color: theme.palette.inkDim,
          ),
        ),
      ),
    );
  }
}
