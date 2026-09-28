import 'package:flutter/widgets.dart';

import '../motion/numeral_source.dart';
import 'rolling_numerals.dart';

/// Centres a [RollingNumerals] value the way its typically-lit digits
/// should read, not its full digit reservation.
///
/// [RollingNumerals] reserves [NumeralFormat.integerDigits]' worth of width
/// and right-anchors its digits within it, on purpose (DESIGN.md 9.3): a
/// value's position must never jitter sideways as its own digit count
/// changes, and an unlit leading digit fades rather than vanishing. That is
/// exactly right for a corner-anchored tile, and exactly wrong for a hero
/// readout most values only need [typicalIntegerDigits] of: plain `Center`
/// centres the *reservation*, leaving the commonly-shorter visible content
/// sitting in its right portion, off-centre. Hit twice already (the road
/// view's hero speed, DESIGN.md 6.11; the Apex cluster's, DESIGN.md 7.3) --
/// this solves it once, from the numeral's own metrics, rather than a
/// third hand-tuned offset.
///
/// It reports [typicalIntegerDigits]' own width to whatever lays it out
/// (so a label below it in a `Column` centres under the same width as the
/// visible digits, not the full reservation), while the full reservation
/// still paints in full, overflowing to that width's left where a rare
/// extra leading digit lives. A value that actually needs more digits than
/// [typicalIntegerDigits] is never clipped -- it reads a little left of
/// centre instead, which is far less wrong than either jittering the whole
/// readout sideways on every such value, or clipping it.
///
/// Centres on the integer part's own width only: a decimal format's dot and
/// decimal columns are not accounted for, since every current use of this
/// is whole numbers.
///
/// The overflowing child is given loose, not tight, width constraints on
/// purpose. A first version forced it to this class's own *estimated* full
/// width (`NumeralMetrics.pitch` times the digit count) via a tight
/// constraint, and `NumeralMetrics`'s own doc comment already says it is an
/// estimate for laying out what sits *around* a readout -- but the gap from
/// the real glyph atlas's own digit advance turned out not to be a rounding
/// error: at size 100 the estimate was a full digit-width short, leaving the
/// numeral's own right edge visibly inside the box's, not flush with it, a
/// capture shot caught but a `debugPrint` of the numbers alongside a
/// translucent marker over the reported box was what actually pinned down.
/// Left loose instead, `RollingNumerals` reports its own real, atlas-
/// measured width, and `alignment: centerRight` aligns *that* -- exact
/// regardless of any gap between the estimate and the atlas. The estimate is
/// only used for the reported (typical-width) box external layout sees,
/// where being a few pixels off is in practice not visible.
class CenteredNumeral extends StatelessWidget {
  const CenteredNumeral({
    super.key,
    required this.source,
    required this.format,
    required this.size,
    required this.typicalIntegerDigits,
    this.role = NumeralRole.accent,
    this.halo = 0,
  });

  final NumeralSource source;
  final NumeralFormat format;
  final double size;

  /// How many integer digits are typically lit; the rest of
  /// [NumeralFormat.integerDigits] is the rarely-used overflow room.
  final int typicalIntegerDigits;

  final NumeralRole role;
  final double halo;

  @override
  Widget build(BuildContext context) {
    final numeral = RollingNumerals(
      source: source,
      format: format,
      size: size,
      role: role,
      halo: halo,
    );
    final spareDigits = format.integerDigits - typicalIntegerDigits;
    if (spareDigits <= 0) return numeral;

    final metrics = NumeralMetrics(size);
    final estimatedFullWidth = format.integerDigits * metrics.pitch;
    final typicalWidth = estimatedFullWidth - spareDigits * metrics.pitch;
    // The outer box's height is pinned explicitly, not left to pass
    // through unconstrained: an ambient unbounded height (Positioned(top,
    // left, right) with no bottom, as the road view's and the Apex
    // cluster's hero readout both sit in) is ordinarily harmless -- Center
    // reports an infinite size upward, but still gives a plain
    // RollingNumerals loose, not infinite, constraints, since it sizes off
    // its own content regardless of what it is offered. OverflowBox does
    // not: its internal offset math multiplies straight through an
    // infinite parent height, producing a transform with an infinite
    // entry (a real crash here, not a hypothetical) if height is left
    // unconstrained the way SizedBox(width:) alone would leave it.
    return SizedBox(
      width: typicalWidth,
      height: metrics.boxHeight,
      child: OverflowBox(
        minWidth: 0,
        maxWidth: estimatedFullWidth * 2, // generous headroom, not a claim.
        maxHeight: metrics.boxHeight * 1.5,
        alignment: Alignment.centerRight,
        child: numeral,
      ),
    );
  }
}
