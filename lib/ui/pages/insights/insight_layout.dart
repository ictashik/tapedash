import 'package:flutter/widgets.dart';

import '../../design/components/tape_label.dart';
import '../../design/theme/palette.dart';
import '../../design/theme/tape_theme.dart';
import '../../design/tokens/spacing.dart';
import '../../design/tokens/typography.dart';
import '../review/review_page.dart' show BracketFramePainter;

/// The shape every insight panel shares: the chart takes the width, and a column of
/// facts in a bracket frame stands on the right (DESIGN.md 7.14).
class InsightPanel extends StatelessWidget {
  const InsightPanel({
    super.key,
    required this.chart,
    required this.facts,
    this.factsWidth = 0.34,
  });

  final Widget chart;

  /// The facts, top to bottom.
  final List<Widget> facts;

  /// The facts column's share of the panel's width.
  final double factsWidth;

  @override
  Widget build(BuildContext context) {
    final palette = TapeTheme.of(context).palette;
    return LayoutBuilder(
      builder: (context, box) {
        final right = (box.maxWidth * factsWidth).clamp(168.0, 280.0);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: chart),
            const SizedBox(width: TapeSpace.s4),
            SizedBox(
              width: right,
              child: CustomPaint(
                painter: BracketFramePainter(color: palette.etchStrong),
                child: Padding(
                  padding: const EdgeInsets.all(TapeSpace.s3),
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: facts,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// A fact: a label, a figure in Saira, and a line of plain words under it.
class InsightFact extends StatelessWidget {
  const InsightFact({
    super.key,
    required this.label,
    required this.value,
    this.note,
    this.color,
    this.size = 20,
  });

  final String label;
  final String value;
  final String? note;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = TapeTheme.of(context).palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: TapeSpace.s2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TapeLabel(label, size: 10),
          const SizedBox(height: 2),
          Text(
            value,
            style: TapeType.numeral(
              size: size,
              weight: 500,
              color: color ?? palette.inkBright,
            ),
            maxLines: 1,
          ),
          if (note != null)
            TapeText(
              note!,
              style: TapeTextStyle.caption,
              color: palette.inkMid,
            ),
        ],
      ),
    );
  }
}

/// Words in a facts column, for the caveat under the figures.
class InsightNote extends StatelessWidget {
  const InsightNote(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final TapePalette palette = TapeTheme.of(context).palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: TapeSpace.s2),
      child: TapeText(
        text,
        style: TapeTextStyle.caption,
        color: color ?? palette.inkMid,
      ),
    );
  }
}

/// What a chart says when there is nothing to draw yet: a title and the one thing
/// that fills it in.
class InsightEmpty extends StatelessWidget {
  const InsightEmpty({super.key, required this.title, required this.how});

  final String title;
  final String how;

  @override
  Widget build(BuildContext context) {
    final palette = TapeTheme.of(context).palette;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TapeLabel(title, size: 11),
            const SizedBox(height: TapeSpace.s2),
            TapeText(
              how,
              style: TapeTextStyle.small,
              color: palette.inkMid,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
