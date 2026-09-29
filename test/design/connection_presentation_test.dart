// The connection states' logic (DESIGN.md 7.12): standby while searching or
// waiting, the beam's one turn per 1.6 s, the breath at 0.25 Hz, the loss,
// and the 300 ms re-light that only a reconnection after a loss plays.
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/ui/design/motion/connection_presentation.dart';
import 'package:tapedash/ui/design/motion/motion_clock.dart';
import 'package:tapedash/ui/design/tokens/connection.dart';

void main() {
  late ManualMotionClock clock;
  late ConnectionPresentation p;

  setUp(() => clock = ManualMotionClock());
  tearDown(() {
    p.dispose();
    clock.dispose();
  });

  ConnectionPresentation make(LinkPhase phase) =>
      p = ConnectionPresentation(clock: clock, initial: phase);

  test('searching is standby; connected is not, and asks for no frames', () {
    make(LinkPhase.searching);
    expect(p.standby, 1);
    expect(clock.attachedCount, greaterThan(0));
    p.update(LinkPhase.connected);
    clock.advance(const Duration(seconds: 2));
    expect(p.standby, closeTo(0, 0.01));
    expect(p.isRelighting, isFalse, reason: 'a first connection is not one');
    expect(clock.attachedCount, 0);
  });

  test('the beam turns once per sweepSeconds', () {
    make(LinkPhase.searching);
    clock.advance(const Duration(milliseconds: 800));
    expect(p.sweep, closeTo(0.5, 0.02));
    clock.advance(const Duration(milliseconds: 800));
    expect(p.sweep, anyOf(lessThan(0.03), greaterThan(0.97)));
    expect(TapeConnection.sweepSeconds, 1.6);
  });

  test('the dot breathes at 0.25 Hz between its two alphas', () {
    make(LinkPhase.waitingForIgnition);
    expect(p.breath, closeTo(TapeConnection.breathAlphaMin, 0.01));
    clock.advance(const Duration(seconds: 2));
    expect(p.breath, closeTo(TapeConnection.breathAlphaMax, 0.01));
    clock.advance(const Duration(seconds: 2));
    expect(p.breath, closeTo(TapeConnection.breathAlphaMin, 0.01));
  });

  test('lost rises, and a reconnection re-lights for 300 ms, once', () {
    make(LinkPhase.connected);
    p.update(LinkPhase.lost);
    clock.advance(const Duration(seconds: 2));
    expect(p.lost, closeTo(1, 0.02));
    expect(p.isRelighting, isFalse);

    p.update(LinkPhase.connected);
    expect(p.isRelighting, isTrue);
    clock.advance(const Duration(milliseconds: 105));
    expect(p.relightGlow, closeTo(1, 0.15), reason: 'peak near 35%');
    clock.advance(const Duration(milliseconds: 250));
    expect(p.isRelighting, isFalse);
    expect(p.relightGlow, 0);
    expect(p.lost, closeTo(0, 0.01));

    // Losing and regaining nothing further does not replay it.
    p.update(LinkPhase.connected);
    expect(p.isRelighting, isFalse);
  });

  test('searching after a loss does not queue a re-light', () {
    make(LinkPhase.connected);
    p.update(LinkPhase.lost);
    p.update(LinkPhase.searching);
    p.update(LinkPhase.connected);
    expect(p.isRelighting, isFalse);
  });
}
