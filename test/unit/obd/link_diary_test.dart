// The connection log Garage shows: lines stamped with the time of day, newest
// last, capped, and readable as text.
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/obd/link_diary.dart';

void main() {
  late FakeClock clock;
  late LinkDiary diary;

  setUp(() {
    clock = FakeClock(start: DateTime(2026, 10, 23, 8, 5, 9));
    diary = LinkDiary(clock: clock, capacity: 3);
  });

  test('a line is stamped with the time of day', () {
    diary.add('ble: attempt 1 of 3');
    expect(diary.lines.value, ['08:05:09  ble: attempt 1 of 3']);
    clock.advance(const Duration(seconds: 70));
    diary.add('ble: link status=133');
    expect(diary.lines.value.last, '08:06:19  ble: link status=133');
  });

  test('it keeps the last lines and drops the oldest', () {
    for (var i = 1; i <= 5; i++) {
      diary.add('line $i');
    }
    expect(diary.lines.value, hasLength(3));
    expect(diary.lines.value.first, endsWith('line 3'));
    expect(diary.lines.value.last, endsWith('line 5'));
  });

  test('listeners hear every line, and it reads as text', () {
    var heard = 0;
    diary.lines.addListener(() => heard++);
    diary.add('a');
    diary.add('b');
    expect(heard, 2);
    expect(diary.format(), '08:05:09  a\n08:05:09  b');
  });

  test('clear empties it', () {
    diary.add('a');
    diary.clear();
    expect(diary.lines.value, isEmpty);
    expect(diary.format(), '');
  });
}
