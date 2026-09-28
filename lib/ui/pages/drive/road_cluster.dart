import 'package:flutter/widgets.dart';

import '../../design/components/road_view.dart';
import '../../design/tokens/tach.dart';
import 'drive_signals.dart';

/// The Road cluster (DESIGN.md 7.3.5): the road view (DESIGN.md 6.11),
/// full-bleed, with the overlays that view draws itself -- the hero speed
/// top-centre and the RPM bar along its horizon line.
///
/// **What is not here yet, on purpose:** the money readout DESIGN.md 6.11
/// places on the driver-side flank, which needs `money/` (CLAUDE.md 13's
/// phase 4). `RoadView` reserves the slot and accepts a [RoadView.moneySlot]
/// widget, so phase 4 only has to pass one in; showing nothing beats showing
/// a fake number (CLAUDE.md 1). The same holds for the car's roll: the
/// accelerometer pipeline does not exist yet, so
/// [DriveSignals.lateralAcceleration] is never ingested into and the car
/// simply does not roll (see that field's own doc comment).
///
/// DESIGN.md 6.11's overlay list is the whole of this cluster's chrome: no
/// status strip and no flanks are named for Road, unlike Apex (DESIGN.md
/// 7.3.1), and CLAUDE.md 12 says to follow the design rather than add to it.
/// The max RPM for the horizon bar is [TapeTach.defaultMaxRpm], the same
/// default the tach arc and shift horizon use; a per-profile range arrives
/// with real vehicle setup (phase 4's vehicle setup work feeds this too).
class RoadCluster extends StatelessWidget {
  const RoadCluster({
    super.key,
    required this.signals,
    required this.width,
    required this.height,
  });

  final DriveSignals signals;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return RoadView(
      speed: signals.speed,
      rpm: signals.rpm,
      maxRpm: TapeTach.defaultMaxRpm,
      longitudinalAcceleration: signals.longitudinalAcceleration,
      lateralAcceleration: signals.lateralAcceleration,
      width: width,
      height: height,
    );
  }
}
