import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../motion/numeral_source.dart';

/// Makes the rolling numerals below it come to rest on a whole digit as [share]
/// rises to 1 (DESIGN.md 5.6: "static numbers in parked views are set normally,
/// without rolling").
///
/// A value that stops at 7.4 rupees would rest with its digit part-way through a
/// roll, and a parked face is looked at for as long as the car stands. With this
/// above them, the numerals glide to the value rounded to the digits they show as
/// the car parks, and back to the live value as it moves off. Nothing else about
/// them changes. The Motion look is untouched: live numerals roll as they always
/// did.
class NumeralSettle extends InheritedWidget {
  const NumeralSettle({super.key, required this.share, required super.child});

  /// 0 while the numerals are live and 1 when they are at rest, usually the
  /// screen's parked share.
  final ValueListenable<double> share;

  static NumeralSettle? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<NumeralSettle>();

  @override
  bool updateShouldNotify(NumeralSettle oldWidget) =>
      !identical(oldWidget.share, share);
}

/// A [NumeralSource] that reads [source], moved towards its value rounded to
/// [decimals] places by [share].
class SettledSource extends ChangeNotifier implements NumeralSource {
  SettledSource({
    required this.source,
    required this.share,
    required this.decimals,
  }) {
    source.addListener(notifyListeners);
    share.addListener(notifyListeners);
  }

  final NumeralSource source;
  final ValueListenable<double> share;
  final int decimals;

  @override
  double get value {
    final raw = source.value;
    final s = share.value.clamp(0.0, 1.0);
    if (s <= 0 || raw.isNaN || raw.isInfinite) return raw;
    var scale = 1.0;
    for (var i = 0; i < decimals; i++) {
      scale *= 10;
    }
    final settled = (raw * scale).round() / scale;
    return raw + (settled - raw) * s;
  }

  @override
  double get staleness => source.staleness;

  @override
  bool get hasValue => source.hasValue;

  @override
  void dispose() {
    source.removeListener(notifyListeners);
    share.removeListener(notifyListeners);
    super.dispose();
  }
}
