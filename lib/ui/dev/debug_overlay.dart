import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../design/components/controls/tape_button.dart';
import '../design/components/tape_label.dart';
import '../design/theme/tape_theme.dart';
import '../design/tokens/spacing.dart';
import '../design/tokens/strokes.dart';

/// One line of the debug overlay: a label and a value that changes.
class DebugRow {
  const DebugRow(this.label, this.value);

  final String label;
  final ValueListenable<String> value;
}

/// A line of text worked out from [sources] whenever any of them changes, for the
/// debug overlay.
class ComputedText extends ChangeNotifier implements ValueListenable<String> {
  ComputedText(Iterable<Listenable> sources, this._compute)
    : _sources = List.of(sources) {
    for (final s in _sources) {
      s.addListener(_changed);
    }
  }

  final List<Listenable> _sources;
  final String Function() _compute;

  void _changed() => notifyListeners();

  @override
  String get value => _compute();

  @override
  void dispose() {
    for (final s in _sources) {
      s.removeListener(_changed);
    }
    super.dispose();
  }
}

/// The debug overlay (CLAUDE.md 9): frames a second, the poll rate, the fuel
/// source, the fidelity tier and the phone's temperature, and a way into the Design
/// Lab. It opens with a long-press on a driving screen and is closed with its own
/// button. It is for the person testing the app in a car (`docs/HARDWARE_HANDOFF.md`
/// asks for these numbers), not for a driver: it is one long-press away and never
/// shown by itself.
class DebugOverlay extends StatelessWidget {
  const DebugOverlay({
    super.key,
    required this.rows,
    required this.onClose,
    this.onOpenLab,
  });

  final List<DebugRow> rows;
  final VoidCallback onClose;

  /// Opens the Design Lab, when there is one to open.
  final VoidCallback? onOpenLab;

  @override
  Widget build(BuildContext context) {
    final palette = TapeTheme.of(context).palette;
    return Container(
      margin: const EdgeInsets.all(TapeSpace.s3),
      padding: const EdgeInsets.all(TapeSpace.s3),
      width: 300,
      decoration: BoxDecoration(
        color: palette.canvas.withValues(alpha: 0.94),
        border: Border.all(color: palette.etchStrong, width: TapeStroke.fine),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const TapeLabel('Debug', size: 11),
          const SizedBox(height: TapeSpace.s1),
          for (final row in rows)
            SizedBox(
              height: 20,
              child: Row(
                children: [
                  SizedBox(width: 96, child: TapeLabel(row.label, size: 10)),
                  Expanded(
                    child: ValueListenableBuilder<String>(
                      valueListenable: row.value,
                      builder: (context, text, _) => TapeText(
                        text,
                        style: TapeTextStyle.caption,
                        color: palette.inkBright,
                        maxLines: 1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: TapeSpace.s2),
          Row(
            children: [
              if (onOpenLab != null) ...[
                TapeButton(
                  label: 'Design Lab',
                  compact: true,
                  onPressed: onOpenLab,
                ),
                const SizedBox(width: TapeSpace.s2),
              ],
              TapeButton(label: 'Close', compact: true, onPressed: onClose),
            ],
          ),
        ],
      ),
    );
  }
}
