import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../../obd/diagnostics_source.dart';
import '../../../obd/dtc/dtc.dart';
import '../../../obd/dtc/dtc_descriptions.dart';
import '../../../obd/pids/pid.dart';
import '../../../vehicle/vehicle_state.dart' show DrivingMode;
import '../../design/components/controls/slide_to_confirm.dart';
import '../../design/components/controls/tape_button.dart';
import '../../design/components/tape_label.dart';
import '../../design/icons/icons.dart';
import '../../design/motion/observable_listenable.dart';
import '../../design/render/chamfer.dart';
import '../../design/theme/palette.dart';
import '../../design/theme/tape_theme.dart';
import '../../design/tokens/spacing.dart';
import '../../design/tokens/strokes.dart';
import '../../design/tokens/typography.dart';

/// Diagnostics (DESIGN.md 7.10): what the adapter and the car are saying.
///
/// On the left the adapter (its name, protocol, supply voltage, the poll rate as
/// a sparkline and the fuel source in use) and the PID matrix, a grid of one small
/// cell for each Mode 01 PID from 01 to 60 (hex), lit where the car answers. On the
/// right the fault codes: the code, what it means in plain words, and whether it is
/// stored or pending; and CLEAR CODES, which is a slide to confirm and works only
/// while parked.
///
/// Parked only: it closes itself if the car starts to move.
class DiagnosticsPage extends StatefulWidget {
  const DiagnosticsPage({
    super.key,
    required this.source,
    required this.mode,
    required this.width,
    required this.height,
    required this.onClose,
    this.descriptions = DtcDescriptions.empty,
  });

  final DiagnosticsSource source;
  final ValueListenable<DrivingMode> mode;
  final double width;
  final double height;
  final VoidCallback onClose;
  final DtcDescriptions descriptions;

  @override
  State<DiagnosticsPage> createState() => DiagnosticsPageState();
}

/// What became of the last read or clear, for the page to say.
enum CodesStatus { idle, reading, read, failed }

class DiagnosticsPageState extends State<DiagnosticsPage> {
  final ValueNotifier<int> _history = ValueNotifier(0);
  final List<double> _rates = [];
  late final ObservableListenable<AdapterInfo?> _info = ObservableListenable(
    widget.source.adapterInfo,
  );
  late final ObservableListenable<double> _rate = ObservableListenable(
    widget.source.pollRate,
  );
  late final ObservableListenable<Object?> _fuel = ObservableListenable(
    widget.source.fuelSource,
  );
  late final ObservableListenable<Object?> _volts = ObservableListenable(
    widget.source.voltage,
  );

  DtcReadResult? _result;
  CodesStatus _status = CodesStatus.idle;
  String? _note;
  int? _pid;
  int _ticket = 0;

  @override
  void initState() {
    super.initState();
    widget.mode.addListener(_onMode);
    widget.source.pollRate.addListener(_onRate);
    _info.addListener(_onInfo);
    if (widget.source.adapterInfo.value != null) _read();
  }

  @override
  void dispose() {
    widget.mode.removeListener(_onMode);
    widget.source.pollRate.removeListener(_onRate);
    _info.removeListener(_onInfo);
    _info.dispose();
    _rate.dispose();
    _fuel.dispose();
    _volts.dispose();
    _history.dispose();
    super.dispose();
  }

  /// What the page has read, and how that went.
  DtcReadResult? get result => _result;
  CodesStatus get status => _status;

  void _onMode() {
    if (widget.mode.value != DrivingMode.parked) widget.onClose();
  }

  void _onRate() {
    _rates.add(widget.source.pollRate.value);
    if (_rates.length > _historyLength) _rates.removeAt(0);
    _history.value++;
  }

  // The car answered while the page was open: read the codes.
  void _onInfo() {
    if (widget.source.adapterInfo.value != null &&
        _status == CodesStatus.idle) {
      _read();
    }
  }

  static const int _historyLength = 60;

  void _read({bool keepNote = false}) {
    final ticket = ++_ticket;
    setState(() {
      _status = CodesStatus.reading;
      if (!keepNote) _note = null;
    });
    widget.source.readCodes((r) {
      if (!mounted || ticket != _ticket) return;
      setState(() {
        _result = r;
        _status = r.ok ? CodesStatus.read : CodesStatus.failed;
      });
    });
  }

  void _clear() {
    widget.source.clearCodes((outcome) {
      if (!mounted) return;
      setState(() {
        _note = switch (outcome) {
          DtcClearOutcome.cleared => 'The codes are cleared.',
          DtcClearOutcome.notStationary => 'The car has to be stopped.',
          DtcClearOutcome.refusedByEcu =>
            'The car would not clear them. Engine off, ignition on, then try again.',
          DtcClearOutcome.failed => 'Could not clear the codes.',
        };
      });
      if (outcome == DtcClearOutcome.cleared) _read(keepNote: true);
    });
  }

  List<(Dtc, bool)> get _codes => [
    for (final d in _result?.stored ?? const <Dtc>[]) (d, true),
    for (final d in _result?.pending ?? const <Dtc>[]) (d, false),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = TapeTheme.of(context);
    final palette = theme.palette;
    final margin = TapeSpace.margin(widget.height);
    // Over everything, the dock included: it has its own Close.
    final bottom = margin;
    final leftW = widget.width * 0.5 - margin;
    final rightLeft = widget.width * 0.54;
    final info = widget.source.adapterInfo.value;

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: Stack(
        children: [
          // Left: the adapter, and the PID matrix.
          Positioned(
            left: margin,
            top: margin,
            width: leftW,
            bottom: bottom,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const TapeLabel('Adapter', size: 11),
                const SizedBox(height: TapeSpace.s1),
                AnimatedBuilder(
                  animation: Listenable.merge([_info, _fuel, _volts]),
                  builder: (context, _) => _AdapterFacts(
                    info: widget.source.adapterInfo.value,
                    fuel: widget.source.fuelSource.value.label,
                    volts: widget.source.voltage.value?.value,
                    palette: palette,
                  ),
                ),
                const SizedBox(height: TapeSpace.s1),
                SizedBox(
                  height: 26,
                  child: Row(
                    children: [
                      AnimatedBuilder(
                        animation: _rate,
                        builder: (context, _) => TapeText(
                          '${widget.source.pollRate.value.toStringAsFixed(1)} /s',
                          style: TapeTextStyle.caption,
                          color: palette.inkMid,
                        ),
                      ),
                      const SizedBox(width: TapeSpace.s2),
                      Expanded(
                        child: CustomPaint(
                          size: Size.infinite,
                          painter: _SparklinePainter(
                            rates: _rates,
                            repaint: _history,
                            palette: palette,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: TapeSpace.s2),
                Row(
                  children: [
                    const TapeLabel('PIDs the car answers', size: 11),
                    const Spacer(),
                    TapeText(
                      info == null ? '—' : '${_answered(info)} of $_pidCount',
                      style: TapeTextStyle.caption,
                      color: palette.inkMid,
                    ),
                  ],
                ),
                const SizedBox(height: TapeSpace.s1),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, box) => GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (d) =>
                          _tapMatrix(d.localPosition, box.biggest),
                      child: CustomPaint(
                        size: box.biggest,
                        painter: PidMatrixPainter(
                          supported: info?.supportedPids ?? const {},
                          selected: _pid,
                          palette: palette,
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  height: 18,
                  child: TapeText(
                    _pidCaption(info),
                    style: TapeTextStyle.caption,
                    color: palette.inkMid,
                    maxLines: 1,
                  ),
                ),
              ],
            ),
          ),
          // Right: the fault codes.
          Positioned(
            left: rightLeft,
            right: margin,
            top: margin,
            bottom: bottom,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const TapeLabel('Fault codes', size: 11),
                    const Spacer(),
                    TapeButton(
                      label: 'Read',
                      compact: true,
                      onPressed: _status == CodesStatus.reading ? null : _read,
                    ),
                    const SizedBox(width: TapeSpace.s2),
                    TapeButton(
                      label: 'Close',
                      icon: TapeIcon.close,
                      compact: true,
                      onPressed: widget.onClose,
                    ),
                  ],
                ),
                const SizedBox(height: TapeSpace.s1),
                Expanded(
                  child: _codesList(palette, theme.livery.numeralWeight),
                ),
                if (_note != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: TapeSpace.s1),
                    child: TapeText(
                      _note!,
                      style: TapeTextStyle.caption,
                      color: palette.inkMid,
                      maxLines: 2,
                    ),
                  ),
                SlideToConfirm(
                  label: 'Slide to clear codes',
                  onConfirmed: _codes.isEmpty ? null : _clear,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _codesList(TapePalette palette, double numeralWeight) {
    final codes = _codes;
    if (_status == CodesStatus.reading) {
      return Center(
        child: TapeText(
          'Asking the car…',
          style: TapeTextStyle.small,
          color: palette.inkMid,
        ),
      );
    }
    if (widget.source.adapterInfo.value == null) {
      return Center(
        child: TapeText(
          'No car connected yet.',
          style: TapeTextStyle.small,
          color: palette.inkMid,
        ),
      );
    }
    if (_status == CodesStatus.failed) {
      return Center(
        child: TapeText(
          'The car did not answer. Ignition on, then Read.',
          style: TapeTextStyle.small,
          color: palette.inkMid,
          textAlign: TextAlign.center,
        ),
      );
    }
    if (codes.isEmpty) {
      return Center(
        child: TapeText(
          'No fault codes.',
          style: TapeTextStyle.small,
          color: palette.accentCore,
        ),
      );
    }
    return ListView.builder(
      itemCount: codes.length,
      physics: const ClampingScrollPhysics(),
      itemBuilder: (context, i) {
        final (dtc, stored) = codes[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: TapeSpace.s2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 78,
                child: Text(
                  dtc.code,
                  style: TapeType.numeral(
                    size: 20,
                    weight: numeralWeight,
                    color: palette.inkBright,
                  ),
                ),
              ),
              Expanded(
                child: TapeText(
                  widget.descriptions.describe(dtc),
                  style: TapeTextStyle.caption,
                  color: palette.inkMid,
                  maxLines: 3,
                ),
              ),
              const SizedBox(width: TapeSpace.s2),
              TapeLabel(
                stored ? 'Stored' : 'Pending',
                size: 10,
                color: stored ? palette.caution : palette.inkDim,
              ),
            ],
          ),
        );
      },
    );
  }

  // The PIDs 01 to 60 (hex), in rows of sixteen.
  static const int _pidCount = 0x60;

  static int _answered(AdapterInfo info) => [
    for (final p in info.supportedPids)
      if (p >= 1 && p <= _pidCount) p,
  ].length;

  void _tapMatrix(Offset at, Size size) {
    final pid = PidMatrixPainter.pidAt(at, size);
    setState(() => _pid = pid == _pid ? null : pid);
  }

  String _pidCaption(AdapterInfo? info) {
    final pid = _pid;
    if (pid == null) {
      return info == null
          ? 'Lit when the car answers.'
          : 'Tap a cell to name it.';
    }
    final hex = pid.toRadixString(16).toUpperCase().padLeft(2, '0');
    final name = Pids.byId(pid)?.name;
    final answers = info?.supportedPids.contains(pid) ?? false;
    return '$hex  ${name ?? 'Not one TapeDash reads'}  ·  '
        '${answers ? 'the car answers' : 'no answer'}';
  }
}

class _AdapterFacts extends StatelessWidget {
  const _AdapterFacts({
    required this.info,
    required this.fuel,
    required this.volts,
    required this.palette,
  });

  final AdapterInfo? info;
  final String fuel;
  final double? volts;
  final TapePalette palette;

  @override
  Widget build(BuildContext context) {
    Widget row(String label, String value) => SizedBox(
      height: 18,
      child: Row(
        children: [
          SizedBox(width: 78, child: TapeLabel(label, size: 10)),
          Expanded(
            child: TapeText(
              value,
              style: TapeTextStyle.caption,
              color: palette.inkBright,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
    final i = info;
    return Column(
      children: [
        row('Adapter', i == null ? '—' : i.banner),
        row('Protocol', i == null ? '—' : protocolName(i.protocolNumber)),
        row('Voltage', volts == null ? '—' : '${volts!.toStringAsFixed(1)} V'),
        row('Fuel from', fuel),
      ],
    );
  }
}

/// The PID matrix's grid: one small chamfered cell for each Mode 01 PID from 01 to
/// 60 (hex), sixteen to a row, lit in the accent where the car answers.
class PidMatrixPainter extends CustomPainter {
  PidMatrixPainter({
    required this.supported,
    required this.selected,
    required this.palette,
  });

  final Set<int> supported;
  final int? selected;
  final TapePalette palette;

  static const int columns = 16;
  static const int rows = 6;
  static const double gap = 2;

  static Size _cell(Size size) => Size(
    (size.width - gap * (columns - 1)) / columns,
    math.min(
      (size.height - gap * (rows - 1)) / rows,
      (size.width - gap * (columns - 1)) / columns,
    ),
  );

  /// The PID (1 to 0x60) under [at], or null between cells.
  static int? pidAt(Offset at, Size size) {
    final cell = _cell(size);
    final col = (at.dx / (cell.width + gap)).floor();
    final row = (at.dy / (cell.height + gap)).floor();
    if (col < 0 || col >= columns || row < 0 || row >= rows) return null;
    return row * columns + col + 1;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cell = _cell(size);
    final stroke = TapeStroke.fine * palette.strokeScale;
    final off = Paint()
      ..color = palette.etch
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    final on = Paint()..color = palette.accentCore;
    final ring = Paint()
      ..color = palette.inkBright
      ..style = PaintingStyle.stroke
      ..strokeWidth = TapeStroke.fine * palette.strokeScale;
    for (var pid = 1; pid <= columns * rows; pid++) {
      final col = (pid - 1) % columns;
      final row = (pid - 1) ~/ columns;
      final rect = Rect.fromLTWH(
        col * (cell.width + gap),
        row * (cell.height + gap),
        cell.width,
        cell.height,
      );
      final path = Chamfer.all(rect.deflate(stroke), 2);
      if (supported.contains(pid)) {
        canvas.drawPath(path, on);
      } else {
        canvas.drawPath(path, off);
      }
      if (pid == selected) canvas.drawPath(Chamfer.all(rect, 2), ring);
    }
  }

  @override
  bool shouldRepaint(PidMatrixPainter old) =>
      !setEquals(old.supported, supported) ||
      old.selected != selected ||
      old.palette != palette;
}

/// The poll rate over the last minute as a thin line.
class _SparklinePainter extends CustomPainter {
  _SparklinePainter({
    required this.rates,
    required Listenable repaint,
    required this.palette,
  }) : super(repaint: repaint);

  final List<double> rates;
  final TapePalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(
      Offset(0, size.height - 1),
      Offset(size.width, size.height - 1),
      Paint()
        ..color = palette.etch
        ..strokeWidth = TapeStroke.fine,
    );
    if (rates.length < 2) return;
    final top = math.max(1.0, rates.reduce(math.max));
    final path = Path();
    for (var i = 0; i < rates.length; i++) {
      final x = size.width * i / (DiagnosticsPageState._historyLength - 1);
      final y = size.height - 2 - (size.height - 4) * (rates[i] / top);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = TapeStroke.regular * palette.strokeScale
        ..color = palette.accentCore,
    );
  }

  @override
  bool shouldRepaint(_SparklinePainter old) => old.palette != palette;
}
