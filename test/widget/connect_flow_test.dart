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
  Object? unpairError;
  final List<String> paired_ = [];
  final List<String> unpaired = [];
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
  Future<void> unpair(String address) async {
    unpaired.add(address);
    if (unpairError != null) throw unpairError!;
  }

  @override
  NativeLink link(String address) => throw UnimplementedError();
}

class FakeChecker implements AdapterChecker {
  bool reachableNow = true;

  /// Overrides [reachableNow] with an answer for each adapter.
  bool Function(AdapterConfig config)? reachableFor;
  void Function()? onTry;
  final List<AdapterConfig> tried = [];

  @override
  bool allows(String host) => NetworkGuard.allows(host);

  @override
  Future<bool> reachable(AdapterConfig config) async {
    tried.add(config);
    onTry?.call();
    return reachableFor?.call(config) ?? reachableNow;
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
    testWidgets('offers Bluetooth (both radios) and WiFi, and Cancel leaves', (
      tester,
    ) async {
      await show(tester);
      expect(find.text('Bluetooth'), findsOneWidget);
      expect(
        find.text('Bluetooth LE'),
        findsNothing,
        reason: 'one Bluetooth choice finds both kinds',
      );
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
        expect(find.textContaining('Paired'), findsNWidgets(2));
        expect(find.textContaining('Classic'), findsNWidgets(3));
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

    testWidgets('a paired adapter is tried before it is taken', (tester) async {
      radios[RadioKind.bluetoothClassic]!.pairedList = [
        adapter('OBDII', 'AA:01', paired: true),
      ];
      await show(tester);
      await tester.tap(find.text('Bluetooth').first);
      await settle(tester);
      await tester.tap(find.text('OBDII'));
      await settle(tester);
      expect(checker.tried.single.address, 'AA:01');
      expect(flow(tester).step, ConnectStep.car);
    });

    testWidgets(
      'one that will not connect offers to forget the pairing and pair again',
      (tester) async {
        final radio = radios[RadioKind.bluetoothClassic]!
          ..pairedList = [adapter('OBDII', 'AA:01', paired: true)];
        checker.reachableNow = false;
        await show(tester);
        await tester.tap(find.text('Bluetooth').first);
        await settle(tester);
        await tester.tap(find.text('OBDII'));
        await settle(tester);
        expect(flow(tester).step, ConnectStep.find);
        expect(flow(tester).failed?.address, 'AA:01');
        expect(find.textContaining('Could not connect'), findsOneWidget);
        expect(radio.scans, 2, reason: 'searching again');

        // The pairing is dropped and made again, and now the adapter answers.
        checker.reachableNow = true;
        await tester.tap(find.text('FORGET AND PAIR AGAIN'));
        await settle(tester);
        expect(radio.unpaired, ['AA:01']);
        expect(radio.paired_, ['AA:01']);
        expect(checker.tried, hasLength(2));
        expect(flow(tester).step, ConnectStep.car);
        expect(flow(tester).chosen!.address, 'AA:01');
      },
    );

    testWidgets('Use anyway takes the adapter that would not connect', (
      tester,
    ) async {
      radios[RadioKind.bluetoothClassic]!.pairedList = [
        adapter('OBDII', 'AA:01', paired: true),
      ];
      checker.reachableNow = false;
      await show(tester);
      await tester.tap(find.text('Bluetooth').first);
      await settle(tester);
      await tester.tap(find.text('OBDII'));
      await settle(tester);
      await tester.tap(find.text('USE ANYWAY'));
      await settle(tester);
      expect(flow(tester).step, ConnectStep.car);
      expect(flow(tester).chosen!.address, 'AA:01');
    });

    testWidgets('a pairing that cannot be forgotten says how to do it', (
      tester,
    ) async {
      final radio = radios[RadioKind.bluetoothClassic]!
        ..pairedList = [adapter('OBDII', 'AA:01', paired: true)]
        ..unpairError = const NativeLinkException(
          NativeLinkProblem.connectFailed,
        );
      checker.reachableNow = false;
      await show(tester);
      await tester.tap(find.text('Bluetooth').first);
      await settle(tester);
      await tester.tap(find.text('OBDII'));
      await settle(tester);
      await tester.tap(find.text('FORGET AND PAIR AGAIN'));
      await settle(tester);
      expect(radio.paired_, isEmpty);
      expect(find.textContaining('Bluetooth settings'), findsOneWidget);
      expect(flow(tester).step, ConnectStep.find);
    });

    testWidgets('BLE has no pairing: the adapter found is the adapter chosen', (
      tester,
    ) async {
      final radio = radios[RadioKind.ble]!
        ..nearby = [adapter('Veepeak BLE', 'AA:09', kind: RadioKind.ble)];
      await show(tester);
      await tester.tap(find.text('Bluetooth').first);
      await settle(tester);
      expect(find.textContaining('Low Energy'), findsOneWidget);
      await tester.tap(find.text('Veepeak BLE'));
      await settle(tester);
      expect(radio.paired_, isEmpty);
      expect(
        checker.tried.single.kind,
        AdapterKind.ble,
        reason: 'a Low Energy adapter is tried too, before it is taken',
      );
      expect(flow(tester).chosen!.kind, AdapterKind.ble);
      expect(flow(tester).step, ConnectStep.car);
    });

    testWidgets('both radios are searched at once, and each adapter is its '
        'radio\'s', (tester) async {
      final classic = radios[RadioKind.bluetoothClassic]!
        ..nearby = [adapter('OBDII', 'AA:01')];
      final ble = radios[RadioKind.ble]!
        ..nearby = [adapter('OBDBLE', 'AA:02', kind: RadioKind.ble)];
      await show(tester);
      await tester.tap(find.text('Bluetooth').first);
      await settle(tester);
      expect(classic.scans, 1);
      expect(ble.scans, 1);
      expect(find.text('OBDII'), findsOneWidget);
      expect(find.text('OBDBLE'), findsOneWidget);
      expect(find.textContaining('Classic'), findsOneWidget);
      expect(find.textContaining('Low Energy'), findsOneWidget);

      await tester.tap(find.text('OBDBLE'));
      await settle(tester);
      expect(classic.scanStops, 1, reason: 'both searches stop on a pick');
      expect(ble.scanStops, 1);
      expect(flow(tester).chosen!.kind, AdapterKind.ble);
      expect(flow(tester).chosen!.address, 'AA:02');
    });

    testWidgets('a phone with only one of the radios searches that one', (
      tester,
    ) async {
      radios[RadioKind.ble]!.current = const RadioStatus(
        supported: false,
        enabled: false,
        permitted: false,
      );
      final classic = radios[RadioKind.bluetoothClassic]!
        ..nearby = [adapter('OBDII', 'AA:01')];
      await show(tester);
      await tester.tap(find.text('Bluetooth').first);
      await settle(tester);
      expect(classic.scans, 1);
      expect(radios[RadioKind.ble]!.scans, 0);
      expect(find.text('OBDII'), findsOneWidget);
    });

    testWidgets('the nearer of two is listed first, and says it is close', (
      tester,
    ) async {
      radios[RadioKind.bluetoothClassic]!.nearby = [
        FoundAdapter(
          name: 'OBDII',
          address: 'AA:01',
          kind: RadioKind.bluetoothClassic,
          rssi: -85,
        ),
        FoundAdapter(
          name: 'OBDII',
          address: 'AA:02',
          kind: RadioKind.bluetoothClassic,
          rssi: -50,
        ),
      ];
      await show(tester);
      await tester.tap(find.text('Bluetooth').first);
      await settle(tester);
      final rows = [
        for (final e in find.byType(Text).evaluate())
          if ((e.widget as Text).data?.contains('AA:0') ?? false)
            (e.widget as Text).data!,
      ];
      expect(rows.first, contains('AA:02'));
      expect(rows.first, contains('Close'));
      expect(rows.last, contains('AA:01'));
      expect(rows.last, contains('Far'));
    });

    testWidgets('an adapter that will not open offers its other radio', (
      tester,
    ) async {
      radios[RadioKind.bluetoothClassic]!.pairedList = [
        adapter('OBDII', 'AA:01', paired: true),
      ];
      radios[RadioKind.ble]!.nearby = [
        adapter('OBDBLE', 'AA:02', kind: RadioKind.ble),
      ];
      // The Classic socket will not open; the Low Energy link does.
      checker.reachableFor = (config) => config.kind == AdapterKind.ble;
      await show(tester);
      await tester.tap(find.text('Bluetooth').first);
      await settle(tester);
      await tester.tap(find.text('OBDII'));
      await settle(tester);
      expect(flow(tester).step, ConnectStep.find);
      expect(find.textContaining('may be the same adapter'), findsOneWidget);
      expect(find.text('TRY OBDBLE'), findsOneWidget);

      await tester.tap(find.text('TRY OBDBLE'));
      await settle(tester);
      expect(flow(tester).step, ConnectStep.car);
      expect(flow(tester).chosen!.kind, AdapterKind.ble);
      expect(flow(tester).chosen!.address, 'AA:02');
    });

    testWidgets('a Low Energy adapter that will not open can be tried again', (
      tester,
    ) async {
      radios[RadioKind.ble]!.nearby = [
        adapter('OBDBLE', 'AA:02', kind: RadioKind.ble),
      ];
      checker.reachableNow = false;
      await show(tester);
      await tester.tap(find.text('Bluetooth').first);
      await settle(tester);
      await tester.tap(find.text('OBDBLE'));
      await settle(tester);
      expect(flow(tester).failed?.address, 'AA:02');
      expect(
        find.text('FORGET AND PAIR AGAIN'),
        findsNothing,
        reason: 'there is no pairing to forget on Low Energy',
      );
      checker.reachableNow = true;
      await tester.tap(find.text('TRY AGAIN'));
      await settle(tester);
      expect(checker.tried, hasLength(2));
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

    testWidgets('a phone with no Bluetooth at all says so and points at WiFi', (
      tester,
    ) async {
      for (final r in radios.values) {
        r.current = const RadioStatus(
          supported: false,
          enabled: false,
          permitted: false,
        );
      }
      await show(tester);
      await tester.tap(find.text('Bluetooth').first);
      await settle(tester);
      expect(find.textContaining('no Bluetooth'), findsOneWidget);
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
      expect(app.adapters.source.value, DriveSource.obd);
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
