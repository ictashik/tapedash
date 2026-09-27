import 'package:flutter/foundation.dart';

import '../../../core/observable.dart';

/// A [ValueListenable] view of a domain [Observable], for `ValueListenableBuilder`
/// and for painters' `repaint:`.
///
/// The domain layers are pure Dart and have their own `Observable`, with the shape
/// of `ValueListenable` (CLAUDE.md 6). This is the line or two that joins them to
/// Flutter. It is for discrete state: the mode, the connection. Live values go
/// through a `SmoothedSignal`, and never rebuild a widget (DESIGN.md 9.3).
class ObservableListenable<T> extends ChangeNotifier
    implements ValueListenable<T> {
  ObservableListenable(this._source) {
    _source.addListener(notifyListeners);
  }

  final Observable<T> _source;

  @override
  T get value => _source.value;

  @override
  void dispose() {
    _source.removeListener(notifyListeners);
    super.dispose();
  }
}
