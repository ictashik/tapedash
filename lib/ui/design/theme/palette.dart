import 'dart:ui' show Color;

import '../tokens/colors.dart';
import '../tokens/livery.dart';
import '../tokens/strokes.dart';
import 'contrast.dart';

/// Daylight and Night are modes applied on top of any livery (DESIGN.md 4.4).
enum TapeMode {
  normal('NORMAL'),

  /// Bright ambient light: halos off, strokes thicker, labels brighter,
  /// contrast over atmosphere.
  daylight('DAYLIGHT'),

  /// Dark ambient light: halos halved, structure dimmed, no glare.
  night('NIGHT');

  const TapeMode(this.label);

  final String label;
}

/// Which flank is nearer the driver (DESIGN.md 4.7). The default is right, for
/// India.
enum DriverSide { left, right }

/// The colours of one livery in one mode, resolved (DESIGN.md 4.3 and 4.4).
///
/// Nothing draws from the raw tokens when a mode changes what a colour should
/// be: it asks the palette. So the rules of Daylight and Night are written once,
/// here.
class TapePalette {
  TapePalette({required this.livery, this.mode = TapeMode.normal});

  final Livery livery;
  final TapeMode mode;

  bool get isDaylight => mode == TapeMode.daylight;
  bool get isNight => mode == TapeMode.night;

  // Surfaces

  Color get canvas => TapeColors.voidColor;
  Color get vignetteCentre => TapeColors.carbon900;
  Color get panel => TapeColors.carbon800;

  /// Tracks and unlit segments.
  Color get track => TapeColors.carbon700;

  /// Disabled and inactive tracks.
  Color get trackInactive => TapeColors.carbon600;

  // Etch (L1, the structure). At night it is 70% (DESIGN.md 4.4).

  Color get etchFaint => _structure(TapeColors.etchFaint);
  Color get etch => _structure(TapeColors.etch);
  Color get etchStrong => _structure(TapeColors.etchStrong);

  /// The glass edge of a parked overlay (DESIGN.md 4.9): the strong etch, at full
  /// strength, since it is not structure.
  Color get glassEdge => TapeColors.etchStrong;

  Color _structure(Color etch) =>
      isNight ? etch.withValues(alpha: etch.a * nightStructure) : etch;

  // Ink

  /// The brightest ink: primary values that are not in the accent.
  Color get inkBright => TapeColors.inkBright;

  /// Secondary values. In Daylight the dim ink is this one.
  Color get inkMid => TapeColors.inkMid;

  /// Units, and anything that must recede. Daylight lifts it to `ink.mid`.
  Color get inkDim => isDaylight ? TapeColors.inkMid : TapeColors.inkDim;

  /// Instrument labels. They keep their full colour at night, and become
  /// `ink.bright` in Daylight.
  Color get label => isDaylight ? TapeColors.inkBright : TapeColors.inkDim;

  /// Stale values: the dim ink, so that Daylight keeps them legible.
  ///
  /// The HUD is one colour on black (DESIGN.md 8), so its stale values are that
  /// colour, dimmed towards black, and never a grey.
  Color get stale => livery.id == LiveryId.hud
      ? Color.lerp(TapeColors.hudBlack, livery.accentCore, hudStaleShare)!
      : inkDim;

  /// How much of the HUD colour a stale HUD value keeps.
  static const double hudStaleShare = 0.45;

  /// The white of needle cores and peak highlights. Used for nothing else at
  /// night, and that is the caller's to keep (DESIGN.md 4.4).
  Color get inkHot => TapeColors.inkHot;

  /// Whether `ink.hot` may be used for more than needle cores.
  bool get inkHotEverywhere => !isNight;

  // Accent

  Color get accentCore => livery.accentCore;
  Color get accentDeep => livery.accentDeep;
  Color get accentGlow => livery.accentGlow;

  /// The colour of live primary numerals. In Daylight an accent that reaches
  /// less than 10:1 against `void` (EMBER) gives way to `ink.bright`, while
  /// needles, segments and fills keep the accent.
  Color get numeral {
    if (isDaylight &&
        Contrast.ratio(livery.accentCore, TapeColors.voidColor) <
            daylightNumeralContrast) {
      return TapeColors.inkBright;
    }
    return livery.accentCore;
  }

  /// The contrast Daylight requires of a primary value against `void`
  /// (DESIGN.md 11).
  static const double daylightNumeralContrast = 10;

  // Money

  /// The digits of a money readout.
  Color get money => TapeColors.moneyCore;

  /// The rupee sign: `money.deep`, and `money.core` in Daylight.
  Color get rupee => isDaylight ? TapeColors.moneyCore : TapeColors.moneyDeep;

  /// A normal Money Tape block (DESIGN.md 6.8), and anywhere else that
  /// wants the deeper of the two money tones on its own, not the rupee
  /// sign's Daylight-lifted version.
  Color get moneyDeep => TapeColors.moneyDeep;

  Color get moneyGlow => TapeColors.moneyGlow;

  // State

  Color get caution => TapeColors.caution;
  Color get critical => TapeColors.critical;

  // Effects

  /// How strong halos are: Daylight has none, Night has half, and the livery
  /// scales what is left (MONO is at 40%).
  double get haloScale => switch (mode) {
    TapeMode.daylight => 0,
    TapeMode.night => 0.5 * livery.haloScale,
    TapeMode.normal => livery.haloScale,
  };

  /// Daylight draws every stroke 50% thicker.
  double get strokeScale => isDaylight ? TapeStroke.daylightScale : 1;

  /// The share of the etch that remains at night.
  static const double nightStructure = 0.7;

  @override
  bool operator ==(Object other) =>
      other is TapePalette &&
      other.livery.id == livery.id &&
      other.livery.accentCore == livery.accentCore &&
      other.mode == mode;

  @override
  int get hashCode => Object.hash(livery.id, livery.accentCore, mode);
}
