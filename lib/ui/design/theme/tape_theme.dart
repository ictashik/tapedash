import 'package:flutter/widgets.dart';

import '../fidelity/fidelity_tier.dart';
import '../tokens/livery.dart';
import '../tokens/motion_tokens.dart';
import 'palette.dart';

/// What the design system needs to know to draw: the livery, the mode, the
/// fidelity tier, the driver's side and whether motion is reduced (DESIGN.md 13.1).
@immutable
class TapeThemeData {
  TapeThemeData({
    this.livery = Liveries.ion,
    this.mode = TapeMode.normal,
    this.tier = FidelityTier.balanced,
    this.driverSide = DriverSide.right,
    this.reduceMotion = false,
  }) : palette = TapePalette(livery: livery, mode: mode);

  final Livery livery;
  final TapeMode mode;
  final FidelityTier tier;
  final DriverSide driverSide;

  /// Garage, Display, Reduce motion; also the system's animation scale at 0
  /// (DESIGN.md 5.8).
  final bool reduceMotion;

  /// The livery's colours in this mode.
  final TapePalette palette;

  TierProfile get profile => tier.profile;

  /// [spec], or the same spring without overshoot when motion is reduced.
  SpringSpec spring(SpringSpec spec) =>
      reduceMotion ? spec.withoutOvershoot : spec;

  TapeThemeData copyWith({
    Livery? livery,
    TapeMode? mode,
    FidelityTier? tier,
    DriverSide? driverSide,
    bool? reduceMotion,
  }) => TapeThemeData(
    livery: livery ?? this.livery,
    mode: mode ?? this.mode,
    tier: tier ?? this.tier,
    driverSide: driverSide ?? this.driverSide,
    reduceMotion: reduceMotion ?? this.reduceMotion,
  );

  @override
  bool operator ==(Object other) =>
      other is TapeThemeData &&
      other.livery.id == livery.id &&
      other.livery.accentCore == livery.accentCore &&
      other.mode == mode &&
      other.tier == tier &&
      other.driverSide == driverSide &&
      other.reduceMotion == reduceMotion;

  @override
  int get hashCode => Object.hash(
    livery.id,
    livery.accentCore,
    mode,
    tier,
    driverSide,
    reduceMotion,
  );
}

/// Gives the widgets below it a [TapeThemeData].
class TapeTheme extends InheritedWidget {
  const TapeTheme({super.key, required this.data, required super.child});

  final TapeThemeData data;

  /// The theme in effect, and an error with a clear message if there is none.
  static TapeThemeData of(BuildContext context) {
    final theme = context.dependOnInheritedWidgetOfExactType<TapeTheme>();
    assert(theme != null, 'No TapeTheme above this widget');
    return theme!.data;
  }

  static TapeThemeData? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TapeTheme>()?.data;

  @override
  bool updateShouldNotify(TapeTheme oldWidget) => data != oldWidget.data;
}
