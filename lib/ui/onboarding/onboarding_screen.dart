import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../brand/wordmark.dart';
import '../design/components/controls/tape_button.dart';
import '../design/components/presence.dart';
import '../design/components/tape_label.dart';
import '../design/components/watch/watch_face.dart';
import '../design/fidelity/frame_probe.dart';
import '../design/icons/icons.dart';
import '../design/motion/motion_scope.dart';
import '../design/motion/spring_value.dart';
import '../design/motion/timeline.dart';
import '../design/theme/tape_theme.dart';
import '../design/tokens/motion_tokens.dart';
import '../design/tokens/spacing.dart';

/// First launch (DESIGN.md 7.11): the cold open, then the choice.
///
/// **Cold open**, at most [TapeDurations.cinematic] (1.2 s): the void, then a single
/// horizontal line of light draws outwards from the centre (the tape), then the
/// TAPEDASH wordmark resolves above it. The animation doubles as the fidelity
/// benchmark (DESIGN.md 9.2): the frame costs seen while it plays are handed to
/// [onBenchmark] when it ends.
///
/// **Choice:** two large chamfer buttons, CONNECT MY CAR (primary) and GPS SPEED
/// ONLY. The wordmark stays where the cold open left it and the buttons reveal
/// beneath it, staggered, so the screen never jumps. CONNECT MY CAR starts the
/// connect flow (`ConnectFlow`); where a screen has none to offer it is disabled
/// and says so. GPS SPEED ONLY drives from the phone's GPS with no adapter.
/// Neither is a guess made for the person: the app asks until one is chosen.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.width,
    required this.height,
    required this.onGps,
    this.onConnect,
    this.onBenchmark,
    this.skipColdOpen = false,
    this.watch = false,
  });

  /// Laid out for a round watch face (DESIGN.md 16.8): the two buttons stacked
  /// inside the circle, not side by side.
  final bool watch;

  final double width;
  final double height;

  /// GPS SPEED ONLY.
  final VoidCallback onGps;

  /// CONNECT MY CAR. Null disables it.
  final VoidCallback? onConnect;

  /// The cost in milliseconds of each frame drawn during the cold open.
  final void Function(List<double> frameMilliseconds)? onBenchmark;

  /// Goes straight to the choice (tests and screenshot scripts).
  final bool skipColdOpen;

  /// Where the wordmark sits, as a share of the height.
  static const double wordmarkCentre = 0.36;

  @override
  State<OnboardingScreen> createState() => OnboardingScreenState();
}

/// The watch's choice (DESIGN.md 16.8): the wordmark high in the circle, and the two
/// buttons one above the other, each as wide as the circle is at its lower edge.
extension _WatchChoice on OnboardingScreenState {
  Widget _buildWatch(BuildContext context) {
    final face = WatchFace.of(widget.width, widget.height);
    final size = face.diameter * 0.08;
    // Each button is as wide as its words need, and sits where the circle is wide
    // enough for it at its lower edge (the choice has no rim to keep clear of).
    const buttonHeight = 48.0;
    // Low in the circle where it is large, and as low as the second button's
    // lower corners allow where it is small: a dense button is about 140 lp wide.
    const buttonWidth = 140.0;
    final room = face.radius * face.radius - math.pow(buttonWidth / 2 + 4, 2);
    final lowest =
        face.radius +
        math.sqrt(math.max(0, room)) -
        (2 * buttonHeight + TapeSpace.s2) -
        TapeSpace.s1;
    final firstTop = math.min(face.diameter * 0.37, lowest);
    final secondTop = firstTop + buttonHeight + TapeSpace.s2;
    return Center(
      child: SizedBox.square(
        dimension: face.diameter,
        child: Stack(
          children: [
            Positioned(
              // Just over the first button: the wordmark is about 1.1 of its size
              // and 10 lp tall, with its line.
              top: firstTop - (1.1 * size + 10) - TapeSpace.s2,
              left: 0,
              right: 0,
              child: Center(
                child: Wordmark(size: size, lineShare: _line, textShare: _text),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: firstTop,
              child: Presence(
                share: _choice,
                child: Center(
                  child: SizedBox(
                    height: buttonHeight,
                    child: TapeButton(
                      label: 'Connect my car',
                      icon: TapeIcon.adapter,
                      primary: true,
                      dense: true,
                      onPressed: _ready ? widget.onConnect : null,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: secondTop,
              child: Presence(
                share: _choice,
                child: Center(
                  child: SizedBox(
                    height: buttonHeight,
                    child: TapeButton(
                      label: 'GPS speed only',
                      icon: TapeIcon.gps,
                      dense: true,
                      onPressed: _ready ? widget.onGps : null,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Share extends ChangeNotifier implements ValueListenable<double> {
  _Share(this._read, Listenable source) {
    source.addListener(notifyListeners);
    _source = source;
  }

  final double Function() _read;
  late final Listenable _source;

  @override
  double get value => _read();

  @override
  void dispose() {
    _source.removeListener(notifyListeners);
    super.dispose();
  }
}

class OnboardingScreenState extends State<OnboardingScreen> {
  Timeline? _open;
  SpringValue? _reveal;
  late _Share _line;
  late _Share _text;
  late _Share _choice;
  FrameProbe? _probe;
  final List<double> _frames = [];
  bool _ready = false;
  bool _started = false;

  /// Whether the choice is on screen and can be pressed.
  bool get choiceReady => _ready;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final clock = MotionScope.of(context);
    _reveal = SpringValue(clock: clock, spec: TapeSprings.reveal, initial: 0);
    _choice = _Share(() => _reveal!.value, _reveal!);
    if (widget.skipColdOpen) {
      _line = _Share(() => 1, ChangeNotifier());
      _text = _Share(() => 1, ChangeNotifier());
      _showChoice();
      return;
    }
    _open = Timeline(
      clock: clock,
      length: TapeDurations.cinematic,
      onDone: _onOpen,
    )..start();
    // Frames are only judged for the length of the cold open.
    _probe = FrameProbe(_frames.addAll)..start();
    _line = _Share(
      () => Timeline.interval(_open!.seconds, 0, 0.7, TapeCurves.enter),
      _open!,
    );
    _text = _Share(
      () => Timeline.interval(_open!.seconds, 0.45, 1.0, TapeCurves.enter),
      _open!,
    );
  }

  void _onOpen() {
    _probe?.stop();
    widget.onBenchmark?.call(List.of(_frames));
    _showChoice();
  }

  void _showChoice() {
    setState(() => _ready = true);
    _reveal!.retarget(1);
  }

  @override
  void dispose() {
    _probe?.stop();
    _open?.dispose();
    _reveal?.dispose();
    _line.dispose();
    _text.dispose();
    _choice.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.watch) return _buildWatch(context);
    final palette = TapeTheme.of(context).palette;
    final size = widget.height * 0.11;
    final wordmarkTop = widget.height * OnboardingScreen.wordmarkCentre - size;
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: Stack(
        children: [
          Positioned(
            top: wordmarkTop,
            left: 0,
            right: 0,
            child: Center(
              child: Wordmark(size: size, lineShare: _line, textShare: _text),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: widget.height * 0.14,
            child: Presence(
              share: _choice,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: TapeSpace.s12 * 5,
                        child: TapeButton(
                          label: 'Connect my car',
                          icon: TapeIcon.adapter,
                          primary: true,
                          onPressed: _ready ? widget.onConnect : null,
                        ),
                      ),
                      const SizedBox(width: TapeSpace.s4),
                      SizedBox(
                        width: TapeSpace.s12 * 5,
                        child: TapeButton(
                          label: 'GPS speed only',
                          icon: TapeIcon.gps,
                          onPressed: _ready ? widget.onGps : null,
                        ),
                      ),
                    ],
                  ),
                  if (widget.onConnect == null) ...[
                    const SizedBox(height: TapeSpace.s3),
                    TapeLabel(
                      'Adapter setup arrives in a later update',
                      color: palette.inkDim,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
