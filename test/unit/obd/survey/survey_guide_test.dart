import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/obd/survey/survey_guide.dart';

void main() {
  late FakeClock clock;
  late SurveyGuide guide;
  late List<(String, bool, int)> marks;
  late List<String> notes;

  setUp(() {
    clock = FakeClock();
    marks = [];
    notes = [];
    guide = SurveyGuide(
      scheduler: clock,
      onMark: (id, on, pass) => marks.add((id, on, pass)),
      onNote: notes.add,
    );
  });

  tearDown(() => guide.dispose());

  GuideState state() => guide.state.value;
  void run(int seconds) => clock.advance(Duration(seconds: seconds));
  void parked() => guide.update(ready: true, moving: false);

  int routineSeconds() =>
      GuideRoutine.parked.fold(0, (sum, s) => sum + s.seconds);

  group('the routine', () {
    test('is a few minutes, and each load is switched on and then off', () {
      expect(routineSeconds(), inInclusiveRange(180, 300));
      final on = <String>{};
      for (final step in GuideRoutine.parked) {
        for (final (id, isOn) in step.marks) {
          isOn ? on.add(id) : on.remove(id);
        }
      }
      expect(on, isEmpty, reason: 'nothing is left on at the end');
    });

    test('names every load the electrical page wants', () {
      final ids = {
        for (final s in GuideRoutine.parked)
          for (final (id, _) in s.marks) id,
      };
      expect(
        ids,
        containsAll([
          'headlights',
          'blower_low',
          'blower_high',
          'ac',
          'defogger',
          'wipers',
          'steering',
          'revs',
        ]),
      );
    });

    test('every step says what to do', () {
      for (final s in GuideRoutine.parked) {
        expect(s.title, isNotEmpty);
        expect(s.instruction.length, greaterThan(10));
        expect(s.seconds, greaterThan(0));
      }
    });
  });

  group('before it begins', () {
    test('it cannot begin until the car is parked and read', () {
      guide.begin();
      expect(state().active, isFalse);

      guide.update(ready: false, moving: false);
      guide.begin();
      expect(state().active, isFalse);

      parked();
      expect(state().canBegin, isTrue);
    });
  });

  group('a run', () {
    test('writes each switch as its step begins, in order, with the pass', () {
      parked();
      guide.begin();
      run(routineSeconds() + 5);

      expect(state().active, isFalse);
      expect(state().passesDone, 1);
      expect(marks.first, ('headlights', true, 1));
      expect(marks.map((m) => m.$1).toList().indexOf('ac'), greaterThan(0));
      // Every on has its off, and the offs come after.
      for (final id in marks.map((m) => m.$1).toSet()) {
        final mine = marks.where((m) => m.$1 == id).toList();
        expect(mine.where((m) => m.$2), hasLength(1), reason: id);
        expect(mine.where((m) => !m.$2), hasLength(1), reason: id);
        expect(mine.first.$2, isTrue, reason: id);
      }
      expect(marks.every((m) => m.$3 == 1), isTrue);
    });

    test('moves on by itself when the time is up', () {
      parked();
      guide.begin();
      expect(state().stepIndex, 0);

      run(GuideRoutine.parked[0].seconds);
      expect(state().stepIndex, 1);
      expect(state().step!.title, 'Headlights on');
      expect(state().remaining, GuideRoutine.parked[1].seconds);
    });

    test('counts down a second at a time', () {
      parked();
      guide.begin();
      final first = state().remaining;

      run(3);

      expect(state().remaining, first - 3);
    });

    test('a step can be skipped: the next begins at once', () {
      parked();
      guide.begin();

      guide.skipStep();

      expect(state().stepIndex, 1);
      expect(marks.single, ('headlights', true, 1));
    });

    test('says what it is doing in the log', () {
      parked();
      guide.begin();
      run(20);

      expect(notes.first, 'guide begin pass=1');
      expect(notes.any((n) => n.startsWith('guide step pass=1 n=1/')), isTrue);
      expect(notes.any((n) => n.contains('title=Headlights_on')), isTrue);
    });

    test('a second run is pass two, and then there are no more', () {
      parked();
      guide.begin();
      run(routineSeconds() + 2);
      guide.begin();
      expect(state().pass, 2);
      run(routineSeconds() + 2);

      expect(state().passesDone, 2);
      expect(marks.where((m) => m.$3 == 2), isNotEmpty);
      guide.begin();
      expect(state().active, isFalse);
      expect(state().canBegin, isFalse);
    });
  });

  group('giving up', () {
    test('stopping part way writes off whatever is on', () {
      parked();
      guide.begin();
      // Into the A/C step.
      var t = 0;
      for (final s in GuideRoutine.parked) {
        if (s.title == 'A/C on') break;
        t += s.seconds;
      }
      run(t + 5);
      expect(marks.last, ('ac', true, 1));

      guide.skipAll();

      expect(marks.last, ('ac', false, 1));
      expect(state().active, isFalse);
      expect(state().passesDone, 1);
    });

    test('declining before beginning counts the run as done', () {
      parked();

      guide.skipAll();

      expect(state().passesDone, 1);
      expect(state().canBegin, isTrue, reason: 'the second is still open');
      expect(marks, isEmpty);
    });

    test(
      'abort stops a run for the survey ending, and does nothing otherwise',
      () {
        parked();
        guide.abort();
        expect(state().passesDone, 0);

        guide.begin();
        run(20);
        guide.abort();
        expect(state().active, isFalse);
        expect(marks.where((m) => !m.$2), isNotEmpty);
      },
    );
  });

  group('the car', () {
    test('moving stops it at once, with a message', () {
      parked();
      guide.begin();
      run(20);

      guide.update(ready: false, moving: true);

      expect(state().active, isFalse);
      expect(state().message, contains('Switch everything off'));
      expect(marks.where((m) => m.$2).length, marks.where((m) => !m.$2).length);
    });

    test('not being read holds it, and it carries on when it is back', () {
      parked();
      guide.begin();
      run(5);
      final left = state().remaining;

      guide.update(ready: false, moving: false);
      run(30);
      expect(state().paused, isTrue);
      expect(state().remaining, left, reason: 'the time does not run');

      parked();
      expect(state().paused, isFalse);
      run(2);
      expect(state().remaining, left - 2);
    });

    test('nothing is asked once it has stopped', () {
      parked();
      guide.begin();
      guide.update(ready: false, moving: true);
      final n = notes.length;

      run(60);

      expect(notes.length, n);
      expect(state().step, isNull);
    });
  });
}
