import 'dart:async';

import '../core/clock.dart';
import '../core/observable.dart';
import '../core/scheduler.dart';
import '../vehicle/sensor.dart';
import '../vehicle/vehicle_state.dart';
import 'dtc/dtc_service.dart';
import 'elm327/elm327_client.dart';
import 'elm327/elm327_init.dart';
import 'poller.dart';
import 'transport/transport.dart';

/// Where the connection to the car stands (DESIGN.md 7.12).
enum ConnectionStatus {
  /// Not started.
  stopped,

  /// Looking for the adapter and starting it up: never yet connected.
  searching,

  /// The adapter is there and set up, and the car does not answer: the ignition
  /// is off.
  waitingForIgnition,

  /// Polling, and the car answers.
  connected,

  /// The link was up and has gone. Values freeze, and it is trying again.
  lost,
}

/// Why the session cannot get on, when there is something to say.
enum ConnectionProblem {
  /// The adapter is there and does not do what TapeDash needs.
  incompatibleAdapter,

  /// The adapter is there and says nothing.
  adapterSilent,
}

/// The adapter's memory of a protocol between runs (CLAUDE.md 8.1): the
/// detected protocol is set directly next time.
abstract interface class AdapterMemory {
  String? get protocol;
  set protocol(String? value);
}

/// An [AdapterMemory] that forgets when the program ends, for tests.
class InMemoryAdapterMemory implements AdapterMemory {
  InMemoryAdapterMemory([this.protocol]);

  @override
  String? protocol;
}

/// The numbers behind the session.
class SessionConfig {
  const SessionConfig({
    this.firstRetry = const Duration(seconds: 1),
    this.longestRetry = const Duration(seconds: 10),
    this.probeInterval = const Duration(seconds: 1),
    this.compatibilityAfterRetries = 3,
    this.settle = const Duration(milliseconds: 300),
    this.poll = const PollConfig(),
  });

  /// The wait before the first reconnection, doubling to [longestRetry].
  final Duration firstRetry;
  final Duration longestRetry;

  /// How often to ask the car whether the ignition is on, while it is off.
  final Duration probeInterval;

  /// This many retries during start-up put the poller in compatibility mode.
  final int compatibilityAfterRetries;

  /// The pause after connecting before the first command.
  final Duration settle;

  final PollConfig poll;
}

/// A claim on PIDs being polled that outlasts a reconnection.
class SessionDemand {
  SessionDemand._(this._session, this._tiers);

  final ObdSession _session;
  final Map<int, PollTier> _tiers;
  PollDemand? _live;
  bool _released = false;

  /// Stops asking for these PIDs.
  void release() {
    if (_released) return;
    _released = true;
    _live?.release();
    _live = null;
    _session._demands.remove(this);
  }
}

/// The whole path from the phone to the car (CLAUDE.md 6): it connects, starts
/// the adapter up, finds what the car supports, polls it into a
/// [VehicleState], and keeps all that going through a dropped link, an
/// adapter that stops answering and the ignition going off and on.
///
/// It works in callbacks and never awaits, so on a fake clock a whole drive runs
/// inside one `advance`.
///
/// What it does when things go wrong:
///  - The link drops: the status is [ConnectionStatus.lost], the values hold and
///    go stale, and it reconnects after 1 s, 2 s, 4 s, 8 s and then every 10 s,
///    starting the adapter up again each time.
///  - The car stops answering: the ignition is taken as off, polling stops and it
///    asks the car every second whether it is back.
///  - The adapter stops answering, or answers only in noise: the link is closed
///    and opened again.
///  - The adapter is not one TapeDash can use: it says so through [problem] and
///    stops trying.
class ObdSession {
  ObdSession({
    required this.transport,
    required this.scheduler,
    required this.clock,
    required this.vehicle,
    AdapterMemory? memory,
    this.config = const SessionConfig(),
  }) : memory = memory ?? InMemoryAdapterMemory() {
    client = Elm327Client(
      transport: transport,
      scheduler: scheduler,
      clock: clock,
    );
    _stateSubscription = transport.state.listen(_onTransportState);
  }

  final Transport transport;
  final Scheduler scheduler;
  final Clock clock;
  final VehicleState vehicle;
  final AdapterMemory memory;
  final SessionConfig config;

  /// The conversation with the adapter.
  late final Elm327Client client;

  final ObservableValue<ConnectionStatus> _status = ObservableValue(
    ConnectionStatus.stopped,
  );
  final ObservableValue<ConnectionProblem?> _problem = ObservableValue(null);
  final ObservableValue<AdapterInfo?> _adapterInfo = ObservableValue(null);
  final ObservableValue<double> _pollRate = ObservableValue(0);
  final ObservableValue<PollHealth> _pollHealth = ObservableValue(
    PollHealth.ok,
  );

  final Set<SessionDemand> _demands = {};

  // Cancellable listeners on the transport, and on the current poller.
  StreamSubscription<TransportState>? _stateSubscription;
  Poller? _poller;
  DtcService? _dtc;
  Elm327Initializer? _initializer;
  ScheduledTask? _retryTask;
  ScheduledTask? _probeTask;

  bool _running = false;

  /// Set when there is no point trying again: the adapter is not one that can be
  /// used.
  bool _halted = false;
  bool _everConnected = false;
  bool _linkUp = false;
  bool _connecting = false;
  Duration _retryDelay = Duration.zero;
  int _silentAdapterRuns = 0;
  int _reconnects = 0;

  void Function()? _pollHealthListener;
  void Function()? _pollRateListener;

  /// Where the connection stands.
  Observable<ConnectionStatus> get status => _status;

  /// What is wrong, if something the user might act on is.
  Observable<ConnectionProblem?> get problem => _problem;

  /// What start-up found: the adapter, the protocol, the PIDs. Null until then.
  Observable<AdapterInfo?> get adapterInfo => _adapterInfo;

  /// How often the fast tier is being read, for the diagnostics.
  Observable<double> get pollRate => _pollRate;

  /// How the polling is going.
  Observable<PollHealth> get pollHealth => _pollHealth;

  /// The current poller, or null while there is none.
  Poller? get poller => _poller;

  /// Fault codes, once the car is connected.
  DtcService? get dtc => _dtc;

  /// How many times the link has been opened again after it was lost.
  int get reconnects => _reconnects;

  bool get isRunning => _running;

  /// Wants [tiers] polled, each PID at its tier, until released, through any
  /// number of reconnections.
  SessionDemand demand(Map<int, PollTier> tiers) {
    final d = SessionDemand._(this, Map.of(tiers));
    _demands.add(d);
    final poller = _poller;
    if (poller != null) d._live = poller.demand(d._tiers);
    return d;
  }

  /// Starts connecting.
  void start() {
    if (_running) return;
    _running = true;
    _halted = false;
    _problem.value = null;
    _status.value = _everConnected
        ? ConnectionStatus.lost
        : ConnectionStatus.searching;
    _retryDelay = Duration.zero;
    if (transport.currentState.isConnected) {
      // Already there: no state change is coming to say so.
      _linkUp = true;
      _onLinkUp();
    } else {
      _connect();
    }
  }

  /// Stops everything and closes the link.
  void stop() {
    if (!_running) return;
    _running = false;
    _cancelWork();
    _retryTask?.cancel();
    _retryTask = null;
    _linkUp = false;
    _connecting = false;
    _status.value = ConnectionStatus.stopped;
    vehicle.setIgnition(IgnitionState.unknown);
    transport.disconnect().catchError((Object _) {});
  }

  // ---------------------------------------------------------------- the link

  void _connect() {
    if (!_running || _connecting || _linkUp) return;
    _connecting = true;
    // The outcome arrives as a state change; the future is only handled so that
    // a failure is not left unhandled.
    transport.connect().then((_) {}, onError: (Object _) {});
  }

  void _onTransportState(TransportState state) {
    if (!_running) return;
    switch (state.status) {
      case TransportStatus.connecting:
        break;
      case TransportStatus.connected:
        _connecting = false;
        if (!_linkUp) {
          _linkUp = true;
          _onLinkUp();
        }
      case TransportStatus.disconnected:
        _connecting = false;
        _linkDown();
    }
  }

  void _linkDown() {
    _linkUp = false;
    _cancelWork();
    if (!_running) return;
    vehicle.setIgnition(IgnitionState.unknown);
    if (_everConnected) _status.value = ConnectionStatus.lost;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (!_running || _halted || _retryTask != null) return;
    _retryDelay = _retryDelay == Duration.zero
        ? config.firstRetry
        : _min(_retryDelay * 2, config.longestRetry);
    _retryTask = scheduler.runAfter(_retryDelay, () {
      _retryTask = null;
      if (_everConnected) _reconnects++;
      _connect();
    });
  }

  static Duration _min(Duration a, Duration b) => a < b ? a : b;

  /// Ends anything in progress on the link: start-up, polling, probing.
  void _cancelWork() {
    _initializer?.cancel();
    _initializer = null;
    _probeTask?.cancel();
    _probeTask = null;
    _stopPoller();
  }

  // ------------------------------------------------------------- start-up

  void _onLinkUp() {
    _initializer = Elm327Initializer(
      client: client,
      scheduler: scheduler,
      options: InitOptions(
        knownProtocol: memory.protocol,
        settle: config.settle,
      ),
    )..run(_onInitDone);
  }

  void _onInitDone(InitResult result) {
    _initializer = null;
    if (!_running || !_linkUp) return;
    switch (result.status) {
      case InitStatus.ready:
        _silentAdapterRuns = 0;
        _retryDelay = Duration.zero;
        _problem.value = null;
        _onReady(result.info!);
      case InitStatus.waitingForIgnition:
        _silentAdapterRuns = 0;
        _retryDelay = Duration.zero;
        _adapterInfo.value = result.info;
        _waitForIgnition();
      case InitStatus.failed:
        switch (result.failure) {
          case InitFailure.linkLost:
            // The transport's own state change handles it.
            break;
          case InitFailure.incompatible:
            // Nothing will change by trying again.
            _halted = true;
            _problem.value = ConnectionProblem.incompatibleAdapter;
            _closeLink(retry: false);
          case InitFailure.noResponse || null:
            if (++_silentAdapterRuns >= 3) {
              _problem.value = ConnectionProblem.adapterSilent;
            }
            _closeLink(retry: true);
        }
    }
  }

  /// Closes the link on purpose, and opens it again unless [retry] is false.
  void _closeLink({required bool retry}) {
    _cancelWork();
    _linkUp = false;
    _connecting = false;
    if (retry) _scheduleReconnect();
    transport.disconnect().catchError((Object _) {});
  }

  // ---------------------------------------------------------- when it works

  void _onReady(AdapterInfo info) {
    _everConnected = true;
    _adapterInfo.value = info;
    final protocol = info.protocolNumber;
    if (protocol != null && protocol != memory.protocol) {
      memory.protocol = protocol;
    }

    final poller = Poller(
      client: client,
      scheduler: scheduler,
      clock: clock,
      supported: info.supportedPids,
      isCan: info.isCan,
      config: config.poll,
      onReading: (r) => vehicle.ingest(
        r.pid.sensor,
        r.value,
        at: r.at,
        receivedAt: r.receivedAt,
      ),
    );
    _poller = poller;
    if (info.retries >= config.compatibilityAfterRetries) {
      poller.compatibilityMode = true;
    }
    _dtc = DtcService(
      client: client,
      scheduler: scheduler,
      isCan: info.isCan,
      isStationary: () {
        final speed = vehicle.speed.value;
        return speed != null &&
            !vehicle.isStale(Sensor.speed) &&
            speed.value == 0;
      },
    );

    _pollHealthListener = () => _onPollHealth(poller.health.value);
    _pollRateListener = () => _pollRate.value = poller.cycleRate.value;
    poller.health.addListener(_pollHealthListener!);
    poller.cycleRate.addListener(_pollRateListener!);

    // The standard tiers for what the car has, then whatever else is wanted.
    poller.demand(Poller.standardTiers(info.supportedPids));
    for (final d in _demands) {
      d._live = poller.demand(d._tiers);
    }
    poller.start();

    _pollHealth.value = PollHealth.ok;
    vehicle.setIgnition(IgnitionState.on);
    _status.value = ConnectionStatus.connected;
  }

  void _onPollHealth(PollHealth health) {
    _pollHealth.value = health;
    if (!_running || !_linkUp) return;
    switch (health) {
      case PollHealth.ok:
        break;
      case PollHealth.ecuSilent:
        // The ignition went off.
        _stopPoller();
        _waitForIgnition();
      case PollHealth.adapterFailing:
        // The adapter has stopped making sense: start the link again.
        _closeLink(retry: true);
    }
  }

  void _stopPoller() {
    final poller = _poller;
    if (poller == null) return;
    if (_pollHealthListener != null) {
      poller.health.removeListener(_pollHealthListener!);
    }
    if (_pollRateListener != null) {
      poller.cycleRate.removeListener(_pollRateListener!);
    }
    poller.stop();
    for (final d in _demands) {
      d._live = null;
    }
    _poller = null;
    _dtc = null;
    _pollHealthListener = null;
    _pollRateListener = null;
  }

  // ------------------------------------------------------ waiting for the car

  void _waitForIgnition() {
    _status.value = ConnectionStatus.waitingForIgnition;
    vehicle.setIgnition(IgnitionState.off);
    _probeLater();
  }

  void _probeLater() {
    _probeTask?.cancel();
    _probeTask = scheduler.runAfter(config.probeInterval, _probe);
  }

  /// Asks the car whether it is there, without starting the adapter up again.
  void _probe() {
    _probeTask = null;
    if (!_running || !_linkUp) return;
    _initializer =
        Elm327Initializer(
          client: client,
          scheduler: scheduler,
          options: InitOptions(knownProtocol: memory.protocol),
        )..run((result) {
          _initializer = null;
          if (!_running || !_linkUp) return;
          switch (result.status) {
            case InitStatus.ready:
              _onReady(result.info!);
            case InitStatus.waitingForIgnition:
              _probeLater();
            case InitStatus.failed:
              if (result.failure == InitFailure.linkLost) return;
              // The adapter went quiet while it waited.
              _closeLink(retry: true);
          }
        }, probeOnly: true);
  }

  /// Stops the session and lets go of everything.
  void dispose() {
    stop();
    client.dispose();
    unawaited(_stateSubscription?.cancel());
    _status.dispose();
    _problem.dispose();
    _adapterInfo.dispose();
    _pollRate.dispose();
    _pollHealth.dispose();
  }
}
