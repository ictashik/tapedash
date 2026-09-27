import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/observable.dart';

void main() {
  group('the value', () {
    test('starts as given, and is what was last set', () {
      final v = ObservableValue<int>(3);

      expect(v.value, 3);
      v.value = 5;
      expect(v.value, 5);
    });

    test('a listener is called when the value changes', () {
      final v = ObservableValue<int>(0);
      final seen = <int>[];
      v.addListener(() => seen.add(v.value));

      v
        ..value = 1
        ..value = 2;

      expect(seen, [1, 2]);
    });

    test('setting an equal value says nothing', () {
      final v = ObservableValue<int>(1);
      var calls = 0;
      v.addListener(() => calls++);

      v.value = 1;

      expect(calls, 0);
    });

    test('notify tells the listeners even when nothing is different', () {
      final list = ObservableValue<List<int>>([1]);
      var calls = 0;
      list.addListener(() => calls++);

      list.value.add(2);
      list.notify();
      list.notify();

      expect(calls, 2);
    });

    test('a listener is called at the moment of the change, not later', () {
      final v = ObservableValue<int>(0);
      var seenInside = -1;
      v.addListener(() => seenInside = v.value);

      v.value = 9;

      expect(seenInside, 9);
    });
  });

  group('listeners', () {
    test('every one is called, in the order they were added', () {
      final v = ObservableValue<int>(0);
      final order = <String>[];
      v
        ..addListener(() => order.add('a'))
        ..addListener(() => order.add('b'))
        ..addListener(() => order.add('c'));

      v.value = 1;

      expect(order, ['a', 'b', 'c']);
    });

    test('a removed listener is not called', () {
      final v = ObservableValue<int>(0);
      var calls = 0;
      void listener() => calls++;
      v.addListener(listener);
      v.value = 1;

      v.removeListener(listener);
      v.value = 2;

      expect(calls, 1);
    });

    test(
      'the same function added twice is called twice, and removed once at a time',
      () {
        final v = ObservableValue<int>(0);
        var calls = 0;
        void listener() => calls++;
        v
          ..addListener(listener)
          ..addListener(listener);

        v.value = 1;
        expect(calls, 2);

        v.removeListener(listener);
        v.value = 2;
        expect(calls, 3);
      },
    );

    test('a listener that removes itself does not stop the others', () {
      final v = ObservableValue<int>(0);
      final order = <String>[];
      late void Function() once;
      once = () {
        order.add('once');
        v.removeListener(once);
      };
      v
        ..addListener(once)
        ..addListener(() => order.add('other'));

      v.value = 1;
      v.value = 2;

      expect(order, ['once', 'other', 'other']);
    });

    test('a listener removed by an earlier one is not called', () {
      final v = ObservableValue<int>(0);
      final order = <String>[];
      late void Function() second;
      second = () => order.add('second');
      v
        ..addListener(() {
          order.add('first');
          v.removeListener(second);
        })
        ..addListener(second);

      v.value = 1;

      expect(order, ['first']);
    });

    test('a listener added during a change waits for the next one', () {
      final v = ObservableValue<int>(0);
      final order = <String>[];
      var added = false;
      v.addListener(() {
        order.add('first');
        if (!added) {
          added = true;
          v.addListener(() => order.add('late'));
        }
      });

      v.value = 1;
      expect(order, ['first']);

      v.value = 2;
      expect(order, ['first', 'first', 'late']);
    });

    test('a listener that sets the value again is called for that too', () {
      final v = ObservableValue<int>(0);
      final seen = <int>[];
      v.addListener(() {
        seen.add(v.value);
        if (v.value == 1) v.value = 2;
      });

      v.value = 1;

      expect(seen, [1, 2]);
      expect(v.value, 2);
    });

    test('listenerCount says how many there are', () {
      final v = ObservableValue<int>(0);
      void a() {}
      v
        ..addListener(a)
        ..addListener(() {});
      expect(v.listenerCount, 2);

      v.removeListener(a);
      expect(v.listenerCount, 1);
    });
  });

  group('disposing', () {
    test('drops the listeners and keeps the value readable', () {
      final v = ObservableValue<int>(4);
      var calls = 0;
      v.addListener(() => calls++);

      v.dispose();
      v.value = 5;

      expect(calls, 0);
      expect(v.value, 5);
      expect(v.listenerCount, 0);
    });

    test('adding a listener afterwards is a mistake', () {
      final v = ObservableValue<int>(0)..dispose();

      expect(() => v.addListener(() {}), throwsStateError);
    });

    test('removing a listener afterwards is harmless', () {
      final v = ObservableValue<int>(0)..dispose();

      v.removeListener(() {});
    });
  });

  test('it can be used through the read-only interface', () {
    final owner = ObservableValue<String>('a');
    final Observable<String> view = owner;
    final seen = <String>[];
    view.addListener(() => seen.add(view.value));

    owner.value = 'b';

    expect(seen, ['b']);
  });
}
