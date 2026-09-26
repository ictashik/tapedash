import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/sim/adapter_quirks.dart';

void main() {
  group('the presets', () {
    test('none is instant and faultless', () {
      const q = AdapterQuirks.none;

      expect(q.latency, Duration.zero);
      expect(q.jitter, Duration.zero);
      expect(q.dropFirstCommand, isFalse);
      expect(q.ignoreAdaptiveTiming, isFalse);
      expect(q.noMultiPid, isFalse);
      expect(q.noDataRate, 0);
      expect(q.missingPromptRate, 0);
      expect(q.garbageRate, 0);
    });

    test('a Bluetooth clone is 40 to 120 ms and ignores adaptive timing', () {
      const q = AdapterQuirks.bluetoothClone;

      expect(q.latency - q.jitter, const Duration(milliseconds: 40));
      expect(q.latency + q.jitter, const Duration(milliseconds: 120));
      expect(q.ignoreAdaptiveTiming, isTrue);
      expect(q.noDataRate, 0);
    });

    test(
      'a flaky one is that, and forgetful, and sometimes silent or noisy',
      () {
        const q = AdapterQuirks.flaky;

        expect(q.latency, AdapterQuirks.bluetoothClone.latency);
        expect(q.dropFirstCommand, isTrue);
        expect(q.noDataRate, greaterThan(0));
        expect(q.missingPromptRate, greaterThan(0));
        expect(q.garbageRate, greaterThan(0));
      },
    );
  });

  group('presets by name', () {
    test('are the three presets', () {
      expect(AdapterQuirks.presets.keys, ['none', 'bluetooth_clone', 'flaky']);
      expect(AdapterQuirks.presets['none'], AdapterQuirks.none);
      expect(
        AdapterQuirks.presets['bluetooth_clone'],
        AdapterQuirks.bluetoothClone,
      );
      expect(AdapterQuirks.presets['flaky'], AdapterQuirks.flaky);
    });
  });

  group('copyWith', () {
    test('changes what it is given and keeps the rest', () {
      final q = AdapterQuirks.flaky.copyWith(noMultiPid: true, noDataRate: 0.5);

      expect(q.noMultiPid, isTrue);
      expect(q.noDataRate, 0.5);
      expect(q.latency, AdapterQuirks.flaky.latency);
      expect(q.dropFirstCommand, isTrue);
      expect(q.garbageRate, AdapterQuirks.flaky.garbageRate);
    });

    test('with nothing given is the same', () {
      final q = AdapterQuirks.flaky.copyWith();

      expect(q.toString(), AdapterQuirks.flaky.toString());
    });
  });

  group('toString', () {
    test('none says none', () {
      expect(AdapterQuirks.none.toString(), 'none');
    });

    test('lists what is switched on', () {
      expect(
        AdapterQuirks.bluetoothClone.toString(),
        'latency 80 ms +/- 40 ms, ignores adaptive timing',
      );
      expect(
        AdapterQuirks.flaky.toString(),
        'latency 80 ms +/- 40 ms, drops first command, '
        'ignores adaptive timing, NO DATA 4%, missing prompt 1%, garbage 0.5%',
      );
    });

    test('a single quirk', () {
      expect(const AdapterQuirks(noMultiPid: true).toString(), 'no multi-PID');
    });
  });
}
