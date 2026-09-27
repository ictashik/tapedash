/// A value that says when it changes.
///
/// It has the shape of Flutter's `ValueListenable`, so a widget layer can wrap
/// one in a line or two, but it lives here so that the domain code, which has
/// no Flutter, can offer live values (CLAUDE.md 6). Listeners are called
/// synchronously, at the moment of the change, which is what lets a fake clock
/// drive a whole drive in one call.
abstract interface class Observable<T> {
  /// The current value.
  T get value;

  /// Calls [listener] after every change, until it is removed.
  void addListener(void Function() listener);

  void removeListener(void Function() listener);
}

/// An [Observable] that its owner sets.
class ObservableValue<T> implements Observable<T> {
  ObservableValue(this._value);

  T _value;
  final List<void Function()> _listeners = [];
  bool _disposed = false;

  @override
  T get value => _value;

  /// Sets the value, and tells the listeners if it is not equal to the old one.
  set value(T next) {
    if (_value == next) return;
    _value = next;
    notify();
  }

  /// Tells the listeners that the value has changed, when it is a mutable
  /// object changed in place, or when each new value counts even if equal.
  void notify() {
    // Listeners may add or remove listeners, or set the value again, while
    // they are called. A listener added now waits for the next change, and one
    // removed now is not called.
    for (final listener in List.of(_listeners)) {
      if (_listeners.contains(listener)) {
        listener();
      }
    }
  }

  @override
  void addListener(void Function() listener) {
    if (_disposed) {
      throw StateError('addListener on a disposed ObservableValue');
    }
    _listeners.add(listener);
  }

  @override
  void removeListener(void Function() listener) {
    _listeners.remove(listener);
  }

  /// How many listeners there are, so a test can check that none are left.
  int get listenerCount => _listeners.length;

  /// Drops every listener. The value can still be read.
  void dispose() {
    _disposed = true;
    _listeners.clear();
  }
}
