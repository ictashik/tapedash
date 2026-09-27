import 'package:flutter/foundation.dart';
import 'package:tapedash/ui/design/motion/numeral_source.dart';

/// A number a test moves by hand, and counts the listeners of.
class ManualNumber extends ChangeNotifier implements NumeralSource {
  ManualNumber(this._value, {this.has = true});

  double _value;
  double _staleness = 0;
  bool has;
  int listeners = 0;

  bool get isListened => listeners > 0;

  @override
  void addListener(VoidCallback listener) {
    listeners++;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    listeners--;
    super.removeListener(listener);
  }

  @override
  double get value => _value;
  set value(double v) {
    _value = v;
    notifyListeners();
  }

  @override
  double get staleness => _staleness;
  set staleness(double v) {
    _staleness = v;
    notifyListeners();
  }

  @override
  bool get hasValue => has;
}
