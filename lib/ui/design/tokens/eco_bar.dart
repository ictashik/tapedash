/// The eco bar's geometry (DESIGN.md 6.7).
abstract final class TapeEcoBar {
  static const double widthShareOfWidth = 0.36;
  static const double heightShareOfHeight = 0.03;

  /// The puck travels over this much of the average, either side.
  static const double travelShareOfAverage = 0.5;

  /// The colour ramp's stops, as a share of the travel (-1 far left/thirstier
  /// to 1 far right/efficient): critical, caution, centre, accent.
  static const double criticalStop = -1;
  static const double cautionStop = -0.5;
  static const double centreStop = 0;
  static const double accentStop = 1;

  /// The puck's diameter, as a share of the bar's height.
  static const double puckDiameterShareOfHeight = 2.2;
}
