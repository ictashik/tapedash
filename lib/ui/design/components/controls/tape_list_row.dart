import 'package:flutter/widgets.dart';

import '../../icons/icons.dart';
import '../../theme/tape_theme.dart';
import '../../tokens/spacing.dart';
import '../../tokens/strokes.dart';
import '../tape_label.dart';
import 'touch_bloom.dart';

/// The list row (DESIGN.md 6.14): 64 lp, the label at the left, the value at the
/// right in `ink.mid`, a chevron, and a hairline under it inset by the margin.
class TapeListRow extends StatelessWidget {
  const TapeListRow({
    super.key,
    required this.label,
    this.value,
    this.icon,
    this.onTap,
    this.chevron = true,
    this.selected = false,
  });

  final String label;
  final String? value;
  final TapeIcon? icon;
  final VoidCallback? onTap;
  final bool chevron;

  /// The row is the one in effect: its label takes the accent.
  final bool selected;

  static const double height = 64;

  @override
  Widget build(BuildContext context) {
    final palette = TapeTheme.of(context).palette;
    final labelColor = onTap == null
        ? palette.inkDim
        : selected
        ? palette.accentCore
        : palette.inkBright;
    return TouchBloom(
      enabled: onTap != null,
      onTap: onTap,
      builder: (context, pressed) => SizedBox(
        height: height,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: TapeSpace.s4),
              child: Row(
                children: [
                  if (icon != null) ...[
                    TapeIconView(
                      icon!,
                      size: 24,
                      color: selected ? palette.accentCore : palette.inkMid,
                    ),
                    const SizedBox(width: TapeSpace.s3),
                  ],
                  Expanded(
                    child: TapeText(label, color: labelColor, maxLines: 1),
                  ),
                  if (value != null)
                    TapeText(value!, color: palette.inkMid, maxLines: 1),
                  if (chevron && onTap != null) ...[
                    const SizedBox(width: TapeSpace.s2),
                    TapeIconView(
                      TapeIcon.chevron,
                      size: 20,
                      color: palette.inkDim,
                    ),
                  ],
                ],
              ),
            ),
            Positioned(
              left: TapeSpace.s4,
              right: TapeSpace.s4,
              bottom: 0,
              height: TapeStroke.fine / 2,
              child: ColoredBox(color: palette.etch),
            ),
          ],
        ),
      ),
    );
  }
}
