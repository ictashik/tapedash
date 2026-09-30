import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/ui/design/motion/signal_history.dart';
import 'package:tapedash/ui/design/motion/smoothing_pipeline.dart';
import 'package:tapedash/ui/design/tokens/motion_tokens.dart';

import 'support/motion_rig.dart';

void main() {
  late MotionRig rig;
  late SmoothedSignal signal;

  setUp(() {
    rig = MotionRig();
    signal = SmoothedSignal(
      motion: rig.motion,
      clock: rig.clock,
      spring: TapeSprings.gauge,
    );
  });

  tearDown(() {
    signal.dispose();
    rig.dispose();
  });

  test('it keeps nothing until the signal has a value', () {
    final h = SignalHistory(signal, capacity: 4)..sample();

    expect(h.length, 0);
  });

  test('it keeps the value of each sample, oldest first', () {
    final h = SignalHistory(signal, capacity: 4);
    for (final v in [10.0, 20.0, 30.0]) {
      signal.ingest(rig.reading(v));
      rig.run(const Duration(seconds: 1));
      h.sample();
    }

    expect(h.length, 3);
    expect(h.oldestFirst, [10.0, 20.0, 30.0]);
    expect(h.at(0), 10);
    expect(h.at(2), 30);
  });

  test('a full ring drops the oldest, and stays the same size', () {
    final h = SignalHistory(signal, capacity: 3);
    for (var v = 1; v <= 7; v++) {
      signal.ingest(rig.reading(v * 10));
      rig.run(const Duration(seconds: 1));
      h.sample();
    }

    expect(h.length, 3);
    expect(h.oldestFirst, [50.0, 60.0, 70.0]);
  });
}
