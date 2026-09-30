import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../../coach/sample_events.dart';
import '../../../coach/tips.dart';
import '../../../core/apportion.dart';
import '../../../money/spend_bucket.dart';
import '../../../trips/route_geometry.dart';
import '../../../trips/trip.dart';
import '../../../trips/trip_library.dart';
import '../../../trips/trip_playback.dart';
import '../../../vehicle/vehicle_state.dart' show DrivingMode;
import '../../design/components/controls/tape_scroll_segmented.dart';
import '../../design/components/controls/tape_segmented.dart' show TapeSegment;
import '../../design/components/presence.dart';
import '../../design/components/rolling_numerals.dart';
import '../../design/components/route_trail.dart';
import '../../design/components/route_view.dart';
import '../../design/components/route_zoom_buttons.dart';
import '../../design/components/tape_label.dart';
import '../../design/components/telemetry_scrubber.dart';
import '../../design/components/trip_transport.dart';
import '../../design/motion/motion_scope.dart';
import '../../design/motion/numeral_source.dart';
import '../../design/motion/playback_channel.dart';
import '../../design/motion/spring_value.dart';
import '../../design/motion/timeline.dart';
import '../../design/motion/trip_player.dart';
import '../../design/theme/palette.dart';
import '../../design/theme/tape_theme.dart';
import '../../design/tokens/motion_tokens.dart';
import '../../design/tokens/shapes.dart';
import '../../design/tokens/spacing.dart';
import '../../design/tokens/strokes.dart';
import '../../design/tokens/typography.dart';
import '../money/bucket_breakdown.dart';
import '../money/money_figure.dart';
import 'replay_hud.dart';
import 'roll_up_source.dart';

/// A request for the Debrief to play (DESIGN.md 7.5): the shell makes one when a
/// trip ends, and Review takes it as soon as it is on screen, which may be a moment
/// later, since the Strip only builds the pages near the one it is showing.
class DebriefRequest extends ChangeNotifier {
  bool _pending = false;

  bool get pending => _pending;

  /// Asks for the Debrief.
  void request() {
    _pending = true;
    notifyListeners();
  }

  /// Takes the request: true once for each [request].
  bool take() {
    final was = _pending;
    _pending = false;
    return was;
  }

  /// Withdraws it (the engine came back).
  void clear() => _pending = false;
}

/// Which metric colours the route, and the scrubber's lower trace: what the
/// trip recorded along the way. The Telemetry cluster's six channels (RPM, speed,
/// throttle, load, coolant, volts) and the money's ₹/km.
enum ReviewMetric {
  speed('Speed'),
  rpm('RPM'),
  throttle('Throttle'),
  load('Load'),
  coolant('Coolant'),
  voltage('Volts'),
  costPerKm('₹/km');

  const ReviewMetric(this.label);

  final String label;

  /// Whether [samples] have anything to show for this metric: the load, the
  /// coolant and the voltage are null for a trip recorded before they were kept,
  /// or from a car that does not report them.
  bool isIn(List<TripSample> samples) => switch (this) {
    load => samples.any((s) => s.load != null),
    coolant => samples.any((s) => s.coolantC != null),
    voltage => samples.any((s) => s.voltage != null),
    _ => true,
  };

  /// The metric at [s], or null where the car did not say.
  double? valueAt(TripSample s, Trip trip) => switch (this) {
    speed => s.speedKmh,
    rpm => s.rpm,
    throttle => s.throttle,
    load => s.load,
    coolant => s.coolantC,
    voltage => s.voltage,
    costPerKm =>
      trip.pricePerLitre == null || s.speedKmh < 5
          ? 0
          : s.litresPerHour * trip.pricePerLitre! / s.speedKmh,
  };

  /// The metric at the cursor, as words: "1850 RPM", "88 °C", "14.1 V".
  String? readout(TripSample s) => switch (this) {
    load => s.load == null ? null : '${s.load!.round()} % LOAD',
    coolant => s.coolantC == null ? null : '${s.coolantC!.round()} °C COOLANT',
    voltage => s.voltage == null ? null : '${s.voltage!.toStringAsFixed(1)} V',
    _ => null,
  };
}

/// Review (DESIGN.md 7.5): a trip laid out. On the left the route trail, with a
/// SPEED, THROTTLE or ₹/KM selector; on the right the receipt (₹ total at display
/// size, then distance, time, km/L, ₹/km and idle time), where it went, and one
/// tip; along the bottom the telemetry scrubber.
///
/// **The Debrief** ([playDebrief]) is this page playing itself when a trip ends:
/// the where-it-went bar fills, the route draws itself with a comet head, the
/// receipt's figures roll up, and the tip fades in, 4.5 s at most; a tap anywhere
/// skips to the end. It never plays while the car moves, since the page is not
/// reachable then.
///
/// Parked only: tips are shown only when the car is not moving ([mode]).
class ReviewPage extends StatefulWidget {
  const ReviewPage({
    super.key,
    required this.library,
    required this.mode,
    required this.width,
    required this.height,
    this.tips = const TipEngine(),
    this.reduceMotion = false,
    this.debrief,
  });

  /// Asks the page to play the Debrief, when it is on screen.
  final DebriefRequest? debrief;

  final TripLibrary library;
  final ValueListenable<DrivingMode> mode;
  final double width;
  final double height;
  final TipEngine tips;

  /// With reduce motion the Debrief shows its end state at once (DESIGN.md 5.8).
  final bool reduceMotion;

  @override
  State<ReviewPage> createState() => ReviewPageState();
}

class ReviewPageState extends State<ReviewPage> {
  Trip? _trip;
  List<TripSample> _samples = const [];
  List<SampleEvent> _events = const [];
  ReviewMetric _metric = ReviewMetric.speed;
  List<ReviewMetric> _metrics = ReviewMetric.values;
  final ValueNotifier<int?> _cursor = ValueNotifier(null);
  final ValueNotifier<double> _seconds = ValueNotifier(double.infinity);
  Timeline? _debrief;
  late final ValueNotifier<double> _full = ValueNotifier(1);
  RouteGeometry? _geometry;
  Size? _geometrySize;
  int _load = 0;

  /// Where the route panel is looking: pinch, drag and double-tap move it.
  RouteViewController? _view;

  // ---- The replay (DESIGN.md 6.12) ----

  /// The trip as a replay, or null for a trip with fewer than two samples.
  TripPlayer? _player;
  ReplayEvents? _replayEvents;

  /// Whether the replay's instruments are up: the camera follows the car and the
  /// receipt gives way to the HUD.
  bool _replaying = false;

  /// Whether the camera is to follow the car, and whether the map turns with it.
  bool _follow = true;
  bool _headingUp = true;
  bool _wasChasing = false;

  /// The car on the route, and where the scrubber's line is (a fractional sample).
  final RouteCar _car = RouteCar();
  final ValueNotifier<double?> _playhead = ValueNotifier(null);
  double _heading = 0;

  /// How many points the route is drawn with: more while replaying, so that the
  /// camera can go in close.
  int _geometryPoints = RouteGeometry.maxPoints;

  /// The receipt and the HUD take turns: each fades by its own share.
  SpringValue? _receiptMix;
  SpringValue? _hudMix;
  bool _hudBuilt = false;

  /// Set while the page moves the scrubber's cursor itself, so that it does not
  /// take its own move for a scrub.
  bool _settingCursor = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final clock = MotionScope.of(context);
    _view ??= RouteViewController(clock: clock)
      ..flags.addListener(_onViewFlags);
    _receiptMix ??= SpringValue(
      clock: clock,
      spec: TapeSprings.gauge,
      initial: 1,
    );
    _hudMix ??= SpringValue(clock: clock, spec: TapeSprings.gauge)
      ..addListener(_onHudMix);
  }

  /// The route as fitted to its panel, and the scrubber's cursor, for tests.
  @visibleForTesting
  RouteGeometry? get routeGeometry => _geometry;

  @visibleForTesting
  int? get cursorSample => _cursor.value;

  /// The replay's player and car, and whether it is on, for tests.
  @visibleForTesting
  TripPlayer? get player => _player;

  @visibleForTesting
  RouteCar get car => _car;

  @visibleForTesting
  bool get isReplaying => _replaying;

  @visibleForTesting
  bool get isFollowing => _follow;

  @visibleForTesting
  bool get isHeadingUp => _headingUp;

  /// The route panel's view, for tests.
  @visibleForTesting
  RouteViewController get routeView => _view!;

  @override
  void initState() {
    super.initState();
    widget.library.selected.addListener(_onSelected);
    widget.debrief?.addListener(_onDebriefRequest);
    _cursor.addListener(_onCursor);
    _onSelected();
    _onDebriefRequest();
  }

  void _onDebriefRequest() {
    final request = widget.debrief;
    if (request == null || !request.pending) return;
    // The page may still be building: play once this frame is done.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && request.take()) playDebrief();
    });
  }

  @override
  void dispose() {
    widget.library.selected.removeListener(_onSelected);
    widget.debrief?.removeListener(_onDebriefRequest);
    _debrief?.dispose();
    _cursor.removeListener(_onCursor);
    _cursor.dispose();
    _disposePlayer();
    _playhead.dispose();
    _car.dispose();
    _receiptMix?.dispose();
    _hudMix?.dispose();
    _view?.flags.removeListener(_onViewFlags);
    _view?.dispose();
    _barShare.dispose();
    _routeShare.dispose();
    _receiptShare.dispose();
    _tipShare.dispose();
    _seconds.dispose();
    _full.dispose();
    super.dispose();
  }

  /// Puts the scrubber's cursor on sample [i], as a drag would.
  @visibleForTesting
  void debugSetCursor(int i) => _cursor.value = i;

  /// The metric colouring the route, and the ones this trip offers.
  @visibleForTesting
  ReviewMetric get metric => _metric;

  @visibleForTesting
  List<ReviewMetric> get availableMetrics => _metrics;

  /// Whether the Debrief is playing.
  bool get isDebriefing => _debrief != null && !_debrief!.isDone;

  void _onSelected() {
    final trip = widget.library.selected.value;
    final ticket = ++_load;
    _leaveReplay();
    if (trip == null) {
      _disposePlayer();
      setState(() {
        _trip = null;
        _samples = const [];
      });
      return;
    }
    widget.library.samples(trip).then((samples) {
      if (!mounted || ticket != _load) return;
      setState(() {
        _trip = trip;
        _samples = samples;
        _events = SampleEvents.find(samples);
        _geometry = null;
        _geometryPoints = RouteGeometry.maxPoints;
        _hudBuilt = false;
        _cursor.value = null;
        _view?.resetNow();
        _makePlayer(trip, samples);
        // Only what this trip has: an older one has no load, coolant or volts.
        _metrics = [
          for (final m in ReviewMetric.values)
            if (m.isIn(samples)) m,
        ];
        if (!_metrics.contains(_metric)) _metric = ReviewMetric.speed;
      });
    });
  }

  /// Plays the Debrief (DESIGN.md 7.5): call it when a trip ends.
  void playDebrief() {
    endReplay();
    _debrief?.dispose();
    if (widget.reduceMotion) {
      _seconds.value = double.infinity;
      _debrief = null;
      setState(() {});
      return;
    }
    _seconds.value = 0;
    final t = Timeline(
      clock: MotionScope.of(context),
      length: TapeDebrief.length,
    );
    t.addListener(() => _seconds.value = t.seconds);
    _debrief = t;
    t.start();
    setState(() {});
  }

  /// Puts the Debrief away without playing the rest (the engine came back).
  void cancelDebrief() {
    _debrief?.dispose();
    _debrief = null;
    _seconds.value = double.infinity;
  }

  // ---- The replay ----

  void _makePlayer(Trip trip, List<TripSample> samples) {
    _disposePlayer();
    final playback = TripPlayback(
      samples,
      pricePerLitre: trip.pricePerLitre,
      tripDistanceKm: trip.distanceKm,
      tripLitres: trip.litres,
    );
    if (!playback.isReplayable) return;
    final player = TripPlayer(
      clock: MotionScope.of(context),
      playback: playback,
    );
    player.addListener(_onPlayer);
    _player = player;
    _replayEvents = ReplayEvents(player: player, events: _events);
  }

  void _disposePlayer() {
    final player = _player;
    final events = _replayEvents;
    _replayEvents = null;
    _player = null;
    if (player == null) return;
    player.removeListener(_onPlayer);
    player.pause();
    // The instruments that listen to it are let go of in this frame's rebuild:
    // it is disposed after them, not under them.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      events?.dispose();
      player.dispose();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  /// Starts the replay (the play button, the first time): the instruments come up,
  /// the camera goes to the car and the play head runs, from where the scrubber's
  /// cursor is if it was put somewhere.
  void beginReplay() {
    final player = _player;
    if (player == null || _replaying) return;
    _skip();
    final from = _cursor.value;
    if (from != null) player.seekToSample(from.toDouble());
    _follow = true;
    _wasChasing = false;
    _heading = 0;
    setState(() {
      _replaying = true;
      _hudBuilt = true;
      // More points for the camera to go in close on (the thinned route's chords
      // would show at that zoom).
      _geometryPoints = TapeReplay.routePoints;
      _geometry = null;
    });
    _receiptMix?.retarget(0);
    _hudMix?.retarget(1);
    player.play();
    _onPlayer();
  }

  /// Leaves the replay (the stop button): the instruments go, the map goes back to
  /// the whole route, and the scrubber's cursor stays where the car was.
  void endReplay() {
    if (!_replaying) return;
    _leaveReplay();
    setState(() {
      _geometryPoints = RouteGeometry.maxPoints;
      _geometry = null;
    });
  }

  /// The part of leaving that needs no rebuild.
  void _leaveReplay() {
    if (!_replaying) return;
    _replaying = false;
    _player?.pause();
    _car.hide();
    _playhead.value = null;
    _view?.reset();
    _receiptMix?.retarget(1);
    _hudMix?.retarget(0);
  }

  void _togglePlay() {
    final player = _player;
    if (player == null) return;
    if (!_replaying) {
      beginReplay();
    } else {
      player.toggle();
    }
  }

  void _onHudMix() {
    // The HUD stays built until it has faded out.
    if (mounted && !_replaying && _hudBuilt && (_hudMix?.value ?? 0) <= 0.001) {
      setState(() => _hudBuilt = false);
    }
  }

  /// The camera was let go of by a drag on the map: stop following.
  void _onViewFlags() {
    final chasing = (_view?.flags.value ?? 0) & 4 != 0;
    if (_wasChasing && !chasing && _replaying) _follow = false;
    _wasChasing = chasing;
  }

  void _toggleFollow() {
    final view = _view;
    if (view == null) return;
    if (view.isChasing) {
      _follow = false;
      view.endChase();
    } else {
      _follow = true;
      _onPlayer();
    }
  }

  void _toggleHeading() {
    setState(() => _headingUp = !_headingUp);
    _onPlayer();
  }

  /// The scrubber was dragged, or the map tapped: the play head goes there.
  void _onCursor() {
    final c = _cursor.value;
    if (_settingCursor || !_replaying || c == null) return;
    _player?.seekToSample(c.toDouble());
  }

  /// A frame of the replay: the scrubber's line, the car, and the camera. It runs
  /// on every frame the play head moves and allocates nothing that lasts.
  void _onPlayer() {
    final player = _player;
    if (player == null || !_replaying) return;
    final f = player.frame;
    _playhead.value = f.sample;
    final whole = f.sample.round();
    if (whole != _cursor.value) {
      _settingCursor = true;
      _cursor.value = whole;
      _settingCursor = false;
    }
    final g = _geometry;
    final view = _view;
    if (g == null || view == null) return;
    final point = g.pointAt(f.sample, player.playback.kmAtSample);
    final x = g.xAt(point);
    final y = g.yAt(point);
    final spacing = g.lengthMetres / math.max(1, g.length - 1);
    _heading = g.headingAt(
      point,
      span: math.max(
        1.0,
        TapeReplay.headingLookMetres / math.max(spacing, 0.1),
      ),
      previous: _heading,
    );
    _car.place(point, x, y, _heading);
    if (_follow) {
      // The camera shows the ground the car will cover in a few seconds: out as it
      // speeds up, in as it slows.
      final metres = (TapeReplay.chaseSeconds * f.speedKmh / 3.6).clamp(
        TapeReplay.chaseMinMetres,
        TapeReplay.chaseMaxMetres,
      );
      final scale = view.size.width / (metres * g.unitsPerMetre);
      // Heading up, the camera looks a little ahead of the car, so that the car sits
      // low in the panel and the road ahead has the room.
      var focus = Offset(x, y);
      if (_headingUp) {
        final ahead =
            view.size.height *
            TapeReplay.chaseAheadShare /
            math.max(view.scale, 1e-3);
        focus += Offset(math.cos(_heading), math.sin(_heading)) * ahead;
      }
      view.chaseTo(
        focus,
        scale: scale.isFinite ? scale : 1,
        rotation: _headingUp ? -math.pi / 2 - _heading : 0,
      );
    } else {
      view.follow(Offset(x, y));
    }
  }

  void _skip() {
    if (isDebriefing) {
      _debrief!.skip();
      _seconds.value = double.infinity;
    }
  }

  // The shares of the Debrief's steps (all 1 when it is not playing).
  SliceShare _slice(double from, double to) =>
      SliceShare(_seconds, from, to, TapeCurves.enter.transform);

  late final SliceShare _barShare = _slice(
    TapeDebrief.barFrom,
    TapeDebrief.barTo,
  );
  late final SliceShare _routeShare = _slice(
    TapeDebrief.routeFrom,
    TapeDebrief.routeTo,
  );
  late final SliceShare _receiptShare = _slice(
    TapeDebrief.receiptFrom,
    TapeDebrief.receiptTo,
  );
  late final SliceShare _tipShare = _slice(
    TapeDebrief.tipFrom,
    TapeDebrief.tipTo,
  );

  @override
  Widget build(BuildContext context) {
    final trip = _trip;
    final palette = TapeTheme.of(context).palette;
    final margin = TapeSpace.margin(widget.height);
    if (trip == null) {
      return SizedBox(
        width: widget.width,
        height: widget.height,
        child: Center(
          child: TapeText(
            'No trips yet. Drive, and the trip lands here.',
            color: palette.inkMid,
          ),
        ),
      );
    }
    final leftW = widget.width * 0.58 - margin;
    // The scrubber stands on the parked dock's clear line (it is over the dock's
    // floor otherwise), the tip sits on the scrubber, and the route takes what is
    // left between the metric selector and the tip.
    final scrubberH = math.max(TapeSpace.touchTarget, widget.height * 0.13);
    final scrubberBottom = widget.height * TapeSpace.clearOfDockShare;
    const tipH = 52.0;
    final shares = (
      bar: _barShare,
      route: _routeShare,
      receipt: _receiptShare,
      tip: _tipShare,
    );
    final tip = widget.tips.tipsFor(trip).firstOrNull;
    const headingH = 20.0;
    const selectorH = 34.0;
    final selectorTop = TapeSpace.s2 + headingH;
    final routeTop = selectorTop + selectorH + TapeSpace.s1;
    final tipTop =
        widget.height - scrubberBottom - scrubberH - TapeSpace.s1 - tipH;
    // A replay takes the tip's room for the map: the tip is not for then.
    final routeH =
        (_replaying ? tipTop + tipH : tipTop - TapeSpace.s1) - routeTop;

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _skip,
        child: Stack(
          children: [
            // The heading: when, and the DEMO badge for a demo trip; the readouts
            // at the cursor take its right-hand side while scrubbing.
            Positioned(
              left: margin,
              top: TapeSpace.s2,
              width: leftW,
              height: headingH,
              child: Row(
                children: [
                  TapeText(
                    formatWhen(trip.startedAt),
                    style: TapeTextStyle.small,
                    color: palette.inkMid,
                  ),
                  if (trip.isDemo) ...[
                    const SizedBox(width: TapeSpace.s2),
                    const TapeLabel('Demo', size: 11),
                  ],
                  // The readout takes what is left of the row and scales down to it:
                  // four readings are wider than the row on a 720 lp screen.
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: TapeSpace.s3),
                      child: Align(
                        alignment: Alignment.centerRight,
                        // A replay has its own readouts (the HUD).
                        child: _replaying
                            ? const SizedBox.shrink()
                            : FittedBox(
                                fit: BoxFit.scaleDown,
                                child: _CursorReadout(
                                  cursor: _cursor,
                                  samples: _samples,
                                  price: trip.pricePerLitre,
                                  metric: _metric,
                                ),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: margin,
              top: selectorTop,
              width: leftW,
              child: TapeScrollSegmented<ReviewMetric>(
                height: selectorH,
                value: _metric,
                onChanged: (m) => setState(() => _metric = m),
                segments: [for (final m in _metrics) TapeSegment(m, m.label)],
              ),
            ),
            Positioned(
              left: margin,
              top: routeTop,
              width: leftW,
              height: routeH,
              child: _route(trip, palette, shares.route),
            ),
            // One tip, in a bracket frame, only while the car is not moving (and
            // not while a replay has the room).
            if (!_replaying)
              Positioned(
                left: margin,
                top: tipTop,
                width: leftW,
                child: ValueListenableBuilder<DrivingMode>(
                  valueListenable: widget.mode,
                  builder: (context, m, _) =>
                      m == DrivingMode.parked && tip != null
                      ? TipPanel(tip: tip, share: shares.tip)
                      : const SizedBox.shrink(),
                ),
              ),
            // The receipt, or, while a replay runs, its instruments: each fades by
            // its own share, so the one gives way to the other.
            Positioned(
              left: widget.width * 0.62,
              right: margin,
              top: TapeSpace.s2,
              bottom: scrubberBottom + scrubberH + TapeSpace.s2,
              child: Stack(
                children: [
                  if (_receiptMix != null)
                    Positioned.fill(
                      child: Presence(
                        share: _receiptMix!,
                        child: _Receipt(
                          key: ValueKey(trip.id),
                          trip: trip,
                          palette: palette,
                          receiptShare: shares.receipt,
                          barShare: shares.bar,
                          height: widget.height,
                        ),
                      ),
                    )
                  else
                    Positioned.fill(
                      child: _Receipt(
                        key: ValueKey(trip.id),
                        trip: trip,
                        palette: palette,
                        receiptShare: shares.receipt,
                        barShare: shares.bar,
                        height: widget.height,
                      ),
                    ),
                  if (_hudBuilt && _player != null && _hudMix != null)
                    Positioned.fill(
                      child: LayoutBuilder(
                        builder: (context, box) => Presence(
                          share: _hudMix!,
                          child: ReplayHud(
                            key: ValueKey(trip.id),
                            player: _player!,
                            events: _replayEvents!,
                            price: trip.pricePerLitre,
                            maxRpm: ScrubberTrace.roundedMax(
                              _samples,
                              (s) => s.rpm,
                              1000,
                            ),
                            width: box.maxWidth,
                            height: box.maxHeight,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // The transport, left of the scrubber.
            if (_player != null)
              Positioned(
                left: margin,
                bottom: scrubberBottom,
                height: scrubberH,
                width: TripTransport.width,
                child: Center(
                  child: TripTransport(
                    player: _player!,
                    replaying: _replaying,
                    onToggle: _togglePlay,
                    onStop: endReplay,
                  ),
                ),
              ),
            Positioned(
              left: _player == null
                  ? margin
                  : margin + TripTransport.width + TapeSpace.s3,
              right: margin,
              bottom: scrubberBottom,
              height: scrubberH,
              child: _samples.length < 2
                  ? const SizedBox.shrink()
                  : TelemetryScrubber(
                      samples: _samples,
                      cursor: _cursor,
                      playhead: _playhead,
                      events: _events,
                      lower: _lowerTrace(trip),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _route(
    Trip trip,
    TapePalette palette,
    ValueListenable<double> reveal,
  ) {
    return LayoutBuilder(
      builder: (context, box) {
        final size = Size(box.maxWidth, box.maxHeight);
        if (_geometry == null || _geometrySize != size) {
          _geometry = RouteGeometry.build(
            _samples,
            size.width,
            size.height,
            maxPoints: _geometryPoints,
          );
          _geometrySize = size;
        }
        final g = _geometry;
        if (g == null) {
          return Center(
            child: TapeText(
              _samples.isEmpty
                  ? 'This trip has no samples.'
                  : 'No route: this trip had no GPS.',
              style: TapeTextStyle.small,
              color: palette.inkMid,
            ),
          );
        }
        final values = _metricSeries(g.sampleIndex, trip);
        final normalised = _normalised(values);
        final markers = <RouteMarker>[
          RouteMarker(null, 0),
          RouteMarker(null, g.length - 1),
          for (final e in _events) RouteMarker(e.type, g.nearestPoint(e.index)),
        ];
        return ValueListenableBuilder<int?>(
          valueListenable: _cursor,
          builder: (context, c, _) => Stack(
            children: [
              Positioned.fill(
                child: RouteTrail(
                  geometry: g,
                  metric: normalised,
                  ramp: _ramp(palette),
                  reveal: reveal,
                  cursor: ValueNotifier(
                    c == null || _replaying ? null : g.nearestPoint(c),
                  ),
                  markers: markers,
                  view: _view,
                  car: _car,
                  // A touch anywhere skips the Debrief while it plays; a tap on
                  // the route puts the scrubber's cursor there (in a replay, the
                  // car: the cursor follows it).
                  onTouch: _skip,
                  onPick: (point) => _cursor.value = g.sampleIndex[point],
                ),
              ),
              Positioned(
                right: 0,
                top: 0,
                child: RouteZoomButtons(
                  view: _view!,
                  onFollow: _replaying ? _toggleFollow : null,
                  onHeading: _replaying ? _toggleHeading : null,
                  headingUp: _headingUp,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// The metric at each of [indices], a missing reading (a channel the car gave
  /// once in a while, or not yet) carrying the last one forward.
  List<double> _metricSeries(List<int> indices, Trip trip) {
    final out = <double>[];
    double? last;
    for (final i in indices) {
      last = _metric.valueAt(_samples[i], trip) ?? last;
      out.add(last ?? 0);
    }
    // The first readings may precede the first value: they take it.
    final first = indices
        .map((i) => _metric.valueAt(_samples[i], trip))
        .firstWhere((v) => v != null, orElse: () => null);
    if (first != null) {
      for (var k = 0; k < indices.length; k++) {
        if (_metric.valueAt(_samples[indices[k]], trip) != null) break;
        out[k] = first;
      }
    }
    return out;
  }

  /// [values] on the 0 to 1 of the route's ramp: percentages on their own scale,
  /// the coolant and the voltage over the range the trip covered (a coolant that
  /// sat at 90 would otherwise look the same as one at 0), the rest by their 95th
  /// percentile.
  List<double> _normalised(List<double> values) => switch (_metric) {
    ReviewMetric.throttle ||
    ReviewMetric.load => normalise(values, fixedMax: 100),
    ReviewMetric.coolant => normaliseSpread(values, minSpan: 10),
    ReviewMetric.voltage => normaliseSpread(values, minSpan: 1),
    _ => normalise(values),
  };

  /// The scrubber's lower trace: the throttle, or the metric chosen, where that
  /// is one of the channels.
  ScrubberTrace? _lowerTrace(Trip trip) => switch (_metric) {
    ReviewMetric.speed ||
    ReviewMetric.throttle ||
    ReviewMetric.costPerKm => null,
    ReviewMetric.rpm => ScrubberTrace(
      value: (s) => s.rpm,
      min: 0,
      max: ScrubberTrace.roundedMax(_samples, (s) => s.rpm, 1000),
    ),
    ReviewMetric.load => ScrubberTrace(value: (s) => s.load, min: 0, max: 100),
    ReviewMetric.coolant => ScrubberTrace.spread(
      _samples,
      (s) => s.coolantC,
      minSpan: 10,
    ),
    ReviewMetric.voltage => ScrubberTrace.spread(
      _samples,
      (s) => s.voltage,
      minSpan: 1,
    ),
  };

  List<Color> _ramp(TapePalette p) => switch (_metric) {
    ReviewMetric.costPerKm => [p.moneyDeep, p.moneyGlow, p.critical],
    _ => [p.accentDeep, p.accentCore, p.inkBright],
  };

  /// "Wed 4 Mar · 8:15 am": the heading of a trip.
  static String formatWhen(DateTime d) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final m = d.minute.toString().padLeft(2, '0');
    return '${days[d.weekday - 1]} ${d.day} ${months[d.month - 1]} · '
        '$h:$m ${d.hour < 12 ? 'am' : 'pm'}';
  }
}

class _CursorReadout extends StatelessWidget {
  const _CursorReadout({
    required this.cursor,
    required this.samples,
    required this.price,
    required this.metric,
  });

  /// The metric chosen: the load, the coolant and the voltage have a readout of
  /// their own, since the three above are always speed, revs and throttle.
  final ReviewMetric metric;

  final ValueListenable<int?> cursor;
  final List<TripSample> samples;
  final double? price;

  @override
  Widget build(BuildContext context) {
    final palette = TapeTheme.of(context).palette;
    return ValueListenableBuilder<int?>(
      valueListenable: cursor,
      builder: (context, c, _) {
        if (c == null || samples.isEmpty) return const SizedBox.shrink();
        final r = ScrubReadout.at(samples, c, price);
        final style = TapeType.label(size: 12, color: palette.inkBright);
        final s = samples[c.clamp(0, samples.length - 1)];
        // On SPEED: speed, revs, throttle and ₹/km. On any other metric: speed,
        // and that metric alone, so the row never grows past its width.
        final items = <String>[
          '${r.speedKmh.round()} KM/H',
          ...switch (metric) {
            ReviewMetric.speed => [
              '${r.rpm.round()} RPM',
              '${r.throttle.round()} % THROTTLE',
              if (r.costPerKm != null) '₹${r.costPerKm!.toStringAsFixed(1)}/KM',
            ],
            ReviewMetric.rpm => ['${r.rpm.round()} RPM'],
            ReviewMetric.throttle => ['${r.throttle.round()} % THROTTLE'],
            ReviewMetric.costPerKm => [
              if (r.costPerKm != null) '₹${r.costPerKm!.toStringAsFixed(1)}/KM',
            ],
            _ => [?metric.readout(s)],
          },
        ];
        return Row(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(width: TapeSpace.s4),
              Text(items[i], style: style),
            ],
          ],
        );
      },
    );
  }
}

class _Receipt extends StatefulWidget {
  const _Receipt({
    super.key,
    required this.trip,
    required this.palette,
    required this.receiptShare,
    required this.barShare,
    required this.height,
  });

  final Trip trip;
  final TapePalette palette;
  final ValueListenable<double> receiptShare;
  final ValueListenable<double> barShare;
  final double height;

  @override
  State<_Receipt> createState() => _ReceiptState();
}

/// The receipt's roll-up sources are made once for the trip (the page keys it by
/// trip) and let go with it, however often the page rebuilds.
class _ReceiptState extends State<_Receipt> {
  final Map<String, RollUpSource> _sources = {};

  RollUpSource _source(
    String key,
    double target,
    ValueListenable<double> share,
    int decimals,
  ) => _sources.putIfAbsent(
    key,
    () => RollUpSource(target, share, decimals: decimals),
  );

  @override
  void dispose() {
    for (final s in _sources.values) {
      s.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final trip = widget.trip;
    final palette = widget.palette;
    final type = TypeScale.forHeight(widget.height);
    final total = trip.bucketLitres.values.fold<double>(0, (a, b) => a + b);
    final price = trip.pricePerLitre;
    final litres = [
      for (final b in SpendBucket.values) trip.bucketLitres[b] ?? 0.0,
    ];
    final shownCost = apportion([for (final l in litres) l * (price ?? 0)]);
    final shownPercent = apportion(litres, total: 100);
    NumeralSource roll(String key, double v, {int decimals = 1}) =>
        _source(key, v, widget.receiptShare, decimals);
    NumeralSource bar(String key, double v) =>
        _source(key, v, widget.barShare, 0);
    final size = type.display * 0.6;

    Widget stat(
      String label,
      double value,
      NumeralFormat f,
      String unit, {
      int decimals = 1,
    }) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TapeLabel(label, size: 10),
          SizedBox(
            height: 18,
            child: OverflowBox(
              maxHeight: NumeralMetrics(15).boxHeight,
              alignment: Alignment.centerLeft,
              child: LabeledNumeral(
                source: roll(label, value, decimals: decimals),
                format: f,
                size: 15,
                unit: unit,
                role: NumeralRole.bright,
              ),
            ),
          ),
        ],
      ),
    );

    const minutes = NumeralFormat(integerDigits: 4);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The total, at display size (a step down on a 360 lp screen).
        SizedBox(
          height: size * 0.9,
          child: OverflowBox(
            maxHeight: size * 2.2,
            alignment: Alignment.centerLeft,
            child: price == null
                ? LabeledNumeral(
                    source: roll('litres', trip.litres),
                    format: rateFormat,
                    size: size,
                    unit: 'L',
                    role: NumeralRole.money,
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '≈₹',
                        style: TapeType.numeral(
                          size: size * 0.5,
                          weight: TapeTheme.of(context).livery.numeralWeight,
                          color: palette.rupee,
                        ),
                      ),
                      FittedNumerals(
                        source: roll(
                          'total',
                          trip.cost ?? trip.litres * price,
                          decimals: 0,
                        ),
                        maxDigits: 6,
                        builder: (context, digits) => RollingNumerals(
                          source: roll(
                            'total',
                            trip.cost ?? trip.litres * price,
                            decimals: 0,
                          ),
                          format: NumeralFormat(
                            integerDigits: digits,
                            grouping: DigitGrouping.indian,
                          ),
                          size: size,
                          role: NumeralRole.money,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: TapeSpace.s1),
        Row(
          children: [
            stat('Distance', trip.distanceKm, rateFormat, 'KM'),
            stat('Time', trip.engineSeconds / 60, minutes, 'MIN', decimals: 0),
          ],
        ),
        const SizedBox(height: TapeSpace.s1),
        Row(
          children: [
            if (trip.kmPerLitre != null)
              stat('Economy', trip.kmPerLitre!, rateFormat, 'KM/L')
            else
              const Spacer(),
            if (trip.costPerKm != null)
              stat('Cost', trip.costPerKm!, rateFormat, '₹/KM')
            else
              const Spacer(),
          ],
        ),
        const SizedBox(height: TapeSpace.s1),
        Row(
          children: [
            stat('Idling', trip.idleSeconds / 60, minutes, 'MIN', decimals: 0),
            const Spacer(),
          ],
        ),
        const Spacer(),
        if (price != null && total > 0)
          BucketBreakdown(
            compact: true,
            // Whole rupees and whole percents that add up (CLAUDE.md 1.6, 8.7).
            cost: {
              for (final (i, b) in SpendBucket.values.indexed)
                b: bar('cost:${b.name}', shownCost[i].toDouble()),
            },
            percent: {
              for (final (i, b) in SpendBucket.values.indexed)
                b: bar('pct:${b.name}', shownPercent[i].toDouble()),
            },
            width: double.infinity,
            labelSize: 10,
            numeralSize: 13,
          ),
      ],
    );
  }
}

/// A tip in a bracket frame (DESIGN.md 7.5): the sentence, and its cost's brackets.
class TipPanel extends StatelessWidget {
  const TipPanel({super.key, required this.tip, this.share});

  final Tip tip;
  final ValueListenable<double>? share;

  @override
  Widget build(BuildContext context) {
    final palette = TapeTheme.of(context).palette;
    final child = CustomPaint(
      painter: BracketFramePainter(color: palette.accentCore),
      child: Padding(
        padding: const EdgeInsets.all(TapeSpace.s3),
        child: TapeText(
          tip.text,
          style: TapeTextStyle.small,
          color: palette.inkBright,
        ),
      ),
    );
    if (share == null) return child;
    // Fades in once, at the end of the Debrief: Presence, the design's one
    // transient-reveal layer, and nothing while it is hidden.
    return Presence(share: share!, child: child);
  }
}

/// Four corner brackets round a box, in [color] (DESIGN.md 4.6's bracket frame).
class BracketFramePainter extends CustomPainter {
  BracketFramePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final arm = TapeShape.bracketArm;
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = TapeStroke.fine;
    for (final (cx, cy, sx, sy) in [
      (0.0, 0.0, 1.0, 1.0),
      (size.width, 0.0, -1.0, 1.0),
      (0.0, size.height, 1.0, -1.0),
      (size.width, size.height, -1.0, -1.0),
    ]) {
      canvas.drawPath(
        Path()
          ..moveTo(cx + sx * arm, cy)
          ..lineTo(cx, cy)
          ..lineTo(cx, cy + sy * arm),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(BracketFramePainter old) => old.color != color;
}
