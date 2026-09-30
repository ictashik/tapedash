// The connect path (DESIGN.md 7.11): adapter type, find and pair, the car, the
// price, the layout. The radios are fakes: the Bluetooth steps are unverified on
// hardware until the handoff (CLAUDE.md 11).
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/app/app_services.dart';
import 'package:tapedash/fuel/fuel_constants.dart';
import 'package:tapedash/obd/adapter_checker.dart';
import 'package:tapedash/obd/adapter_config.dart';
import 'package:tapedash/obd/transport/native_link.dart';
import 'package:tapedash/obd/transport/wifi_transport.dart';
import 'package:tapedash/platform/adapter_radio.dart';
import 'package:tapedash/ui/design/components/controls/tape_numpad.dart';
import 'package:tapedash/ui/design/components/controls/tape_slider.dart';
import 'package:tapedash/ui/design/icons/icons.dart';
import 'package:tapedash/ui/design/motion/motion_clock.dart';
import 'package:tapedash/ui/design/render/render_kit.dart';
import 'package:tapedash/ui/onboarding/connect_flow.dart';

import '../design/support/harness.dart';

class FakeRadio implements AdapterRadio {
  FakeRadio(this.kind);

  @override
  final RadioKind kind;

  RadioStatus current = const RadioStatus(
    supported: true,
    enabled: true,
    permitted: true,
  );
  RadioStatus afterPermission = const RadioStatus(
    supported: true,
    enabled: true,
    permitted: true,
  );
  List<FoundAdapter> pairedList = const [];
  List<FoundAdapter> nearby = const [];
  Object? pairError;
  final List<String> paired_ = [];
  int scans = 0;
  int scanStops = 0;
  int permissionAsks = 0;

  @override
  Future<RadioStatus> status() async => current;

  @override
  Future<bool> requestPermission() async {
    permissionAsks++;
    current = afterPermission;
    return current.permitted;
  }

  @override
  Future<List<FoundAdapter>> paired() async => pairedList;

  @override
  Stream<FoundAdapter> scan() {
    scans++;
    // Closed when the search is cancelled: the flow cancels it.
    // ignore: close_sinks
    late StreamController<FoundAdapter> c;
    c = StreamController<FoundAdapter>(
      onListen: () {
        for (final a in nearby) {
          c.add(a);
        }
      },
      onCancel: () => scanStops++,
    );
    return c.stream;
  }

  @override
  Future<void> pair(String address) async {
    paired_.add(address);
    if (pairError != null) throw pairError!;
  }

  @override
  NativeLink link(String address) => throw UnimplementedError();
}

class FakeChecker implements AdapterChecker {
  bool reachableNow = true;
  final List<AdapterConfig> tried = [];

  @override
  bool allows(String host) => NetworkGuard.allows(host);

  @override
  Future<bool> reachable(AdapterConfig config) async {
    tried.add(config);
    return reachableNow;
  }
}

/// A digit or the point on the numpad (not the same character typed in a field).
Finder _key(String k) =>
    find.descendant(of: find.byType(TapeNumpad), matching: find.text(k));

/// The numpad's back key: the one key drawn as a glyph, not a digit.
final Finder _backspace = find.descendant(
  of: find.byType(TapeNumpad),
  matching: find.byType(TapeIconView),
);

FoundAdapter adapter(
  String name,
  String address, {
  bool paired = false,
  RadioKind kind = RadioKind.bluetoothClassic,
}) => FoundAdapter(name: name, address: address, kind: kind, paired: paired);

void main() {
  late TapeRenderKit kit;
  late ManualMotionClock motion;
  late AppServices app;
  late FakeChecker checker;
  late Map<RadioKind, FakeRadio> radios;
  var done = 0;
  var cancelled = 0;

  setUpAll(loadTapeFonts);

  setUp(() async {
    kit = TapeRenderKit();
    motion = ManualMotionClock();
    app = await AppServices.memory();
    checker = FakeChecker();
    radios = {for (final k in RadioKind.values) k: FakeRadio(k)};
    done = 0;
    cancelled = 0;
  });

  tearDown(() {
    kit.dispose();
    motion.dispose();
  });

  Future<void> show(
    WidgetTester tester, {
    Size size = const Size(720, 360),
  }) async {
    setWindow(tester, size);
    await tester.pumpWidget(
      tapeHarness(
        kit: kit,
        motion: motion,
        child: ConnectFlow(
          services: app,
          checker: checker,
          radios: (k) => radios[k]!,
          width: size.width,
          height: size.height,
          onDone: () => done++,
          onCancel: () => cancelled++,
        ),
      ),
    );
    await tester.pump();
  }

  ConnectFlowState flow(WidgetTester tester) =>
      tester.state<ConnectFlowState>(find.byType(ConnectFlow));

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  for (final size in const [Size(640, 360), Size(720, 360), Size(800, 360)]) {
    testWidgets('every step lays out at ${size.width.toInt()}x360', (
      tester,
    ) async {
      radios[RadioKind.bluetoothClassic]!
        ..pairedList = [adapter('OBDII', 'AA:01', paired: true)]
        ..nearby = [adapter('Speaker', 'AA:02')];
      await show(tester, size: size);
      expect(flow(tester).step, ConnectStep.type);
      await tester.tap(find.text('Bluetooth').first);
      await settle(tester);
      expect(flow(tester).step, ConnectStep.find);
      await tester.tap(find.text('OBDII'));
      await settle(tester);
      expect(flow(tester).step, ConnectStep.car);
      await tester.tap(find.text('NEXT'));
      await settle(tester);
      expect(flow(tester).step, ConnectStep.price);
      await tester.tap(find.text('SKIP'));
      await settle(tester);
      expect(flow(tester).step, ConnectStep.layout);
      expect(tester.takeException(), isNull);
    });
  }

  group('the first step', () {
    testWidgets('offers the three kinds, and Cancel leaves', (tester) async {
      await show(tester);
      expect(find.text('Bluetooth'), findsOneWidget);
      expect(find.text('Bluetooth LE'), findsOneWidget);
      expect(find.text('WiFi'), findsOneWidget);
      expect(find.text('STEP 1 OF 5'), findsOneWidget);
      await tester.tap(find.text('CANCEL'));
      expect(cancelled, 1);
    });
  });

  group('finding a Bluetooth adapter', () {
    testWidgets(
      'paired adapters are listed first, likely ones on top, and a scan runs',
      (tester) async {
        final radio = radios[RadioKind.bluetoothClassic]!
          ..pairedList = [
            adapter('Zed speaker', 'AA:03', paired: true),
            adapter('OBDII', 'AA:01', paired: true),
          ]
          ..nearby = [adapter('Vgate iCar Pro', 'AA:02')];
        await show(tester);
        await tester.tap(find.text('Bluetooth').first);
        await settle(tester);

        expect(radio.scans, 1);
        final order = [
          for (final e in find.byType(Text).evaluate()) (e.widget as Text).data,
        ];
        // Likely adapters first (OBDII, Vgate), then the rest.
        expect(
          order.indexOf('OBDII'),
          lessThan(order.indexOf('Vgate iCar Pro')),
          reason: 'paired ahead of unpaired among likely adapters',
        );
        expect(
          order.indexOf('Vgate iCar Pro'),
          lessThan(order.indexOf('Zed speaker')),
        );
        expect(find.text('Paired'), findsNWidgets(2));
      },
    );

    testWidgets('a paired adapter is chosen, and the scan stops', (
      tester,
    ) async {
      final radio = radios[RadioKind.bluetoothClassic]!
        ..pairedList = [adapter('OBDII', 'AA:01', paired: true)];
      await show(tester);
      await tester.tap(find.text('Bluetooth').first);
      await settle(tester);
      await tester.tap(find.text('OBDII'));
      await settle(tester);
      expect(flow(tester).step, ConnectStep.car);
      expect(radio.scanStops, 1);
      expect(radio.paired_, isEmpty, reason: 'already paired');
      expect(
        flow(tester).chosen,
        const AdapterConfig(
          kind: AdapterKind.bluetoothClassic,
          address: 'AA:01',
          name: 'OBDII',
        ),
      );
    });

    testWidgets(
      'an unpaired one is paired first, telling the user about the PIN',
      (tester) async {
        final radio = radios[RadioKind.bluetoothClassic]!
          ..nearby = [adapter('OBDII', 'AA:02')];
        await show(tester);
        await tester.tap(find.text('Bluetooth').first);
        await settle(tester);
        await tester.tap(find.text('OBDII'));
        await tester.pump();
        await settle(tester);
        expect(radio.paired_, ['AA:02']);
        expect(flow(tester).step, ConnectStep.car);
        expect(flow(tester).chosen!.address, 'AA:02');
      },
    );

    testWidgets('a pairing that fails says so, and the search goes on', (
      tester,
    ) async {
      final radio = radios[RadioKind.bluetoothClassic]!
        ..nearby = [adapter('OBDII', 'AA:02')]
        ..pairError = const NativeLinkException(
          NativeLinkProblem.connectFailed,
        );
      await show(tester);
      await tester.tap(find.text('Bluetooth').first);
      await settle(tester);
      await tester.tap(find.text('OBDII'));
      await settle(tester);
      expect(flow(tester).step, ConnectStep.find);
      expect(flow(tester).isPairing, isFalse);
      expect(find.textContaining('Could not pair'), findsOneWidget);
      expect(radio.scans, 2, reason: 'searching again');
    });

    testWidgets('BLE has no pairing: the adapter found is the adapter chosen', (
      tester,
    ) async {
      final radio = radios[RadioKind.ble]!
        ..nearby = [adapter('Veepeak BLE', 'AA:09', kind: RadioKind.ble)];
      await show(tester);
      await tester.tap(find.text('Bluetooth LE'));
      await settle(tester);
      await tester.tap(find.text('Veepeak BLE'));
      await settle(tester);
      expect(radio.paired_, isEmpty);
      expect(flow(tester).chosen!.kind, AdapterKind.ble);
      expect(flow(tester).step, ConnectStep.car);
    });

    testWidgets('permission is asked for, then the search starts', (
      tester,
    ) async {
      final radio = radios[RadioKind.bluetoothClassic]!
        ..current = const RadioStatus(
          supported: true,
          enabled: true,
          permitted: false,
        )
        ..nearby = [adapter('OBDII', 'AA:02')];
      await show(tester);
      await tester.tap(find.text('Bluetooth').first);
      await settle(tester);
      expect(find.textContaining('needs permission'), findsOneWidget);
      expect(radio.scans, 0);

      await tester.tap(find.text('ALLOW'));
      await settle(tester);
      expect(radio.permissionAsks, 1);
      expect(radio.scans, 1);
      expect(find.text('OBDII'), findsOneWidget);
    });

    testWidgets('Bluetooth off is said, and Try again looks again', (
      tester,
    ) async {
      final radio = radios[RadioKind.bluetoothClassic]!
        ..current = const RadioStatus(
          supported: true,
          enabled: false,
          permitted: true,
        );
      await show(tester);
      await tester.tap(find.text('Bluetooth').first);
      await settle(tester);
      expect(find.textContaining('Bluetooth is off'), findsOneWidget);

      radio
        ..current = const RadioStatus(
          supported: true,
          enabled: true,
          permitted: true,
        )
        ..nearby = [adapter('OBDII', 'AA:02')];
      await tester.tap(find.text('TRY AGAIN'));
      await settle(tester);
      expect(find.text('OBDII'), findsOneWidget);
    });

    testWidgets('a phone with no such radio says so and points at WiFi', (
      tester,
    ) async {
      radios[RadioKind.ble]!.current = const RadioStatus(
        supported: false,
        enabled: false,
        permitted: false,
      );
      await show(tester);
      await tester.tap(find.text('Bluetooth LE'));
      await settle(tester);
      expect(find.textContaining('no Bluetooth LE'), findsOneWidget);
      expect(find.textContaining('WiFi adapter would work'), findsOneWidget);
    });

    testWidgets('Back leaves the search and returns to the kinds', (
      tester,
    ) async {
      final radio = radios[RadioKind.bluetoothClassic]!;
      await show(tester);
      await tester.tap(find.text('Bluetooth').first);
      await settle(tester);
      await tester.tap(find.text('BACK'));
      await settle(tester);
      expect(flow(tester).step, ConnectStep.type);
      expect(radio.scanStops, 1);
    });
  });

  group('a WiFi adapter', () {
    Future<void> toWifi(WidgetTester tester) async {
      await show(tester);
      await tester.tap(find.text('WiFi'));
      await settle(tester);
    }

    testWidgets('starts at the usual address and port, and goes on', (
      tester,
    ) async {
      await toWifi(tester);
      expect(find.text('192.168.0.10'), findsOneWidget);
      expect(find.text('35000'), findsOneWidget);
      await tester.tap(find.text('NEXT'));
      await settle(tester);
      expect(flow(tester).step, ConnectStep.car);
      expect(
        flow(tester).chosen,
        const AdapterConfig(
          kind: AdapterKind.wifi,
          address: '192.168.0.10',
          port: 35000,
          name: 'WiFi adapter',
        ),
      );
    });

    testWidgets('Test tries the adapter, and says what happened', (
      tester,
    ) async {
      await toWifi(tester);
      await tester.tap(find.text('TEST'));
      await settle(tester);
      expect(find.text('The adapter answered.'), findsOneWidget);
      expect(checker.tried.single.address, '192.168.0.10');

      checker.reachableNow = false;
      await tester.tap(find.text('TEST'));
      await settle(tester);
      expect(find.textContaining('Nothing answered'), findsOneWidget);
    });

    testWidgets('an address outside the private ranges is refused, not tried', (
      tester,
    ) async {
      await toWifi(tester);
      // Clear the address and type 8.8.8.8.
      for (var i = 0; i < 14; i++) {
        await tester.tap(_backspace);
        await tester.pump();
      }
      for (final k in '8 . 8 . 8 . 8'.split(' ')) {
        await tester.tap(_key(k));
        await tester.pump();
      }
      expect(find.text('8.8.8.8'), findsOneWidget);
      await tester.tap(find.text('TEST'));
      await settle(tester);
      expect(
        find.textContaining('only talks to adapters on your own network'),
        findsOneWidget,
      );
      expect(checker.tried, isEmpty);

      await tester.tap(find.text('NEXT'));
      await settle(tester);
      expect(flow(tester).step, ConnectStep.find);
    });

    testWidgets('Next waits for a whole address', (tester) async {
      await toWifi(tester);
      for (var i = 0; i < 3; i++) {
        await tester.tap(_backspace);
        await tester.pump();
      }
      await tester.tap(find.text('NEXT'), warnIfMissed: false);
      await settle(tester);
      expect(
        flow(tester).step,
        ConnectStep.find,
        reason: '192.168.0. is not one',
      );
    });
  });

  group('the car, the price and the layout', () {
    Future<void> toCar(WidgetTester tester) async {
      radios[RadioKind.bluetoothClassic]!.pairedList = [
        adapter('OBDII', 'AA:01', paired: true),
      ];
      await show(tester);
      await tester.tap(find.text('Bluetooth').first);
      await settle(tester);
      await tester.tap(find.text('OBDII'));
      await settle(tester);
    }

    testWidgets('the car is set, and kept as it is entered', (tester) async {
      await toCar(tester);
      await tester.tap(find.text('DIESEL'));
      await tester.pump();
      final engine = find.widgetWithText(TapeSlider, 'ENGINE SIZE');
      await tester.tapAt(tester.getTopRight(engine) + const Offset(-2, 34));
      await tester.pump();
      await tester.tap(find.text('NEXT'));
      await settle(tester);
      expect(app.setup.value.fuelType, FuelType.diesel);
      expect(app.setup.value.displacementLitres, closeTo(6.0, 0.1));
      expect(flow(tester).step, ConnectStep.price);

      // Going back does not lose it.
      await tester.tap(find.text('BACK'));
      await settle(tester);
      expect(find.text('6.0 L'), findsOneWidget);
    });

    testWidgets('the price is typed on the numpad and kept', (tester) async {
      await toCar(tester);
      await tester.tap(find.text('NEXT'));
      await settle(tester);
      expect(find.text('NEXT'), findsOneWidget);
      for (final k in '1 0 8 . 5'.split(' ')) {
        await tester.tap(_key(k));
        await tester.pump();
      }
      expect(find.text('108.5'), findsOneWidget);
      await tester.tap(find.text('NEXT'));
      await settle(tester);
      expect(app.money.price.value, closeTo(108.5, 1e-9));
      expect(flow(tester).step, ConnectStep.layout);
    });

    testWidgets('the price can be skipped, and is then left unset', (
      tester,
    ) async {
      await toCar(tester);
      await tester.tap(find.text('NEXT'));
      await settle(tester);
      await tester.tap(find.text('SKIP'));
      await settle(tester);
      expect(app.money.price.value, isNull);
      expect(flow(tester).step, ConnectStep.layout);
    });

    testWidgets(
      'a price that no fuel costs is called wrong and cannot be saved',
      (tester) async {
        await toCar(tester);
        await tester.tap(find.text('NEXT'));
        await settle(tester);
        for (final k in '9 9 9 9'.split(' ')) {
          await tester.tap(_key(k));
          await tester.pump();
        }
        expect(find.text('That price looks wrong.'), findsOneWidget);
        await tester.tap(find.text('NEXT'), warnIfMissed: false);
        await settle(tester);
        expect(flow(tester).step, ConnectStep.price);
      },
    );

    testWidgets('the layout is picked, and Start driving saves everything', (
      tester,
    ) async {
      await toCar(tester);
      await tester.tap(find.text('NEXT'));
      await settle(tester);
      await tester.tap(find.text('SKIP'));
      await settle(tester);
      await tester.ensureVisible(find.text('Road'));
      await tester.pump();
      await tester.tap(find.text('Road'));
      await tester.pump();
      expect(done, 0);
      await tester.tap(find.text('START DRIVING'));
      await settle(tester);

      expect(done, 1);
      expect(app.settings.cluster.value, 4);
      expect(app.settings.onboarded.value, isTrue);
      expect(app.adapters.useAdapter.value, isTrue);
      expect(app.adapters.adapter.value!.address, 'AA:01');
    });

    testWidgets('nothing is saved as the adapter until the end', (
      tester,
    ) async {
      await toCar(tester);
      await tester.tap(find.text('NEXT'));
      await settle(tester);
      expect(app.adapters.adapter.value, isNull);
      expect(app.settings.onboarded.value, isFalse);
    });
  });
}
