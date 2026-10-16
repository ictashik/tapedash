import 'package:flutter/widgets.dart';

import '../../../app/survey_drive.dart';
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
/// Three states. Before: what it will do and what it will not. During: how it is
/// going, in numbers big enough to see on the dash, and nothing to touch while
/// the car moves; when the car has stood still for a few seconds, the marks
/// (headlights, A/C... each noted in the log with its time, to tell later what
/// each one did to the battery voltage) and the button that ends it. After:
/// where the file is.
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

/// Things the user does that load the electrics, to note with a time in the
/// log. All but the last are switches; steering is turning the wheel lock to
/// lock, marked on while it is done.
const List<(String, String)> surveyMarks = [
  ('headlights', 'Headlights'),
  ('blower', 'Blower'),
  ('ac', 'A/C'),
  ('defogger', 'Defogger'),
  ('wipers', 'Wipers'),
  ('steering', 'Steering'),
];

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

  /// Which marks are on.
  final Set<String> _marked = {};
  bool _finishing = false;

  @override
  void dispose() {
    _stage.dispose();
    _progress.dispose();
    _canFinish.dispose();
    _saveFailed.dispose();
    super.dispose();
  }

  void _toggle(String id) {
    final on = !_marked.contains(id);
    setState(() => on ? _marked.add(id) : _marked.remove(id));
    widget.drive.mark(id, on);
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

  // ------------------------------------------------------------------- ready

  Widget _ready(BuildContext context) {
    final palette = TapeTheme.of(context).palette;
    Widget line(String text) => Padding(
      padding: const EdgeInsets.only(bottom: TapeSpace.s2),
      child: TapeText(text, style: TapeTextStyle.small, color: palette.inkMid),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: SingleChildScrollView(
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
                line(
                  'It asks every computer in the car for everything it will '
                  'say, and writes the whole conversation to a file on this '
                  'phone. From that we can see what TapeDash could show.',
                ),
                line(
                  'It only reads. It does not clear codes or change anything '
                  'in the car, and nothing leaves the phone.',
                ),
                line(
                  'The dashboard is off while it runs. Start it, put the '
                  'phone on the dash and drive as you usually do, for twenty '
                  'minutes or more. Stop it when you are parked.',
                ),
                line(
                  'Parked with the engine running, at the start and again at '
                  'the end, switch the headlights, blower, A/C, rear '
                  'defogger and wipers on and off, and turn the steering '
                  'wheel lock to lock. Mark each one on the next screen.',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: TapeSpace.s6),
        SizedBox(
          width: 200,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TapeButton(
                label: 'Start survey',
                icon: TapeIcon.play,
                primary: true,
                onPressed: widget.drive.start,
              ),
              const SizedBox(height: TapeSpace.touchGap),
              TapeButton(label: 'Not now', onPressed: widget.onClose),
            ],
          ),
        ),
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
    final palette = TapeTheme.of(context).palette;
    final p = widget.drive.progress.value;
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
          child: canFinish ? _parkedControls(context) : _drivingNote(context),
        ),
      ],
    );
  }

  /// While the car moves there is nothing to press.
  Widget _drivingNote(BuildContext context) {
    final palette = TapeTheme.of(context).palette;
    return Align(
      alignment: Alignment.bottomLeft,
      child: TapeText(
        'Nothing to do while driving. When you stop, the marks and the '
        'finish button appear.',
        style: TapeTextStyle.caption,
        color: palette.inkMid,
      ),
    );
  }

  Widget _parkedControls(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TapeLabel('Mark what you switch on', size: 10),
        const SizedBox(height: TapeSpace.s1),
        Expanded(
          child: Wrap(
            spacing: TapeSpace.touchGap,
            runSpacing: TapeSpace.touchGap,
            children: [
              for (final (id, label) in surveyMarks)
                SizedBox(
                  width: 128,
                  child: TapeButton(
                    label: label,
                    dense: true,
                    primary: _marked.contains(id),
                    onPressed: () => _toggle(id),
                  ),
                ),
            ],
          ),
        ),
        TapeButton(
          label: _finishing ? 'Saving…' : 'Finish survey',
          icon: TapeIcon.stop,
          primary: true,
          onPressed: _finishing ? null : _finish,
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- finished

  Widget _finished(BuildContext context) {
    final palette = TapeTheme.of(context).palette;
    final p = widget.drive.progress.value;
    final failed = p.phase == SurveyPhase.failed;
    final name = widget.drive.fileName ?? '';
    final saved = !widget.drive.saveFailed.value;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: Column(
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
        ),
        const SizedBox(width: TapeSpace.s6),
        SizedBox(
          width: 200,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TapeButton(
                label: 'Dashboard',
                primary: true,
                onPressed: widget.onClose,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
