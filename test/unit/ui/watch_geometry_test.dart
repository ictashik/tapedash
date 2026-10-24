// The watch's geometry and type (DESIGN.md 16.3, 16.4): the circle's chord, the
// shares of D, the type scale's floors, the form factor rule and the livery's
// weight floor.
import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/ui/design/components/watch/watch_face.dart';
import 'package:tapedash/ui/design/tokens/livery.dart';
import 'package:tapedash/ui/design/tokens/spacing.dart';
import 'package:tapedash/ui/design/tokens/watch.dart';

void main() {
  group('the form factor', () {
    test(
      'a shorter side under 300 lp is a watch, whichever way it is held',
      () {
        expect(FormFactor.ofSize(225, 225), FormFactor.watch);
        expect(FormFactor.ofSize(280, 320), FormFactor.watch);
        expect(FormFactor.ofSize(320, 280), FormFactor.watch);
        expect(FormFactor.ofSize(299.9, 900), FormFactor.watch);
      },
    );

    test('a phone, in either landscape, is not', () {
      expect(FormFactor.ofSize(640, 360), FormFactor.phone);
      expect(FormFactor.ofSize(800, 360), FormFactor.phone);
      expect(FormFactor.ofSize(300, 300), FormFactor.phone);
    });
  });

  group('the face', () {
    const face = WatchFace(225);

    test('has its centre, rim and core as shares of the diameter', () {
      expect(face.radius, 112.5);
      expect(face.centre.dx, 112.5);
      expect(face.rimOuter, closeTo(0.485 * 225, 1e-9));
      expect(face.rimDepth, closeTo(0.07 * 225, 1e-9));
      expect(face.rimInner, closeTo(face.rimOuter - face.rimDepth, 1e-9));
      expect(face.coreRadius, closeTo(0.37 * 225, 1e-9));
      // The core is inside the rim, with a margin.
      expect(face.coreRadius, lessThan(face.rimInner));
    });

    test(
      'the chord of the circle is widest at the middle and 0 at its edges',
      () {
        expect(face.chordAt(112.5), closeTo(225, 1e-9));
        expect(face.chordAt(0), 0);
        expect(face.chordAt(225), 0);
        expect(face.chordAt(-5), 0);
        // At 0.25 D from the top the half-chord is sqrt(r^2 - (0.25 D)^2).
        expect(
          face.chordAt(0.25 * 225),
          closeTo(2 * math.sqrt(112.5 * 112.5 - 56.25 * 56.25), 1e-9),
        );
      },
    );

    test('the room for a line is the narrower of its top and its bottom', () {
      final room = face.roomAt(face.footY, 30);
      expect(
        room,
        closeTo(
          math.min(
            face.chordAt(face.footY - 15, circleRadius: face.coreRadius),
            face.chordAt(face.footY + 15, circleRadius: face.coreRadius),
          ),
          1e-9,
        ),
      );
      // Lower down the core is narrower.
      expect(face.roomAt(0.8 * 225, 30), lessThan(face.roomAt(0.6 * 225, 30)));
    });

    test('knows whether a rectangle is inside the circle', () {
      expect(
        face.contains(
          Rect.fromCenter(center: face.centre, width: 10, height: 10),
        ),
        isTrue,
      );
      expect(face.contains(const Rect.fromLTWH(0, 0, 20, 20)), isFalse);
      expect(face.contains(const Rect.fromLTWH(40, 40, 145, 145)), isTrue);
    });

    test('the zones go down the face in order, with room between them', () {
      expect(face.crownY, lessThan(face.heroY));
      expect(face.heroY, lessThan(face.footY));
      expect(face.footY, lessThan(face.tapeY));
      expect(face.tapeY, lessThan(face.diameter));
    });

    test('every zone line is inside the face at every checked diameter', () {
      for (final d in TapeWatch.checkedDiameters) {
        final f = WatchFace(d);
        for (final y in [f.crownY, f.heroY, f.footY, f.tapeY]) {
          expect(f.chordAt(y), greaterThan(0.4 * d), reason: 'y $y at $d');
        }
      }
    });
  });

  group('the type scale', () {
    test('at 225 it is the table of DESIGN.md 16.4', () {
      final t = WatchType.forDiameter(225);
      expect(t.hero, closeTo(72, 1e-9));
      expect(t.display, closeTo(47.25, 1e-9));
      expect(t.primary, closeTo(29.25, 1e-9));
      expect(t.secondary, closeTo(20.25, 1e-9));
      expect(t.label, closeTo(13.95, 1e-9));
    });

    test(
      'a label is never under 12 lp, on the smallest or the largest face',
      () {
        for (final d in <double>[120, 192, 198, 225, 240, 280, 400]) {
          expect(WatchType.forDiameter(d).label, greaterThanOrEqualTo(12));
        }
      },
    );

    test('each size is no smaller than the next smaller one', () {
      for (final d in TapeWatch.checkedDiameters) {
        final t = WatchType.forDiameter(d);
        expect(t.hero, greaterThan(t.display));
        expect(t.display, greaterThan(t.primary));
        expect(t.primary, greaterThan(t.secondary));
        expect(t.secondary, greaterThan(t.label));
      }
    });

    test('a wheel row is a touch target (DESIGN.md 6.14)', () {
      expect(TapeWatch.wheelRow, greaterThanOrEqualTo(TapeSpace.touchTarget));
    });
  });

  group('the numeral weight floor', () {
    test('MONO\'s Light 300 is lifted to 500 and keeps its character', () {
      final watch = Liveries.mono.withNumeralWeightAtLeast(
        TapeWatch.minNumeralWeight,
      );
      expect(watch.numeralWeight, 500);
      expect(watch.id, LiveryId.mono);
      expect(watch.accentCore, Liveries.mono.accentCore);
      expect(watch.haloScale, Liveries.mono.haloScale);
    });

    test('a heavier livery is left as it is', () {
      expect(
        Liveries.ember.withNumeralWeightAtLeast(500),
        same(Liveries.ember),
      );
      expect(Liveries.ion.withNumeralWeightAtLeast(500), same(Liveries.ion));
    });
  });
}
