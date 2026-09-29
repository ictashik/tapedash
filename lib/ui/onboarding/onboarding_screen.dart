import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../brand/wordmark.dart';
import '../design/components/controls/tape_button.dart';
import '../design/components/presence.dart';
import '../design/components/tape_label.dart';
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
/// **Choice:** two large chamfer buttons, TRY A DEMO DRIVE (primary) and CONNECT
/// MY CAR. The wordmark stays where the cold open left it and the buttons
/// reveal beneath it, staggered, so the screen never jumps. The connect path's
/// scenes (adapter, pairing, car setup, price, cluster) need the real
/// transports (phase 6), so CONNECT MY CAR is disabled and says so, rather
/// than lead to a scene that does not exist.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.width,
    required this.height,
    required this.onDemo,
    this.onBenchmark,
    this.skipColdOpen = false,
  });

  final double width;
  final double height;

  /// TRY A DEMO DRIVE.
  final VoidCallback onDemo;

  /// The cost in milliseconds of each frame drawn during the cold open.
  final void Function(List<double> frameMilliseconds)? onBenchmark;

  /// Goes straight to the choice (tests and screenshot scripts).
  final bool skipColdOpen;

  /// Where the wordmark sits, as a share of the height.
  static const double wordmarkCentre = 0.36;

  @override
  State<OnboardingScreen> createState() => OnboardingScreenState();
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
                          label: 'Try a demo drive',
                          icon: TapeIcon.hud,
                          primary: true,
                          onPressed: _ready ? widget.onDemo : null,
                        ),
                      ),
                      const SizedBox(width: TapeSpace.s4),
                      SizedBox(
                        width: TapeSpace.s12 * 5,
                        child: const TapeButton(
                          label: 'Connect my car',
                          icon: TapeIcon.adapter,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: TapeSpace.s3),
                  TapeLabel(
                    'Adapter setup arrives in a later update',
                    color: palette.inkDim,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
