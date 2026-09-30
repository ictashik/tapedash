// The icon set (DESIGN.md 4.8): the required glyphs, drawn on a 24-unit grid with
// straight lines along an axis or at 45 degrees, and circles as the only curves.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/ui/design/icons/icons.dart';
import 'package:tapedash/ui/design/render/render_kit.dart';
import 'package:tapedash/ui/design/theme/palette.dart';
import 'package:tapedash/ui/design/theme/tape_theme.dart';
import 'package:tapedash/ui/design/tokens/colors.dart';

import 'support/harness.dart';

/// The glyphs DESIGN.md 4.8 requires.
const _required = [
  'adapter',
  'bluetooth',
  'wifi',
  'gps',
  'check-engine',
  'coolant',
  'voltage',
  'fuel-pump',
  'clock',
  'lock',
  'back',
  'close',
  'chevron',
  'garage',
  'history',
  'coach',
  'review',
  'rupee',
  'idle',
  'hard-accel',
  'hard-brake',
  'speed',
  'phone-hot',
  'demo',
  'hud',
  'flip',
  'pit-stop',
  'end-trip',
  'zoom-in',
  'zoom-out',
  'fit',
  'play',
  'pause',
  'stop',
  'north',
  'heading',
];

void main() {
  setUpAll(loadTapeFonts);

  group('the set', () {
    test('has every glyph DESIGN.md 4.8 requires, and no others', () {
      expect(
        TapeIcon.values.map((i) => i.label).toList()..sort(),
        [..._required]..sort(),
      );
    });

    test('has 36 icons, each different from the others', () {
      expect(TapeIcon.values, hasLength(36));
      expect({for (final i in TapeIcon.values) i.path}, hasLength(36));
    });

    test('every icon has marks to draw, and parses without an error', () {
      for (final icon in TapeIcon.values) {
        expect(icon.ops, isNotEmpty, reason: icon.label);
      }
    });

    test('an unknown command is an error, not a silent gap', () {
      expect(() => TapeIcon.parsePath('M 1 1 X 2 2'), throwsFormatException);
      expect(() => TapeIcon.parsePath('M 1 1 L 2 2'), returnsNormally);
    });

    test('a path parses into the marks it describes', () {
      final ops = TapeIcon.parsePath(
        'M 1 2 L 3 4 Z O 5 6 7 D 8 9 1 Q 2 3 4 M 0 0 L 1 1',
      );

      expect(ops, hasLength(5));
      expect((ops[0] as IconLine).points, [1, 2, 3, 4]);
      expect((ops[0] as IconLine).closed, isTrue);
      expect((ops[1] as IconCircle).filled, isFalse);
      expect((ops[2] as IconCircle).filled, isTrue);
      expect((ops[3] as IconDot).size, 4);
      expect((ops[4] as IconLine).closed, isFalse);
    });
  });

  group('the grid', () {
    test(
      'everything is inside the 24-unit grid, with a margin for the stroke',
      () {
        for (final icon in TapeIcon.values) {
          for (final op in icon.ops) {
            switch (op) {
              case IconLine():
                for (var i = 0; i < op.points.length; i++) {
                  expect(
                    op.points[i],
                    inInclusiveRange(1, 23),
                    reason: '${icon.label} ${op.points}',
                  );
                }
              case IconCircle():
                expect(
                  op.x - op.radius,
                  greaterThanOrEqualTo(1),
                  reason: icon.label,
                );
                expect(
                  op.x + op.radius,
                  lessThanOrEqualTo(23),
                  reason: icon.label,
                );
                expect(
                  op.y - op.radius,
                  greaterThanOrEqualTo(1),
                  reason: icon.label,
                );
                expect(
                  op.y + op.radius,
                  lessThanOrEqualTo(23),
                  reason: icon.label,
                );
              case IconDot():
                expect(op.x, greaterThanOrEqualTo(1), reason: icon.label);
                expect(op.y, greaterThanOrEqualTo(1), reason: icon.label);
                expect(
                  op.x + op.size,
                  lessThanOrEqualTo(23),
                  reason: icon.label,
                );
                expect(
                  op.y + op.size,
                  lessThanOrEqualTo(23),
                  reason: icon.label,
                );
            }
          }
        }
      },
    );

    test(
      'every line runs along an axis or at 45 degrees: chamfers, no free curves',
      () {
        for (final icon in TapeIcon.values) {
          for (final op in icon.ops) {
            if (op is! IconLine) continue;
            final points = op.points;
            final n = points.length ~/ 2;
            for (var i = 0; i < (op.closed ? n : n - 1); i++) {
              final a = i;
              final b = (i + 1) % n;
              final dx = points[b * 2] - points[a * 2];
              final dy = points[b * 2 + 1] - points[a * 2 + 1];
              final ok = dx == 0 || dy == 0 || dx.abs() == dy.abs();
              expect(
                ok,
                isTrue,
                reason:
                    '${icon.label}: ($dx, $dy) is not along an axis or a diagonal',
              );
            }
          }
        }
      },
    );

    test('the circles are the only curves, and there are few of them', () {
      final withCircles = TapeIcon.values.where(
        (i) => i.ops.any((o) => o is IconCircle),
      );

      expect(withCircles.map((i) => i.label).toSet(), {
        'gps',
        'coolant',
        'clock',
        'coach',
        'review',
        'speed',
        'idle',
      });
    });

    test('an icon is about as big as the grid, so the set is even', () {
      for (final icon in TapeIcon.values) {
        var minX = 99.0, maxX = 0.0, minY = 99.0, maxY = 0.0;
        void see(double x, double y) {
          minX = math.min(minX, x);
          maxX = math.max(maxX, x);
          minY = math.min(minY, y);
          maxY = math.max(maxY, y);
        }

        for (final op in icon.ops) {
          switch (op) {
            case IconLine():
              for (var i = 0; i < op.points.length; i += 2) {
                see(op.points[i], op.points[i + 1]);
              }
            case IconCircle():
              see(op.x - op.radius, op.y - op.radius);
              see(op.x + op.radius, op.y + op.radius);
            case IconDot():
              see(op.x, op.y);
              see(op.x + op.size, op.y + op.size);
          }
        }
        expect(
          math.max(maxX - minX, maxY - minY),
          greaterThanOrEqualTo(12),
          reason: '${icon.label} is not tiny',
        );
      }
    });
  });

  group('drawing', () {
    testWidgets('every icon draws something, in the colour it is given', (
      tester,
    ) async {
      setWindow(tester, const Size(640, 360));
      final kit = TapeRenderKit();
      addTearDown(kit.dispose);

      for (final icon in TapeIcon.values) {
        await tester.pumpWidget(
          tapeHarness(
            kit: kit,
            child: Align(
              alignment: Alignment.topLeft,
              child: TapeIconView(icon, size: 48, color: TapeColors.moneyCore),
            ),
          ),
        );
        final image = await renderImage(tester);
        late ByteData data;
        await tester.runAsync(() async => data = (await image.toByteData())!);
        var inked = 0;
        for (var y = 0; y < 96; y++) {
          for (var x = 0; x < 96; x++) {
            final p = data.getUint32((y * image.width + x) * 4);
            if (p == 0xF3CF86FF) inked++;
          }
        }
        expect(inked, greaterThan(60), reason: icon.label);
      }
    });

    testWidgets(
      'an icon takes the label colour by default, and Daylight thickens its stroke',
      (tester) async {
        setWindow(tester, const Size(640, 360));
        final kit = TapeRenderKit();
        addTearDown(kit.dispose);

        Future<int> ink(TapeMode mode, int colour) async {
          await tester.pumpWidget(
            tapeHarness(
              kit: kit,
              theme: TapeThemeData(mode: mode),
              child: const Align(
                alignment: Alignment.topLeft,
                child: TapeIconView(TapeIcon.close, size: 48),
              ),
            ),
          );
          final image = await renderImage(tester);
          late ByteData data;
          await tester.runAsync(() async => data = (await image.toByteData())!);
          var inked = 0;
          for (var y = 0; y < 96; y++) {
            for (var x = 0; x < 96; x++) {
              final p = data.getUint32((y * image.width + x) * 4);
              if ((p >> 8) == colour) inked++;
            }
          }
          return inked;
        }

        final normal = await ink(TapeMode.normal, 0x7A838F);
        final day = await ink(TapeMode.daylight, 0xE7ECF1);

        expect(normal, greaterThan(100), reason: 'ink.dim in normal mode');
        expect(
          day,
          greaterThan(normal * 1.2),
          reason: 'ink.bright, and 50% thicker',
        );
      },
    );

    test('paintTapeIcon scales to any size', () {
      for (final size in [16.0, 24.0, 48.0, 96.0]) {
        final recorder = ui.PictureRecorder();
        paintTapeIcon(
          ui.Canvas(recorder),
          TapeIcon.gps,
          ui.Offset.zero,
          size,
          TapeColors.inkBright,
        );
        final picture = recorder.endRecording();

        expect(picture, isNotNull);
        picture.dispose();
      }
    });
  });
}
