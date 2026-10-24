import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';

import '../obd/adapter_config.dart';
import '../ui/design/components/watch/watch_face.dart';
import '../ui/design/components/watch/watch_wheel.dart';
import '../ui/design/motion/motion_clock.dart';
import '../ui/design/motion/observable_listenable.dart';
import '../ui/design/tokens/livery.dart';
import '../ui/pages/watch/watch_sheets.dart';
import 'app_info.dart';
import 'app_services.dart';
import 'exchange_coordinator.dart';

/// Which screen of the menu is up.
enum _Sheet { none, menu, source, price, look, data, message, about }

/// The watch's menu and the wheels it opens (DESIGN.md 16.7), over the face: the
/// settings worth changing at the wrist, each a wheel the bezel, a swipe and a tap
/// turn. It is the same for a drive from the adapter and one from the GPS alone,
/// which differ only in what is in it (an adapter drive has a price and a trip to
/// end; a GPS-only one has a trip to reset).
///
/// It draws nothing while it is closed. [WatchMenuState.open] opens it and
/// [WatchMenuState.back] closes the innermost screen (the Back button's, a swipe
/// to the right's), and says whether there was one.
class WatchMenu extends StatefulWidget {
  const WatchMenu({
    super.key,
    required this.app,
    required this.face,
    required this.motion,
    this.rotary,
    this.exchange,
    this.onChangeAdapter,
    this.onEndTrip,
    this.onResetTrip,
    this.tripRunning,
    this.gpsOnly = false,
    this.onOpenChanged,
  });

  final AppServices app;
  final WatchFace face;
  final MotionClock motion;

  /// The bezel.
  final Stream<int>? rotary;
  final ExchangeCoordinator? exchange;

  /// Opens the connect flow (the app's).
  final VoidCallback? onChangeAdapter;

  /// Ends the trip being recorded. Null leaves the row out.
  final VoidCallback? onEndTrip;

  /// Puts a GPS drive's distance, time and fastest back to nothing. Null leaves
  /// the row out.
  final VoidCallback? onResetTrip;

  /// Whether a trip is being recorded, for the End trip row.
  final ValueListenable<bool>? tripRunning;

  /// The drive is on the GPS alone: no price.
  final bool gpsOnly;

  /// Told when the menu opens or closes, so that the reel can let go of the bezel.
  final ValueChanged<bool>? onOpenChanged;

  @override
  State<WatchMenu> createState() => WatchMenuState();
}

class WatchMenuState extends State<WatchMenu> {
  final List<_Sheet> _sheets = [];

  _Sheet get _sheet => _sheets.isEmpty ? _Sheet.none : _sheets.last;

  AppServices get _app => widget.app;
  Stream<int>? get _rotary => widget.rotary;

  /// Whether any screen of the menu is up.
  bool get isOpen => _sheets.isNotEmpty;

  /// Opens the menu.
  void open() => _push(_Sheet.menu);

  /// Closes the innermost screen. Returns false if none was open.
  bool back() {
    if (_sheets.isEmpty) return false;
    _close();
    return true;
  }

  void _push(_Sheet sheet) {
    setState(() => _sheets.add(sheet));
    widget.onOpenChanged?.call(true);
  }

  void _open(_Sheet sheet) => _push(sheet);

  void _close() {
    if (_sheets.isEmpty) return;
    setState(_sheets.removeLast);
    if (_sheets.isEmpty) widget.onOpenChanged?.call(false);
  }

  void _closeAll() {
    if (_sheets.isEmpty) return;
    setState(_sheets.clear);
    widget.onOpenChanged?.call(false);
  }

  /// Says what an export or an import did, over the Data wheel.
  void _show() {
    if (!mounted) return;
    setState(() => _sheets.add(_Sheet.message));
  }

  @override
  Widget build(BuildContext context) {
    if (_sheet == _Sheet.none) return const SizedBox.shrink();
    return WatchSheet(
      face: widget.face,
      onClose: _close,
      // Its own key: a wheel opened over a wheel would be the same widget in the
      // same place, and keep the other's row.
      child: KeyedSubtree(
        key: ValueKey(_sheet),
        child: _sheetBody(widget.face, widget.motion),
      ),
    );
  }

  Widget _sheetBody(WatchFace face, MotionClock motion) {
    final rotary = _rotary;
    switch (_sheet) {
      case _Sheet.menu:
      case _Sheet.none:
        return ListenableBuilder(
          listenable: Listenable.merge([
            ?widget.tripRunning,
            ObservableListenable(_app.adapters.source),
            ObservableListenable(_app.money.price),
            if (widget.exchange != null)
              ObservableListenable(widget.exchange!.status),
          ]),
          builder: (context, _) {
            final source = _app.adapters.source.value;
            final price = _app.money.price.value;
            final items = <(String, String?, VoidCallback)>[
              (
                'Connect',
                _app.adapters.adapter.value?.displayName ?? 'No adapter',
                () {
                  _closeAll();
                  widget.onChangeAdapter?.call();
                },
              ),
              (
                'Speed from',
                source == DriveSource.gps ? 'GPS only' : 'Adapter',
                () => _open(_Sheet.source),
              ),
              if (!widget.gpsOnly && source != DriveSource.gps)
                (
                  'Price',
                  price == null
                      ? 'Not set'
                      : '₹${price.toStringAsFixed(1)} a litre',
                  () => _open(_Sheet.price),
                ),
              (
                'Look',
                _app.settings.livery.value.name.toUpperCase(),
                () => _open(_Sheet.look),
              ),
              if (widget.exchange != null)
                (
                  'Data',
                  widget.exchange!.status.value.inboxFiles > 0
                      ? '${widget.exchange!.status.value.inboxFiles} waiting'
                      : null,
                  () => _open(_Sheet.data),
                ),
              if (widget.onResetTrip != null)
                (
                  'Reset trip',
                  'distance, time, fastest',
                  () {
                    widget.onResetTrip!();
                    _closeAll();
                  },
                ),
              if (widget.onEndTrip != null && widget.tripRunning?.value == true)
                (
                  'End trip',
                  null,
                  () {
                    widget.onEndTrip?.call();
                    _closeAll();
                  },
                ),
              ('About', appVersion, () => _open(_Sheet.about)),
            ];
            return WatchWheel(
              title: 'Menu',
              itemCount: items.length,
              face: face,
              motion: motion,
              rotary: rotary,
              rowAt: (i) => WheelRow(label: items[i].$1, value: items[i].$2),
              onChoose: (i) => items[i].$3(),
            );
          },
        );
      case _Sheet.source:
        final adapter = _app.adapters.adapter.value != null;
        final gps = _app.adapters.source.value == DriveSource.gps;
        return WatchChoiceWheel(
          title: 'Speed from',
          labels: const ['Adapter', 'GPS only'],
          chosen: gps ? 1 : 0,
          face: face,
          motion: motion,
          rotary: rotary,
          onChoose: (i) {
            if (i == 1) {
              unawaited(_app.adapters.setSource(DriveSource.gps));
            } else if (adapter) {
              unawaited(_app.adapters.setSource(DriveSource.obd));
            } else {
              _closeAll();
              widget.onChangeAdapter?.call();
              return;
            }
            _closeAll();
          },
        );
      case _Sheet.price:
        const first = 60.0;
        const step = 0.1;
        const count = 1001;
        final current = _app.money.price.value ?? 100.0;
        return WatchWheel(
          title: '₹ a litre',
          itemCount: count,
          initial: ((current - first) / step).round().clamp(0, count - 1),
          fastStride: 10,
          face: face,
          motion: motion,
          rotary: rotary,
          rowAt: (i) =>
              WheelRow(label: '₹${(first + i * step).toStringAsFixed(1)}'),
          onChoose: (i) {
            unawaited(
              _app.money.setPrice(
                double.parse((first + i * step).toStringAsFixed(1)),
              ),
            );
            _close();
          },
        );
      case _Sheet.look:
        final now = _app.settings.livery.value;
        return WatchChoiceWheel(
          title: 'Look',
          labels: [for (final l in Liveries.all) l.name],
          chosen: Liveries.all.indexWhere((l) => l.id == now),
          face: face,
          motion: motion,
          rotary: rotary,
          onChoose: (i) {
            _app.settings.livery.value = Liveries.all[i].id;
            _close();
          },
        );
      case _Sheet.data:
        final exchange = widget.exchange;
        if (exchange == null) return const SizedBox.shrink();
        return ListenableBuilder(
          listenable: ObservableListenable(exchange.status),
          builder: (context, _) {
            final s = exchange.status.value;
            final rows = <(String, String?, Future<void> Function())>[
              (
                'Export',
                'to the outbox folder',
                () async {
                  await exchange.exportAll();
                  _show();
                },
              ),
              (
                'Import',
                s.inboxFiles == 0
                    ? 'inbox is empty'
                    : '${s.inboxFiles} file${s.inboxFiles == 1 ? '' : 's'} waiting',
                () async {
                  await exchange.importInbox();
                  _show();
                },
              ),
              if (s.offered.isNotEmpty)
                (
                  'Apply setup',
                  'from the last file',
                  () async {
                    await exchange.applyOffered();
                    _show();
                  },
                ),
            ];
            return WatchWheel(
              title: 'Data',
              itemCount: rows.length,
              face: face,
              motion: motion,
              rotary: rotary,
              rowAt: (i) => WheelRow(label: rows[i].$1, value: rows[i].$2),
              onChoose: (i) => unawaited(rows[i].$3()),
            );
          },
        );
      case _Sheet.message:
        final s = widget.exchange?.status.value;
        return WatchMessage(
          face: face,
          text: s?.sentence ?? '',
          ok: s?.ok ?? true,
          lines: s?.offered ?? const [],
          onClose: _close,
        );
      case _Sheet.about:
        return WatchWheel(
          title: 'About',
          itemCount: 2,
          face: face,
          motion: motion,
          rotary: rotary,
          rowAt: (i) => i == 0
              ? const WheelRow(label: 'TapeDash', value: appVersion)
              : const WheelRow(label: 'Offline', value: 'No account, no cloud'),
          onChoose: (_) => _close(),
        );
    }
  }
}
