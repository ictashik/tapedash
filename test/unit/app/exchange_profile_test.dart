// The app's setup as an exchange file sees it (docs/EXCHANGE.md 1): what is read, what
// is applied and what is left alone, that a setup survives a round trip through the
// file's own checks, and that the names the pure checker allows are the enums'.
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/app/app_services.dart';
import 'package:tapedash/app/app_settings.dart';
import 'package:tapedash/app/exchange_profile.dart';
import 'package:tapedash/core/currency.dart';
import 'package:tapedash/core/fuel_blend.dart';
import 'package:tapedash/exchange/tdx_profile.dart';
import 'package:tapedash/fuel/fuel_constants.dart';
import 'package:tapedash/obd/adapter_config.dart';
import 'package:tapedash/ui/design/fidelity/fidelity_tier.dart';
import 'package:tapedash/ui/design/motion/ignition_sequence.dart';
import 'package:tapedash/ui/design/theme/mode_controller.dart';
import 'package:tapedash/ui/design/theme/palette.dart';
import 'package:tapedash/ui/design/tokens/colors.dart';
import 'package:tapedash/ui/design/tokens/hud.dart';
import 'package:tapedash/ui/design/tokens/livery.dart';
import 'package:tapedash/ui/hud/hud_settings.dart';

List<String> names(Iterable<Enum> values) => [for (final v in values) v.name];

void main() {
  test('the names the pure checker allows are the enums\' own', () {
    expect(TdxProfile.fuelTypes, names(FuelType.values));
    expect(TdxProfile.blends, names(PetrolBlend.values));
    expect(TdxProfile.adapterKinds, names(AdapterKind.values));
    expect(TdxProfile.sources, names(DriveSource.values));
    expect(TdxProfile.presets, names(CoachPreset.values));
    expect(TdxProfile.liveries, [for (final l in Liveries.all) l.id.name]);
    expect(TdxProfile.driverSides, names(DriverSide.values));
    expect(TdxProfile.ignitions, names(IgnitionMode.values));
    expect(TdxProfile.hudColors, names(HudColor.values));
    expect(TdxProfile.hudLayouts, names(HudLayout.values));
    expect(TdxProfile.hudScaleMin, TapeHud.scaleMin);
    expect(TdxProfile.hudScaleMax, TapeHud.scaleMax);
    expect(TdxProfile.tiers, names(FidelityTier.values));
    expect(TdxProfile.modes, names(ModeSetting.values));
    expect(TdxProfile.currencies, [
      Currency.inr.code,
      Currency.usd.code,
      Currency.gbp.code,
    ]);
  });

  late AppServices app;
  late ExchangeProfile profile;

  setUp(() async {
    app = await AppServices.memory();
    profile = ExchangeProfile(app);
  });

  test(
    'reads the car, the price, the adapter, the coach and the look',
    () async {
      await app.setVehicleSetup(
        const VehicleSetup(
          fuelType: FuelType.diesel,
          displacementLitres: 2.2,
          tankLitres: 55,
          blend: PetrolBlend.e10,
        ),
      );
      await app.money.setPrice(98.4);
      await app.adapters.choose(
        const AdapterConfig(
          kind: AdapterKind.ble,
          address: '66:1E:32:00:11:22',
          name: 'OBDBLE',
        ),
      );
      app.settings.coachPreset.value = CoachPreset.sporty;
      app.settings.speedLimitKmh.value = 110;
      app.settings.livery.value = LiveryId.ember;
      app.settings.driverSide.value = DriverSide.left;
      app.settings.cluster.value = 2;

      final p = await profile.readProfile();
      expect(p['vehicle'], {
        'fuelType': 'diesel',
        'displacementL': 2.2,
        'tankL': 55.0,
        'blend': 'e10',
      });
      expect(p['money'], {'pricePerLitre': 98.4, 'currency': 'INR'});
      expect(p['adapter'], {
        'kind': 'ble',
        'address': '66:1E:32:00:11:22',
        'name': 'OBDBLE',
      });
      expect(p['source'], 'obd');
      expect(p['coach'], {'preset': 'sporty', 'speedLimitKmh': 110.0});
      expect((p['look']! as Map)['livery'], 'ember');
      expect((p['look']! as Map)['driverSide'], 'left');
      expect((p['look']! as Map)['cluster'], 2);
    },
  );

  test('a price that is not set is not in the file', () async {
    final p = await profile.readProfile();
    expect((p['money']! as Map).containsKey('pricePerLitre'), isFalse);
    expect(p.containsKey('adapter'), isFalse);
    expect(p.containsKey('source'), isFalse);
  });

  test('what it reads, the file\'s own checks accept whole', () async {
    await app.money.setPrice(101.5);
    await app.adapters.choose(
      const AdapterConfig(
        kind: AdapterKind.wifi,
        address: '192.168.0.10',
        port: 35000,
      ),
    );
    final read = await profile.readProfile();
    final clean = TdxProfile.cleanProfile(read);
    expect(clean.problems, isEmpty);
    expect(clean.values, read);
    final device = TdxProfile.cleanDevice(await profile.readDevice());
    expect(device.problems, isEmpty);
  });

  test('applies a setup to another device, a part at a time', () async {
    final other = await AppServices.memory();
    other.settings.livery.value = LiveryId.vfd;
    await ExchangeProfile(other).applyProfile({
      'vehicle': {'fuelType': 'diesel', 'tankL': 60.0},
      'money': {'pricePerLitre': 105.25, 'currency': 'GBP'},
      'adapter': {
        'kind': 'wifi',
        'address': '192.168.0.10',
        'port': 35000,
        'name': 'WiFi',
      },
      'source': 'gps',
      'coach': {'preset': 'gentle'},
      'look': {'livery': 'mono', 'cluster': 3, 'reduceMotion': true},
    });
    final setup = other.setup.value;
    expect(setup.fuelType, FuelType.diesel);
    expect(setup.tankLitres, 60);
    expect(setup.displacementLitres, 1.5, reason: 'not in the file: left');
    expect(other.money.price.value, 105.25);
    expect(other.money.currency.value.code, 'GBP');
    expect(other.adapters.adapter.value!.address, '192.168.0.10');
    expect(
      other.adapters.source.value,
      DriveSource.gps,
      reason: 'the source is applied after the adapter',
    );
    expect(other.settings.coachPreset.value, CoachPreset.gentle);
    expect(other.settings.speedLimitKmh.value, 100, reason: 'left');
    expect(other.settings.livery.value, LiveryId.mono);
    expect(other.settings.cluster.value, 3);
    expect(other.settings.reduceMotion.value, isTrue);
    expect(other.settings.driverSide.value, DriverSide.right, reason: 'left');
  });

  test('settings of one screen are applied by themselves', () async {
    await profile.applyDevice({
      'hud': {'color': 'amber', 'flipH': false, 'flipV': true, 'scale': 1.3},
      'tier': 'lite',
      'mode': 'night',
      'sound': {'enabled': true, 'profile': 'v8', 'volume': 0.4},
      'compatibility': true,
      'recordSessions': true,
    });
    final s = app.settings;
    expect(s.hud.color, HudColor.amber);
    expect(s.hud.flipHorizontal, isFalse);
    expect(s.hud.flipVertical, isTrue);
    expect(s.hud.scale, 1.3);
    expect(s.hud.layout, HudLayout.drive, reason: 'left');
    expect(s.tierPin.value, FidelityTier.lite);
    expect(s.modeSetting.value, ModeSetting.night);
    expect(s.soundEnabled.value, isTrue);
    expect(s.soundProfile.value, 'v8');
    expect(s.soundVolume.value, 0.4);
    expect(app.adapters.compatibilityMode.value, isTrue);
    expect(app.adapters.recordSessions.value, isTrue);
  });

  test('says in lines what a setup would change', () async {
    final lines = await profile.describeProfile({
      'vehicle': {'fuelType': 'petrol', 'displacementL': 1.2},
      'money': {'pricePerLitre': 115.0},
      'adapter': {'kind': 'ble', 'address': 'AA:BB', 'name': 'OBDBLE'},
      'source': 'gps',
      'coach': {'preset': 'normal'},
      'look': {'livery': 'ion'},
    });
    expect(lines, [
      'Car: petrol, 1.2 L, 40.0 L tank',
      'Price: 115.0 a litre',
      'Adapter: OBDBLE',
      'Speed from: GPS only',
      'Coach: normal',
      'Look: ION',
    ]);
  });

  test('the install id is made once and kept', () async {
    final a = await AppServices.memory();
    expect(a.installId, matches(RegExp(r'^[0-9a-f]{8}$')));
    await a.load();
    final again = a.installId;
    await a.load();
    expect(a.installId, again);
  });
}
