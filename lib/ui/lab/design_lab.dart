import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../../core/fake_clock.dart';
import '../../vehicle/reading.dart';
import '../design/components/backdrop.dart';
import '../design/components/controls/tape_button.dart';
import '../design/components/controls/tape_list_row.dart';
import '../design/components/controls/tape_segmented.dart';
import '../design/components/controls/tape_slider.dart';
import '../design/components/controls/tape_toggle.dart';
import '../design/components/rolling_numerals.dart';
import '../design/components/tape_label.dart';
import '../design/fidelity/fidelity_tier.dart';
import '../design/fidelity/frame_probe.dart';
import '../design/icons/icons.dart';
import '../design/motion/motion_clock.dart';
import '../design/motion/smoothing_pipeline.dart';
import '../design/theme/mode_controller.dart';
import '../design/theme/palette.dart';
import '../design/theme/tape_theme.dart';
import '../design/tokens/colors.dart';
import '../design/tokens/livery.dart';
import '../design/tokens/motion_tokens.dart';
import '../design/tokens/spacing.dart';
import '../design/tokens/typography.dart';
import '../dev/dev_settings.dart';
import 'lab_io.dart';

/// One tab of the gallery.
enum LabTab { numerals, controls, icons }

/// A destination the capture sweep visits: one tab in one livery and mode.
class LabCapture {
  const LabCapture(this.tab, this.livery, this.mode);

  final LabTab tab;
  final Livery livery;
  final TapeMode mode;

  String get filename =>
      'lab-${tab.name}-${livery.name.toLowerCase()}-${mode.name}';
}

/// Saves one capture. The default writes a file; a test gives its own to check
/// what would have been written without touching disk.
typedef CaptureSink = Future<void> Function(String filename, Uint8List png);

/// The Design Lab (DESIGN.md 13.2): a gallery of every component with sliders for
/// its inputs, switchers for livery, mode, fidelity tier, Motion/Parked, driver
/// side, reduce motion, slow motion and aspect frame, a frame-timing graph, and a
/// capture-all that renders combinations to PNGs.
///
/// It is always shipped, and reachable from the debug overlay's long-press or a
/// launch flag (CLAUDE.md 9, DESIGN.md 13.2) — for now, from the dev button on the
/// void screen, since the Strip and its pages arrive in phase 3b.
class DesignLab extends StatefulWidget {
  const DesignLab({
    super.key,
    this.onClose,
    this.captureSink,
    this.captureRenderer,
  });

  final VoidCallback? onClose;

  /// Where "capture all" writes. Defaults to the app's temporary directory; see
  /// [defaultCaptureSink].
  final CaptureSink? captureSink;

  /// Turns the captured widget key into PNG bytes. Defaults to
  /// [renderKeyToPng], the real rasteriser; a test gives its own, since driving
  /// `RenderRepaintBoundary.toImage` through repeated frame pumps in the same
  /// `tester.runAsync` block the sweep uses does not settle under
  /// `flutter_test` (a framework limitation, not a claim about the real
  /// renderer, which the design review package's device captures exercise
  /// directly).
  final Future<Uint8List?> Function(GlobalKey key)? captureRenderer;

  /// Rasterises whatever [key]'s `RepaintBoundary` holds to PNG bytes, or null
  /// if it is not attached.
  static Future<Uint8List?> renderKeyToPng(GlobalKey key) async {
    final boundary =
        key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data?.buffer.asUint8List();
  }

  /// Writes [png] to `<system temp>/tapedash-lab/<filename>.png`.
  ///
  /// This is a stand-in until the device channel offers a proper app-storage path
  /// (CLAUDE.md 5, "Device features"); noted in docs/DECISIONS.md. On the dev
  /// machine and in CI this still produces real files for the review package.
  static Future<void> defaultCaptureSink(String filename, Uint8List png) async {
    // ignore: avoid_slow_async_io
    final dir = await _tempDir();
    final file = _joinAndWrite(dir, filename, png);
    await file;
  }

  static Future<String> _tempDir() async {
    // dart:io is not imported in lib/ui/design (DESIGN.md keeps painting code
    // platform-free); the lab is the one place under ui/ that is allowed to touch
    // it, same as trips' sqflite adapter is the one exception under trips/.
    return LabIo.tempDirectory();
  }

  static Future<void> _joinAndWrite(
    String dir,
    String filename,
    Uint8List png,
  ) => LabIo.writeFile(dir, filename, png);

  @override
  State<DesignLab> createState() => _DesignLabState();
}

class _DesignLabState extends State<DesignLab> {
  final DevSettings _settings = DevSettings();
  LabTab _tab = LabTab.numerals;
  final FakeClock _clock = FakeClock();
  late final ManualMotionClock _sampleMotion = ManualMotionClock();
  late final SmoothedSignal _heroValue = SmoothedSignal(
    motion: _sampleMotion,
    clock: _clock,
    spring: TapeSprings.gauge,
  );
  late final SmoothedSignal _moneyValue = SmoothedSignal(
    motion: _sampleMotion,
    clock: _clock,
    spring: TapeSprings.gauge,
  );
  double _liveValue = 42;

  FrameProbe? _probe;
  final List<double> _frameHistory = [];
  bool _capturing = false;
  String _captureStatus = '';

  final GlobalKey _captureKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _heroValue.ingest(_reading(_liveValue));
    _moneyValue.ingest(_reading(14.6));
    _settings.addListener(_onSettingsChanged);
  }

  void _onSettingsChanged() {
    if (_settings.showFrameGraph) {
      _probe ??= FrameProbe(_onFrames)..start();
    } else {
      _probe?.stop();
      _probe = null;
      _frameHistory.clear();
    }
    setState(() {});
  }

  void _onFrames(List<double> ms) {
    _frameHistory.addAll(ms);
    while (_frameHistory.length > 120) {
      _frameHistory.removeAt(0);
    }
    if (mounted) setState(() {});
  }

  Reading _reading(double v) {
    final now = _clock.monotonic();
    return Reading(value: v, at: now, receivedAt: now);
  }

  void _nudgeLive(double v) {
    _liveValue = v;
    _clock.advance(TapeMotion.labNudgeStep);
    _heroValue.ingest(_reading(v));
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettingsChanged);
    _probe?.stop();
    _heroValue.dispose();
    _moneyValue.dispose();
    _sampleMotion.dispose();
    _settings.dispose();
    super.dispose();
  }

  Future<void> _captureAll() async {
    setState(() {
      _capturing = true;
      _captureStatus = 'Capturing…';
    });
    final sink = widget.captureSink ?? DesignLab.defaultCaptureSink;
    final render = widget.captureRenderer ?? DesignLab.renderKeyToPng;
    var count = 0;
    final savedLivery = _settings.livery;
    final savedMode = _settings.modeSetting;
    final savedTab = _tab;
    try {
      for (final tab in LabTab.values) {
        for (final livery in Liveries.all) {
          for (final mode in TapeMode.values) {
            setState(() {
              _tab = tab;
              _settings.livery = livery;
              _settings.modeSetting = switch (mode) {
                TapeMode.normal => ModeSetting.normal,
                TapeMode.daylight => ModeSetting.daylight,
                TapeMode.night => ModeSetting.night,
              };
            });
            await WidgetsBinding.instance.endOfFrame;
            await WidgetsBinding.instance.endOfFrame;
            final png = await render(_captureKey);
            if (png != null) {
              await sink(LabCapture(tab, livery, mode).filename, png);
              count++;
            }
          }
        }
      }
      setState(() => _captureStatus = 'Wrote $count captures');
    } finally {
      setState(() {
        _tab = savedTab;
        _settings.livery = savedLivery;
        _settings.modeSetting = savedMode;
        _capturing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = TapeThemeData(
      livery: _settings.livery,
      mode: _settings.modeSetting.fixed ?? TapeMode.normal,
      tier: _settings.tierPin ?? FidelityTier.balanced,
      driverSide: _settings.driverSide,
      reduceMotion: _settings.reduceMotion,
    );
    return TapeTheme(
      data: theme,
      child: Material3Free(
        child: TapeBackdrop(
          child: SafeArea(
            child: Column(
              children: [
                _topBar(theme),
                Expanded(
                  // A chosen aspect frame (DESIGN.md 13.2) letterboxes the
                  // gallery so a component can be checked at 18:9 or 20:9
                  // without the phone itself being that shape. Native fills
                  // the space, with no frame imposed.
                  child: _settings.frame.ratio == null
                      ? RepaintBoundary(
                          key: _captureKey,
                          child: ColoredBox(
                            color: theme.palette.canvas,
                            child: _tabContent(theme),
                          ),
                        )
                      : Center(
                          child: AspectRatio(
                            aspectRatio: _settings.frame.ratio!,
                            child: RepaintBoundary(
                              key: _captureKey,
                              child: ColoredBox(
                                color: theme.palette.canvas,
                                child: _tabContent(theme),
                              ),
                            ),
                          ),
                        ),
                ),
                _bottomBar(theme),
                if (_settings.showFrameGraph) _frameGraph(theme),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _topBar(TapeThemeData theme) {
    final palette = theme.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        TapeSpace.s4,
        TapeSpace.s3,
        TapeSpace.s4,
        TapeSpace.s2,
      ),
      child: Row(
        children: [
          const TapeLabel('DESIGN LAB', size: 14),
          const SizedBox(width: TapeSpace.s4),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final tab in LabTab.values)
                    Padding(
                      padding: const EdgeInsets.only(right: TapeSpace.s3),
                      child: TapeButton(
                        label: tab.name,
                        onPressed: () => setState(() => _tab = tab),
                        tone: _tab == tab
                            ? ButtonTone.accent
                            : ButtonTone.accent,
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (widget.onClose != null)
            TapeButton(
              label: 'Close',
              icon: TapeIcon.close,
              onPressed: widget.onClose,
            ),
          const SizedBox(width: TapeSpace.s2),
          TapeText(
            _settings.isOverridden ? 'overridden' : '',
            style: TapeTextStyle.caption,
            color: palette.caution,
          ),
        ],
      ),
    );
  }

  Widget _tabContent(TapeThemeData theme) {
    switch (_tab) {
      case LabTab.numerals:
        return _numeralsTab(theme);
      case LabTab.controls:
        return _controlsTab(theme);
      case LabTab.icons:
        return _iconsTab(theme);
    }
  }

  Widget _numeralsTab(TapeThemeData theme) {
    final palette = theme.palette;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(TapeSpace.s6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              RollingNumerals(
                source: _heroValue,
                format: const NumeralFormat(integerDigits: 3),
                size: 96,
                halo: 0.3,
              ),
              const SizedBox(width: TapeSpace.s6),
              RollingNumerals(
                source: _moneyValue,
                format: const NumeralFormat(integerDigits: 3, decimals: 1),
                size: 56,
                role: NumeralRole.money,
                halo: 0.3,
              ),
            ],
          ),
          const SizedBox(height: TapeSpace.s6),
          TapeSlider(
            label: 'Value',
            value: _liveValue,
            min: 0,
            max: 200,
            format: (v) => v.round().toString(),
            onChanged: _nudgeLive,
          ),
          const SizedBox(height: TapeSpace.s2),
          TapeText(
            'Retargets the spring on every step; try slow motion to see the detent.',
            style: TapeTextStyle.caption,
            color: palette.inkDim,
          ),
        ],
      ),
    );
  }

  Widget _controlsTab(TapeThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(TapeSpace.s6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const TapeLabel('Buttons'),
          const SizedBox(height: TapeSpace.s2),
          Wrap(
            spacing: TapeSpace.s3,
            runSpacing: TapeSpace.s3,
            children: [
              TapeButton(
                label: 'Garage',
                icon: TapeIcon.garage,
                onPressed: () {},
              ),
              TapeButton(label: 'Save', primary: true, onPressed: () {}),
              TapeButton(
                label: 'Set fuel price',
                tone: ButtonTone.money,
                onPressed: () {},
              ),
              const TapeButton(label: 'Disabled'),
            ],
          ),
          const SizedBox(height: TapeSpace.s6),
          const TapeLabel('Toggle and selector'),
          const SizedBox(height: TapeSpace.s2),
          Row(
            children: [
              TapeToggle(value: true, onChanged: (_) {}),
              const SizedBox(width: TapeSpace.s2),
              TapeToggle(value: false, onChanged: (_) {}),
              const SizedBox(width: TapeSpace.s4),
              SizedBox(
                width: 260,
                child: TapeSegmented<int>(
                  segments: const [
                    TapeSegment(0, 'Gentle'),
                    TapeSegment(1, 'Normal'),
                    TapeSegment(2, 'Sporty'),
                  ],
                  value: 1,
                  onChanged: (_) {},
                ),
              ),
            ],
          ),
          const SizedBox(height: TapeSpace.s6),
          const TapeLabel('List rows'),
          SizedBox(
            width: 320,
            child: Column(
              children: [
                TapeListRow(
                  label: 'Fuel price',
                  value: '₹104.2 / L',
                  icon: TapeIcon.pitStop,
                  onTap: () {},
                ),
                const TapeListRow(label: 'Version', value: '0.2.0'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _iconsTab(TapeThemeData theme) {
    final palette = theme.palette;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(TapeSpace.s6),
      child: Wrap(
        spacing: TapeSpace.s4,
        runSpacing: TapeSpace.s4,
        children: [
          for (final icon in TapeIcon.values)
            SizedBox(
              width: 64,
              child: Column(
                children: [
                  TapeIconView(icon, size: 32, color: palette.accentCore),
                  const SizedBox(height: TapeSpace.s1),
                  TapeText(
                    icon.label,
                    style: TapeTextStyle.caption,
                    color: palette.inkDim,
                    maxLines: 1,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _bottomBar(TapeThemeData theme) {
    final palette = theme.palette;
    // A single scrolling row, not a Wrap: the Lab has to fit the 360 lp height of
    // the design canvas the components themselves are built for (DESIGN.md 4.7),
    // so its own chrome does not get a taller budget than the app it is testing.
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: TapeSpace.s4,
        vertical: TapeSpace.s2,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (final child in [
              _liverySwitcher(),
              _modeSwitcher(),
              _tierSwitcher(),
              _drivingSwitcher(),
              _driverSideSwitcher(),
              _slowMotionSwitcher(),
              _frameSwitcher(),
              _toggleRow('Reduce motion', _settings.reduceMotion, (v) {
                _settings.update((s) => s.reduceMotion = v);
              }),
              _toggleRow('Frame graph', _settings.showFrameGraph, (v) {
                _settings.update((s) => s.showFrameGraph = v);
              }),
              TapeButton(
                label: _capturing ? 'Capturing…' : 'Capture all',
                onPressed: _capturing ? null : _captureAll,
              ),
              if (_captureStatus.isNotEmpty)
                TapeText(
                  _captureStatus,
                  style: TapeTextStyle.caption,
                  color: palette.inkDim,
                ),
            ])
              Padding(
                padding: const EdgeInsets.only(right: TapeSpace.s3),
                child: child,
              ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text, Widget child) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      TapeLabel(text, size: 10),
      const SizedBox(width: TapeSpace.s1),
      child,
    ],
  );

  Widget _liverySwitcher() => _label(
    'LIVERY',
    SizedBox(
      width: 220,
      child: TapeSegmented<LiveryId>(
        segments: [for (final l in Liveries.all) TapeSegment(l.id, l.name)],
        value: _settings.livery.id,
        onChanged: (id) =>
            _settings.update((s) => s.livery = Liveries.byId(id)),
      ),
    ),
  );

  Widget _modeSwitcher() => _label(
    'MODE',
    SizedBox(
      width: 220,
      child: TapeSegmented<ModeSetting>(
        segments: const [
          TapeSegment(ModeSetting.auto, 'Auto'),
          TapeSegment(ModeSetting.normal, 'Normal'),
          TapeSegment(ModeSetting.daylight, 'Day'),
          TapeSegment(ModeSetting.night, 'Night'),
        ],
        value: _settings.modeSetting,
        onChanged: (m) => _settings.update((s) => s.modeSetting = m),
      ),
    ),
  );

  Widget _tierSwitcher() => _label(
    'TIER',
    SizedBox(
      width: 180,
      child: TapeSegmented<FidelityTier?>(
        segments: const [
          TapeSegment(null, 'Auto'),
          TapeSegment(FidelityTier.lite, 'Lite'),
          TapeSegment(FidelityTier.balanced, 'Bal.'),
          TapeSegment(FidelityTier.full, 'Full'),
        ],
        value: _settings.tierPin,
        onChanged: (t) => _settings.update((s) => s.tierPin = t),
      ),
    ),
  );

  Widget _drivingSwitcher() => _label(
    'DRIVING',
    SizedBox(
      width: 220,
      child: TapeSegmented<DrivingOverride>(
        segments: [
          for (final d in DrivingOverride.values) TapeSegment(d, d.label),
        ],
        value: _settings.driving,
        onChanged: (d) => _settings.update((s) => s.driving = d),
      ),
    ),
  );

  Widget _driverSideSwitcher() => _label(
    'DRIVER',
    SizedBox(
      width: 140,
      child: TapeSegmented<DriverSide>(
        segments: const [
          TapeSegment(DriverSide.left, 'Left'),
          TapeSegment(DriverSide.right, 'Right'),
        ],
        value: _settings.driverSide,
        onChanged: (d) => _settings.update((s) => s.driverSide = d),
      ),
    ),
  );

  Widget _frameSwitcher() => _label(
    'FRAME',
    SizedBox(
      width: 220,
      child: TapeSegmented<AspectFrame>(
        segments: [for (final f in AspectFrame.values) TapeSegment(f, f.label)],
        value: _settings.frame,
        onChanged: (f) => _settings.update((s) => s.frame = f),
      ),
    ),
  );

  Widget _slowMotionSwitcher() => _label(
    'SLOW MO',
    SizedBox(
      width: 220,
      child: TapeSegmented<double>(
        segments: const [
          TapeSegment(1.0, '1x'),
          TapeSegment(2.0, '0.5x'),
          TapeSegment(4.0, '0.25x'),
          TapeSegment(10.0, '0.1x'),
        ],
        value: _settings.slowMotion,
        onChanged: (v) => _settings.update((s) => s.slowMotion = v),
      ),
    ),
  );

  Widget _toggleRow(String label, bool value, ValueChanged<bool> onChanged) =>
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TapeLabel(label, size: 10),
          const SizedBox(width: TapeSpace.s1),
          TapeToggle(value: value, onChanged: onChanged),
        ],
      );

  Widget _frameGraph(TapeThemeData theme) => SizedBox(
    height: 48,
    child: CustomPaint(
      painter: _FrameGraphPainter(_frameHistory, theme.palette),
    ),
  );
}

class _FrameGraphPainter extends CustomPainter {
  _FrameGraphPainter(this.frames, this.palette);

  final List<double> frames;
  final TapePalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = palette.panel);
    if (frames.isEmpty) return;
    final budget = 16.7;
    final path = Path();
    final step = size.width / (frames.length - 1).clamp(1, 1 << 30);
    for (var i = 0; i < frames.length; i++) {
      final x = i * step;
      final y =
          size.height -
          (frames[i] / (budget * 2)).clamp(0.0, 1.0) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final budgetY = size.height - 0.5 * size.height;
    canvas.drawLine(
      Offset(0, budgetY),
      Offset(size.width, budgetY),
      Paint()
        ..color = palette.etchStrong
        ..strokeWidth = 1,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = palette.accentCore
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_FrameGraphPainter old) => true;
}

/// A shell with no Material ancestor, so the lab (like the rest of `ui/`) never
/// depends on one (DESIGN.md 13.1). `Directionality` and `MediaQuery` are enough
/// for the widgets used here.
class Material3Free extends StatelessWidget {
  const Material3Free({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DefaultTextStyle(
    style: TapeType.body(color: TapeColors.inkBright),
    child: child,
  );
}
