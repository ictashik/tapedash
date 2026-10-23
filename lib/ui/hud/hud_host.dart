import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../design/components/alerts.dart';
import '../design/motion/numeral_source.dart';
import '../pages/drive/drive_signals.dart';
import '../pages/money/money_signals.dart';
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
    this.money,
    this.tripCost,
    this.costPerKm,
    this.alert,
    this.layout,
    this.showRpm = true,
  });

  /// The layout to show in place of the one chosen in Garage (see
  /// `HudView.layout`).
  final HudLayout? layout;

  /// Whether the Drive layout has its RPM bar.
  final bool showRpm;

  final HudSettings settings;
  final DriveSignals signals;
  final double width;
  final double height;
  final Widget child;

  /// The trip computer's signals: the HUD's money layouts read ₹ this trip and ₹/km
  /// from them while there is a price, and say money is unavailable otherwise.
  final MoneySignals? money;

  /// Explicit sources, for a test (overriding [money]).
  final NumeralSource? tripCost;
  final NumeralSource? costPerKm;
  final ValueListenable<AlertLevel>? alert;

  Widget _hud(NumeralSource? cost, NumeralSource? perKm, {String? note}) =>
      HudView(
        signals: signals,
        settings: settings,
        width: width,
        height: height,
        tripCost: cost,
        costPerKm: perKm,
        alert: alert,
        layout: layout,
        showRpm: showRpm,
        moneyNote: note ?? 'MONEY UNAVAILABLE',
      );

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
                child: money == null
                    ? _hud(tripCost, costPerKm)
                    : ValueListenableBuilder<MoneyView>(
                        valueListenable: money!.view,
                        builder: (context, view, _) => view == MoneyView.rupees
                            ? _hud(money!.cost, money!.costPerKm)
                            : _hud(
                                null,
                                null,
                                note: view == MoneyView.litres
                                    ? 'SET A FUEL PRICE'
                                    : null,
                              ),
                      ),
              ),
            ),
        ],
      ),
    );
  }
}
