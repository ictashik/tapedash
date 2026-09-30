// The engine sound in the running app: turned on in the settings, it follows the
// drive that is on the screen (here the demo), and the screen leaving takes it away.
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/app/app_services.dart';
import 'package:tapedash/app/drive_shell.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/sound/engine_profile.dart';
import 'package:tapedash/sound/pcm_sink.dart';
import 'package:tapedash/sound/voice_host.dart';
import 'package:tapedash/ui/design/motion/motion_clock.dart';
import 'package:tapedash/ui/design/render/render_kit.dart';

import '../design/support/harness.dart';

class _Voice implements VoiceHost {
  bool running = false;
  double peakRpm = 0;
  bool everActive = false;
  bool? requireExternal;
  EngineProfile? profile;

  @override
  Stream<String> get events => const Stream.empty();

  @override
  Future<SinkStart> start(
    EngineProfile profile, {
    required double volume,
    bool requireExternalOutput = false,
  }) async {
    running = true;
    this.profile = profile;
    requireExternal = requireExternalOutput;
    return SinkStart.started;
  }

  @override
  void setProfile(EngineProfile profile) => this.profile = profile;

  @override
  void setVolume(double volume) {}

  @override
  void setControls({
    required double rpm,
    required double load,
    required bool active,
  }) {
    if (active) {
      everActive = true;
      if (rpm > peakRpm) peakRpm = rpm;
    }
  }

  @override
  Future<void> stop() async => running = false;
}

void main() {
  setUpAll(loadTapeFonts);

  testWidgets('the demo drive is heard, and the screen going takes it away', (
    tester,
  ) async {
    setWindow(tester, const Size(720, 360));
    final kit = TapeRenderKit();
    addTearDown(kit.dispose);
    final motion = ManualMotionClock();
    addTearDown(motion.dispose);
    final app = await AppServices.memory();
    app.settings.soundEnabled.value = true;
    app.settings.soundProfile.value = 'v6';
    final clock = FakeClock()..advance(const Duration(seconds: 100));
    final voices = <_Voice>[];
    await tester.pumpWidget(
      tapeHarness(
        kit: kit,
        motion: motion,
        child: DriveShell(
          clock: clock,
          scheduler: clock,
          scenario: 'city_stop_go',
          app: app,
          soundHost: () {
            final v = _Voice();
            voices.add(v);
            return v;
          },
        ),
      ),
    );
    Future<void> run(int ms) async {
      for (var t = 0; t < ms; t += 100) {
        motion.advance(const Duration(milliseconds: 100));
        clock.advance(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await run(30000);

    final voice = voices.single;
    expect(voice.running, isTrue);
    expect(voice.profile, EngineProfile.v6);
    expect(voice.requireExternal, isTrue, reason: 'car audio only, by default');
    expect(voice.everActive, isTrue, reason: 'the demo car has an engine');
    expect(voice.peakRpm, greaterThan(1200));

    // The app going to the background takes it away.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    expect(voice.running, isFalse);

    // Turned off, nothing is left on when the screen returns.
    app.settings.soundEnabled.value = false;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    expect(voice.running, isFalse);
  });

  testWidgets('with the sound off, no voice is ever made', (tester) async {
    setWindow(tester, const Size(720, 360));
    final kit = TapeRenderKit();
    addTearDown(kit.dispose);
    final motion = ManualMotionClock();
    addTearDown(motion.dispose);
    final app = await AppServices.memory();
    final clock = FakeClock()..advance(const Duration(seconds: 100));
    var made = 0;
    await tester.pumpWidget(
      tapeHarness(
        kit: kit,
        motion: motion,
        child: DriveShell(
          clock: clock,
          scheduler: clock,
          app: app,
          soundHost: () {
            made++;
            return _Voice();
          },
        ),
      ),
    );

    for (var t = 0; t < 5000; t += 100) {
      motion.advance(const Duration(milliseconds: 100));
      clock.advance(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(made, 0);
  });
}
