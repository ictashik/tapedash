import 'package:flutter/widgets.dart';

import '../../design/components/tape_label.dart';
import '../../design/theme/tape_theme.dart';
import '../../design/tokens/spacing.dart';

/// An honest placeholder for a page whose content is a later phase's work
/// (CLAUDE.md 13): the page's own name, and the one line saying what it is
/// waiting for. Never a fake data screen -- CLAUDE.md 1's honest numbers
/// extends to an absent screen: an empty panel with the truth beats an
/// invented one.
///
/// Parked-only by the motion lock (DESIGN.md 7.1), so it may use the
/// parked voice (DESIGN.md 10): the name as an instrument label, the note
/// in sentence case.
class StripPlaceholder extends StatelessWidget {
  const StripPlaceholder({
    super.key,
    required this.name,
    required this.note,
    required this.width,
    required this.height,
  });

  final String name;

  /// The one line of truth about why the page is empty.
  final String note;

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final palette = TapeTheme.of(context).palette;
    return SizedBox(
      width: width,
      height: height,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TapeLabel(name, size: 14),
            const SizedBox(height: TapeSpace.s2),
            TapeText(note, color: palette.inkMid),
          ],
        ),
      ),
    );
  }
}
