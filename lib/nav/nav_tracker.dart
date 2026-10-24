import '../core/clock.dart';
import '../core/observable.dart';
import '../core/scheduler.dart';
import 'nav_arrow.dart';
import 'nav_notification.dart';
import 'nav_parser.dart';
import 'nav_state.dart';

/// Whether what the navigation says can be believed right now.
enum NavFreshness {
  /// Nothing is navigating.
  none,

  /// Maps has said something recently enough.
  fresh,

  /// Maps has been silent for too long: the turn on the HUD may be behind the
  /// car. The HUD says so; it never shows an old turn as a live one
  /// (CLAUDE.md 4, "Stale is stale").
  stale,
}

/// Holds what Google Maps' navigation notification last said, and for how long
/// that can be believed (docs/NAV.md).
///
/// - [state] is the notification, read. It changes when Maps posts or removes
///   its notification.
/// - [freshness] turns stale when Maps has gone quiet: Maps was seen posting
///   every second or two on the move, so fifteen seconds of silence with the car
///   moving is too many. A standing car gets longer, since Maps has less to say.
/// - [distanceToTurnEstimateM] is Maps' distance to the turn, counted down by the
///   car's own speed between its posts (it posts in steps of 50 m, which at 50
///   km/h is one every 3.6 s). It is for a marker that moves smoothly; the figure
///   shown as text is Maps' own, because that is the one the voice agrees with.
///
/// The speed comes from [onSpeed] (the car's speed, from the OBD adapter or the
/// phone's GPS). Everything is on the injected clock and scheduler.
class NavTracker {
  NavTracker({
    required Clock clock,
    required Scheduler scheduler,
    this.parser = const NavParser(),
    this.staleAfterMoving = const Duration(seconds: 15),
    this.staleAfterStopped = const Duration(minutes: 3),
    this.checkEvery = const Duration(seconds: 1),
  }) : _clock = clock,
       _state = ObservableValue(NavState.idle(clock.now())),
       _freshness = ObservableValue(NavFreshness.none),
       _estimate = ObservableValue(null) {
    _check = scheduler.runEvery(checkEvery, _checkFreshness);
  }

  final Clock _clock;
  final NavParser parser;
  final Duration staleAfterMoving;
  final Duration staleAfterStopped;
  final Duration checkEvery;

  final ObservableValue<NavState> _state;
  final ObservableValue<NavFreshness> _freshness;
  final ObservableValue<double?> _estimate;
  late final ScheduledTask _check;

  Duration? _lastPost;
  Duration? _lastSpeedSample;
  double _speedMs = 0;
  double _travelledM = 0;
  final Map<String, NavArrow> _arrows = {};

  Observable<NavState> get state => _state;
  Observable<NavFreshness> get freshness => _freshness;

  /// Maps' distance to the turn less what the car has gone since, in metres; null
  /// when there is no distance or the navigation is stale.
  Observable<double?> get distanceToTurnEstimateM => _estimate;

  /// An arrow already received, by its id, for a notification that carries only
  /// the id.
  NavArrow? arrowFor(String id) => _arrows[id];

  /// A notification of Maps' arrived (decoded from the channel).
  void onNotification(NavNotification notification) {
    final arrow = notification.arrow;
    if (arrow != null) _arrows[arrow.id] = arrow;
    final next = parser.parse(notification, _clock.now());
    _lastPost = _clock.monotonic();
    _travelledM = 0;
    _state.value = next;
    _freshness.value = NavFreshness.fresh;
    _estimate.value = next.distanceToTurnM;
  }

  /// Maps took its notification away: navigation has ended.
  void onRemoved() {
    _lastPost = null;
    _travelledM = 0;
    _state.value = NavState.idle(_clock.now());
    _freshness.value = NavFreshness.none;
    _estimate.value = null;
  }

  /// The car's speed in metres a second.
  void onSpeed(double speedMs) {
    final now = _clock.monotonic();
    final before = _lastSpeedSample;
    _lastSpeedSample = now;
    final previousSpeed = _speedMs;
    _speedMs = speedMs < 0 ? 0 : speedMs;
    if (before == null) return;
    // The distance over the interval, at the mean of the two speeds. An interval
    // longer than two seconds is a gap in the data, not time the car was moving.
    var dt = (now - before).inMicroseconds / Duration.microsecondsPerSecond;
    if (dt <= 0) return;
    if (dt > 2) dt = 0;
    _travelledM += (previousSpeed + _speedMs) / 2 * dt;
    _updateEstimate();
  }

  void _updateEstimate() {
    final s = _state.value;
    final base = s.distanceToTurnM;
    if (s.phase != NavPhase.guiding ||
        base == null ||
        _freshness.value != NavFreshness.fresh) {
      _estimate.value = null;
      return;
    }
    final next = base - _travelledM;
    _estimate.value = next < 0 ? 0 : next;
  }

  void _checkFreshness() {
    final post = _lastPost;
    if (post == null || _state.value.phase == NavPhase.idle) return;
    final age = _clock.monotonic() - post;
    // Moving faster than walking pace (5 km/h).
    final limit = _speedMs > 1.4 ? staleAfterMoving : staleAfterStopped;
    final next = age > limit ? NavFreshness.stale : NavFreshness.fresh;
    if (next != _freshness.value) {
      _freshness.value = next;
      _updateEstimate();
    }
  }

  void dispose() {
    _check.cancel();
    _state.dispose();
    _freshness.dispose();
    _estimate.dispose();
  }
}
