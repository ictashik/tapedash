import 'package:flutter/foundation.dart';

import '../../design/motion/numeral_source.dart';

/// A number that rolls up from 0 to [target] as [share] goes from 0 to 1: the
/// receipt's figures in the Debrief (DESIGN.md 7.5). With a share held at 1 it is
/// simply the number, rounded to the [decimals] it is shown with, so that a parked
/// figure rests on whole digits instead of part-way through a roll (DESIGN.md
/// 5.6: static numbers in parked views are set normally).
class RollUpSource extends ChangeNotifier implements NumeralSource {
  RollUpSource(double target, this.share, {this.decimals = 0})
    : _target = _round(target, decimals) {
    share.addListener(notifyListeners);
  }

  final ValueListenable<double> share;
  final int decimals;
  final double _target;

  double get target => _target;

  static double _round(double v, int decimals) {
    var scale = 1.0;
    for (var i = 0; i < decimals; i++) {
      scale *= 10;
    }
    return (v * scale).roundToDouble() / scale;
  }

  @override
  double get value => _target * share.value.clamp(0.0, 1.0);

  @override
  double get staleness => 0;

  @override
  bool get hasValue => true;

  @override
  void dispose() {
    share.removeListener(notifyListeners);
    super.dispose();
  }
}

/// A [ValueListenable] read through a window of another: 0 until [from], 1 from
/// [to], and [curve]'d between, over the Debrief's seconds. It is how each step of
/// the Debrief takes its own slice of one timeline.
class SliceShare extends ChangeNotifier implements ValueListenable<double> {
  SliceShare(this._seconds, this.from, this.to, this.curve) {
    _seconds.addListener(notifyListeners);
  }

  final ValueListenable<double> _seconds;
  final double from;
  final double to;
  final double Function(double t) curve;

  @override
  double get value {
    final s = _seconds.value;
    if (s <= from) return 0;
    if (s >= to) return 1;
    return curve((s - from) / (to - from));
  }

  @override
  void dispose() {
    _seconds.removeListener(notifyListeners);
    super.dispose();
  }
}
