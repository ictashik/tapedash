import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../../vehicle/vehicle_state.dart' show DrivingMode;
import '../../design/components/backdrop.dart';
import '../../design/icons/icons.dart';
import '../../design/motion/motion_clock.dart';
import '../../design/motion/shared_elements.dart';
import '../../design/motion/spring_value.dart';
import '../../design/motion/timeline.dart';
import '../../design/theme/palette.dart';
import '../../design/theme/tape_theme.dart';
import '../../design/tokens/motion_tokens.dart';
import '../../design/tokens/spacing.dart';
import 'page_tape.dart';
import 'shared_elements_layer.dart';

/// The Strip (DESIGN.md 7.1): the app is one continuous horizontal panel of
/// five pages, Drive at home in the centre:
///
/// `REVIEW · MONEY · [ DRIVE ] · COACH · HISTORY`
///
/// A horizontal swipe moves between pages on `spring.page`, with parallax
/// in the tiers that allow it: the void's canvas is the L0 layer and drifts
/// at 0.1x of the page's own move, while the pages are the L2 data layer
/// and move 1:1. While the car is moving, only Money and Drive are
/// reachable: a swipe toward a locked page rubber-bands against the
/// reachable edge and shows the lock glyph for [TapeMotion.lockGlyph]; and
/// the lock is a rule rather than a suggestion, so a page left on when the
/// car starts moving returns to the nearest reachable page on `spring.snap`,
/// inside the 300 ms the motion return allows (DESIGN.md 5.7's "motion mode
/// always wins").
///
/// The strip does not rebuild for its own motion: the pages ride one [Flow]
/// whose delegate reads the spring fresh per frame, so a swipe repaints
/// transforms and never a widget tree. The pages themselves are mounted by
/// a window around the settled position -- Drive always (it is the home
/// page, and whatever the Drive page keeps for itself lives there), the
/// others while they or a neighbour could be on screen.
///
/// A double-tap on Drive or Money calls [TheStrip.onToggleHud] (DESIGN.md 7.1);
/// what the HUD is, is `lib/ui/hud/`'s.
///
/// **What is not here yet, on purpose:** the pages' real contents (Money, Review,
/// Coach and History are phases 4 and 5 -- the placeholders say so), the
/// eco bar that hides while parked (phase 4), and the parallax of the L1
/// and L3 layers, which arrives when the pages themselves are built as
/// layered compositions rather than one data layer each. The parked dock is
/// the next piece of this phase.
class TheStrip extends StatefulWidget {
  const TheStrip({
    super.key,
    required this.pages,
    required this.mode,
    required this.motion,
    required this.width,
    required this.height,
    this.onToggleHud,
  });

  /// The page the strip opens on, Drive's place in the five.
  static const int homePage = 2;

  /// The Money page's own index in the five (DESIGN.md 7.1).
  static const int moneyPage = 1;

  /// The five pages, in `REVIEW · MONEY · DRIVE · COACH · HISTORY` order.
  final List<Widget> pages;

  /// Parked or motion (DESIGN.md 7.2), from the vehicle state.
  final ValueListenable<DrivingMode> mode;

  /// The clock the strip's own motion runs on.
  final MotionClock motion;

  final double width;
  final double height;

  /// Called by a double-tap on Drive or Money (DESIGN.md 7.1 and 8). Null
  /// leaves the double-tap unclaimed.
  final VoidCallback? onToggleHud;

  @override
  State<TheStrip> createState() => TheStripState();
}

class TheStripState extends State<TheStrip> {
  late SpringValue _offset;
  late SharedElementsController _shared;
  Timeline? _lockGlyph;

  /// The page index the mounted window was last built around.
  int _windowAt = TheStrip.homePage;

  /// The raw drag position the spring chases, in pages.
  double _raw = TheStrip.homePage.toDouble();

  @override
  void initState() {
    super.initState();
    _offset = SpringValue(
      clock: widget.motion,
      spec: TapeSprings.page,
      initial: TheStrip.homePage.toDouble(),
    )..addListener(_onOffset);
    _shared = SharedElementsController(offset: _offset);
    widget.mode.addListener(_onMode);
  }

  @override
  void didUpdateWidget(TheStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.mode, widget.mode)) {
      oldWidget.mode.removeListener(_onMode);
      widget.mode.addListener(_onMode);
      _onMode();
    }
    if (!identical(oldWidget.motion, widget.motion)) {
      // The clock the spring runs on is replaced by the test harnesses; the
      // spring is rebuilt on the new one rather than carried across.
      final at = _offset.value;
      _offset.dispose();
      _offset = SpringValue(
        clock: widget.motion,
        spec: TapeSprings.page,
        initial: at,
      )..addListener(_onOffset);
      _shared.dispose();
      _shared = SharedElementsController(offset: _offset);
    }
  }

  @override
  void dispose() {
    _offset.removeListener(_onOffset);
    _offset.dispose();
    _shared.dispose();
    _lockGlyph?.dispose();
    widget.mode.removeListener(_onMode);
    super.dispose();
  }

  /// Where the strip is now, in pages.
  double get offset => _offset.value;

  /// Moves to [page] as a release would, within what the motion lock allows:
  /// for tests and the screenshot scripts, which cannot drag a real hand.
  @visibleForTesting
  void goTo(int page) {
    final (min, max) = reachOf(widget.mode.value);
    _offset
      ..setSpec(TapeSprings.page)
      ..retarget(page.clamp(min, max).toDouble());
  }

  /// The reachable page range (DESIGN.md 7.1): everything while parked;
  /// Money and Drive only while moving.
  (int, int) reachOf(DrivingMode mode) => switch (mode) {
    DrivingMode.parked => (0, 4),
    DrivingMode.motion => (1, 2),
  };

  /// A page's slot is mounted while the strip could be showing it or a
  /// neighbour: within a page of the position (the same open window the
  /// flow paints on), or home (the Drive page's own state lives there and
  /// is never torn down for a swipe).
  static bool _mounted(int i, double offset) =>
      i == TheStrip.homePage || (i - 1 < offset && offset < i + 1);

  /// The canvas's own span: the viewport plus the whole drift range, as a
  /// share of the page width.
  static double canvasShareOf(double width) =>
      width * (1 + 2 * TheStrip.homePage * TapeMotion.parallax.first);

  /// The offset a raw drag wants, resisted past the reachable range
  /// (DESIGN.md 7.1's rubber-band): in range it is the raw itself; past an
  /// edge it stops [TapeMotion.lockedSwipeGive] of a page into the locked
  /// side and holds. Exposed for a direct test.
  static double resisted(double raw, double min, double max) {
    if (raw < min) {
      return min - TapeMotion.lockedSwipeGive * (min - raw).clamp(0.0, 1.0);
    }
    if (raw > max) {
      return max + TapeMotion.lockedSwipeGive * (raw - max).clamp(0.0, 1.0);
    }
    return raw;
  }

  /// Where a release settles (DESIGN.md 7.1): the nearest page to the raw,
  /// with a real hand's velocity carrying the landing one page further in
  /// the hand's own direction -- never skipping a page the raw was already
  /// past, and never beyond the strip's own ends. A page the reachable
  /// range keeps out is left to the caller, which springs back and shows
  /// the lock glyph. Exposed for a direct test.
  static int settleTarget(double raw, double velocity) {
    var landing = raw.round().clamp(0, 4);
    if (velocity.abs() > TapeMotion.pageFlingVelocity) {
      // The hand's own momentum carries the landing one page further in the
      // hand's own direction.
      landing += velocity > 0 ? 1 : -1;
      landing = landing.clamp(0, 4);
    }
    return landing;
  }

  void _onOffset() {
    // The mounted window changes exactly when the offset crosses an integer
    // (a page's neighbour window is open while it is within a page of the
    // position), so the floor is the signal to rebuild on -- and nothing
    // else: a mid-flight repaint is the Flow's, never the strip's own.
    final floor = _offset.value.floor();
    if (floor != _windowAt) {
      setState(() => _windowAt = floor);
    }
  }

  void _onMode() {
    setState(() {});
    final (min, max) = reachOf(widget.mode.value);
    if (_offset.value < min || _offset.value > max) {
      _offset
        ..setSpec(TapeSprings.snap)
        ..retarget(_offset.value.clamp(min.toDouble(), max.toDouble()));
    }
  }

  void _onHorizontalDragStart(DragStartDetails details) {
    // A drag takes over from whatever page move is in flight, and from here
    // the spring chases the finger: the release then carries the hand's own
    // velocity into the settle.
    _offset.setSpec(TapeSprings.page);
    _raw = _offset.value;
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    final (min, max) = reachOf(widget.mode.value);
    _raw -= details.primaryDelta! / widget.width;
    _offset.retarget(resisted(_raw, min.toDouble(), max.toDouble()));
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    // The hand's own velocity, not the spring's (the spring chases the
    // finger, so its own velocity lags the hand by the chase itself) -- and
    // in the offset's own direction: the offset moves against the finger's
    // dx, so a leftward hand (dx negative) is an offset moving up.
    _settle(_raw, -details.velocity.pixelsPerSecond.dx / widget.width);
  }

  void _onDoubleTap() {
    // Only on Drive or Money (DESIGN.md 7.1), the pages the motion lock keeps
    // reachable: the page the strip is nearest to.
    final page = _offset.value.round();
    if (page == TheStrip.homePage || page == TheStrip.moneyPage) {
      widget.onToggleHud?.call();
    }
  }

  void _onHorizontalDragCancel() {
    // A cancelled drag settles to the nearest reachable page, with no hand
    // velocity to carry.
    _settle(_offset.value, 0);
  }

  void _settle(double at, double velocity) {
    final (min, max) = reachOf(widget.mode.value);
    final wanted = settleTarget(at, velocity);
    final clamped = wanted.clamp(min, max).toInt();
    if (clamped != wanted) {
      // The release was toward a page the lock keeps out: back to the
      // reachable side, and say why, for [TapeMotion.lockGlyph].
      _showLockGlyph();
    }
    _offset.retarget(clamped.toDouble());
  }

  void _showLockGlyph() {
    _lockGlyph?.dispose();
    _lockGlyph = Timeline(
      clock: widget.motion,
      length: TapeMotion.lockGlyph,
      onDone: () {
        if (mounted) setState(() => _lockGlyph = null);
      },
    )..start();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = TapeTheme.of(context);
    final parallax = theme.profile.parallax;

    final children = <Widget>[
      // Layer L0: the canvas, wide enough to cover the whole drift range,
      // so the parallax never uncovers an edge at either end of the strip.
      SizedBox(
        width: TheStripState.canvasShareOf(widget.width),
        height: widget.height,
        child: const TapeBackdrop(),
      ),
      for (var i = 0; i < widget.pages.length; i++)
        SizedBox(
          width: widget.width,
          height: widget.height,
          child: _mounted(i, _offset.value.floorToDouble())
              ? widget.pages[i]
              : const SizedBox.shrink(),
        ),
    ];

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: _onHorizontalDragStart,
        onHorizontalDragUpdate: _onHorizontalDragUpdate,
        onHorizontalDragEnd: _onHorizontalDragEnd,
        onHorizontalDragCancel: _onHorizontalDragCancel,
        onDoubleTap: widget.onToggleHud == null ? null : _onDoubleTap,
        child: Stack(
          children: [
            Positioned.fill(
              child: SharedElementsScope(
                controller: _shared,
                child: Flow(
                  delegate: _StripFlowDelegate(
                    offset: _offset,
                    parallax: parallax,
                    width: widget.width,
                  ),
                  children: children,
                ),
              ),
            ),
            Positioned.fill(
              child: SharedElementsLayer(controller: _shared, offset: _offset),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: TapeSpace.pageTapeHeight,
              child: PageTape(
                offset: _offset,
                mode: widget.mode,
                width: widget.width,
              ),
            ),
            if (_lockGlyph != null)
              Positioned(
                bottom: TapeSpace.pageTapeHeight + TapeSpace.s1,
                left: 0,
                right: 0,
                height: LockGlyph.size + TapeSpace.s1,
                child: CustomPaint(
                  painter: _LockGlyphPainter(
                    timeline: _lockGlyph!,
                    palette: theme.palette,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The strip's own motion (DESIGN.md 7.1): each child of the one [Flow]
/// rides at its layer's own share of the page's move -- the canvas at L0's
/// 0.1x, the pages themselves at 1.0x -- and children that are off screen
/// are not painted at all, so a page move costs transforms only.
class _StripFlowDelegate extends FlowDelegate {
  _StripFlowDelegate({
    required this.offset,
    required this.parallax,
    required this.width,
  }) : super(repaint: offset);

  final ValueListenable<double> offset;
  final bool parallax;
  final double width;

  /// The canvas is the first child; the pages follow.
  static const int _backdropChild = 0;

  @override
  BoxConstraints getConstraintsForChild(int i, BoxConstraints constraints) {
    if (i != _backdropChild) return constraints;
    // The canvas is wider than the viewport by its own drift range, so the
    // parallax never uncovers an edge; the viewport's own tight constraints
    // would clamp it back to one page wide.
    return constraints.copyWith(
      minWidth: TheStripState.canvasShareOf(width),
      maxWidth: TheStripState.canvasShareOf(width),
    );
  }

  @override
  void paintChildren(FlowPaintingContext context) {
    final page = offset.value;

    // Layer L0: the canvas, drifting at the L0 share around the home page
    // so the parallax never uncovers an edge at either end of the strip.
    if (parallax) {
      final dx = -page * width * TapeMotion.parallax.first;
      context.paintChild(
        _backdropChild,
        transform: Matrix4.translationValues(dx, 0, 0),
      );
    } else {
      context.paintChild(_backdropChild);
    }

    // The pages, at 1.0x: a page is painted only when its own span meets
    // the viewport, the same open window the mounted slot list is built
    // around.
    for (var i = 0; i < context.childCount - 1; i++) {
      final dx = (i - page) * width;
      if (dx < context.size.width && dx + width > 0) {
        context.paintChild(
          i + 1,
          transform: Matrix4.translationValues(dx, 0, 0),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_StripFlowDelegate oldDelegate) =>
      oldDelegate.parallax != parallax || oldDelegate.width != width;
}

/// The lock glyph a swipe toward a locked page leaves on screen for
/// [TapeMotion.lockGlyph]: there at once, out without ceremony.
class _LockGlyphPainter extends CustomPainter {
  _LockGlyphPainter({required this.timeline, required this.palette})
    : super(repaint: timeline);

  final Timeline timeline;
  final TapePalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final t = timeline.progress;
    final alpha = t < 0.75 ? 1.0 : 1.0 - (t - 0.75) / 0.25;
    if (alpha <= 0) return;
    paintTapeIcon(
      canvas,
      TapeIcon.lock,
      Offset(
        (size.width - LockGlyph.size) / 2,
        (size.height - LockGlyph.size) / 2,
      ),
      LockGlyph.size,
      palette.inkMid.withValues(alpha: palette.inkMid.a * alpha),
    );
  }

  @override
  bool shouldRepaint(_LockGlyphPainter oldDelegate) =>
      oldDelegate.palette != palette;
}

/// The glyph's own size, inside the box it is centred in.
abstract final class LockGlyph {
  static const double size = 16;
}
