import 'dart:async';

import 'package:flutter/widgets.dart';

import '../core/clock.dart';
import '../core/observable.dart';
import '../core/scheduler.dart';
import '../obd/adapter_config.dart';
import '../obd/transport/session_sink.dart';
import '../platform/device_features.dart';
import '../platform/fake_device_features.dart';
import '../platform/file_session_sink.dart';
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
import '../ui/dev/debug_overlay.dart';
import '../ui/dev/dev_settings.dart';
import '../ui/lab/design_lab.dart';
import '../ui/onboarding/connect_flow.dart';
import '../ui/onboarding/onboarding_screen.dart';
import 'app_info.dart';
import 'app_services.dart';
import 'app_settings.dart';
import 'demo_drive.dart';
import 'display_controller.dart';
import 'drive_shell.dart';
import 'live_drive.dart';
import 'radio_transport_factory.dart';
import 'transport_adapter_checker.dart';

/// Root widget.
///
/// The app opens on the cold open and the choice (DESIGN.md 7.11); the demo path
/// goes to the Strip, driven by Demo Mode (the connect path needs phase 6), with
/// one way into the design system: a small dev button that opens the Design Lab (DESIGN.md 13.2), shown
/// in debug and profile builds, and in a release build made with
/// `--dart-define=TAPEDASH_DEV=true`. It uses [WidgetsApp] rather than
/// `MaterialApp`, since Material widgets are banned (DESIGN.md 13.1).
class TapeDashApp extends StatelessWidget {
  const TapeDashApp({
    super.key,
    this.clock = const SystemClock(),
    this.scheduler = const SystemScheduler(),
    this.onboarding = true,
    this.skipColdOpen = DevMode.skipColdOpen,
    this.services,
    this.scenario,
    this.transports,
    this.sessionSink,
    this.device,
  });

  /// The phone's own features (light sensor, brightness, battery). Null is a phone
  /// with none, as in a test: the display then stays as it is.
  final DeviceFeatures? device;

  /// Makes the transport for the adapter the user chose. Null uses the real
  /// ones (a test gives a factory for a simulated adapter).
  final RadioTransportFactory? transports;

  /// Where recorded sessions go. Null writes files on the phone.
  final SessionSink? sessionSink;

  /// The demo drive to run, if not the one chosen in Garage (tests).
  final String? scenario;

  /// The app's settings and trip log. Null uses empty in-memory ones (tests).
  final AppServices? services;

  /// Whether the app opens on the cold open and the choice (DESIGN.md 7.11), or
  /// straight on the drive (tests, and a later launch once the choice is
  /// remembered -- which needs the settings store, the Garage's piece).
  final bool onboarding;

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
        onboarding: onboarding,
        skipColdOpen: skipColdOpen,
        services: services,
        scenario: scenario,
        transports: transports,
        sessionSink: sessionSink,
        device: device,
      ),
    );
  }
}

class _Shell extends StatefulWidget {
  const _Shell({
    required this.clock,
    required this.scheduler,
    required this.onboarding,
    required this.skipColdOpen,
    required this.services,
    required this.scenario,
    required this.transports,
    required this.sessionSink,
    required this.device,
  });

  final DeviceFeatures? device;
  final RadioTransportFactory? transports;
  final SessionSink? sessionSink;
  final String? scenario;
  final Clock clock;
  final Scheduler scheduler;
  final bool onboarding;
  final bool skipColdOpen;
  final AppServices? services;

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  late final TapeRenderKit _kit = TapeRenderKit();
  bool _labOpen = false;

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

  // The choice at first launch is asked once: a later launch goes straight in.
  late bool _onboarded = !widget.onboarding || _settings.onboarded.value;

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

  /// The demo drive, started at launch so that it is already connected when
  /// the user chooses it (DESIGN.md 7.11: the ignition within a second). Not
  /// built at all for a launch that goes straight to the user's own adapter.
  DemoDrive? _demo;

  /// The drive from the user's adapter, when that is what they use.
  LiveDrive? _live;
  int _syncs = 0;

  /// Whether the connect flow is on screen.
  bool _connecting = false;

  AdapterStore get _adapters => _services.adapters;

  @override
  void initState() {
    super.initState();
    _adapters.adapter.addListener(_syncDrive);
    _adapters.useAdapter.addListener(_syncDrive);
    _adapters.compatibilityMode.addListener(_syncDrive);
    _adapters.recordSessions.addListener(_syncDrive);
    _syncDrive();
    unawaited(_display.start());
    if (DevMode.launchScreen == 'lab') _labOpen = true;
  }

  /// Makes the drive the settings ask for: the adapter's when there is one and it
  /// is in use, the demo otherwise. Changes made in Garage (another adapter,
  /// compatibility mode, recording) reach the drive here; they only happen while
  /// parked.
  Future<void> _syncDrive() async {
    final ticket = ++_syncs;
    final config = _adapters.useAdapter.value ? _adapters.adapter.value : null;
    if (config == null) {
      final old = _live;
      _live = null;
      _demo ??= DemoDrive(
        clock: widget.clock,
        scheduler: widget.scheduler,
        scenario: widget.scenario ?? _settings.demoScenario.value,
        profile: _settings.demoProfile.value,
      );
      _demo!.start();
      if (mounted) setState(() {});
      unawaited(old?.dispose());
      return;
    }
    // Something is in use that is not the demo: let the demo stand down.
    _demo?.stop();
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
    );
    setState(() {});
    unawaited(old?.dispose());
  }

  @override
  void dispose() {
    _adapters.adapter.removeListener(_syncDrive);
    _adapters.useAdapter.removeListener(_syncDrive);
    _adapters.compatibilityMode.removeListener(_syncDrive);
    _adapters.recordSessions.removeListener(_syncDrive);
    _demo?.dispose();
    unawaited(_live?.dispose());
    _phoneHot.dispose();
    for (final t in _debugTexts) {
      t.dispose();
    }
    unawaited(_display.dispose());
    _kit.dispose();
    super.dispose();
  }

  void _openConnect() => setState(() => _connecting = true);

  Widget _screen() {
    if (_connecting) {
      return LayoutBuilder(
        builder: (context, box) => TapeBackdrop(
          child: ConnectFlow(
            services: _services,
            checker: TransportAdapterChecker(_transports),
            radios: _transports.radio,
            width: box.maxWidth,
            height: box.maxHeight,
            onCancel: () => setState(() => _connecting = false),
            onDone: () => setState(() {
              _connecting = false;
              _onboarded = true;
            }),
          ),
        ),
      );
    }
    if (_onboarded) {
      final live = _live;
      final demo = _demo;
      // Waiting for the adapter's drive to be made (a moment at launch).
      if (live == null && demo == null) return const SizedBox.shrink();
      return DriveShell(
        // A different drive is a different shell: it starts fresh.
        key: ValueKey(live ?? demo),
        demo: live == null ? demo : null,
        live: live,
        app: _services,
        clock: widget.clock,
        scheduler: widget.scheduler,
        onChangeAdapter: _openConnect,
        phoneHot: _phoneHot,
        phoneTemperature: _display.temperature,
        debugRows: _debugRows,
        onOpenLab: () => setState(() => _labOpen = true),
      );
    }
    return LayoutBuilder(
      builder: (context, box) => TapeBackdrop(
        child: OnboardingScreen(
          width: box.maxWidth,
          height: box.maxHeight,
          skipColdOpen: widget.skipColdOpen,
          onBenchmark: _onBenchmark,
          onDemo: () {
            _settings.onboarded.value = true;
            setState(() => _onboarded = true);
          },
          onConnect: _openConnect,
        ),
      ),
    );
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
              livery: Liveries.byId(_settings.livery.value),
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
                          if (DevMode.buttonVisible)
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
