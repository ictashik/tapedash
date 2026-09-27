import 'dart:ui' show Color;

/// The four liveries (DESIGN.md 4.4).
enum LiveryId { ion, ember, vfd, mono }

/// How a livery draws its numerals.
enum NumeralFace {
  /// Saira, wide: the typeface of the design.
  saira,

  /// The seven-segment renderer, with ghost segments (DESIGN.md 6.17).
  sevenSegment,
}

/// A livery swaps the accent colours, the numeral style and the texture. Layout
/// and motion never change (DESIGN.md 4.4).
class Livery {
  const Livery({
    required this.id,
    required this.name,
    required this.character,
    required this.accentCore,
    required this.accentDeep,
    required this.accentGlow,
    required this.numerals,
    required this.numeralWeight,
    this.haloScale = 1,
    this.ghostAlpha = 0,
    this.mesh = false,
  });

  final LiveryId id;

  /// Shown in the Garage and the Design Lab.
  final String name;

  /// One line on what it feels like.
  final String character;

  /// Live primary data and needles.
  final Color accentCore;

  /// Fills and tracks.
  final Color accentDeep;

  /// Halos only (the light layer, L3).
  final Color accentGlow;

  final NumeralFace numerals;

  /// The `wght` of Saira for this livery's numerals: Medium, SemiBold or Light.
  /// Unused by the seven-segment face.
  final double numeralWeight;

  /// How strong this livery's halos are, against the standard. MONO's are 40%.
  final double haloScale;

  /// How visible an unlit seven-segment is: 7% of the accent. 0 for the others.
  final double ghostAlpha;

  /// A fine hex mesh over data areas, at 3% (VFD only).
  final bool mesh;

  bool get isSevenSegment => numerals == NumeralFace.sevenSegment;
}

/// The liveries, as tokens.
abstract final class Liveries {
  /// The default: cool, electric, modern.
  static const Livery ion = Livery(
    id: LiveryId.ion,
    name: 'ION',
    character: 'Cool, electric, modern',
    accentCore: Color(0xFF5CE1FF),
    accentDeep: Color(0xFF1296FF),
    accentGlow: Color(0xFF2EC8FF),
    numerals: NumeralFace.saira,
    numeralWeight: 500,
  );

  /// Warm and sporty.
  static const Livery ember = Livery(
    id: LiveryId.ember,
    name: 'EMBER',
    character: 'Warm, sporty',
    accentCore: Color(0xFFFF7A3D),
    accentDeep: Color(0xFFE8461C),
    accentGlow: Color(0xFFFF6A2B),
    numerals: NumeralFace.saira,
    numeralWeight: 600,
  );

  /// An 80s digital dash: glowing segments with ghost digits.
  static const Livery vfd = Livery(
    id: LiveryId.vfd,
    name: 'VFD',
    character: '80s digital dash',
    accentCore: Color(0xFF6BF7DC),
    accentDeep: Color(0xFF1FC2A4),
    accentGlow: Color(0xFF3DFFD5),
    numerals: NumeralFace.sevenSegment,
    numeralWeight: 500,
    ghostAlpha: 0.07,
    mesh: true,
  );

  /// Luxury and restrained, with thin strokes.
  static const Livery mono = Livery(
    id: LiveryId.mono,
    name: 'MONO',
    character: 'Luxury, restrained',
    accentCore: Color(0xFFF2F3F4),
    accentDeep: Color(0xFFA9AFB7),
    accentGlow: Color(0xFFFFFFFF),
    numerals: NumeralFace.saira,
    numeralWeight: 300,
    haloScale: 0.4,
  );

  static const List<Livery> all = [ion, ember, vfd, mono];

  static Livery byId(LiveryId id) => all.firstWhere((l) => l.id == id);
}
