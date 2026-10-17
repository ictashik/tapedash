import 'package:flutter/widgets.dart';

import '../../../app/survey_drive.dart';
import '../../../obd/survey/survey_guide.dart';
import '../../../obd/survey/survey_runner.dart';
import '../../design/components/controls/tape_button.dart';
import '../../design/components/tape_label.dart';
import '../../design/icons/icons.dart';
import '../../design/motion/observable_listenable.dart';
import '../../design/theme/tape_theme.dart';
import '../../design/tokens/spacing.dart';

/// The survey drive (Garage → Survey drive): a plain, glanceable screen for a
/// drive whose point is the file it leaves behind (docs/SURVEY.md).
///
/// **It leads.** Before: what it will do and will not do. Then, once the car
/// answers and stands still, the parked checks: one step at a time, a big title,
/// what to do, a countdown, and the log noting each switch as it is asked for,
/// so nothing is tapped or remembered. Then the drive, which asks for nothing
/// and shows nothing to touch while the car moves. When the car stops again, the
/// same checks can be run a second time, and then the survey ended. After: where
/// the file is.
///
/// The numbers change once a second, so this page rebuilds once a second. That
/// is a decision for this screen only: it is not a driving screen (DESIGN.md
/// 9.3's rule for live values is about those), and it has almost nothing to
/// draw.
class SurveyPage extends StatefulWidget {
  const SurveyPage({
    super.key,
    required this.drive,
    required this.width,
    required this.height,
    required this.onClose,
  });

  final SurveyDrive drive;
  final double width;
  final double height;

  /// Leaves the survey for the dashboard.
  final VoidCallback onClose;

  @override
  State<SurveyPage> createState() => SurveyPageState();
}

class SurveyPageState extends State<SurveyPage> {
  late final ObservableListenable<SurveyStage> _stage = ObservableListenable(
    widget.drive.stage,
  );
  late final ObservableListenable<SurveyProgress> _progress =
      ObservableListenable(widget.drive.progress);
  late final ObservableListenable<bool> _canFinish = ObservableListenable(
    widget.drive.canFinish,
  );
  late final ObservableListenable<bool> _saveFailed = ObservableListenable(
    widget.drive.saveFailed,
  );
  late final ObservableListenable<GuideState> _guide = ObservableListenable(
    widget.drive.guide.state,
  );

  bool _finishing = false;

  @override
  void dispose() {
    _stage.dispose();
    _progress.dispose();
    _canFinish.dispose();
    _saveFailed.dispose();
    _guide.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    setState(() => _finishing = true);
    await widget.drive.finish();
    if (mounted) setState(() => _finishing = false);
  }

  @override
  Widget build(BuildContext context) {
    final margin = TapeSpace.margin(widget.height);
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: Padding(
        padding: EdgeInsets.all(margin),
        child: AnimatedBuilder(
          animation: Listenable.merge([
            _stage,
            _progress,
            _canFinish,
            _saveFailed,
            _guide,
          ]),
          builder: (context, _) => switch (widget.drive.stage.value) {
            SurveyStage.ready => _ready(context),
            SurveyStage.running => _running(context),
            SurveyStage.finished => _finished(context),
          },
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ layout

  /// Text on the left, buttons in a column on the right.
  Widget _split({required Widget text, required List<Widget> buttons}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: text),
        const SizedBox(width: TapeSpace.s6),
        SizedBox(
          width: 200,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < buttons.length; i++) ...[
                if (i > 0) const SizedBox(height: TapeSpace.touchGap),
                buttons[i],
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _para(BuildContext context, String text) {
    final palette = TapeTheme.of(context).palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: TapeSpace.s2),
      child: TapeText(text, style: TapeTextStyle.small, color: palette.inkMid),
    );
  }

  // ------------------------------------------------------------------- ready

  Widget _ready(BuildContext context) {
    return _split(
      text: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const TapeLabel('Survey drive', size: 11),
            const SizedBox(height: TapeSpace.s2),
            const TapeText(
              'Find out what your car can report',
              style: TapeTextStyle.title,
            ),
            const SizedBox(height: TapeSpace.s3),
            _para(
              context,
              'It asks every computer in the car for everything it will say, '
              'and writes the whole conversation to a file on this phone. From '
              'that we can see what TapeDash could show.',
            ),
            _para(
              context,
              'It only reads. It does not clear codes or change anything in '
              'the car, and nothing leaves the phone. The dashboard is off '
              'while it runs.',
            ),
            _para(
              context,
              'It leads you: first a few minutes of parked checks, switching '
              'the lights, blower, A/C and wipers on and off as it asks. Then '
              'you drive as usual, twenty minutes or more. Then, parked, the '
              'checks once more and you are done.',
            ),
            _para(
              context,
              'Park with the engine running, the handbrake on, and the phone on '
              'the dash.',
            ),
          ],
        ),
      ),
      buttons: [
        TapeButton(
          label: 'Start survey',
          icon: TapeIcon.play,
          primary: true,
          onPressed: widget.drive.start,
        ),
        TapeButton(label: 'Not now', onPressed: widget.onClose),
      ],
    );
  }

  // ----------------------------------------------------------------- running

  static String _phaseText(SurveyPhase phase) => switch (phase) {
    SurveyPhase.connecting => 'Connecting to the adapter…',
    SurveyPhase.starting => 'Starting the adapter…',
    SurveyPhase.discovering => 'Asking which computers answer…',
    SurveyPhase.probing => 'Reading everything once…',
    SurveyPhase.driving => 'Reading the car. Drive as you usually do.',
    SurveyPhase.waitingForCar =>
      'The car is off. It carries on when you start it.',
    SurveyPhase.finished => 'Finished.',
    SurveyPhase.failed => 'Could not read the car.',
  };

  static String _clock(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  Widget _running(BuildContext context) {
    final g = widget.drive.guide.state.value;
    final p = widget.drive.progress.value;
    if (g.active) return _checks(context, g);
    final starting =
        p.phase == SurveyPhase.connecting ||
        p.phase == SurveyPhase.starting ||
        p.phase == SurveyPhase.discovering ||
        p.phase == SurveyPhase.probing;
    if (g.passesDone == 0 && starting) return _gettingReady(context, p);
    if (g.passesDone == 0 && g.canBegin) return _offer(context);
    return _driving(context, g, p);
  }

  /// The adapter is being set up and the car asked what it has.
  Widget _gettingReady(BuildContext context, SurveyProgress p) {
    final palette = TapeTheme.of(context).palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const TapeLabel('Survey drive', size: 11),
        const SizedBox(height: TapeSpace.s2),
        const TapeText('Getting ready', style: TapeTextStyle.title),
        const SizedBox(height: TapeSpace.s3),
        TapeText(
          _phaseText(p.phase),
          style: TapeTextStyle.body,
          color: palette.inkMid,
        ),
        const SizedBox(height: TapeSpace.s2),
        TapeText(
          'Keep the engine running and the car where it is.',
          style: TapeTextStyle.small,
          color: palette.inkMid,
        ),
      ],
    );
  }

  /// Ready, before the first checks.
  Widget _offer(BuildContext context) {
    return _split(
      text: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const TapeLabel('Survey drive · before you drive', size: 11),
            const SizedBox(height: TapeSpace.s2),
            const TapeText('Parked checks', style: TapeTextStyle.title),
            const SizedBox(height: TapeSpace.s3),
            _para(
              context,
              'About four minutes. It tells you what to switch on and off, one '
              'thing at a time, and keeps the time. Engine running, car in P '
              'with the handbrake on.',
            ),
            _para(
              context,
              'There is a step that revs the engine a little. It says what to '
              'do, and you can skip any step.',
            ),
          ],
        ),
      ),
      buttons: [
        TapeButton(
          label: 'Begin checks',
          icon: TapeIcon.play,
          primary: true,
          onPressed: widget.drive.guide.begin,
        ),
        TapeButton(label: 'Skip checks', onPressed: widget.drive.guide.skipAll),
      ],
    );
  }

  /// A step of the checks: what to do, and how long.
  Widget _checks(BuildContext context, GuideState g) {
    final palette = TapeTheme.of(context).palette;
    final step = g.step!;
    final fraction = step.seconds == 0
        ? 1.0
        : (1 - g.remaining / step.seconds).clamp(0.0, 1.0);
    return _split(
      text: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TapeLabel(
            g.pass == 1
                ? 'Checks · before the drive'
                : 'Checks · after the drive',
            size: 11,
          ),
          const SizedBox(height: TapeSpace.s1),
          TapeLabel(
            'Step ${g.stepIndex + 1} of ${g.stepCount}',
            size: 10,
            color: palette.inkDim,
          ),
          const SizedBox(height: TapeSpace.s3),
          TapeText(step.title, style: TapeTextStyle.headline),
          const SizedBox(height: TapeSpace.s2),
          Expanded(
            child: SingleChildScrollView(
              child: TapeText(
                step.instruction,
                style: TapeTextStyle.body,
                color: palette.inkMid,
              ),
            ),
          ),
          if (g.paused || g.message != null)
            Padding(
              padding: const EdgeInsets.only(bottom: TapeSpace.s2),
              child: TapeText(
                g.message ?? 'Waiting.',
                style: TapeTextStyle.small,
                color: palette.caution,
              ),
            ),
          Row(
            children: [
              TapeText('${g.remaining}', style: TapeTextStyle.title),
              const SizedBox(width: TapeSpace.s2),
              TapeLabel('seconds', size: 10, color: palette.inkDim),
              const SizedBox(width: TapeSpace.s3),
              Expanded(
                child: SizedBox(
                  height: 6,
                  child: Stack(
                    children: [
                      Positioned.fill(child: ColoredBox(color: palette.track)),
                      Positioned.fill(
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: fraction,
                          child: ColoredBox(color: palette.accentCore),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      buttons: [
        TapeButton(label: 'Next step', onPressed: widget.drive.guide.skipStep),
        TapeButton(label: 'Stop checks', onPressed: widget.drive.guide.skipAll),
      ],
    );
  }

  /// Between the checks: the drive, and what to do when parked.
  Widget _driving(BuildContext context, GuideState g, SurveyProgress p) {
    final palette = TapeTheme.of(context).palette;
    final canFinish = widget.drive.canFinish.value;
    Widget fact(String label, String value) => SizedBox(
      height: 20,
      child: Row(
        children: [
          SizedBox(width: 96, child: TapeLabel(label, size: 10)),
          Expanded(
            child: TapeText(
              value,
              style: TapeTextStyle.caption,
              color: palette.inkBright,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
    String volts(double? v) => v == null ? '—' : '${v.toStringAsFixed(1)} V';
    final shortDrive = p.elapsed < SurveyDrive.shortDrive;
    // The checks again: if the first were skipped or stopped, now; if they were
    // gone through, once there has been a drive.
    final showChecks = g.canBegin && (g.lastIncomplete || !shortDrive);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 5,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const TapeLabel('Survey drive', size: 11),
              const SizedBox(height: TapeSpace.s1),
              TapeText(_clock(p.elapsed), style: TapeTextStyle.headline),
              const SizedBox(height: TapeSpace.s1),
              TapeText(
                _phaseText(p.phase),
                style: TapeTextStyle.body,
                color: palette.inkMid,
              ),
              const SizedBox(height: TapeSpace.s3),
              fact(
                'Computers',
                p.ecus.isEmpty ? '—' : '${p.ecus.length} answering',
              ),
              fact(
                'Read so far',
                p.pidsAvailable == 0
                    ? '—'
                    : '${p.pidsSeen} of ${p.pidsAvailable}',
              ),
              fact(
                'Answers',
                '${p.answersPerSecond.toStringAsFixed(1)} a second',
              ),
              fact('Battery', volts(p.volts)),
              fact('At the socket', volts(p.adapterVolts)),
              if (p.linkDrops > 0) fact('Link lost', '${p.linkDrops} times'),
              if (widget.drive.saveFailed.value)
                const Padding(
                  padding: EdgeInsets.only(top: TapeSpace.s1),
                  child: TapeText(
                    'Could not save to the phone just now. It will try again.',
                    style: TapeTextStyle.caption,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: TapeSpace.s4),
        Expanded(
          flex: 4,
          child: canFinish
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (g.message != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: TapeSpace.s2),
                        child: TapeText(
                          g.message!,
                          style: TapeTextStyle.small,
                          color: palette.caution,
                        ),
                      ),
                    Expanded(
                      child: SingleChildScrollView(
                        child: TapeText(
                          _parkedAdvice(g, shortDrive),
                          style: TapeTextStyle.small,
                          color: palette.inkMid,
                        ),
                      ),
                    ),
                    if (showChecks) ...[
                      TapeButton(
                        label: g.lastIncomplete && g.passesDone == 1
                            ? 'Do the checks now'
                            : 'Repeat the checks',
                        icon: TapeIcon.play,
                        onPressed: widget.drive.guide.begin,
                      ),
                      const SizedBox(height: TapeSpace.touchGap),
                    ],
                    TapeButton(
                      label: _finishing ? 'Saving…' : 'Finish survey',
                      icon: TapeIcon.stop,
                      primary: !showChecks,
                      onPressed: _finishing ? null : _finish,
                    ),
                  ],
                )
              : Align(
                  alignment: Alignment.bottomLeft,
                  child: TapeText(
                    'Nothing to do while driving. When you stop, the next step '
                    'appears here.',
                    style: TapeTextStyle.caption,
                    color: palette.inkMid,
                  ),
                ),
        ),
      ],
    );
  }

  /// What to say when the car is standing between the checks.
  static String _parkedAdvice(GuideState g, bool shortDrive) {
    if (shortDrive && g.passesDone == 1) {
      return 'Pull away when you are ready. Drive for twenty minutes or more, '
          'as you usually do. If there is a clear, legal stretch, include a '
          'steady 60 to 100 km/h, a firm (not flat-out) acceleration, and a '
          'lift-off coast. Nothing is required.';
    }
    if (g.passesDone == 1) {
      return 'Parked. Run the checks once more, with the engine warm, then '
          'finish. Or finish now.';
    }
    return 'Both runs of the checks are done. Finish the survey.';
  }

  // ---------------------------------------------------------------- finished

  Widget _finished(BuildContext context) {
    final palette = TapeTheme.of(context).palette;
    final p = widget.drive.progress.value;
    final failed = p.phase == SurveyPhase.failed;
    final name = widget.drive.fileName ?? '';
    final saved = !widget.drive.saveFailed.value;
    return _split(
      text: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const TapeLabel('Survey drive', size: 11),
          const SizedBox(height: TapeSpace.s2),
          TapeText(
            failed
                ? 'The survey could not run'
                : (saved ? 'Survey saved' : 'Could not save the survey'),
            style: TapeTextStyle.title,
          ),
          const SizedBox(height: TapeSpace.s3),
          if (failed && p.detail != null)
            TapeText(
              p.detail!,
              style: TapeTextStyle.small,
              color: palette.inkMid,
            ),
          if (!failed && saved) ...[
            TapeText(
              '${p.requests} requests in ${_clock(p.elapsed)}, '
              '${p.pidsSeen} different values read.',
              style: TapeTextStyle.small,
              color: palette.inkMid,
            ),
            const SizedBox(height: TapeSpace.s3),
            TapeText(name, style: TapeTextStyle.body),
            const SizedBox(height: TapeSpace.s1),
            TapeText(
              'In ${SurveyDrive.where} on this phone. Copy it to a '
              'computer over USB and keep it: it is the whole survey.',
              style: TapeTextStyle.small,
              color: palette.inkMid,
            ),
          ],
          if (!failed && !saved)
            TapeText(
              'The phone would not take the file. Free some space and '
              'run the survey again.',
              style: TapeTextStyle.small,
              color: palette.inkMid,
            ),
        ],
      ),
      buttons: [
        TapeButton(
          label: 'Dashboard',
          primary: true,
          onPressed: widget.onClose,
        ),
      ],
    );
  }
}
