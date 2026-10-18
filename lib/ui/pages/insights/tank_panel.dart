import 'package:flutter/widgets.dart';

import '../../../insights/tank_reading.dart';
import '../../../money/calibration.dart';
import '../../design/components/insights/tank_gauge.dart';
import '../../design/components/money.dart';
import '../../design/components/tape_label.dart';
import '../../design/theme/tape_theme.dart';
import '../../design/tokens/spacing.dart';
import '../../design/tokens/typography.dart';
import 'insight_layout.dart';

/// Tank without a gauge (DESIGN.md 7.14): litres left and the range, counted from
/// the last full tank, for a car that sends no fuel level.
class TankPanel extends StatelessWidget {
  const TankPanel({super.key, required this.reading});

  /// Null until a full tank has been logged.
  final TankReading? reading;

  static MoneyConfidence _pips(CalibrationConfidence c) => switch (c) {
    CalibrationConfidence.uncalibrated => MoneyConfidence.uncalibrated,
    CalibrationConfidence.calibrating => MoneyConfidence.calibrating,
    CalibrationConfidence.calibrated => MoneyConfidence.calibrated,
  };

  @override
  Widget build(BuildContext context) {
    final palette = TapeTheme.of(context).palette;
    final r = reading;
    return InsightPanel(
      chart: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 112,
            child: TankGauge(
              level: r?.level,
              reserve: TankReading.reserveShare,
            ),
          ),
          const SizedBox(width: TapeSpace.s6),
          Expanded(
            child: r == null
                ? const InsightEmpty(
                    title: 'Nothing to count from yet',
                    how:
                        'Fill the tank to the top, log it at Pit Stop with FULL TANK on, '
                        'and the dash counts the litres from there.',
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const TapeLabel('In the tank', size: 11),
                      const SizedBox(height: TapeSpace.s1),
                      _Figure(
                        '≈ ${r.litres.round()}',
                        'L',
                        56,
                        palette.inkBright,
                      ),
                      const SizedBox(height: TapeSpace.s3),
                      const TapeLabel('Range', size: 11),
                      const SizedBox(height: TapeSpace.s1),
                      r.rangeKm == null
                          ? TapeText(
                              'Drive 20 km and it shows.',
                              style: TapeTextStyle.small,
                              color: palette.inkMid,
                            )
                          : _Figure(
                              '≈ ${_to5(r.rangeKm!)}',
                              'KM',
                              28,
                              palette.inkBright,
                            ),
                      if (r.inReserve) ...[
                        const SizedBox(height: TapeSpace.s3),
                        TapeText(
                          'In the reserve.',
                          style: TapeTextStyle.small,
                          color: palette.caution,
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
      facts: [
        if (r != null) ...[
          InsightFact(
            label: 'Since the last full tank',
            value: '${r.usedLitres.toStringAsFixed(1)} L',
            note: '${r.kmSinceFull.round()} km driven',
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: TapeSpace.s3),
            child: Row(
              children: [
                ConfidencePips(
                  confidence: _pips(r.confidence),
                  palette: palette,
                ),
                const SizedBox(width: TapeSpace.s2),
                TapeLabel(r.confidence.name, size: 10, color: palette.money),
              ],
            ),
          ),
        ],
        const InsightNote(
          'Your car sends no fuel level, so the dash counts the litres it has '
          'used since the last full tank. Each full fill-up checks the count and '
          'tightens it.',
        ),
      ],
    );
  }

  /// To the nearest 5 km: a range is not known to the kilometre.
  static int _to5(double km) => (km / 5).round() * 5;
}

class _Figure extends StatelessWidget {
  const _Figure(this.value, this.unit, this.size, this.color);

  final String value;
  final String unit;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final palette = TapeTheme.of(context).palette;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          value,
          style: TapeType.numeral(size: size, weight: 500, color: color),
        ),
        const SizedBox(width: TapeSpace.s1),
        TapeLabel(unit, size: size * 0.4, color: palette.inkDim),
      ],
    );
  }
}
