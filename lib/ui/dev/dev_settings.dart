import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../../vehicle/vehicle_state.dart';
import '../design/fidelity/fidelity_tier.dart';
import '../design/theme/mode_controller.dart';
import '../design/theme/palette.dart';
import '../design/tokens/livery.dart';

/// Build flags for the developer tools.
///
/// The deck's button is compiled in whatever the build, and shown in debug and profile
/// builds, and in a release build made with `--dart-define=TAPEDASH_DEV=true`.
/// Without either, the only way in is the long-press that opens the debug overlay
/// (CLAUDE.md 9, DESIGN.md 11).
abstract final class DevMode {
  /// Whether the developer deck's button is shown.
  static const bool buttonVisible = bool.fromEnvironment(
    'TAPEDASH_DEV',
    defaultValue: !kReleaseMode,
  );

  /// A screen to open at launch instead of the cold open, such as `lab:numerals`:
  /// how a screenshot script reaches a page without touching the screen.
  static const String launchScreen = String.fromEnvironment('TAPEDASH_START');

  /// Skips the cold open, for tests and screenshot scripts.
  static const bool skipColdOpen = bool.fromEnvironment(
    'TAPEDASH_NO_COLD_OPEN',
  );
}

/// How the developer forces Motion or Parked whatever the car says (DESIGN.md 7.2).
///
/// With a real adapter, this is how the Motion layout is seen with the car standing
/// still, and the parked pages are seen with the car moving. It changes what the
/// screen shows and never what the car or the adapter is doing.
enum DrivingOverride {
  follow('FOLLOW CAR'),
  motion('MOTION'),
  parked('PARKED');

  const DrivingOverride(this.label);

  final String label;

  /// The mode to show, given the mode the vehicle is in.
  DrivingMode resolve(DrivingMode actual) => switch (this) {
    follow => actual,
    motion => DrivingMode.motion,
    parked => DrivingMode.parked,
  };
}

/// The aspect ratio frames of DESIGN.md 4.7 and 13.2: the design is authored at 16:9
/// and checked at 18:9 and 20:9.
enum AspectFrame {
  native('NATIVE', null),
  ratio16x9('16:9', 16 / 9),
  ratio18x9('18:9', 18 / 9),
  ratio20x9('20:9', 20 / 9);

  const AspectFrame(this.label, this.ratio);

  final String label;

  /// Width over height, or null to use the whole screen.
  final double? ratio;
}

/// What the developer can turn to see the design differently (DESIGN.md 13.2): the
/// livery, the mode, the tier, Motion or Parked, the driver's side, reduced motion,
/// slow motion and the aspect ratio.
///
/// The app reads these on top of its own state, and shows them as overridden, so
/// they are never mistaken for the real thing.
class DevSettings extends ChangeNotifier {
  DevSettings({
    this.livery = Liveries.ion,
    this.modeSetting = ModeSetting.auto,
  });

  Livery livery;
  ModeSetting modeSetting;

  /// A fidelity tier held by hand, or null to let the detector and governor choose.
  FidelityTier? tierPin;

  bool reduceMotion = false;
  DriverSide driverSide = DriverSide.right;
  DrivingOverride driving = DrivingOverride.follow;
  AspectFrame frame = AspectFrame.native;

  double _slowMotion = 1;

  /// How much slower time runs, 1 for normal: `timeDilation` (DESIGN.md 13.2).
  double get slowMotion => _slowMotion;

  /// Shows the frame timing graph.
  bool showFrameGraph = false;

  /// Whether anything is set away from its default, for the badge on the deck's
  /// button.
  bool get isOverridden =>
      livery.id != LiveryId.ion ||
      modeSetting != ModeSetting.auto ||
      tierPin != null ||
      reduceMotion ||
      driving != DrivingOverride.follow ||
      frame != AspectFrame.native ||
      _slowMotion != 1;

  void update(void Function(DevSettings settings) change) {
    change(this);
    notifyListeners();
  }

  set slowMotion(double value) {
    _slowMotion = value;
    timeDilation = value;
  }

  void reset() {
    livery = Liveries.ion;
    modeSetting = ModeSetting.auto;
    tierPin = null;
    reduceMotion = false;
    driverSide = DriverSide.right;
    driving = DrivingOverride.follow;
    frame = AspectFrame.native;
    slowMotion = 1;
    showFrameGraph = false;
    notifyListeners();
  }

  /// The mode to show for a car in [actual], with the override applied.
  DrivingMode effectiveDriving(DrivingMode actual) => driving.resolve(actual);
}
