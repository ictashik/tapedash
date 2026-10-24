import 'nav_arrow.dart';

/// Where the navigation is, as far as the notification says.
enum NavPhase {
  /// No navigation: Maps has none running, or its notification is gone.
  idle,

  /// Maps is setting a route up (`Starting navigation…`).
  starting,

  /// Maps is finding a new route (`Rerouting...`).
  rerouting,

  /// Maps is guiding.
  guiding,
}

/// Which of the two shapes Google Maps' notification had (docs/NAV.md). Kept for
/// the diagnostics page and for a test; nothing else depends on it.
enum NavShape {
  /// The distance in the title, the street in the text, and `28 min · 6.7 km ·
  /// 9:25 PM ETA` in the sub text.
  classic,

  /// Android 16's progress style: the distance and the instruction in the title,
  /// the distance to the turn on its own, the route's length and progress in
  /// metres, and only `Arrive 9:25 PM`.
  progress,
}

/// What the HUD shows of the navigation, read from one notification.
///
/// Every figure is optional, because a notification may not have it and because
/// one that cannot be read is left out rather than guessed (CLAUDE.md 1.6): the
/// HUD then shows Google's own words ([distanceText], [etaText]).
class NavState {
  const NavState({
    required this.phase,
    required this.receivedAt,
    this.shape,
    this.message,
    this.instruction,
    this.distanceText,
    this.distanceToTurnM,
    this.arrow,
    this.distanceLeftM,
    this.timeLeft,
    this.timeLeftIsDerived = false,
    this.eta,
    this.etaText,
  });

  /// Nothing is navigating.
  const NavState.idle(this.receivedAt)
    : phase = NavPhase.idle,
      shape = null,
      message = null,
      instruction = null,
      distanceText = null,
      distanceToTurnM = null,
      arrow = null,
      distanceLeftM = null,
      timeLeft = null,
      timeLeftIsDerived = false,
      eta = null,
      etaText = null;

  final NavPhase phase;

  /// When TapeDash received this, on its own clock.
  final DateTime receivedAt;

  final NavShape? shape;

  /// Google's own words for a state that has no turn (`Starting navigation…`,
  /// `Rerouting...`), in the phone's language.
  final String? message;

  /// The manoeuvre without its distance: `Turn right at Richmond Cir onto
  /// Mission Rd`, `toward Vittal Mallya Rd`, `Head north`.
  final String? instruction;

  /// The distance to the turn as Google wrote it, spaces ordinary: `650 m`.
  final String? distanceText;

  /// The same in metres, when it could be read, as Google rounded it (in steps
  /// of 50 m at a distance).
  final double? distanceToTurnM;

  /// The manoeuvre's picture, a mask.
  final NavArrow? arrow;

  /// The distance left to the destination, in metres: the route's length less
  /// the progress, or Google's `6.7 km`.
  final double? distanceLeftM;

  /// The time left to the destination: Google's own `28 min`, or, when
  /// [timeLeftIsDerived], the ETA less the time on the phone's clock.
  final Duration? timeLeft;
  final bool timeLeftIsDerived;

  /// When the car arrives, from the ETA's time of day.
  final DateTime? eta;

  /// The ETA as Google wrote it: `9:25 PM`.
  final String? etaText;

  bool get isGuiding => phase == NavPhase.guiding;

  @override
  String toString() =>
      'NavState($phase ${distanceText ?? '-'} ${instruction ?? message ?? '-'} '
      'left ${distanceLeftM?.round() ?? '-'} m, ETA ${etaText ?? '-'})';
}
