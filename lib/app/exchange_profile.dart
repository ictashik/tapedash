import '../core/currency.dart';
import '../core/fuel_blend.dart';
import '../exchange/exchange_service.dart';
import '../fuel/fuel_constants.dart';
import '../obd/adapter_config.dart';
import '../ui/design/fidelity/fidelity_tier.dart';
import '../ui/design/motion/ignition_sequence.dart';
import '../ui/design/theme/mode_controller.dart' show ModeSetting;
import '../ui/design/theme/palette.dart' show DriverSide;
import '../ui/design/tokens/colors.dart' show HudColor;
import '../ui/design/tokens/livery.dart';
import '../ui/hud/hud_settings.dart';
import 'app_services.dart';
import 'app_settings.dart';

/// The app's setup as the exchange file sees it (docs/EXCHANGE.md 1): read from the
/// settings, the car's setup, the price and the adapter into plain maps, and applied
/// back from maps that `TdxProfile` has already checked.
///
/// Only what a map holds is touched: a part that is missing is left as it is.
class ExchangeProfile implements ProfileAccess {
  ExchangeProfile(this.app);

  final AppServices app;

  T _byName<T extends Enum>(List<T> values, String name, T fallback) =>
      values.firstWhere((v) => v.name == name, orElse: () => fallback);

  @override
  Future<Map<String, Object?>> readProfile() async {
    final s = app.settings;
    final setup = app.setup.value;
    final adapter = app.adapters.adapter.value;
    final price = app.money.price.value;
    return {
      'vehicle': {
        'fuelType': setup.fuelType.name,
        'displacementL': setup.displacementLitres,
        'tankL': setup.tankLitres,
        'blend': setup.blend.name,
      },
      'money': {
        'pricePerLitre': ?price,
        'currency': app.money.currency.value.code,
      },
      if (adapter != null) 'adapter': adapter.toJson(),
      if (app.adapters.source.value != null)
        'source': app.adapters.source.value!.name,
      'coach': {
        'preset': s.coachPreset.value.name,
        'speedLimitKmh': s.speedLimitKmh.value,
      },
      'look': {
        'livery': s.livery.value.name,
        'driverSide': s.driverSide.value.name,
        'cluster': s.cluster.value,
        'ignition': s.ignition.value.name,
        'reduceMotion': s.reduceMotion.value,
      },
    };
  }

  @override
  Future<Map<String, Object?>> readDevice() async {
    final s = app.settings;
    final hud = s.hud;
    return {
      'hud': {
        'color': hud.color.name,
        'layout': hud.layout.name,
        'flipH': hud.flipHorizontal,
        'flipV': hud.flipVertical,
        'position': hud.verticalPosition,
        'scale': hud.scale,
      },
      if (s.tierPin.value != null) 'tier': s.tierPin.value!.name,
      'mode': s.modeSetting.value.name,
      'sound': {
        'enabled': s.soundEnabled.value,
        'profile': s.soundProfile.value,
        'volume': s.soundVolume.value,
        'speaker': s.soundOnSpeaker.value,
      },
      'compatibility': app.adapters.compatibilityMode.value,
      'recordSessions': app.adapters.recordSessions.value,
    };
  }

  @override
  Future<List<String>> describeProfile(Map<String, Object?> clean) async {
    final lines = <String>[];
    final vehicle = clean['vehicle'];
    if (vehicle is Map) {
      final now = app.setup.value;
      final fuel = vehicle['fuelType'] ?? now.fuelType.name;
      final cc = vehicle['displacementL'] ?? now.displacementLitres;
      final tank = vehicle['tankL'] ?? now.tankLitres;
      lines.add('Car: $fuel, $cc L, $tank L tank');
    }
    final money = clean['money'];
    if (money is Map && money['pricePerLitre'] != null) {
      final p = (money['pricePerLitre']! as num).toStringAsFixed(1);
      lines.add('Price: $p a litre');
    }
    final adapter = clean['adapter'];
    if (adapter is Map) {
      final name = (adapter['name'] as String?)?.isNotEmpty == true
          ? adapter['name']
          : adapter['address'];
      lines.add('Adapter: $name');
    }
    if (clean['source'] != null) {
      lines.add(
        'Speed from: ${clean['source'] == 'gps' ? 'GPS only' : 'adapter'}',
      );
    }
    final coach = clean['coach'];
    if (coach is Map) {
      final preset = coach['preset'] ?? app.settings.coachPreset.value.name;
      lines.add('Coach: $preset');
    }
    final look = clean['look'];
    if (look is Map && look['livery'] != null) {
      lines.add('Look: ${(look['livery']! as String).toUpperCase()}');
    }
    return lines;
  }

  @override
  Future<void> applyProfile(Map<String, Object?> clean) async {
    final s = app.settings;
    final vehicle = clean['vehicle'];
    if (vehicle is Map) {
      final now = app.setup.value;
      await app.setVehicleSetup(
        VehicleSetup(
          fuelType: vehicle['fuelType'] == null
              ? now.fuelType
              : _byName(
                  FuelType.values,
                  vehicle['fuelType']! as String,
                  now.fuelType,
                ),
          displacementLitres:
              (vehicle['displacementL'] as num?)?.toDouble() ??
              now.displacementLitres,
          tankLitres: (vehicle['tankL'] as num?)?.toDouble() ?? now.tankLitres,
          blend: vehicle['blend'] == null
              ? now.blend
              : _byName(
                  PetrolBlend.values,
                  vehicle['blend']! as String,
                  now.blend,
                ),
        ),
      );
    }
    final money = clean['money'];
    if (money is Map) {
      if (money['pricePerLitre'] != null) {
        await app.money.setPrice((money['pricePerLitre']! as num).toDouble());
      }
      if (money['currency'] != null) {
        await app.money.setCurrency(switch (money['currency']) {
          'USD' => Currency.usd,
          'GBP' => Currency.gbp,
          _ => Currency.inr,
        });
      }
    }
    final adapter = clean['adapter'];
    if (adapter is Map) {
      final config = AdapterConfig.fromJson(adapter);
      if (config != null) await app.adapters.choose(config);
    }
    // The source after the adapter: choosing an adapter makes it the source.
    final source = clean['source'];
    if (source is String) {
      await app.adapters.setSource(
        _byName(DriveSource.values, source, DriveSource.obd),
      );
    }
    final coach = clean['coach'];
    if (coach is Map) {
      if (coach['preset'] != null) {
        s.coachPreset.value = _byName(
          CoachPreset.values,
          coach['preset']! as String,
          s.coachPreset.value,
        );
      }
      if (coach['speedLimitKmh'] != null) {
        s.speedLimitKmh.value = (coach['speedLimitKmh']! as num).toDouble();
      }
    }
    final look = clean['look'];
    if (look is Map) {
      if (look['livery'] != null) {
        s.livery.value = _byName(
          Liveries.all.map((l) => l.id).toList(),
          look['livery']! as String,
          s.livery.value,
        );
      }
      if (look['driverSide'] != null) {
        s.driverSide.value = _byName(
          DriverSide.values,
          look['driverSide']! as String,
          s.driverSide.value,
        );
      }
      if (look['cluster'] != null) s.cluster.value = look['cluster']! as int;
      if (look['ignition'] != null) {
        s.ignition.value = _byName(
          IgnitionMode.values,
          look['ignition']! as String,
          s.ignition.value,
        );
      }
      if (look['reduceMotion'] != null) {
        s.reduceMotion.value = look['reduceMotion']! as bool;
      }
    }
  }

  @override
  Future<void> applyDevice(Map<String, Object?> clean) async {
    final s = app.settings;
    final hud = clean['hud'];
    if (hud is Map) {
      final h = s.hud;
      if (hud['color'] != null) {
        h.color = _byName(HudColor.values, hud['color']! as String, h.color);
      }
      if (hud['layout'] != null) {
        h.layout = _byName(
          HudLayout.values,
          hud['layout']! as String,
          h.layout,
        );
      }
      if (hud['flipH'] != null) h.flipHorizontal = hud['flipH']! as bool;
      if (hud['flipV'] != null) h.flipVertical = hud['flipV']! as bool;
      if (hud['position'] != null) {
        h.verticalPosition = (hud['position']! as num).toDouble();
      }
      if (hud['scale'] != null) h.scale = (hud['scale']! as num).toDouble();
    }
    if (clean['tier'] != null) {
      s.tierPin.value = _byName(
        FidelityTier.values,
        clean['tier']! as String,
        FidelityTier.balanced,
      );
    }
    if (clean['mode'] != null) {
      s.modeSetting.value = _byName(
        ModeSetting.values,
        clean['mode']! as String,
        s.modeSetting.value,
      );
    }
    final sound = clean['sound'];
    if (sound is Map) {
      if (sound['enabled'] != null) {
        s.soundEnabled.value = sound['enabled']! as bool;
      }
      if (sound['profile'] != null) {
        s.soundProfile.value = sound['profile']! as String;
      }
      if (sound['volume'] != null) {
        s.soundVolume.value = (sound['volume']! as num).toDouble();
      }
      if (sound['speaker'] != null) {
        s.soundOnSpeaker.value = sound['speaker']! as bool;
      }
    }
    if (clean['compatibility'] != null) {
      await app.adapters.setCompatibilityMode(clean['compatibility']! as bool);
    }
    if (clean['recordSessions'] != null) {
      await app.adapters.setRecordSessions(clean['recordSessions']! as bool);
    }
  }
}
