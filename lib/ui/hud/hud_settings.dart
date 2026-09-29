// The private fields cannot be initializing formals of the public named
// parameters they are set from.
// ignore_for_file: prefer_initializing_formals

import 'package:flutter/foundation.dart';

import '../design/tokens/colors.dart' show HudColor;
import '../design/tokens/hud.dart';

/// Which of DESIGN.md 8's three layouts the HUD shows.
enum HudLayout {
  /// Huge speed, a thin RPM bar beneath, an alert slot.
  drive('Drive'),

  /// Speed on the left, ₹ this trip on the right.
  driveMoney('Drive + Money'),

  /// Huge ₹ this trip, ₹/km beneath.
  money('Money');

  const HudLayout(this.label);

  final String label;
}

/// Everything the user sets about the HUD (DESIGN.md 8): the colour, the layout,
/// the two flips, the vertical position and the scale, and whether the HUD is up
/// at all. The alignment pattern is a state of the HUD too, so it is here.
///
/// Plain state, no storage: the Garage (a later phase 3b piece) reads and writes
/// it through `shared_preferences`, and the last mode is remembered there. It
/// notifies on any change; the HUD rebuilds for a setting and never for data.
class HudSettings extends ChangeNotifier {
  HudSettings({
    HudColor color = HudColor.green,
    HudLayout layout = HudLayout.drive,
    bool flipHorizontal = true,
    bool flipVertical = false,
    double verticalPosition = 0,
    double scale = 1,
    bool active = false,
  }) : _color = color,
       _layout = layout,
       _flipHorizontal = flipHorizontal,
       _flipVertical = flipVertical,
       _verticalPosition = _clampPosition(verticalPosition),
       _scale = _clampScale(scale),
       _active = active;

  HudColor _color;
  HudLayout _layout;
  bool _flipHorizontal;
  bool _flipVertical;
  double _verticalPosition;
  double _scale;
  bool _active;
  bool _showAlignment = false;

  static double _clampPosition(double v) => v.clamp(-1.0, 1.0);
  static double _clampScale(double v) =>
      v.clamp(TapeHud.scaleMin, TapeHud.scaleMax);

  HudColor get color => _color;
  HudLayout get layout => _layout;

  /// Flip Horizontal is on by default (DESIGN.md 8): a windshield reflection is
  /// a mirror image.
  bool get flipHorizontal => _flipHorizontal;
  bool get flipVertical => _flipVertical;

  /// -1 to 1, up positive: how far the image sits above or below the middle.
  double get verticalPosition => _verticalPosition;

  double get scale => _scale;

  /// Whether the HUD is up (DESIGN.md 7.1's double-tap toggles it).
  bool get active => _active;

  /// Whether the alignment pattern replaces the HUD's layout (Garage → HUD,
  /// parked only: the caller of [showAlignmentPattern] holds that rule).
  bool get showAlignment => _showAlignment;

  set color(HudColor v) => _set(() => _color = v, _color != v);
  set layout(HudLayout v) => _set(() => _layout = v, _layout != v);
  set flipHorizontal(bool v) =>
      _set(() => _flipHorizontal = v, _flipHorizontal != v);
  set flipVertical(bool v) => _set(() => _flipVertical = v, _flipVertical != v);
  set verticalPosition(double v) {
    final c = _clampPosition(v);
    _set(() => _verticalPosition = c, _verticalPosition != c);
  }

  set scale(double v) {
    final c = _clampScale(v);
    _set(() => _scale = c, _scale != c);
  }

  set active(bool v) => _set(() {
    _active = v;
    if (!v) _showAlignment = false;
  }, _active != v);

  set showAlignment(bool v) => _set(() {
    _showAlignment = v;
    if (v) _active = true;
  }, _showAlignment != v);

  /// The double-tap and the dock button.
  void toggle() => active = !_active;

  void _set(VoidCallback apply, bool changed) {
    if (!changed) return;
    apply();
    notifyListeners();
  }
}
