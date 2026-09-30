import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../app/app_services.dart';
import '../../core/fuel_blend.dart';
import '../../fuel/fuel_constants.dart';
import '../../money/pit_stop_form.dart';
import '../../obd/adapter_checker.dart';
import '../../obd/adapter_config.dart';
import '../../obd/address_entry.dart';
import '../../platform/adapter_radio.dart';
import '../design/components/controls/tape_button.dart';
import '../design/components/controls/tape_list_row.dart';
import '../design/components/controls/tape_numpad.dart';
import '../design/components/controls/tape_segmented.dart';
import '../design/components/controls/tape_slider.dart';
import '../design/components/tape_label.dart';
import '../design/icons/icons.dart';
import '../design/theme/palette.dart';
import '../design/theme/tape_theme.dart';
import '../design/tokens/spacing.dart';
import '../design/tokens/strokes.dart';

/// The connect path (DESIGN.md 7.11): adapter type, find and pair it, the car,
/// the price of fuel (skippable), and the layout to start on. A thin tape across
/// the top shows how far along it is.
///
/// Nothing is saved until the last step, except that the car's setup and the price
/// are kept as they are entered: going back never loses them. **Not yet as the
/// spec has it:** the last step lists the five layouts by name, not with live
/// previews, and the scenes' illustrations are simple line art.
///
/// Unverified on hardware until the handoff (CLAUDE.md 11): the Bluetooth steps
/// are tested against fake radios.
class ConnectFlow extends StatefulWidget {
  const ConnectFlow({
    super.key,
    required this.services,
    required this.checker,
    required this.radios,
    required this.width,
    required this.height,
    required this.onDone,
    required this.onCancel,
  });

  final AppServices services;

  /// Says whether an address may be used, and whether an adapter answers.
  final AdapterChecker checker;

  /// The Bluetooth radio for a kind.
  final AdapterRadio Function(RadioKind kind) radios;

  final double width;
  final double height;

  /// Called once the adapter is saved and the flow is finished.
  final VoidCallback onDone;

  /// Called when the user backs out of the first step.
  final VoidCallback onCancel;

  @override
  State<ConnectFlow> createState() => ConnectFlowState();
}

/// The steps, in order.
enum ConnectStep { type, find, car, price, layout }

/// Where a WiFi ELM327 usually is.
const String _defaultHost = '192.168.0.10';
const int _defaultPort = 35000;

class ConnectFlowState extends State<ConnectFlow> {
  ConnectStep _step = ConnectStep.type;
  AdapterKind? _kind;
  AdapterConfig? _chosen;

  // Finding a Bluetooth adapter.
  RadioStatus? _status;
  final List<FoundAdapter> _found = [];
  // Cancelled in _stopScan.
  // ignore: cancel_subscriptions
  StreamSubscription<FoundAdapter>? _scan;
  bool _pairing = false;
  String? _note;

  // A WiFi adapter.
  final AddressEntry _entry = AddressEntry(
    host: _defaultHost,
    port: '$_defaultPort',
  );
  bool _testing = false;

  // The car, the price and the layout.
  late VehicleSetup _setup = widget.services.setup.value;
  final PitStopForm _price = PitStopForm(priceOnly: true);
  late int _cluster = widget.services.settings.cluster.value;

  ConnectStep get step => _step;
  AdapterKind? get kind => _kind;
  AdapterConfig? get chosen => _chosen;
  bool get isPairing => _pairing;

  @override
  void dispose() {
    _stopScan();
    super.dispose();
  }

  RadioKind get _radioKind =>
      _kind == AdapterKind.ble ? RadioKind.ble : RadioKind.bluetoothClassic;

  static const Map<ConnectStep, String> _titles = {
    ConnectStep.type: 'How does your adapter connect?',
    ConnectStep.find: 'Find your adapter',
    ConnectStep.car: 'Your car',
    ConnectStep.price: 'What does fuel cost?',
    ConnectStep.layout: 'Pick a layout',
  };

  static const Map<ConnectStep, String> _hints = {
    ConnectStep.type:
        'Plug the adapter into the car\'s OBD port, under the dash, and turn the ignition on.',
    ConnectStep.find: 'Keep the adapter plugged in and the ignition on.',
    ConnectStep.car:
        'So fuel and money can be worked out. The estimates get better with your fill-ups.',
    ConnectStep.price:
        'A litre, in rupees. You can skip this and set it later.',
    ConnectStep.layout:
        'Swipe up or down on the drive screen to change it any time.',
  };

  // ---- moving between steps --------------------------------------------

  void _go(ConnectStep next) => setState(() {
    _step = next;
    _note = null;
  });

  void _back() {
    switch (_step) {
      case ConnectStep.type:
        widget.onCancel();
      case ConnectStep.find:
        _stopScan();
        _go(ConnectStep.type);
      case ConnectStep.car:
        _go(ConnectStep.find);
      case ConnectStep.price:
        _go(ConnectStep.car);
      case ConnectStep.layout:
        _go(ConnectStep.price);
    }
  }

  // ---- step 1: type ------------------------------------------------------

  void _chooseKind(AdapterKind kind) {
    _kind = kind;
    _found.clear();
    _status = null;
    _go(ConnectStep.find);
    if (kind != AdapterKind.wifi) unawaited(_prepareRadio());
  }

  // ---- step 2: find ------------------------------------------------------

  Future<void> _prepareRadio() async {
    final radio = widget.radios(_radioKind);
    RadioStatus status;
    try {
      status = await radio.status();
    } on Object {
      status = const RadioStatus(
        supported: false,
        enabled: false,
        permitted: false,
      );
    }
    if (!mounted) return;
    setState(() => _status = status);
    if (status.ready) await _startScan();
  }

  Future<void> _allow() async {
    final radio = widget.radios(_radioKind);
    try {
      await radio.requestPermission();
    } on Object {
      // Shown by the status below.
    }
    await _prepareRadio();
  }

  Future<void> _startScan() async {
    _stopScan();
    final radio = widget.radios(_radioKind);
    try {
      final paired = await radio.paired();
      if (!mounted) return;
      setState(() {
        for (final a in paired) {
          if (!_found.contains(a)) _found.add(a);
        }
        _sortFound();
      });
    } on Object {
      // A phone that will not list them can still search.
    }
    _scan = radio.scan().listen(
      (a) {
        if (!mounted || _found.contains(a)) return;
        setState(() {
          _found.add(a);
          _sortFound();
        });
      },
      onError: (Object _) {
        if (mounted) {
          setState(() => _note = 'The search stopped. Try again.');
        }
      },
    );
  }

  void _sortFound() {
    _found.sort((a, b) {
      if (a.looksLikeAdapter != b.looksLikeAdapter) {
        return a.looksLikeAdapter ? -1 : 1;
      }
      if (a.paired != b.paired) return a.paired ? -1 : 1;
      return a.displayName.compareTo(b.displayName);
    });
  }

  // Not awaited: letting go of a search is the radio's business, and the screen
  // does not wait for it.
  void _stopScan() {
    final scan = _scan;
    _scan = null;
    unawaited(scan?.cancel());
  }

  Future<void> _pick(FoundAdapter adapter) async {
    if (_pairing) return;
    _stopScan();
    if (adapter.kind == RadioKind.bluetoothClassic && !adapter.paired) {
      setState(() {
        _pairing = true;
        _note =
            'Pairing with ${adapter.displayName}. If it asks for a PIN, '
            'try 1234 or 0000.';
      });
      try {
        await widget.radios(RadioKind.bluetoothClassic).pair(adapter.address);
      } on Object {
        if (!mounted) return;
        setState(() {
          _pairing = false;
          _note =
              'Could not pair. Check the PIN (usually 1234 or 0000) and try again.';
        });
        unawaited(_startScan());
        return;
      }
      if (!mounted) return;
      setState(() => _pairing = false);
    }
    _chosen = AdapterConfig(
      kind: _kind!,
      address: adapter.address,
      name: adapter.name,
    );
    _go(ConnectStep.car);
  }

  // WiFi.

  AdapterConfig? _wifiConfig() {
    if (!_entry.complete) return null;
    return AdapterConfig(
      kind: AdapterKind.wifi,
      address: _entry.host,
      port: _entry.portNumber,
      name: 'WiFi adapter',
    );
  }

  Future<void> _testWifi() async {
    final config = _wifiConfig();
    if (config == null || _testing) return;
    if (!widget.checker.allows(config.address)) {
      setState(
        () => _note =
            'TapeDash only talks to adapters on your own network: that address is not one.',
      );
      return;
    }
    setState(() {
      _testing = true;
      _note = 'Trying ${config.address}…';
    });
    final answered = await widget.checker.reachable(config);
    final message = answered
        ? 'The adapter answered.'
        : 'Nothing answered. Join the adapter\'s WiFi network in Android\'s settings first.';
    if (!mounted) return;
    setState(() {
      _testing = false;
      _note = message;
    });
  }

  void _useWifi() {
    final config = _wifiConfig();
    if (config == null) return;
    if (!widget.checker.allows(config.address)) {
      setState(
        () => _note =
            'TapeDash only talks to adapters on your own network: that address is not one.',
      );
      return;
    }
    _chosen = config;
    _go(ConnectStep.car);
  }

  // ---- steps 3 to 5 ------------------------------------------------------

  Future<void> _carNext() async {
    await widget.services.setVehicleSetup(_setup);
    if (mounted) _go(ConnectStep.price);
  }

  Future<void> _priceNext({required bool skip}) async {
    final price = _price.pricePerLitre;
    if (!skip && price != null && _price.canSave) {
      await widget.services.money.setPrice(price);
    }
    if (mounted) _go(ConnectStep.layout);
  }

  Future<void> _finish() async {
    final config = _chosen;
    if (config == null) return;
    widget.services.settings.cluster.value = _cluster;
    await widget.services.adapters.choose(config);
    widget.services.settings.onboarded.value = true;
    if (mounted) widget.onDone();
  }

  // ---- drawing -----------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final palette = TapeTheme.of(context).palette;
    final margin = TapeSpace.margin(widget.height);
    final leftW = widget.width * 0.34 - margin;
    final rightLeft = widget.width * 0.40;
    final index = ConnectStep.values.indexOf(_step);

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: Stack(
        children: [
          // The progress, a thin tape at the top.
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 4,
            child: CustomPaint(
              painter: _ProgressPainter(
                share: (index + 1) / ConnectStep.values.length,
                palette: palette,
              ),
            ),
          ),
          Positioned(
            left: margin,
            top: margin,
            width: leftW,
            bottom: margin,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TapeLabel(
                  'Step ${index + 1} of ${ConnectStep.values.length}',
                  size: 11,
                ),
                const SizedBox(height: TapeSpace.s1),
                TapeText(
                  _titles[_step]!,
                  style: TapeTextStyle.title,
                  maxLines: 3,
                ),
                const SizedBox(height: TapeSpace.s2),
                TapeText(
                  _hints[_step]!,
                  style: TapeTextStyle.caption,
                  color: palette.inkMid,
                  maxLines: 4,
                ),
                const Spacer(),
                SizedBox(
                  height: widget.height * 0.26,
                  width: leftW,
                  child: CustomPaint(
                    painter: _IllustrationPainter(_step, palette),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: rightLeft,
            right: margin,
            top: margin,
            bottom: margin,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _content(palette)),
                const SizedBox(height: TapeSpace.s2),
                _buttons(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buttons() {
    final Widget? next = switch (_step) {
      ConnectStep.type => null,
      ConnectStep.find =>
        _kind == AdapterKind.wifi
            ? TapeButton(
                label: 'Next',
                primary: true,
                onPressed: _entry.complete ? _useWifi : null,
              )
            : null,
      ConnectStep.car => TapeButton(
        label: 'Next',
        primary: true,
        onPressed: _carNext,
      ),
      ConnectStep.price => TapeButton(
        label: 'Next',
        primary: true,
        onPressed: _price.canSave ? () => _priceNext(skip: false) : null,
      ),
      ConnectStep.layout => TapeButton(
        label: 'Start driving',
        primary: true,
        icon: TapeIcon.hud,
        onPressed: _finish,
      ),
    };
    return Row(
      children: [
        TapeButton(
          label: _step == ConnectStep.type ? 'Cancel' : 'Back',
          icon: _step == ConnectStep.type ? TapeIcon.close : TapeIcon.back,
          compact: true,
          onPressed: _back,
        ),
        const SizedBox(width: TapeSpace.s2),
        if (_step == ConnectStep.price)
          TapeButton(
            label: 'Skip',
            compact: true,
            onPressed: () => _priceNext(skip: true),
          ),
        if (_step == ConnectStep.find && _kind == AdapterKind.wifi)
          TapeButton(
            label: 'Test',
            compact: true,
            onPressed: _entry.complete && !_testing ? _testWifi : null,
          ),
        const Spacer(),
        ?next,
      ],
    );
  }

  Widget _content(TapePalette palette) => switch (_step) {
    ConnectStep.type => _typeList(),
    ConnectStep.find =>
      _kind == AdapterKind.wifi ? _wifiEntry(palette) : _findList(palette),
    ConnectStep.car => _carSetup(),
    ConnectStep.price => _priceEntry(palette),
    ConnectStep.layout => _layoutList(),
  };

  Widget _typeList() => ListView(
    physics: const ClampingScrollPhysics(),
    children: [
      TapeListRow(
        label: 'Bluetooth',
        value: 'Most cheap adapters',
        icon: TapeIcon.bluetooth,
        onTap: () => _chooseKind(AdapterKind.bluetoothClassic),
      ),
      TapeListRow(
        label: 'Bluetooth LE',
        value: 'Newer adapters',
        icon: TapeIcon.bluetooth,
        onTap: () => _chooseKind(AdapterKind.ble),
      ),
      TapeListRow(
        label: 'WiFi',
        value: 'Has its own network',
        icon: TapeIcon.wifi,
        onTap: () => _chooseKind(AdapterKind.wifi),
      ),
    ],
  );

  Widget _findList(TapePalette palette) {
    final status = _status;
    Widget message(String text, {List<Widget> actions = const []}) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TapeText(text, style: TapeTextStyle.small, color: palette.inkMid),
        const SizedBox(height: TapeSpace.s2),
        ...actions,
      ],
    );

    if (status == null) {
      return message('Looking at Bluetooth…');
    }
    if (!status.supported) {
      return message(
        'This phone has no ${_kind == AdapterKind.ble ? 'Bluetooth LE' : 'Bluetooth'}. A WiFi adapter would work.',
      );
    }
    if (!status.permitted) {
      return message(
        'TapeDash needs permission to find nearby Bluetooth devices. It uses it for nothing else.',
        actions: [TapeButton(label: 'Allow', primary: true, onPressed: _allow)],
      );
    }
    if (!status.enabled) {
      return message(
        'Bluetooth is off. Turn it on in Android\'s settings, then try again.',
        actions: [TapeButton(label: 'Try again', onPressed: _prepareRadio)],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            TapeLabel(_scan == null ? 'Adapters' : 'Adapters nearby', size: 11),
            const Spacer(),
            TapeButton(
              label: 'Search again',
              compact: true,
              onPressed: _pairing ? null : _startScan,
            ),
          ],
        ),
        const SizedBox(height: TapeSpace.s1),
        Expanded(
          child: _found.isEmpty
              ? Center(
                  child: TapeText(
                    'Searching…',
                    style: TapeTextStyle.small,
                    color: palette.inkMid,
                  ),
                )
              : ListView(
                  physics: const ClampingScrollPhysics(),
                  children: [
                    for (final a in _found)
                      TapeListRow(
                        label: a.displayName,
                        value: a.paired ? 'Paired' : a.address,
                        selected: a.looksLikeAdapter,
                        onTap: _pairing ? null : () => _pick(a),
                      ),
                  ],
                ),
        ),
        if (_note != null)
          TapeText(
            _note!,
            style: TapeTextStyle.caption,
            color: palette.inkMid,
            maxLines: 2,
          ),
      ],
    );
  }

  Widget _wifiEntry(TapePalette palette) {
    final keySize =
        ((widget.height - 2 * TapeSpace.margin(widget.height) - 70) / 4).clamp(
          40.0,
          56.0,
        );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _EntryField(
                label: 'Address',
                text: _entry.host,
                active: !_entry.editingPort,
                onTap: () => setState(() => _entry.editingPort = false),
              ),
              const SizedBox(height: TapeSpace.s2),
              _EntryField(
                label: 'Port',
                text: _entry.port,
                active: _entry.editingPort,
                onTap: () => setState(() => _entry.editingPort = true),
              ),
              const SizedBox(height: TapeSpace.s2),
              if (_note != null)
                TapeText(
                  _note!,
                  style: TapeTextStyle.caption,
                  color: palette.inkMid,
                  maxLines: 4,
                )
              else
                TapeText(
                  'Join the adapter\'s WiFi network in Android\'s settings first. '
                  'Most are at $_defaultHost, port $_defaultPort.',
                  style: TapeTextStyle.caption,
                  color: palette.inkDim,
                  maxLines: 4,
                ),
            ],
          ),
        ),
        const SizedBox(width: TapeSpace.s3),
        TapeNumpad(
          keySize: keySize,
          onKey: (k) => setState(() {
            _entry.press(k);
            _note = null;
          }),
        ),
      ],
    );
  }

  Widget _carSetup() => ListView(
    physics: const ClampingScrollPhysics(),
    children: [
      TapeSegmented<FuelType>(
        height: 40,
        value: _setup.fuelType,
        onChanged: (t) => setState(() => _setup = _setup.copyWith(fuelType: t)),
        segments: const [
          TapeSegment(FuelType.petrol, 'Petrol'),
          TapeSegment(FuelType.diesel, 'Diesel'),
        ],
      ),
      if (_setup.fuelType == FuelType.petrol) ...[
        const SizedBox(height: TapeSpace.s2),
        TapeSegmented<PetrolBlend>(
          height: 40,
          value: _setup.blend,
          onChanged: (b) => setState(() => _setup = _setup.copyWith(blend: b)),
          segments: [
            for (final b in PetrolBlend.values) TapeSegment(b, b.label),
          ],
        ),
      ],
      const SizedBox(height: TapeSpace.s2),
      TapeSlider(
        label: 'Engine size',
        value: _setup.displacementLitres,
        min: 0.6,
        max: 6,
        format: (v) => '${v.toStringAsFixed(1)} L',
        onChanged: (v) => setState(
          () => _setup = _setup.copyWith(
            displacementLitres: (v * 10).round() / 10,
          ),
        ),
      ),
      TapeSlider(
        label: 'Tank',
        value: _setup.tankLitres,
        min: 20,
        max: 120,
        format: (v) => '${v.round()} L',
        onChanged: (v) => setState(
          () => _setup = _setup.copyWith(tankLitres: v.roundToDouble()),
        ),
      ),
    ],
  );

  Widget _priceEntry(TapePalette palette) {
    final keySize =
        ((widget.height - 2 * TapeSpace.margin(widget.height) - 70) / 4).clamp(
          40.0,
          56.0,
        );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _EntryField(
                label: 'Price a litre',
                labelWidth: 104,
                text: _price.amountText,
                unit: '₹',
                active: true,
                onTap: () {},
              ),
              const SizedBox(height: TapeSpace.s2),
              if (_price.amountText.isNotEmpty &&
                  _price.issues().contains(PitStopIssue.priceImplausible))
                TapeText(
                  'That price looks wrong.',
                  style: TapeTextStyle.caption,
                  color: palette.caution,
                ),
            ],
          ),
        ),
        const SizedBox(width: TapeSpace.s3),
        TapeNumpad(
          keySize: keySize,
          onKey: (k) => setState(() => _price.press(k)),
        ),
      ],
    );
  }

  static const List<String> _layouts = [
    'Apex',
    'Tape',
    'Minimal',
    'Telemetry',
    'Road',
  ];

  Widget _layoutList() => ListView(
    physics: const ClampingScrollPhysics(),
    children: [
      for (var i = 0; i < _layouts.length; i++)
        _LayoutRow(
          name: _layouts[i],
          selected: i == _cluster,
          onTap: () => setState(() => _cluster = i),
        ),
    ],
  );
}

/// One layout to choose from: a touch target tall, the chosen one lit.
class _LayoutRow extends StatelessWidget {
  const _LayoutRow({
    required this.name,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = TapeTheme.of(context).palette;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: TapeSpace.touchTarget,
        child: Row(
          children: [
            Container(
              width: 4,
              height: 24,
              color: selected ? palette.accentCore : palette.etch,
            ),
            const SizedBox(width: TapeSpace.s3),
            TapeText(
              name,
              color: selected ? palette.accentCore : palette.inkBright,
            ),
          ],
        ),
      ),
    );
  }
}

/// A number being typed: its label and what has been typed so far.
class _EntryField extends StatelessWidget {
  const _EntryField({
    required this.label,
    required this.text,
    required this.active,
    required this.onTap,
    this.unit,
    this.labelWidth = 72,
  });

  final double labelWidth;
  final String label;
  final String text;
  final bool active;
  final VoidCallback onTap;
  final String? unit;

  @override
  Widget build(BuildContext context) {
    final palette = TapeTheme.of(context).palette;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: TapeSpace.s2),
        decoration: BoxDecoration(
          border: Border.all(
            color: active ? palette.accentCore : palette.etchStrong,
            width: TapeStroke.fine,
          ),
        ),
        child: Row(
          children: [
            SizedBox(width: labelWidth, child: TapeLabel(label, size: 10)),
            if (unit != null) ...[
              TapeText(unit!, color: palette.money),
              const SizedBox(width: TapeSpace.s1),
            ],
            Expanded(
              child: TapeText(
                text.isEmpty ? '—' : text,
                style: TapeTextStyle.title,
                color: text.isEmpty ? palette.inkDim : palette.inkBright,
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressPainter extends CustomPainter {
  _ProgressPainter({required this.share, required this.palette});

  final double share;
  final TapePalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, size.height - 1, size.width, 1),
      Paint()..color = palette.etch,
    );
    canvas.drawRect(
      Rect.fromLTWH(0, size.height - 2, size.width * share, 2),
      Paint()..color = palette.accentCore,
    );
  }

  @override
  bool shouldRepaint(_ProgressPainter old) =>
      old.share != share || old.palette != palette;
}

/// The scenes' line art (DESIGN.md 7.11), in the accent: the adapter going into
/// the port, the ignition on, the phone on the dash.
class _IllustrationPainter extends CustomPainter {
  _IllustrationPainter(this.step, this.palette);

  final ConnectStep step;
  final TapePalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = palette.accentCore
      ..style = PaintingStyle.stroke
      ..strokeWidth = TapeStroke.fine * palette.strokeScale
      ..strokeJoin = StrokeJoin.miter;
    final dim = Paint()
      ..color = palette.etchStrong
      ..style = PaintingStyle.stroke
      ..strokeWidth = TapeStroke.fine * palette.strokeScale;
    final w = size.width;
    final h = size.height;
    switch (step) {
      case ConnectStep.type:
      case ConnectStep.find:
        // The OBD port under the dash, and the adapter about to go in.
        final port = Path()
          ..moveTo(w * 0.52, h * 0.30)
          ..lineTo(w * 0.94, h * 0.30)
          ..lineTo(w * 0.86, h * 0.72)
          ..lineTo(w * 0.60, h * 0.72)
          ..close();
        canvas.drawPath(port, dim);
        for (var i = 0; i < 4; i++) {
          final x = w * (0.60 + i * 0.07);
          canvas.drawLine(Offset(x, h * 0.42), Offset(x, h * 0.56), dim);
        }
        canvas.drawRect(
          Rect.fromLTWH(w * 0.04, h * 0.32, w * 0.36, h * 0.38),
          line,
        );
        canvas.drawLine(
          Offset(w * 0.40, h * 0.42),
          Offset(w * 0.52, h * 0.42),
          line,
        );
        canvas.drawLine(
          Offset(w * 0.40, h * 0.60),
          Offset(w * 0.52, h * 0.60),
          line,
        );
        canvas.drawCircle(
          Offset(w * 0.12, h * 0.51),
          3,
          Paint()..color = palette.accentCore,
        );
      case ConnectStep.car:
        // An ignition key, turned on.
        canvas.drawCircle(Offset(w * 0.30, h * 0.5), h * 0.22, line);
        canvas.drawCircle(Offset(w * 0.30, h * 0.5), h * 0.07, dim);
        canvas.drawLine(
          Offset(w * 0.52, h * 0.5),
          Offset(w * 0.92, h * 0.5),
          line,
        );
        canvas.drawLine(
          Offset(w * 0.78, h * 0.5),
          Offset(w * 0.78, h * 0.68),
          line,
        );
        canvas.drawLine(
          Offset(w * 0.88, h * 0.5),
          Offset(w * 0.88, h * 0.62),
          line,
        );
      case ConnectStep.price:
      case ConnectStep.layout:
        // The phone on the dash, under the windscreen.
        canvas.drawLine(Offset(0, h * 0.30), Offset(w, h * 0.16), dim);
        canvas.drawLine(Offset(0, h * 0.86), Offset(w, h * 0.86), dim);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.22, h * 0.32, w * 0.56, h * 0.44),
            const Radius.circular(3),
          ),
          line,
        );
        canvas.drawLine(
          Offset(w * 0.28, h * 0.62),
          Offset(w * 0.72, h * 0.62),
          line,
        );
        canvas.drawCircle(Offset(w * 0.5, h * 0.46), h * 0.08, line);
    }
  }

  @override
  bool shouldRepaint(_IllustrationPainter old) =>
      old.step != step || old.palette != palette;
}
