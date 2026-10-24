part of 'connect_flow.dart';

/// The connect flow on a round watch face (DESIGN.md 16.8): the same steps, the
/// same radios, pairing and trial of the link as the phone's, drawn as wheels the
/// bezel and a swipe can turn. There is no keypad on a wrist, so:
///
/// - **Type** is a wheel: Bluetooth (which finds both radios), WiFi, Cancel.
/// - **Find**, for Bluetooth, is a wheel of what the radios found, nearest first,
///   each with its radio and how close it is. A pick is tried before it is taken.
///   When it will not open the wheel becomes the way out: forget the pairing and
///   pair again, try the same adapter on its other radio, use it anyway, search
///   again. For WiFi it is the usual address (192.168.0.10, port 35000) and a test;
///   any other address arrives by import.
/// - **Done**: the adapter is saved and the drive begins. The car's fuel, the price
///   and the layout are not asked (they have their defaults, and arrive by import
///   or from the menu).
///
/// Back (the button, or a swipe to the right) goes a step back. Nothing is saved
/// until the end.
extension _WatchConnect on ConnectFlowState {
  Widget _buildWatch(BuildContext context) {
    final face = WatchFace.of(widget.width, widget.height);
    final motion = MotionScope.of(context);
    final palette = TapeTheme.of(context).palette;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: (d) {
        if (d.velocity.pixelsPerSecond.dx > WatchSheet.closeVelocity) _back();
      },
      child: Center(
        child: SizedBox.square(
          dimension: face.diameter,
          child: Stack(
            children: [
              // Where in the flow, as a short arc of the rim.
              Positioned.fill(
                child: CustomPaint(
                  painter: _WatchProgressPainter(
                    share: _step == ConnectStep.type ? 0.34 : 0.67,
                    face: face,
                    palette: palette,
                  ),
                ),
              ),
              Positioned.fill(
                child: KeyedSubtree(
                  key: ValueKey('${_step.name}-${_watchPhase()}'),
                  child: _watchStep(context, face, motion),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Which screen of a step is up, so that a wheel is made fresh for each.
  String _watchPhase() {
    if (_pairing || _checking) return 'busy';
    if (_failed != null) return 'failed';
    if (_testing) return 'testing';
    final s = _status;
    if (_step == ConnectStep.find && _kind != AdapterKind.wifi) {
      if (s == null) return 'looking';
      if (!s.supported) return 'none';
      if (!s.permitted) return 'allow';
      if (!s.enabled) return 'off';
      return 'list${_found.length}';
    }
    return 'wheel';
  }

  Widget _watchStep(BuildContext context, WatchFace face, MotionClock motion) {
    switch (_step) {
      case ConnectStep.type:
        return _wheel(face, motion, 'Adapter', [
          _Row(
            'Bluetooth',
            'most adapters',
            () => _chooseKind(AdapterKind.bluetoothClassic),
          ),
          _Row(
            'WiFi',
            'has its own network',
            () => _chooseKind(AdapterKind.wifi),
          ),
          _Row('Cancel', null, widget.onCancel),
        ]);
      case ConnectStep.find:
        return _kind == AdapterKind.wifi
            ? _watchWifi(face, motion)
            : _watchFind(face, motion);
      case ConnectStep.car:
      case ConnectStep.price:
      case ConnectStep.layout:
        // Not asked on a watch: if a state got here, finish with what there is.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_finish());
        });
        return _say(face, 'Starting…');
    }
  }

  Widget _watchFind(WatchFace face, MotionClock motion) {
    if (_pairing || _checking) return _say(face, _note ?? 'Working…');
    final failed = _failed;
    if (failed != null) {
      final other = _otherRadio(failed);
      return _wheel(face, motion, 'No answer', [
        if (failed.kind == RadioKind.bluetoothClassic)
          _Row('Forget, pair again', 'asks for the PIN afresh', _forgetAndPair)
        else
          _Row('Try again', failed.displayName, () => unawaited(_pick(failed))),
        if (other != null)
          _Row(
            'Try ${other.displayName}',
            'its other radio',
            () => unawaited(_pick(other)),
          ),
        _Row('Use anyway', 'ignition off?', _useAnyway),
        _Row('Back', null, _dismissFailure),
      ]);
    }
    final status = _status;
    if (status == null) return _say(face, 'Looking at Bluetooth…');
    if (!status.supported) {
      return _wheel(face, motion, 'No Bluetooth', [
        _Row(
          'WiFi instead',
          'an adapter with its own network',
          () => _chooseKind(AdapterKind.wifi),
        ),
        _Row('Back', null, _back),
      ]);
    }
    if (!status.permitted) {
      return _wheel(face, motion, 'Permission', [
        _Row('Allow', 'to find nearby devices', () => unawaited(_allow())),
        _Row('Back', null, _back),
      ]);
    }
    if (!status.enabled) {
      return _wheel(face, motion, 'Bluetooth is off', [
        _Row(
          'Try again',
          'turn it on in settings',
          () => unawaited(_prepareRadio()),
        ),
        _Row('Back', null, _back),
      ]);
    }
    return _wheel(face, motion, _scanning ? 'Searching' : 'Adapters', [
      for (final a in _found)
        _Row(a.displayName, _watchDescribe(a), () => unawaited(_pick(a))),
      _Row(
        'Search again',
        _found.isEmpty ? 'nothing found yet' : null,
        () => unawaited(_startScan()),
      ),
      _Row('Back', null, _back),
    ]);
  }

  Widget _watchWifi(WatchFace face, MotionClock motion) {
    if (_testing) return _say(face, _note ?? 'Trying…');
    return _wheel(face, motion, 'WiFi adapter', [
      _Row('Use $_defaultHost', 'port $_defaultPort', _useWifi),
      _Row(
        'Test the link',
        _note ?? 'join its network first',
        () => unawaited(_testWifi()),
      ),
      _Row('Back', null, _back),
    ]);
  }

  /// "Low Energy · Close": the radio and the signal, without the address.
  String _watchDescribe(FoundAdapter a) {
    final radio = a.kind == RadioKind.ble ? 'LE' : 'Classic';
    final rssi = a.rssi;
    final signal = rssi == null
        ? ''
        : rssi >= -60
        ? ' · close'
        : rssi >= -75
        ? ' · near'
        : ' · far';
    return '$radio$signal';
  }

  Widget _wheel(
    WatchFace face,
    MotionClock motion,
    String title,
    List<_Row> rows,
  ) => WatchWheel(
    title: title,
    itemCount: rows.length,
    face: face,
    motion: motion,
    rotary: widget.rotary,
    rowAt: (i) => WheelRow(label: rows[i].label, value: rows[i].value),
    onChoose: (i) => rows[i].run(),
  );

  /// A few words in the middle of the face while something is tried.
  Widget _say(WatchFace face, String text) {
    final palette = TapeTheme.of(context).palette;
    return Center(
      child: SizedBox(
        width: face.roomAt(face.radius, face.diameter * 0.45),
        child: Text(
          text,
          textAlign: TextAlign.center,
          maxLines: 5,
          overflow: TextOverflow.ellipsis,
          style: TapeType.parkedSmall(color: palette.inkBright),
        ),
      ),
    );
  }
}

class _Row {
  const _Row(this.label, this.value, this.run);
  final String label;
  final String? value;
  final VoidCallback run;
}

/// A short arc of the rim that says how far through the flow it is.
class _WatchProgressPainter extends CustomPainter {
  _WatchProgressPainter({
    required this.share,
    required this.face,
    required this.palette,
  });

  final double share;
  final WatchFace face;
  final TapePalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(center: face.centre, radius: face.rimRadius);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = TapeStroke.regular
      ..strokeCap = StrokeCap.butt;
    // The whole way, faint; and the part done, lit; from 12 o'clock, clockwise.
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi,
      false,
      paint..color = palette.track,
    );
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * share,
      false,
      paint..color = palette.accentCore,
    );
  }

  @override
  bool shouldRepaint(_WatchProgressPainter old) =>
      old.share != share || old.palette != palette || old.face != face;
}
