import '../core/clock.dart';
import '../core/observable.dart';

/// What the app has been doing to reach the adapter, a line at a time, kept in
/// memory and shown in Garage: when a link would not come up, which kind of socket
/// was tried, what status code the radio gave, which services the adapter listed.
///
/// A link that will not come up says nothing else, and a person in a car with a
/// phone in their hand cannot go and fetch a file. This is the same story the
/// session recording tells (a line starting `link`), but it needs no recording
/// switched on and no cable, and it is read on the phone itself.
///
/// It holds the last [capacity] lines and is lost when the app is closed. Nothing
/// in it leaves the phone: it is plain text about the radio, with the adapter's
/// Bluetooth address (which is the adapter's, not the person's) and no location.
class LinkDiary {
  LinkDiary({required this.clock, this.capacity = 300});

  final Clock clock;
  final int capacity;

  final ObservableValue<List<String>> _lines = ObservableValue(const []);

  /// The lines, oldest first.
  Observable<List<String>> get lines => _lines;

  /// Adds a line, stamped with the time of day.
  void add(String text) {
    final t = clock.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final line = '${two(t.hour)}:${two(t.minute)}:${two(t.second)}  $text';
    final next = [..._lines.value, line];
    _lines.value = next.length > capacity
        ? next.sublist(next.length - capacity)
        : next;
  }

  void clear() => _lines.value = const [];

  /// All of it as text, oldest first.
  String format() => _lines.value.join('\n');
}
