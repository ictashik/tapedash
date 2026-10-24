import 'package:flutter/widgets.dart';

import '../design/components/rolling_numerals.dart';
import '../design/motion/numeral_source.dart';
import '../design/render/glyph_atlas.dart';
import '../design/render/render_kit.dart';
import '../design/theme/tape_theme.dart';
import '../design/tokens/hud.dart';
import '../design/tokens/typography.dart';

// The parts the HUD's layouts are built from (DESIGN.md 8), shared by hud_view.dart
// and nav_hud.dart.

/// Puts a numeral of [size] so that the middle of its *ink* is at [centre],
/// horizontally centred on [centreX]: the numeral's box is much taller than its
/// ink (the detent and roll room, DESIGN.md 5.6), so a layout laid out by box
/// would sit the digits well off where they are meant to be.
Positioned hudAtInk({
  required double centreX,
  required double centreY,
  required double size,
  required double boxWidth,
  required Widget child,
}) {
  final m = NumeralMetrics(size);
  final inkMiddle = m.inkTop + m.inkHeight / 2;
  return Positioned(
    left: centreX - boxWidth / 2,
    width: boxWidth,
    top: centreY - inkMiddle,
    // The child is centred in a box as tall as a numeral's own, so that a
    // dash or a ₹ sits on the same middle as the digits beside it.
    child: SizedBox(
      height: m.boxHeight,
      child: Center(child: child),
    ),
  );
}

/// A HUD label: UPPERCASE Barlow Semi Condensed, at least 0.06H, in the HUD
/// colour (a dim label would vanish in the glass).
Widget hudLabel(String text, double height, Color color) => Text(
  text,
  style: TapeType.label(size: height * TapeHud.labelShare, color: color),
  maxLines: 1,
  softWrap: false,
);

/// The HUD's numerals: Bold Saira from the glyph atlas, in the HUD colour, no
/// halo, [typical] integer digits wide and centred on them.
///
/// [CenteredNumeral] centres on an *estimate* of a digit's width (its own doc
/// comment says so), which at the HUD's huge sizes is a whole digit-width
/// wide of the atlas's real one: a measured 54 lp of drift on a 198 lp "64".
/// The HUD's numerals are the largest on any screen and sit alone, so this
/// reads the real advance from the same atlas the numerals draw from.
class HudNumerals extends StatelessWidget {
  const HudNumerals({
    super.key,
    required this.source,
    required this.format,
    required this.size,
    required this.typical,
  });

  final NumeralSource source;
  final NumeralFormat format;
  final double size;
  final int typical;

  @override
  Widget build(BuildContext context) {
    final theme = TapeTheme.of(context);
    final atlas = TapeRenderScope.of(context).atlases.get(
      GlyphAtlasSpec(
        sizeLp: size,
        devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
        weight: theme.livery.numeralWeight,
      ),
    );
    final metrics = NumeralMetrics(size);
    final numeral = RollingNumerals(
      source: source,
      format: format,
      size: size,
      role: NumeralRole.accent,
    );
    // The typical digits, plus the format's separators and decimals, at their
    // real advances: the width the lit part of the readout occupies.
    final lit = typical + format.decimals;
    var width = lit * atlas.digitAdvance;
    if (format.grouping != DigitGrouping.none) {
      final commas = format.grouping == DigitGrouping.indian
          ? (typical - 1) ~/ 2
          : (typical - 1) ~/ 3;
      width += commas * (atlas.glyph(0x2C)?.advance ?? 0);
    }
    if (format.decimals > 0) width += atlas.glyph(0x2E)?.advance ?? 0;
    final full =
        (format.integerDigits + format.decimals) * atlas.digitAdvance * 2;
    return SizedBox(
      width: width,
      height: metrics.boxHeight,
      child: OverflowBox(
        minWidth: 0,
        maxWidth: full,
        maxHeight: metrics.boxHeight * 1.5,
        alignment: Alignment.centerRight,
        child: numeral,
      ),
    );
  }
}
