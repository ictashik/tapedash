import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/app/demo_drive.dart';
import 'package:tapedash/app/demo_location_source.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/location/location_source.dart';

void main() {
  test(
    'the demo GPS gives fixes, and carries on when the drive starts over',
    () {
      final clock = FakeClock();
      final demo = DemoDrive(
        clock: clock,
        scheduler: clock,
        scenario: 'cold_start_idle',
      );
      addTearDown(demo.dispose);
      final gps = DemoLocationSource(
        demo: demo,
        scheduler: clock,
        clock: clock,
      );
      addTearDown(gps.dispose);
      final fixes = <LocationFix>[];
      final sub = gps.fixes.listen(fixes.add);
      addTearDown(sub.cancel);

      demo.start();
      gps.start();
      clock.advance(const Duration(seconds: 10));
      expect(fixes, isNotEmpty);
      expect(gps.isRunning, isTrue);

      // The drive starting over builds a new car; the GPS follows it.
      final before = fixes.length;
      demo.restart();
      clock.advance(const Duration(seconds: 10));
      expect(fixes.length, greaterThan(before));
      expect(gps.isRunning, isTrue);

      gps.stop();
      clock.advance(const Duration(seconds: 1));
      final after = fixes.length;
      clock.advance(const Duration(seconds: 10));
      expect(fixes.length, after);
    },
  );
}
