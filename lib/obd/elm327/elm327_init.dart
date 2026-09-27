import '../../core/scheduler.dart';
import '../pids/pid_discovery.dart';
import 'elm327_client.dart';
import 'elm327_failure.dart';

/// What to know before starting an adapter up.
class InitOptions {
  const InitOptions({
    this.knownProtocol,
    this.settle = const Duration(milliseconds: 300),
    this.retries = 2,
  });

  /// The protocol this adapter found last time, as `ATDPN` numbered it (`'6'`
  /// for 11-bit CAN at 500 kbaud). Setting it directly saves the adapter its
  /// search. If it turns out wrong, the search is done after all.
  final String? knownProtocol;

  /// The pause after connecting before the first command, since many clones
  /// are not ready for one straight away (CLAUDE.md 8.1).
  final Duration settle;

  /// How many times a command that got no usable answer is tried again.
  final int retries;
}

/// The adapter and the car, as start-up found them.
class AdapterInfo {
  const AdapterInfo({
    required this.banner,
    required this.protocolNumber,
    required this.supportedPids,
    required this.ecuCount,
    required this.retries,
    required this.warnings,
  });

  /// What `ATZ` printed, such as `ELM327 v1.5`. A clone may say anything.
  final String banner;

  /// The protocol the adapter is using, as a digit or letter (`'6'`), or null
  /// if it would not say.
  final String? protocolNumber;

  /// The Mode 01 PIDs the car answers.
  final Set<int> supportedPids;

  /// How many ECUs answered the first request for PIDs.
  final int ecuCount;

  /// How many commands had to be tried again during start-up: the more, the
  /// worse the adapter.
  final int retries;

  /// What did not go to plan and was worked around, in words.
  final List<String> warnings;

  /// Whether the car is on ISO 15765-4 CAN, protocols 6 to 9. Only there can
  /// several PIDs be asked for at once, and only there is the response-count
  /// digit safe to use (CLAUDE.md 8.2). If the adapter would not say, it is
  /// taken as not CAN, which is slower and safe.
  bool get isCan => protocolNumber != null && '6789'.contains(protocolNumber!);
}

enum InitStatus {
  /// The adapter is set up and the car answers.
  ready,

  /// The adapter is set up and the car does not answer: the ignition is off.
  waitingForIgnition,

  /// The adapter could not be started.
  failed,
}

/// Why start-up failed.
enum InitFailure {
  /// The adapter never answered, or answered nothing that made sense.
  noResponse,

  /// The adapter answered, and does not do what TapeDash needs.
  incompatible,

  /// The link went during start-up.
  linkLost,
}

class InitResult {
  const InitResult(this.status, {this.info, this.failure, this.detail});

  final InitStatus status;

  /// Set when [status] is ready; for waiting, it has no PIDs.
  final AdapterInfo? info;

  final InitFailure? failure;

  /// For the log, in words.
  final String? detail;

  bool get isReady => status == InitStatus.ready;

  @override
  String toString() =>
      'InitResult($status${failure == null ? '' : ', $failure'})';
}

/// Starts an ELM327 adapter up (CLAUDE.md 8.1): `ATZ`, `ATE0`, `ATL0`, `ATS0`,
/// `ATH0`, `ATAT1`, `ATSP0` (or the protocol found last time), then `0100`,
/// with a settle before it all and a retry, at most twice, of anything that
/// gets no usable answer.
///
/// It tolerates an adapter that will not switch off echo, linefeeds or spaces,
/// or that does not know adaptive timing, since the parser copes with all of
/// those, and says so in [AdapterInfo.warnings]. It does not tolerate one that
/// will not switch headers off, or will not take a protocol.
class Elm327Initializer {
  Elm327Initializer({
    required this.client,
    required this.scheduler,
    this.options = const InitOptions(),
  });

  final Elm327Client client;
  final Scheduler scheduler;
  final InitOptions options;

  late void Function(InitResult result) _done;
  bool _cancelled = false;
  bool _finished = false;
  ScheduledTask? _settleTask;

  String _banner = '';
  int _retries = 0;
  final List<String> _warnings = [];
  bool _usedKnownProtocol = false;
  bool _triedAuto = false;
  int _discoveryRetries = 0;
  bool _restarted = false;
  DiscoveryHandle? _discovery;

  /// Runs the whole start-up, and calls [done] once. With [probeOnly] the
  /// adapter is taken as already set up, and only the car is asked, for when
  /// the ignition was off and is being waited for.
  void run(void Function(InitResult result) done, {bool probeOnly = false}) {
    _done = done;
    if (probeOnly) {
      _discover();
    } else {
      _settleTask = scheduler.runAfter(options.settle, () => _reset(0));
    }
  }

  /// Stops without calling back.
  void cancel() {
    _cancelled = true;
    _settleTask?.cancel();
    _discovery?.cancel();
  }

  void _finish(InitResult result) {
    if (_cancelled || _finished) return;
    _finished = true;
    _done(result);
  }

  void _fail(InitFailure failure, String detail) =>
      _finish(InitResult(InitStatus.failed, failure: failure, detail: detail));

  // ---------------------------------------------------------------- ATZ

  void _reset(int attempt) {
    if (_cancelled) return;
    client.command('ATZ', (reply) {
      if (_cancelled) return;
      if (reply.failure == Elm327Failure.disconnected) {
        return _fail(InitFailure.linkLost, 'the link went during ATZ');
      }
      if (reply.ok && reply.lines.isNotEmpty) {
        _banner = reply.lines.last;
        _setUp(0);
      } else if (attempt < options.retries) {
        _retries++;
        _reset(attempt + 1);
      } else {
        _fail(InitFailure.noResponse, 'ATZ got no answer');
      }
    }, timeout: client.timing.resetTimeout);
  }

  // ----------------------------------------------- the settings, one by one

  /// The settings, and whether start-up cannot go on without each. Echo,
  /// linefeeds and spaces are things the parser copes with either way, and
  /// adaptive timing only makes things faster.
  static const List<(String, bool)> _settings = [
    ('ATE0', false),
    ('ATL0', false),
    ('ATS0', false),
    ('ATH0', true),
    ('ATAT1', false),
  ];

  void _setUp(int index) {
    if (_cancelled) return;
    if (index >= _settings.length) return _chooseProtocol();
    final (command, essential) = _settings[index];
    _expectOk(command, essential: essential, then: () => _setUp(index + 1));
  }

  void _chooseProtocol() {
    final known = options.knownProtocol;
    _usedKnownProtocol = known != null;
    _expectOk(
      known == null ? 'ATSP0' : 'ATSP$known',
      essential: true,
      then: _discover,
    );
  }

  /// Sends [command] and goes on to [then] once the adapter says OK. What is
  /// not OK is tried again, unless the adapter does not know the command; and
  /// if it never works, that is a failure if [essential] and a warning if not.
  void _expectOk(
    String command, {
    required bool essential,
    required void Function() then,
    int attempt = 0,
  }) {
    client.command(command, (reply) {
      if (_cancelled) return;
      if (reply.failure == Elm327Failure.disconnected) {
        return _fail(InitFailure.linkLost, 'the link went during $command');
      }
      final saidOk =
          reply.ok && reply.lines.any((l) => l.toUpperCase().contains('OK'));
      if (saidOk) return then();

      final unsupported = reply.failure == Elm327Failure.unknownCommand;
      if (!unsupported && attempt < options.retries) {
        _retries++;
        return _expectOk(
          command,
          essential: essential,
          then: then,
          attempt: attempt + 1,
        );
      }
      if (essential) {
        return _fail(
          unsupported ? InitFailure.incompatible : InitFailure.noResponse,
          '$command was ${unsupported ? 'not understood' : 'not answered'}',
        );
      }
      _warnings.add(
        '$command ${unsupported ? 'is not understood' : 'was not answered'}',
      );
      then();
    }, timeout: null);
  }

  // -------------------------------------------------------------- the car

  void _discover() {
    if (_cancelled) return;
    _discovery = PidDiscovery.run(client, (result) {
      if (_cancelled) return;
      final failure = result.failure;
      if (failure == null) {
        if (result.incomplete) _warnings.add('the PID search was cut short');
        return _learnProtocol(result);
      }

      switch (failure) {
        case Elm327Failure.disconnected:
          _fail(InitFailure.linkLost, 'the link went while asking the car');
        case Elm327Failure.unknownCommand:
          _fail(
            InitFailure.incompatible,
            'the adapter did not understand 0100',
          );
        case Elm327Failure.lowVoltageReset:
          // The adapter reset itself, and has forgotten every setting.
          if (!_restarted) {
            _restarted = true;
            _warnings.add('the adapter reset itself');
            _reset(0);
          } else {
            _fail(InitFailure.noResponse, 'the adapter keeps resetting');
          }
        case Elm327Failure.timeout ||
            Elm327Failure.garbled ||
            Elm327Failure.stopped ||
            Elm327Failure.bufferFull:
          // Nothing, or noise, or a command that was cut off: not the car
          // saying no. Try again.
          if (_discoveryRetries < options.retries) {
            _discoveryRetries++;
            _retries++;
            _discover();
          } else {
            _fail(InitFailure.noResponse, '0100 got no usable answer');
          }
        default:
          // The car said no. If the protocol was one remembered from before, it
          // may be the wrong one: let the adapter search after all.
          if (_usedKnownProtocol && !_triedAuto) {
            _triedAuto = true;
            _warnings.add('the remembered protocol did not work');
            _expectOk('ATSP0', essential: true, then: _discover);
          } else {
            _finish(
              InitResult(
                InitStatus.waitingForIgnition,
                info: _info(protocol: null, pids: const {}, ecus: 0),
                detail: 'the car did not answer: ${failure.name}',
              ),
            );
          }
      }
    }, firstTimeout: client.timing.searchTimeout);
  }

  void _learnProtocol(DiscoveryResult found) {
    client.command('ATDPN', (reply) {
      if (_cancelled) return;
      final number = reply.ok && reply.lines.isNotEmpty
          ? _protocolNumber(reply.lines.last)
          : null;
      if (number != null) return _ready(found, number);

      // Some clones have no ATDPN. ATDP describes it in words.
      client.command('ATDP', (reply) {
        if (_cancelled) return;
        final text = reply.ok && reply.lines.isNotEmpty
            ? reply.lines.last.toUpperCase()
            : '';
        String? guess;
        if (text.contains('15765')) guess = '6';
        if (guess == null) {
          _warnings.add('the adapter would not say which protocol it uses');
        }
        _ready(found, guess);
      });
    });
  }

  /// `A6` or `6` as `6`. Null if it is not a protocol number.
  static String? _protocolNumber(String line) {
    final text = line.trim().toUpperCase();
    final match = RegExp(r'^A?([0-9A-C])$').firstMatch(text);
    return match?.group(1);
  }

  void _ready(DiscoveryResult found, String? protocol) => _finish(
    InitResult(
      InitStatus.ready,
      info: _info(
        protocol: protocol,
        pids: found.supported,
        ecus: found.ecuCount,
      ),
    ),
  );

  AdapterInfo _info({
    required String? protocol,
    required Set<int> pids,
    required int ecus,
  }) => AdapterInfo(
    banner: _banner,
    protocolNumber: protocol,
    supportedPids: pids,
    ecuCount: ecus,
    retries: _retries,
    warnings: List.unmodifiable(_warnings),
  );
}
