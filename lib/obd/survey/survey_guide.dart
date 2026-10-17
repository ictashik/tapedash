import '../../core/observable.dart';
import '../../core/scheduler.dart';

/// One thing to ask of the person at a time during the parked checks of a survey
/// (docs/SURVEY.md): what to do, for how long, and what to write in the log when
/// it begins.
class GuideStep {
  const GuideStep({
    required this.title,
    required this.instruction,
    required this.seconds,
    this.marks = const [],
  });

  /// A few words, big on the screen: `Headlights on`.
  final String title;

  /// A sentence on what to do.
  final String instruction;

  /// How long it lasts if nobody skips it.
  final int seconds;

  /// What is switched on or off as this step begins: `(id, on)`. The log gets a
  /// mark for each, so the voltage can be read against it later.
  final List<(String, bool)> marks;
}

/// The parked checks: the engine running and the car standing, one electrical
/// load after another, each on for long enough to see the battery voltage and
/// the revs settle, then off. About three and a half minutes.
abstract final class GuideRoutine {
  static const List<GuideStep> parked = [
    GuideStep(
      title: 'Everything off',
      instruction:
          'Engine running, car standing, lights, A/C and wipers off. Hands and '
          'feet off the controls.',
      seconds: 15,
    ),
    GuideStep(
      title: 'Headlights on',
      instruction: 'Switch the headlights on (low beam).',
      seconds: 15,
      marks: [('headlights', true)],
    ),
    GuideStep(
      title: 'Headlights off',
      instruction: 'Switch them off.',
      seconds: 10,
      marks: [('headlights', false)],
    ),
    GuideStep(
      title: 'Blower low',
      instruction: 'Blower on, lowest speed. A/C off.',
      seconds: 12,
      marks: [('blower_low', true)],
    ),
    GuideStep(
      title: 'Blower high',
      instruction: 'Turn the blower to its highest speed.',
      seconds: 12,
      marks: [('blower_low', false), ('blower_high', true)],
    ),
    GuideStep(
      title: 'Blower off',
      instruction: 'Switch the blower off.',
      seconds: 10,
      marks: [('blower_high', false)],
    ),
    GuideStep(
      title: 'A/C on',
      instruction: 'Switch the A/C on, as you would on a hot day.',
      seconds: 25,
      marks: [('ac', true)],
    ),
    GuideStep(
      title: 'A/C off',
      instruction: 'Switch the A/C and the blower off.',
      seconds: 12,
      marks: [('ac', false)],
    ),
    GuideStep(
      title: 'Rear defogger on',
      instruction: 'Switch the rear defogger on.',
      seconds: 15,
      marks: [('defogger', true)],
    ),
    GuideStep(
      title: 'Rear defogger off',
      instruction: 'Switch it off.',
      seconds: 10,
      marks: [('defogger', false)],
    ),
    GuideStep(
      title: 'Wipers on',
      instruction: 'Spray the washer once, and put the wipers on fast.',
      seconds: 15,
      marks: [('wipers', true)],
    ),
    GuideStep(
      title: 'Wipers off',
      instruction: 'Switch the wipers off.',
      seconds: 10,
      marks: [('wipers', false)],
    ),
    GuideStep(
      title: 'Steering',
      instruction:
          'Turn the steering wheel slowly from lock to lock, twice, and a '
          'little faster once.',
      seconds: 20,
      marks: [('steering', true)],
    ),
    GuideStep(
      title: 'Hands off',
      instruction: 'Let go of the wheel, and keep it straight.',
      seconds: 10,
      marks: [('steering', false)],
    ),
    GuideStep(
      title: 'Gentle revs (optional)',
      instruction:
          'Only if you are comfortable with it: in P with the handbrake on, '
          'press the accelerator so the revs rise to about 2,000, hold for '
          'three seconds, let go. Three times. Not higher. Skip if unsure.',
      seconds: 30,
      marks: [('revs', true)],
    ),
    GuideStep(
      title: 'Settle',
      instruction: 'Feet off the pedals.',
      seconds: 10,
      marks: [('revs', false)],
    ),
  ];
}

/// Where the guide is.
class GuideState {
  const GuideState({
    this.ready = false,
    this.active = false,
    this.pass = 0,
    this.passesDone = 0,
    this.stepIndex = 0,
    this.stepCount = 0,
    this.step,
    this.remaining = 0,
    this.paused = false,
    this.message,
    this.lastIncomplete = false,
  });

  /// Whether the car is parked with the survey reading it: the checks can begin.
  final bool ready;

  /// Whether a run through the checks is going.
  final bool active;

  /// Which run it is, 1 or 2 (0 before the first).
  final int pass;

  /// How many runs are over, by finishing or by being given up (0 to 2).
  final int passesDone;

  /// The step now, counting from 0, and how many there are.
  final int stepIndex;
  final int stepCount;
  final GuideStep? step;

  /// Seconds left in the step.
  final int remaining;

  /// Held because the car is not being read (it went off).
  final bool paused;

  /// Something to say: why the checks stopped, for instance.
  final String? message;

  /// Whether the last run to end was given up, declined or stopped, and not
  /// gone through to the end.
  final bool lastIncomplete;

  /// Whether another run could be started now.
  bool get canBegin => ready && !active && passesDone < 2;
}

/// Leads the parked checks of a survey: tells the person what to switch on or
/// off, for how long, and writes each switch into the log as it asks for it.
///
/// It only runs while the car stands. If the car moves it stops that moment and
/// says to switch everything off; if the car is off (not being read) it waits.
/// It never speaks while the car is moving: the driving screen has no part in
/// it (CLAUDE.md 1.5).
class SurveyGuide {
  SurveyGuide({
    required this.scheduler,
    required this.onMark,
    required this.onNote,
    this.routine = GuideRoutine.parked,
  }) {
    _state = ObservableValue(const GuideState());
  }

  final Scheduler scheduler;

  /// Called as a step begins, for each switch it names.
  final void Function(String id, bool on, int pass) onMark;

  /// Called with a line for the log (`step pass=1 n=3 ...`).
  final void Function(String text) onNote;

  final List<GuideStep> routine;

  late final ObservableValue<GuideState> _state;
  ScheduledTask? _tick;

  bool _ready = false;
  bool _active = false;
  bool _paused = false;
  int _pass = 0;
  int _passesDone = 0;
  int _index = 0;
  int _remaining = 0;
  String? _message;
  bool _lastIncomplete = false;

  /// What is switched on, by the guide's own account, so that giving up halfway
  /// can write the offs.
  final Set<String> _on = {};

  Observable<GuideState> get state => _state;

  /// Tells the guide about the car: [ready] if it is parked and being read,
  /// [moving] if it has speed. Call it on every change.
  void update({required bool ready, required bool moving}) {
    _ready = ready;
    if (_active && moving) {
      _stop('The car moved, so the checks stopped. Switch everything off.');
      return;
    }
    if (_active) {
      final held = !ready;
      if (held != _paused) {
        _paused = held;
        _message = held ? 'The car is not answering. The checks wait.' : null;
        onNote('guide ${held ? 'paused' : 'resumed'}');
      }
    }
    _publish();
  }

  /// Starts a run through the checks. Does nothing if the car is not parked and
  /// read, or two runs are done.
  void begin() {
    if (!_state.value.canBegin) return;
    _active = true;
    _paused = false;
    _pass = _passesDone + 1;
    _index = 0;
    _message = null;
    onNote('guide begin pass=$_pass');
    _enter();
    _tick?.cancel();
    _tick = scheduler.runEvery(const Duration(seconds: 1), _onTick);
    _publish();
  }

  /// Leaves the step now, for the next.
  void skipStep() {
    if (!_active) return;
    onNote('guide skip pass=$_pass n=${_index + 1}');
    _next();
  }

  /// Gives the checks up (or, before they are begun, declines them).
  void skipAll() {
    if (_active) {
      _stop(null);
    } else if (_passesDone < 2) {
      _passesDone++;
      _lastIncomplete = true;
      onNote('guide declined pass=$_passesDone');
      _publish();
    }
  }

  /// Stops a run in progress, writing off whatever it had switched on, because
  /// the survey is ending. Does nothing if no run is going.
  void abort() {
    if (_active) _stop(null);
  }

  void _onTick() {
    if (!_active || _paused) return;
    if (--_remaining <= 0) _next();
    _publish();
  }

  void _next() {
    _index++;
    if (_index >= routine.length) {
      _finish();
      return;
    }
    _enter();
    _publish();
  }

  /// A step begins: its switches are written down.
  void _enter() {
    final step = routine[_index];
    _remaining = step.seconds;
    onNote(
      'guide step pass=$_pass n=${_index + 1}/${routine.length} '
      'title=${step.title.replaceAll(' ', '_')}',
    );
    for (final (id, on) in step.marks) {
      on ? _on.add(id) : _on.remove(id);
      onMark(id, on, _pass);
    }
  }

  void _finish() {
    _tick?.cancel();
    _tick = null;
    _active = false;
    _paused = false;
    _passesDone = _pass;
    _lastIncomplete = false;
    _message = null;
    onNote('guide done pass=$_pass');
    _publish();
  }

  /// Ends a run early. Anything it had switched on is marked off, so that the
  /// log never has a load left on that the person has been told to switch off.
  void _stop(String? message) {
    _tick?.cancel();
    _tick = null;
    for (final id in _on.toList()) {
      onMark(id, false, _pass);
    }
    _on.clear();
    _active = false;
    _paused = false;
    _passesDone = _pass;
    _lastIncomplete = true;
    _message = message;
    onNote('guide stopped pass=$_pass n=${_index + 1}');
    _publish();
  }

  void _publish() {
    _state.value = GuideState(
      ready: _ready,
      active: _active,
      pass: _pass,
      passesDone: _passesDone,
      stepIndex: _index,
      stepCount: routine.length,
      step: _active ? routine[_index] : null,
      remaining: _remaining,
      paused: _paused,
      message: _message,
      lastIncomplete: _lastIncomplete,
    );
  }

  void dispose() {
    _tick?.cancel();
    _tick = null;
    _state.dispose();
  }
}
