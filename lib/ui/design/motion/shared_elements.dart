import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../components/numeral_format.dart';
import '../tokens/motion_tokens.dart';
import 'numeral_source.dart';

/// Which end of a shared-element flight a registration is for.
enum SharedElementEndKind { from, to }

/// The canonical element ids, so a cluster and a page agree on the name.
abstract final class SharedElementIds {
  /// The speed shared element (DESIGN.md 7.1): Drive hero -> Money status
  /// corner. Real data now.
  static const String speed = 'speed';

  /// The trip-rupees shared element (DESIGN.md 7.1): Drive floor ₹ ->
  /// Money centre ₹. Both ends need `money/` (phase 4); registered
  /// when that engine exists, not before (CLAUDE.md 1: never invent data).
  static const String tripRupees = 'trip-rupees';
}

/// The merged view of a shared element, for the flight layer to paint.
@immutable
class SharedElementSpec {
  const SharedElementSpec({
    required this.id,
    required this.fromPage,
    required this.toPage,
    required this.fromRect,
    required this.toRect,
    required this.fromSize,
    required this.toSize,
    required this.source,
    required this.format,
    required this.typicalIntegerDigits,
    required this.role,
    this.parkedShare,
    this.parkedScaleShare = 1,
    this.staggerIndex = 0,
  });

  final String id;
  final int fromPage;
  final int toPage;
  final Rect fromRect;
  final Rect toRect;

  /// The font size the numeral is built at on the from end -- the size the
  /// flying copy is painted at, and scaled down for the flight.
  final double fromSize;

  /// The font size the numeral lands at on the to end.
  final double toSize;

  final NumeralSource source;
  final NumeralFormat format;
  final int typicalIntegerDigits;
  final NumeralRole role;

  /// The from end's parked share, for the scale the parked hero is at.
  final ValueListenable<double>? parkedShare;
  final double parkedScaleShare;
  final int staggerIndex;
}

/// The registration data one end of a shared element supplies.
class _EndRegistration {
  _EndRegistration({
    required this.end,
    required this.page,
    required this.size,
    required this.source,
    required this.format,
    required this.typicalIntegerDigits,
    required this.role,
    this.parkedShare,
    this.parkedScaleShare = 1,
    this.staggerIndex = 0,
  });

  final SharedElementEndKind end;
  final int page;
  final double size;
  final NumeralSource source;
  final NumeralFormat format;
  final int typicalIntegerDigits;
  final NumeralRole role;
  final ValueListenable<double>? parkedShare;
  final double parkedScaleShare;
  final int staggerIndex;

  Rect? rect;
}

/// The shared-elements controller (DESIGN.md 7.1). Pages register the two
/// ends of an element; the strip's flight layer reads the merged specs and
/// paints the flying numeral between them as a pure function of the strip's
/// offset spring.
///
/// Every transition is interruptible and reversible mid-flight -- the offset
/// is `spring.page`, and the flight's progress, position and scale are pure
/// functions of it, so they inherit the spring's ease and keep their velocity
/// across a mid-swipe reversal.
class SharedElementsController extends ChangeNotifier {
  SharedElementsController({required this.offset}) {
    offset.addListener(notifyListeners);
  }

  /// The strip's offset spring: the flight's progress is a pure function of it.
  final ValueListenable<double> offset;

  final Map<String, _EndRegistration> _from = {};
  final Map<String, _EndRegistration> _to = {};
  final Map<String, _EndShare> _shares = {}; // keyed by 'id/end'.

  /// The completed specs, for the layer to paint.
  Iterable<SharedElementSpec> get elements => _merged().values;

  /// Registers one end of an element. Repeated calls with the same data are
  /// idempotent (no notify).
  void registerEnd(
    String id,
    SharedElementEndKind end, {
    required int page,
    required double size,
    required NumeralSource source,
    required NumeralFormat format,
    required int typicalIntegerDigits,
    required NumeralRole role,
    ValueListenable<double>? parkedShare,
    double parkedScaleShare = 1,
    int staggerIndex = 0,
  }) {
    final map = end == SharedElementEndKind.from ? _from : _to;
    final existing = map[id];
    if (existing != null &&
        existing.page == page &&
        existing.size == size &&
        identical(existing.source, source) &&
        existing.format == format &&
        existing.typicalIntegerDigits == typicalIntegerDigits &&
        existing.role == role &&
        identical(existing.parkedShare, parkedShare) &&
        existing.parkedScaleShare == parkedScaleShare &&
        existing.staggerIndex == staggerIndex) {
      return;
    }
    map[id] = _EndRegistration(
      end: end,
      page: page,
      size: size,
      source: source,
      format: format,
      typicalIntegerDigits: typicalIntegerDigits,
      role: role,
      parkedShare: parkedShare,
      parkedScaleShare: parkedScaleShare,
      staggerIndex: staggerIndex,
    );
    _pingShares(id);
    notifyListeners();
  }

  /// Updates the rect of one end, measured by the wrapper. Does not notify
  /// if the rect is unchanged, so a re-measure after every build does not
  /// trigger a rebuild loop.
  void updateEndRect(String id, SharedElementEndKind end, Rect rect) {
    final map = end == SharedElementEndKind.from ? _from : _to;
    final r = map[id];
    if (r == null || r.rect == rect) return;
    r.rect = rect;
    notifyListeners();
  }

  /// Removes one end (unregistered on dispose or deactivation).
  void unregisterEnd(String id, SharedElementEndKind end) {
    final map = end == SharedElementEndKind.from ? _from : _to;
    if (map.remove(id) != null) {
      _pingShares(id);
      notifyListeners();
    }
  }

  /// The fade share for one end's own copy: a [ValueListenable] the page
  /// reads and passes into the numeral so that the travelling copy is the
  /// only one visible during the flight.
  ValueListenable<double> ownShareOf(String id, SharedElementEndKind end) {
    final key = _shareKey(id, end);
    var share = _shares[key];
    if (share == null) {
      share = _EndShare(controller: this, id: id, end: end);
      _shares[key] = share;
    }
    return share;
  }

  static String _shareKey(String id, SharedElementEndKind end) =>
      '$id/${end.name}';

  /// Pings every share that has been asked for, for either end of [id].
  void _pingShares(String id) {
    for (final end in SharedElementEndKind.values) {
      _shares[_shareKey(id, end)]?.ping();
    }
  }

  SharedElementSpec? _specOf(String id) {
    final from = _from[id];
    final to = _to[id];
    if (from == null || to == null || from.rect == null || to.rect == null) {
      return null;
    }
    return SharedElementSpec(
      id: id,
      fromPage: from.page,
      toPage: to.page,
      fromRect: from.rect!,
      toRect: to.rect!,
      fromSize: from.size,
      toSize: to.size,
      source: from.source,
      format: from.format,
      typicalIntegerDigits: from.typicalIntegerDigits,
      role: from.role,
      parkedShare: from.parkedShare,
      parkedScaleShare: from.parkedScaleShare,
      staggerIndex: from.staggerIndex,
    );
  }

  Map<String, SharedElementSpec> _merged() {
    final result = <String, SharedElementSpec>{};
    for (final id in {..._from.keys, ..._to.keys}) {
      final spec = _specOf(id);
      if (spec != null) result[id] = spec;
    }
    return result;
  }

  /// Whether both ends of [id] are registered, for tests.
  @visibleForTesting
  bool isComplete(String id) => _from.containsKey(id) && _to.containsKey(id);

  @override
  void dispose() {
    offset.removeListener(notifyListeners);
    for (final share in _shares.values) {
      share.dispose();
    }
    _shares.clear();
    _from.clear();
    _to.clear();
    super.dispose();
  }

  // -- pure math (exposed for direct tests) --

  /// How far through the flight [offset] is, 0 at [fromPage] and 1 at [toPage].
  static double flightOf(
    double offset, {
    required int fromPage,
    required int toPage,
  }) {
    final span = (fromPage - toPage).toDouble();
    if (span == 0) return 0;
    return ((fromPage - offset) / span).clamp(0.0, 1.0);
  }

  /// The element's own rect at flight [t], lerped between [from] and [to].
  static Rect rectAt(double t, Rect from, Rect to) =>
      Rect.lerp(from, to, t.clamp(0.0, 1.0))!;

  /// The element's paint scale at flight [t]:  [fromScale] at the from end
  /// and [toSizeShare] (= toSize/fromSize) at the to end.
  static double scaleAt(double t, double fromScale, double toSizeShare) =>
      ui.lerpDouble(fromScale, toSizeShare, t.clamp(0.0, 1.0))!;

  /// The from end's own copy: full at t=0, gone by [TapeMotion.sharedElementDepart].
  static double fromEndOwnShare(double t) =>
      1 - (t / TapeMotion.sharedElementDepart).clamp(0.0, 1.0);

  /// The to end's own copy: hidden until [TapeMotion.sharedElementArrive],
  /// full at t=1.
  static double toEndOwnShare(double t) =>
      ((t - TapeMotion.sharedElementArrive) /
              (1 - TapeMotion.sharedElementArrive))
          .clamp(0.0, 1.0);
}

/// An inherited scope that provides the [SharedElementsController] to pages.
class SharedElementsScope extends InheritedWidget {
  const SharedElementsScope({
    super.key,
    required this.controller,
    required super.child,
  });

  final SharedElementsController controller;

  static SharedElementsController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<SharedElementsScope>()
      ?.controller;

  @override
  bool updateShouldNotify(SharedElementsScope old) =>
      !identical(old.controller, controller);
}

/// A listenable share per (id, end), computed from the offset spring and the
/// controller's own registrations (which tell it the pages for the flight).
class _EndShare extends ChangeNotifier implements ValueListenable<double> {
  _EndShare({required this.controller, required this.id, required this.end}) {
    controller.offset.addListener(ping);
    controller.addListener(ping);
  }

  final SharedElementsController controller;
  final String id;
  final SharedElementEndKind end;

  void ping() => notifyListeners();

  @override
  double get value {
    final from = controller._from[id];
    final to = controller._to[id];
    if (from == null || to == null) {
      return end == SharedElementEndKind.from ? 1 : 0;
    }
    final t = SharedElementsController.flightOf(
      controller.offset.value,
      fromPage: from.page,
      toPage: to.page,
    );
    return end == SharedElementEndKind.from
        ? SharedElementsController.fromEndOwnShare(t)
        : SharedElementsController.toEndOwnShare(t);
  }

  @override
  void dispose() {
    controller.offset.removeListener(ping);
    controller.removeListener(ping);
    super.dispose();
  }
}
