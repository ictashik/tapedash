import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:tapedash/insights/insight_data.dart';
import 'package:tapedash/insights/rest_voltage_log.dart';
import 'package:tapedash/insights/tank_reading.dart';
import 'package:tapedash/money/fuel_ledger.dart';
import 'package:tapedash/trips/trip.dart';
import 'package:tapedash/ui/pages/insights/insights_page.dart';
import 'package:tapedash/vehicle/vehicle_state.dart';

/// The Insights page on made-up data, as the shell would build it: for the page's
/// widget tests and its captures. One place to give it a new input.
Widget insightsPageFor({
  required InsightData data,
  required FuelLedger ledger,
  required ValueListenable<DrivingMode> mode,
  required Size size,
  InsightTab? tab,
  List<RestReading> rest = const [],
  Trip? selected,
  VoidCallback? onClose,
}) => InsightsPage(
  load: () async => data,
  tank: (trips) => TankReading.of(ledger: ledger, tankLitres: 40, trips: trips),
  selected: () => selected,
  rest: () => rest,
  mode: mode,
  width: size.width,
  height: size.height,
  onClose: onClose ?? () {},
  initial: tab ?? InsightTab.values.first,
);

/// Ten weeks of a battery at rest, slowly sagging, one reading a week or so.
List<RestReading> madeRestReadings(DateTime now) => [
  for (var i = 0; i < 12; i++)
    RestReading(
      now.subtract(Duration(days: (11 - i) * 6)),
      [
        12.58,
        12.57,
        12.58,
        12.55,
        12.54,
        12.55,
        12.52,
        12.51,
        12.49,
        12.48,
        12.46,
        12.44,
      ][i],
    ),
];
