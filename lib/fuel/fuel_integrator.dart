import 'fuel_estimator.dart';

/// A stretch of fuel burnt between two estimates.
class FuelIncrement {
  const FuelIncrement({
    required this.litres,
    required this.from,
    required this.to,
    required this.flow,
    this.filledGap = false,
  });

  /// Litres burnt, before calibration.
  final double litres;
  final Duration from;
  final Duration to;

  /// The estimate at the end of the stretch.
  final FuelFlow flow;

  /// The stretch was longer than a normal gap between estimates (the adapter
  /// missed a beat), and was filled with the average of the two rates on either
  /// side of it.
  final bool filledGap;

  Duration get length => to - from;
}

/// Adds up litres from a stream of litres-an-hour estimates (CLAUDE.md 8.6).
///
/// Between two estimates the rate is taken as the average of the two, which
/// suits a rate sampled about once a second. A stretch with no estimate for
/// more than [maxGap] (an adapter that dropped, a car that stopped answering)
/// is not integrated at all: burning nothing is a smaller error than making up
/// a long run of fuel, and a reconnect never brings a spike.
class FuelIntegrator {
  FuelIntegrator({
    this.maxGap = const Duration(seconds: 30),
    this.normalGap = const Duration(seconds: 3),
  });

  final Duration maxGap;

  /// A stretch longer than this is reported as a filled gap.
  final Duration normalGap;

  FuelFlow? _last;
  double _litres = 0;

  /// Litres burnt so far, before calibration.
  double get litres => _litres;

  /// The last estimate added.
  FuelFlow? get last => _last;

  /// Adds an estimate, and returns the stretch it closes: null for the first,
  /// or when the estimate is not after the last.
  FuelIncrement? add(FuelFlow flow) {
    final previous = _last;
    _last = flow;
    if (previous == null) return null;
    final dt = flow.at - previous.at;
    if (dt <= Duration.zero) {
      _last = previous;
      return null;
    }
    if (dt > maxGap) {
      return FuelIncrement(
        litres: 0,
        from: previous.at,
        to: flow.at,
        flow: flow,
        filledGap: true,
      );
    }
    final litres =
        (previous.litresPerHour + flow.litresPerHour) /
        2 *
        (dt.inMicroseconds / 1e6) /
        3600;
    _litres += litres;
    return FuelIncrement(
      litres: litres,
      from: previous.at,
      to: flow.at,
      flow: flow,
      filledGap: dt > normalGap,
    );
  }

  /// Forgets everything: a new trip.
  void reset() {
    _last = null;
    _litres = 0;
  }

  /// Forgets the last estimate but keeps the total, so that the time between it
  /// and the next (an engine that was off) is not counted.
  void breakStretch() => _last = null;
}
