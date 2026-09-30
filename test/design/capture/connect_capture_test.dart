// The connect flow's steps, for a look. Skipped unless TAPEDASH_CAPTURE_DIR is set.
import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/app/app_services.dart';
import 'package:tapedash/obd/adapter_checker.dart';
import 'package:tapedash/obd/adapter_config.dart';
import 'package:tapedash/obd/transport/native_link.dart';
import 'package:tapedash/platform/adapter_radio.dart';
import 'package:tapedash/ui/design/components/backdrop.dart';
import 'package:tapedash/ui/design/motion/motion_clock.dart';
import 'package:tapedash/ui/design/render/render_kit.dart';
import 'package:tapedash/ui/onboarding/connect_flow.dart';

import '../support/harness.dart';

class _Radio implements AdapterRadio {
  _Radio(this.kind);

  @override
  final RadioKind kind;

  @override
  Future<RadioStatus> status() async =>
      const RadioStatus(supported: true, enabled: true, permitted: true);
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<List<FoundAdapter>> paired() async => [
    FoundAdapter(
      name: 'OBDII',
      address: '00:1D:A5:68:98:8B',
      kind: kind,
      paired: true,
    ),
    FoundAdapter(
      name: 'JBL Flip 5',
      address: '40:EF:4C:01:02:03',
      kind: kind,
      paired: true,
    ),
  ];
  @override
  Stream<FoundAdapter> scan() => Stream.fromIterable([
    FoundAdapter(
      name: 'Vgate iCar Pro',
      address: '11:22:33:44:55:66',
      kind: kind,
    ),
  ]);
  @override
  Future<void> pair(String address) async {}
  @override
  NativeLink link(String address) => throw UnimplementedError();
}

class _Checker implements AdapterChecker {
  @override
  bool allows(String host) => true;
  @override
  Future<bool> reachable(AdapterConfig config) async => true;
}

void main() {
  final enabled = Platform.environment['TAPEDASH_CAPTURE_DIR'] != null;
  setUpAll(loadTapeFonts);

  testWidgets('the connect flow, step by step', (tester) async {
    setWindow(tester, const Size(720, 360));
    final kit = TapeRenderKit();
    addTearDown(kit.dispose);
    final motion = ManualMotionClock();
    addTearDown(motion.dispose);
    final app = await AppServices.memory();
    await tester.pumpWidget(
      tapeHarness(
        kit: kit,
        motion: motion,
        child: TapeBackdrop(
          child: ConnectFlow(
            services: app,
            checker: _Checker(),
            radios: _Radio.new,
            width: 720,
            height: 360,
            onDone: () {},
            onCancel: () {},
          ),
        ),
      ),
    );
    Future<void> settle() async {
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    await settle();
    await capturePng(tester, 'connect-1-type');
    await tester.tap(find.text('Bluetooth').first);
    await settle();
    await capturePng(tester, 'connect-2-find');
    await tester.tap(find.text('OBDII'));
    await settle();
    await capturePng(tester, 'connect-3-car');
    await tester.tap(find.text('NEXT'));
    await settle();
    await capturePng(tester, 'connect-4-price');
    await tester.tap(find.text('SKIP'));
    await settle();
    await capturePng(tester, 'connect-5-layout');
    // And the WiFi entry.
    await tester.tap(find.text('BACK'));
    await settle();
    await tester.tap(find.text('BACK'));
    await settle();
    await tester.tap(find.text('BACK'));
    await settle();
    await tester.tap(find.text('BACK'));
    await settle();
    await tester.tap(find.text('WiFi'));
    await settle();
    await capturePng(tester, 'connect-2-wifi');
  }, skip: !enabled);
}
