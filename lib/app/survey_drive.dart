import 'dart:async';

import '../core/clock.dart';
import '../core/observable.dart';
import '../core/scheduler.dart';
import '../obd/adapter_config.dart';
import '../obd/obd_session.dart' show AdapterMemory;
import '../obd/survey/survey_guide.dart';
import '../obd/survey/survey_runner.dart';
import '../obd/survey/survey_schedule.dart';
import '../obd/transport/recording_transport.dart';
import '../obd/transport/session_sink.dart';
import '../obd/transport/transport.dart';
import '../obd/transport_factory.dart';

/// Where a survey drive stands, for its screen.
enum SurveyStage {
  /// Not begun: the screen says what it will do.
  ready,

  /// Reading the car.
  running,

  /// Over, and saved if it could be.
  finished,
}

/// A survey drive (Garage → Survey drive): the user's own adapter, read as
/// thoroughly as it allows, with the whole conversation written down in a file
/// on the phone, so that it can be studied at a desk.
///
/// It takes the adapter over for as long as it runs, so the dashboard is not
/// running at the same time: the app stops the live drive first and builds it
/// again when this is closed. It writes only to the log, and only on the phone;
/// nothing is sent anywhere. It always records, since the log is the point.
class SurveyDrive {
  SurveyDrive({
    required this.adapter,
    required this.transports,
    required this.clock,
    required this.scheduler,
    required this.sink,
    this.memory,
    this.config = const SurveyConfig(),
    this.flushEvery = const Duration(seconds: 20),
    this.parkedFor = const Duration(seconds: 5),
    this.appVersion = '',
  });

  final AdapterConfig adapter;
  final TransportFactory transports;
  final Clock clock;
  final Scheduler scheduler;
  final SessionSink sink;
  final AdapterMemory? memory;
  final SurveyConfig config;

  /// How often the log is written to the phone while the survey runs, so that a
  /// phone that dies or an app that is killed still leaves the last good copy.
  final Duration flushEvery;

  /// How long the car has to have stood still before the survey can be ended
  /// from the screen: nothing is asked of the driver while the car moves.
  final Duration parkedFor;
  final String appVersion;

  final ObservableValue<SurveyStage> _stage = ObservableValue(
    SurveyStage.ready,
  );
  final ObservableValue<SurveyProgress> _progress = ObservableValue(
    const SurveyProgress(phase: SurveyPhase.connecting, elapsed: Duration.zero),
  );
  final ObservableValue<bool> _canFinish = ObservableValue(true);
  final ObservableValue<bool> _saveFailed = ObservableValue(false);

  /// The guided checks while parked. Made with the survey, so it is there to be
  /// watched from the start.
  late final SurveyGuide guide = SurveyGuide(
    scheduler: scheduler,
    onMark: _writeMark,
    onNote: (text) => _recorder?.note('survey $text'),
  );

  Transport? _transport;
  RecordingTransport? _recorder;
  SurveyRunner? _runner;
  ScheduledTask? _flush;
  String? _fileName;
  Duration? _stoppedSince;
  Future<void>? _completion;
  bool _disposed = false;
  void Function()? _progressListener;

  Observable<SurveyStage> get stage => _stage;

  Observable<SurveyProgress> get progress => _progress;

  /// Whether the survey can be ended from the screen: the car has stood still
  /// for [parkedFor], or it is not being read (off, or not begun).
  Observable<bool> get canFinish => _canFinish;

  /// Whether the last write to the phone failed.
  Observable<bool> get saveFailed => _saveFailed;

  /// The name the log is saved under, once begun.
  String? get fileName => _fileName;

  /// Under this a survey has not had much of a drive: the screen still asks for
  /// one, and does not yet offer the checks again if the first were gone through.
  static const Duration shortDrive = Duration(minutes: 15);

  /// The folder on the phone it is saved in, as `adb pull` would name it.
  static const String where =
      'Android/data/io.github.ictashik.tapedash/files/recordings';

  /// Begins. Does nothing if it has begun.
  void start() {
    if (_stage.value != SurveyStage.ready || _disposed) return;
    final now = clock.now().toUtc();
    _fileName = 'survey-${_stamp(now)}-${adapter.kind.name}.log';
    final transport = transports.create(adapter);
    _transport = transport;
    final recorder = RecordingTransport(
      transport,
      clock: clock,
      header: {
        'survey': '1',
        'app': 'tapedash $appVersion'.trim(),
        'adapter': adapter.displayName,
        'kind': adapter.kind.name,
        'address': adapter.address,
        'started': now.toIso8601String(),
      },
    );
    _recorder = recorder;
    final runner = SurveyRunner(
      transport: recorder,
      clock: clock,
      scheduler: scheduler,
      config: config,
      note: recorder.note,
      memory: memory,
    );
    _runner = runner;
    _progressListener = () => _onProgress(runner.progress.value);
    runner.progress.addListener(_progressListener!);
    _flush = scheduler.runEvery(flushEvery, () => unawaited(_save()));
    _stage.value = SurveyStage.running;
    runner.start();
  }

  void _onProgress(SurveyProgress p) {
    _progress.value = p;
    final now = clock.monotonic();
    final speed = p.speedKmh;
    if (speed == 0) {
      _stoppedSince ??= now;
    } else if (speed != null) {
      _stoppedSince = null;
    }
    final reading =
        p.phase == SurveyPhase.driving || p.phase == SurveyPhase.probing;
    final since = _stoppedSince;
    final parked = since != null && now - since >= parkedFor;
    _canFinish.value = !reading || parked;
    guide.update(
      ready: p.phase == SurveyPhase.driving && parked,
      moving: speed != null && speed > 0,
    );
    if (p.phase == SurveyPhase.finished || p.phase == SurveyPhase.failed) {
      unawaited(_complete());
    }
  }

  /// Writes into the log that [id] (`headlights`, `ac`...) was switched [on] or
  /// off now, in run [pass] of the checks, so that what it did to the battery
  /// voltage can be told later.
  void _writeMark(String id, bool on, int pass) {
    if (_stage.value != SurveyStage.running) return;
    _recorder?.note('survey mark id=$id state=${on ? 'on' : 'off'} pass=$pass');
  }

  /// Ends the survey and saves the log. Safe to call again.
  Future<void> finish() async {
    final runner = _runner;
    if (runner == null) return;
    // Anything the checks had switched on is written off before the end.
    guide.abort();
    runner.finish('stopped by the user');
    await _complete();
  }

  /// Saves, lets go of the adapter and marks the survey over. Every caller gets
  /// the same one, so that whoever asks last also waits for it to finish.
  Future<void> _complete() => _completion ??= _doComplete();

  Future<void> _doComplete() async {
    _flush?.cancel();
    _flush = null;
    await _save();
    await _release();
    _canFinish.value = true;
    if (!_disposed) _stage.value = SurveyStage.finished;
  }

  Future<void> _save() async {
    final recorder = _recorder;
    final name = _fileName;
    if (recorder == null || name == null) return;
    try {
      await sink.save(name, recorder.log.format());
      _saveFailed.value = false;
    } on Object {
      // A full or unwritable phone must not stop the survey; the next flush
      // tries again, and the screen says so.
      _saveFailed.value = true;
    }
  }

  Future<void> _release() async {
    final runner = _runner;
    if (runner != null) {
      if (_progressListener != null) {
        runner.progress.removeListener(_progressListener!);
      }
      runner.dispose();
    }
    // The recorder is only tidying its streams; nothing waits for that. What
    // does matter is that the adapter's link is closed before the dashboard
    // opens it again.
    unawaited(_recorder?.dispose());
    await _transport?.disconnect().catchError((Object _) {});
    _runner = null;
    _recorder = null;
    _transport = null;
  }

  /// Lets go of everything. The log is saved first if a survey was running.
  Future<void> dispose() async {
    if (_disposed) return;
    if (_stage.value == SurveyStage.running) {
      guide.abort();
      _runner?.finish('closed');
      await _complete();
    }
    _disposed = true;
    guide.dispose();
    _flush?.cancel();
    _stage.dispose();
    _progress.dispose();
    _canFinish.dispose();
    _saveFailed.dispose();
  }

  static String _stamp(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}${two(t.month)}${two(t.day)}-'
        '${two(t.hour)}${two(t.minute)}${two(t.second)}';
  }
}
