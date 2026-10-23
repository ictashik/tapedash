// The words and figures the GPS screen writes: the compass point of a heading and
// the moving time.
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/ui/pages/drive/gps_cluster.dart';

void main() {
  test('a heading is the nearest of the eight compass points', () {
    expect(compassPoint(0), 'N');
    expect(compassPoint(22), 'N');
    expect(compassPoint(23), 'NE');
    expect(compassPoint(90), 'E');
    expect(compassPoint(180), 'S');
    expect(compassPoint(269), 'W');
    expect(compassPoint(330), 'NW');
    expect(compassPoint(338), 'N', reason: 'past 337.5 it is nearer north');
    expect(compassPoint(359.9), 'N');
    expect(compassPoint(-90), 'W', reason: 'a negative bearing wraps');
    expect(compassPoint(450), 'E');
    expect(compassPoint(null), isNull);
  });

  test('moving time is minutes and seconds, then hours', () {
    expect(formatMovingTime(Duration.zero), '0:00');
    expect(formatMovingTime(const Duration(seconds: 9)), '0:09');
    expect(formatMovingTime(const Duration(seconds: 45)), '0:45');
    expect(formatMovingTime(const Duration(minutes: 12, seconds: 34)), '12:34');
    expect(formatMovingTime(const Duration(minutes: 59, seconds: 59)), '59:59');
    expect(formatMovingTime(const Duration(hours: 1)), '1:00:00');
    expect(
      formatMovingTime(const Duration(hours: 2, minutes: 5, seconds: 9)),
      '2:05:09',
    );
  });
}
