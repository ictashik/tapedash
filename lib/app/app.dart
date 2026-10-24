import 'dart:async';
import 'dart:io' show Directory;

import 'package:flutter/widgets.dart';

import '../core/clock.dart';
import '../core/observable.dart';
import '../core/scheduler.dart';
import '../location/gps_drive.dart';
import '../location/location_source.dart';
import '../obd/adapter_config.dart';
import '../obd/transport/session_sink.dart';
import '../platform/device_features.dart';
import '../platform/exchange_files.dart';
import '../platform/exchange_host.dart';
import '../platform/fake_device_features.dart';
import '../platform/file_session_sink.dart';
import '../platform/native_location_source.dart';
import '../ui/design/components/backdrop.dart';
import '../ui/design/components/controls/tape_button.dart';
import '../ui/design/fidelity/tier_detector.dart';
import '../ui/design/icons/icons.dart';
import '../ui/design/motion/motion_clock.dart';
import '../ui/design/motion/motion_scope.dart';
import '../ui/design/motion/observable_listenable.dart';
import '../ui/design/render/render_kit.dart';
import '../ui/design/theme/tape_theme.dart';
import '../ui/design/tokens/colors.dart';
import '../ui/design/tokens/livery.dart';
import '../ui/design/tokens/spacing.dart';
import '../ui/design/tokens/watch.dart';
import '../ui/dev/debug_overlay.dart';
import '../ui/dev/dev_settings.dart';
import '../ui/lab/design_lab.dart';
import '../ui/onboarding/connect_flow.dart';
import '../ui/onboarding/onboarding_screen.dart';
import '../ui/pages/survey/survey_page.dart';
import 'app_info.dart';
import 'app_services.dart';
import 'app_settings.dart';
import 'display_controller.dart';
import 'drive_shell.dart';
import 'exchange_coordinator.dart';
import 'gps_shell.dart';
import 'live_drive.dart';
import 'radio_transport_factory.dart';
import 'survey_drive.dart';
import 'transport_adapter_checker.dart';
import 'watch_shell.dart';

/// Root widget.
///
/// The app opens on the cold open and the choice (DESIGN.md 7.11): connect the
/// car's adapter, or use the phone's GPS alone for the speed. Whichever is chosen
/// is the source from then on and is remembered; **nothing else is ever
/// substituted for it** (an adapter that will not connect stays "looking for your
/// adapter", it does not turn into another source). There is one way into the
/// design system: a small dev button that opens the Design Lab (DESIGN.md 13.2),
/// shown in debug and profile builds, and in a release build made with
/// `--dart-define=TAPEDASH_DEV=true`. It uses [WidgetsApp] rather than
/// `MaterialApp`, since Material widgets are banned (DESIGN.md 13.1).
class TapeDashApp extends StatelessWidget {
  const TapeDashApp({
    super.key,
    this.clock = const SystemClock(),
    this.scheduler = const SystemScheduler(),
    this.skipColdOpen = DevMode.skipColdOpen,
    this.services,
    this.transports,
    this.sessionSink,
    this.device,
    this.location,
    this.formFactor,
    this.exchangeHost,
    this.exchangeRoot,
  });

  /// What the phone gives the exchange (the launch's request, the file picker, the
  /// share sheet). Null uses the phone's own; a test gives a fake.
  final ExchangeHost? exchangeHost;

  /// Where the exchange files are kept. Null is the phone's own external files
  /// folder; a test gives a temporary directory.
  final Directory? exchangeRoot;

  /// Whether the screens are laid out for a phone or for a watch (DESIGN.md 16.2).
  /// Null chooses from the size of the screen: a shorter side under 300 lp is a
  /// watch. `main` passes the watch when the platform says it is one.
  final FormFactor? formFactor;

  /// The phone's GPS, for a drive on the GPS alone and for a trip's route. Null
  /// uses the phone's own; a test gives a simulated one.
  final LocationSource? location;

  /// The phone's own features (light sensor, brightness, battery). Null is a phone
  /// with none, as in a test: the display then stays as it is.
  final DeviceFeatures? device;

  /// Makes the transport for the adapter the user chose. Null uses the real
  /// ones (a test gives a factory for a simulated adapter).
  final RadioTransportFactory? transports;

  /// Where recorded sessions go. Null writes files on the phone.
  final SessionSink? sessionSink;

  /// The app's settings and trip log. Null uses empty in-memory ones (tests).
  final AppServices? services;

  /// Goes straight to the choice, past the cold open.
  final bool skipColdOpen;

  /// Time, injected (CLAUDE.md 5): a test gives a `FakeClock` for both.
  final Clock clock;
  final Scheduler scheduler;

  @override
  Widget build(BuildContext context) {
    return WidgetsApp(
      color: TapeColors.voidColor,
      debugShowCheckedModeBanner: false,
      builder: (context, child) => _Shell(
        clock: clock,
        scheduler: scheduler,
        skipColdOpen: skipColdOpen,
        services: services,
        transports: transports,
        sessionSink: sessionSink,
        device: device,
        location: location,
        formFactor: formFactor,
        exchangeHost: exchangeHost,
        exchangeRoot: exchangeRoot,
      ),
    );
  }
}

class _Shell extends StatefulWidget {
  const _Shell({
    required this.clock,
    required this.scheduler,
    required this.skipColdOpen,
    required this.services,
    required this.transports,
    required this.sessionSink,
    required this.device,
    required this.location,
    required this.formFactor,
    required this.exchangeHost,
    required this.exchangeRoot,
  });

  final ExchangeHost? exchangeHost;
  final Directory? exchangeRoot;
  final FormFactor? formFactor;
  final LocationSource? location;
  final DeviceFeatures? device;
  final RadioTransportFactory? transports;
  final SessionSink? sessionSink;
  final Clock clock;
  final Scheduler scheduler;
  final bool skipColdOpen;
  final AppServices? services;

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> with WidgetsBindingObserver {
  late final TapeRenderKit _kit = TapeRenderKit();
  bool _labOpen = false;

  /// Moves the app's data out and in (docs/EXCHANGE.md): Garage's rows, the watch's
  /// Data row and what adb asks at the launch. Made once the form factor is known.
  ExchangeCoordinator? _exchange;
  late final ExchangeHost _exchangeHost =
      widget.exchangeHost ?? NativeExchangeHost();
  StreamSubscription<void>? _arrivals;

  /// What the user has set: saved on the phone when there are services (and in
  /// memory for a test that gives none).
  late final AppSettings _settings = _services.settings;
  late final Listenable _themeChanges = Listenable.merge([
    _settings.livery,
    _settings.driverSide,
    _settings.reduceMotion,
    ObservableListenable(_display.mode),
    ObservableListenable(_display.tier),
  ]);

  /// The light, the brightness, the heat and the fidelity tier (DESIGN.md 4.4, 9.2).
  late final DisplayController _display = DisplayController(
    device: widget.device ?? FakeDeviceFeatures(),
    clock: widget.clock,
    scheduler: widget.scheduler,
    settings: _settings,
    // Frame timings are only the phone's to give when there is a phone.
    watchFrames: widget.device != null,
  );

  late final ObservableListenable<bool> _phoneHot = ObservableListenable(
    _display.phoneHot,
  );

  /// What the debug overlay says of the phone and the display (CLAUDE.md 9).
  late final List<DebugRow> _debugRows = _makeDebugRows();

  List<DebugRow> _makeDebugRows() {
    DebugRow row(
      String label,
      List<Observable<Object?>> sources,
      String Function() text,
    ) {
      final c = ComputedText([
        for (final s in sources) ObservableListenable<Object?>(s),
      ], text);
      _debugTexts.add(c);
      return DebugRow(label, c);
    }

    return [
      row('Frames', [_display.frameStats], () {
        final f = _display.frameStats.value;
        return f.fps == 0
            ? '—'
            : '${f.fps.toStringAsFixed(0)} fps  ·  p90 ${f.p90Milliseconds.toStringAsFixed(1)} ms';
      }),
      row('Tier', [_display.tier], () {
        final t = _display.tier.value;
        return '${t.tier.label}  ·  ${t.reason.name}'
            '${t.fpsCap == null ? '' : '  ·  ${t.fpsCap} fps cap'}';
      }),
      row('Mode', [_display.mode, _display.lux], () {
        final lux = _display.lux.value;
        return '${_display.mode.value.name}'
            '${lux == null ? '' : '  ·  ${lux.round()} lux'}';
      }),
      row(
        'Battery',
        [_display.temperature],
        () => _display.temperature.value == null
            ? '—'
            : '${_display.temperature.value!.toStringAsFixed(1)} °C',
      ),
    ];
  }

  final List<ComputedText> _debugTexts = [];

  void _onBenchmark(List<double> frames) {
    _display.onDetected(const TierDetector().decide(frameMilliseconds: frames));
  }

  late final RadioTransportFactory _transports =
      widget.transports ?? RadioTransportFactory();
  late final SessionSink _sink =
      widget.sessionSink ??
      FileSessionSink(widget.device ?? FakeDeviceFeatures());
  late final AppServices _services = widget.services ?? AppServices.inMemory();

  /// The drive from the user's adapter, when that is the source.
  LiveDrive? _live;

  /// The drive on the phone's GPS alone, when that is the source.
  GpsDrive? _gps;
  int _syncs = 0;

  /// Whether the connect flow is on screen.
  bool _connecting = false;

  /// Whether a survey drive has the screen (Garage → Survey drive). It takes the
  /// adapter over, so the dashboard's drive is gone for as long as it lasts and
  /// is made again when it ends.
  bool _surveying = false;

  /// The survey itself, once the dashboard has let go of the adapter.
  SurveyDrive? _survey;

  AdapterStore get _adapters => _services.adapters;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _arrivals = _exchangeHost.arrivals.listen(
      (_) => unawaited(_exchange?.checkRequest()),
    );
    _adapters.adapter.addListener(_syncDrive);
    _adapters.source.addListener(_syncDrive);
    _adapters.compatibilityMode.addListener(_syncDrive);
    _adapters.recordSessions.addListener(_syncDrive);
    _syncDrive();
    unawaited(_display.start());
    if (DevMode.launchScreen == 'lab') _labOpen = true;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_exchange != null) return;
    final device = widget.device ?? FakeDeviceFeatures();
    final exchange = ExchangeCoordinator(
      app: _services,
      files: ExchangeFiles(rootDirectory: widget.exchangeRoot, device: device),
      host: _exchangeHost,
      clock: widget.clock,
      installId: _services.installId,
      deviceKind: _isWatch(context) ? 'watch' : 'phone',
      deviceName: '',
      appVersion: appVersion,
    );
    _exchange = exchange;
    unawaited(exchange.refresh());
    // What adb asked for at the launch, once the first frame is up.
    unawaited(exchange.checkRequest());
    unawaited(device.deviceName().then(exchange.nameDevice));
  }

  /// The app came back to the front: a request may have arrived with it.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_exchange?.checkRequest());
      unawaited(_exchange?.refresh());
    }
  }

  /// Makes the drive the settings ask for: the adapter's, the phone's GPS alone,
  /// or none while the source has not been chosen (the screen then asks). Changes
  /// made in Garage (another adapter, the source, compatibility mode, recording)
  /// reach the drive here; they only happen while parked. **Nothing is ever
  /// substituted**: with the adapter chosen, a drive that cannot connect stays an
  /// adapter drive, trying again.
  Future<void> _syncDrive() async {
    // A survey has the adapter; it gives the drive back when it ends. So does
    // the connect flow, which pairs and tries adapters of its own.
    if (_surveying || _connecting) return;
    final ticket = ++_syncs;
    final source = _adapters.source.value;
    if (source == DriveSource.gps) {
      final old = _live;
      _live = null;
      _gps ??= GpsDrive(
        location: widget.location ?? NativeLocationSource(),
        clock: widget.clock,
        scheduler: widget.scheduler,
      );
      if (mounted) setState(() {});
      unawaited(old?.dispose());
      return;
    }
    final gps = _gps;
    _gps = null;
    final config = source == DriveSource.obd ? _adapters.adapter.value : null;
    if (config == null) {
      final old = _live;
      _live = null;
      if (mounted) setState(() {});
      unawaited(old?.dispose());
      unawaited(gps?.dispose());
      return;
    }
    unawaited(gps?.dispose());
    final memory = await _adapters.memoryFor(config);
    if (!mounted || ticket != _syncs) return;
    final old = _live;
    _live = LiveDrive(
      adapter: config,
      transports: _transports,
      clock: widget.clock,
      scheduler: widget.scheduler,
      memory: memory,
      compatibility: _adapters.compatibilityMode.value,
      recordSessions: _adapters.recordSessions.value,
      sink: _sink,
      appVersion: appVersion,
      diary: _services.linkDiary,
    );
    setState(() {});
    unawaited(old?.dispose());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_arrivals?.cancel());
    _exchange?.dispose();
    _adapters.adapter.removeListener(_syncDrive);
    _adapters.source.removeListener(_syncDrive);
    _adapters.compatibilityMode.removeListener(_syncDrive);
    _adapters.recordSessions.removeListener(_syncDrive);
    unawaited(_gps?.dispose());
    unawaited(_live?.dispose());
    unawaited(_survey?.dispose());
    _phoneHot.dispose();
    for (final t in _debugTexts) {
      t.dispose();
    }
    unawaited(_display.dispose());
    _kit.dispose();
    super.dispose();
  }

  /// Opens the connect flow. The dashboard's drive lets go of the adapter first:
  /// it keeps reopening the old one every few seconds, and that would cut across a
  /// pairing and the flow's own test of the link.
  void _openConnect() {
    final old = _live;
    _live = null;
    _syncs++;
    setState(() => _connecting = true);
    unawaited(old?.dispose());
  }

  void _closeConnect({required bool done}) {
    if (done) _settings.onboarded.value = true;
    setState(() => _connecting = false);
    unawaited(_syncDrive());
  }

  /// Hands the adapter from the dashboard to a survey drive. The dashboard's link
  /// is closed first, since an adapter takes one connection at a time.
  Future<void> _openSurvey() async {
    final config = _adapters.source.value == DriveSource.obd
        ? _adapters.adapter.value
        : null;
    if (config == null || _surveying) return;
    _surveying = true;
    final old = _live;
    _live = null;
    setState(() {});
    await old?.dispose();
    final memory = await _adapters.memoryFor(config);
    if (!mounted || !_surveying) return;
    setState(() {
      _survey = SurveyDrive(
        adapter: config,
        transports: _transports,
        clock: widget.clock,
        scheduler: widget.scheduler,
        sink: _sink,
        memory: memory,
        appVersion: appVersion,
      );
    });
  }

  /// Ends the survey screen and gives the adapter back to the dashboard, which is
  /// made again once the survey has let go of the link.
  Future<void> _closeSurvey() async {
    final survey = _survey;
    _survey = null;
    if (mounted) setState(() {});
    await survey?.dispose();
    _surveying = false;
    if (mounted) await _syncDrive();
  }

  /// Whether the screens are the watch's (DESIGN.md 16.2): the platform said so,
  /// or the screen is too small to be anything else.
  bool _isWatch(BuildContext context) {
    final forced = widget.formFactor;
    if (forced != null) return forced == FormFactor.watch;
    final size = MediaQuery.sizeOf(context);
    return FormFactor.ofSize(size.width, size.height) == FormFactor.watch;
  }

  Widget _screen() {
    final watch = _isWatch(context);
    if (_connecting) {
      return LayoutBuilder(
        builder: (context, box) => TapeBackdrop(
          child: ConnectFlow(
            services: _services,
            checker: TransportAdapterChecker(_transports),
            radios: _transports.radio,
            width: box.maxWidth,
            height: box.maxHeight,
            onCancel: () => _closeConnect(done: false),
            onDone: () => _closeConnect(done: true),
          ),
        ),
      );
    }
    if (_surveying) {
      final survey = _survey;
      // The dashboard is letting go of the adapter, or the survey is.
      if (survey == null) return const SizedBox.shrink();
      return LayoutBuilder(
        builder: (context, box) => TapeBackdrop(
          child: SurveyPage(
            drive: survey,
            width: box.maxWidth,
            height: box.maxHeight,
            onClose: () => unawaited(_closeSurvey()),
          ),
        ),
      );
    }
    switch (_adapters.source.value) {
      case DriveSource.obd:
        final live = _live;
        // Waiting for the adapter's drive to be made (a moment at launch).
        if (live == null) return const SizedBox.shrink();
        if (watch) {
          return WatchShell(
            key: ValueKey(live),
            exchange: _exchange,
            feed: live,
            app: _services,
            clock: widget.clock,
            scheduler: widget.scheduler,
            location: widget.location,
            device: widget.device,
            onChangeAdapter: _openConnect,
            phoneHot: _phoneHot,
          );
        }
        return DriveShell(
          // A different drive is a different shell: it starts fresh.
          key: ValueKey(live),
          exchange: _exchange,
          feed: live,
          app: _services,
          clock: widget.clock,
          scheduler: widget.scheduler,
          location: widget.location,
          onChangeAdapter: _openConnect,
          onSurvey: () => unawaited(_openSurvey()),
          phoneHot: _phoneHot,
          phoneTemperature: _display.temperature,
          debugRows: _debugRows,
          onOpenLab: () => setState(() => _labOpen = true),
        );
      case DriveSource.gps:
        final gps = _gps;
        if (gps == null) return const SizedBox.shrink();
        return GpsShell(
          key: ValueKey(gps),
          exchange: _exchange,
          gps: gps,
          app: _services,
          clock: widget.clock,
          scheduler: widget.scheduler,
          onChangeAdapter: _openConnect,
          phoneHot: _phoneHot,
          phoneTemperature: _display.temperature,
          debugRows: _debugRows,
          onOpenLab: () => setState(() => _labOpen = true),
        );
      case null:
        return LayoutBuilder(
          builder: (context, box) => TapeBackdrop(
            child: OnboardingScreen(
              width: box.maxWidth,
              height: box.maxHeight,
              // A person who has seen the cold open once does not see it again
              // when the app asks the question a second time.
              skipColdOpen: widget.skipColdOpen || _settings.onboarded.value,
              onBenchmark: _onBenchmark,
              onGps: () {
                _settings.onboarded.value = true;
                unawaited(_adapters.setSource(DriveSource.gps));
              },
              onConnect: _openConnect,
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return MotionScope(
      child: TapeRenderScope(
        kit: _kit,
        // The look follows Garage: livery, driver side, reduce motion and a held
        // fidelity tier (Auto is the one the cold open's frame timings chose).
        child: AnimatedBuilder(
          animation: _themeChanges,
          builder: (context, _) => TapeTheme(
            data: TapeThemeData(
              livery: _isWatch(context)
                  ? Liveries.byId(
                      _settings.livery.value,
                    ).withNumeralWeightAtLeast(TapeWatch.minNumeralWeight)
                  : Liveries.byId(_settings.livery.value),
              mode: _display.mode.value,
              tier: _display.tier.value.tier,
              driverSide: _settings.driverSide.value,
              reduceMotion: _settings.reduceMotion.value,
            ),
            child: _TierBinder(
              display: _display,
              child: _labOpen
                  ? DesignLab(onClose: () => setState(() => _labOpen = false))
                  : ColoredBox(
                      color: TapeColors.voidColor,
                      child: Stack(
                        children: [
                          Positioned.fill(child: _screen()),
                          // Only on the first screens: over the drive it would sit on the
                          // connect flow's and Garage's buttons, and the debug overlay (a
                          // long-press) opens the Lab from there.
                          if (DevMode.buttonVisible &&
                              _adapters.source.value == null &&
                              !_connecting)
                            Positioned(
                              right: TapeSpace.s4,
                              bottom: TapeSpace.s4,
                              child: TapeButton(
                                label: 'Design Lab',
                                icon: TapeIcon.hud,
                                onPressed: () =>
                                    setState(() => _labOpen = true),
                              ),
                            ),
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Holds the motion clock to the frame rate the fidelity governor asks for: 30 fps
/// for a hot phone or one that cannot keep up (DESIGN.md 9.1, 9.2).
class _TierBinder extends StatefulWidget {
  const _TierBinder({required this.display, required this.child});

  final DisplayController display;
  final Widget child;

  @override
  State<_TierBinder> createState() => _TierBinderState();
}

class _TierBinderState extends State<_TierBinder> {
  MotionClock? _clock;

  @override
  void initState() {
    super.initState();
    widget.display.tier.addListener(_apply);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _clock = MotionScope.of(context);
    _apply();
  }

  @override
  void dispose() {
    widget.display.tier.removeListener(_apply);
    super.dispose();
  }

  void _apply() => _clock?.maxFps = widget.display.tier.value.fpsCap;

  @override
  Widget build(BuildContext context) => widget.child;
}
