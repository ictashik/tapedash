import 'dart:ui' show Color;

/// Colour tokens from DESIGN.md 4.3.
///
/// Only `void` exists so far. The rest of the palette arrives with the design
/// system in phase 3a.
abstract final class TapeColors {
  /// `void`, #050607: the canvas behind everything, and the Android launch
  /// window colour. Not pure black, which looks grey-blue on cheap LCDs.
  ///
  /// Must match `tapedash_void` in `android/app/src/main/res/values/colors.xml`.
  static const Color voidColor = Color(0xFF050607);
}
