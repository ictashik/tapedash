import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../design/components/alerts.dart';
import '../design/motion/numeral_source.dart';
import '../pages/drive/drive_signals.dart';
import 'hud_settings.dart';
import 'hud_view.dart';

/// Lays the HUD over the app's strip while [settings] says it is up (DESIGN.md
/// 7.1 and 8): a double-tap on the HUD puts it down again, as a double-tap on
/// Drive or Money puts it up. The strip underneath stays mounted, so nothing
/// it was doing is lost, and its own gestures are covered by the HUD's opaque
/// layer while the HUD is up.
///
/// It rebuilds for the toggle only; the HUD inside repaints for its data.
class HudHost extends StatelessWidget {
  const HudHost({
    super.key,
    required this.settings,
    required this.signals,
    required this.width,
    required this.height,
    required this.child,
    this.tripCost,
    this.costPerKm,
    this.alert,
  });

  final HudSettings settings;
  final DriveSignals signals;
  final double width;
  final double height;
  final Widget child;
  final NumeralSource? tripCost;
  final NumeralSource? costPerKm;
  final ValueListenable<AlertLevel>? alert;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => Stack(
        children: [
          Positioned.fill(child: child),
          if (settings.active)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onDoubleTap: settings.toggle,
                child: HudView(
                  signals: signals,
                  settings: settings,
                  width: width,
                  height: height,
                  tripCost: tripCost,
                  costPerKm: costPerKm,
                  alert: alert,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
