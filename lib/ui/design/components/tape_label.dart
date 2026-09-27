import 'package:flutter/widgets.dart';

import '../theme/tape_theme.dart';
import '../tokens/typography.dart';

/// An instrument label: UPPERCASE Barlow Semi Condensed Medium, tracked out
/// (DESIGN.md 4.5 and 10). It takes the theme's label colour, which Daylight lifts
/// to `ink.bright`.
class TapeLabel extends StatelessWidget {
  const TapeLabel(this.text, {super.key, this.size = 12, this.color});

  final String text;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final palette = TapeTheme.of(context).palette;
    return Text(
      text.toUpperCase(),
      style: TapeType.label(size: size, color: color ?? palette.label),
      maxLines: 1,
      softWrap: false,
    );
  }
}

/// Parked UI text: Barlow at the fixed sizes of DESIGN.md 4.5, sentence case.
class TapeText extends StatelessWidget {
  const TapeText(
    this.text, {
    super.key,
    this.style = TapeTextStyle.body,
    this.color,
    this.maxLines,
    this.textAlign,
  });

  final String text;
  final TapeTextStyle style;
  final Color? color;
  final int? maxLines;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final palette = TapeTheme.of(context).palette;
    final resolved = color ?? palette.inkBright;
    return Text(
      text,
      style: switch (style) {
        TapeTextStyle.headline => TapeType.headline(color: resolved),
        TapeTextStyle.title => TapeType.title(color: resolved),
        TapeTextStyle.body => TapeType.body(color: resolved),
        TapeTextStyle.small => TapeType.small(color: resolved),
        TapeTextStyle.caption => TapeType.caption(color: resolved),
      },
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
      textAlign: textAlign,
    );
  }
}

/// The five parked sizes (DESIGN.md 4.5).
enum TapeTextStyle { headline, title, body, small, caption }
