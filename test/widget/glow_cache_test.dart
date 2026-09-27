// GlowSprite (DESIGN.md 4.9): drawCentered's geometry. A real bug shipped
// twice (the shift horizon's breathing glow, then the eco bar's puck halo)
// from halving `size` — which is the core *plus the margin on both sides* —
// as if it were the core's own half-size, overshooting the centre by one
// margin on every axis. These tests pin the fix so it cannot silently
// regress: the ratio between `size` and the requested core is checked
// directly (no rendering), and `drawCentered`'s actual pixel output is
// checked by its intensity centroid, which a Gaussian blur preserves
// exactly regardless of sigma — the robust way to check it, rather than
// eyeballing where a blurred edge "looks" centred.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/ui/design/render/glow_cache.dart';

import '../design/support/harness.dart';

void main() {
  group('GlowSprite.size (DESIGN.md 4.9)', () {
    test('is the core plus the margin on both sides, not just the core', () {
      final cache = GlowCache();
      final sprite = cache.get(
        const GlowSpec(shape: GlowShape.disc, width: 40, height: 40, sigma: 6),
      );
      addTearDown(cache.clear);

      // size == core + 2*margin, to within the sub-pixel rounding that
      // building the sprite at an integer image size introduces.
      expect(sprite.size.width, closeTo(40 + 2 * sprite.margin, 1));
      expect(sprite.size.height, closeTo(40 + 2 * sprite.margin, 1));
      // The mistake this pins: size/2 is NOT the core's half-size.
      expect(sprite.size.width / 2, isNot(closeTo(20, 1)));
    });
  });

  group('GlowSprite.drawCentered (DESIGN.md 4.9)', () {
    Future<ui.Image> renderAt(WidgetTester tester, Offset center) async {
      // dpr 1 throughout: drawCentered's contract is in logical/canvas
      // coordinates, and comparing centroid pixels straight against the
      // requested center is simplest when image pixels and logical pixels
      // coincide 1:1 (at the default dpr 2, every logical unit is 2 image
      // pixels, and the centroid below would need dividing back down).
      setWindow(tester, const Size(120, 120), dpr: 1);
      final cache = GlowCache();
      addTearDown(cache.clear);
      final sprite = cache.get(
        const GlowSpec(shape: GlowShape.disc, width: 24, height: 24, sigma: 5),
      );
      await tester.pumpWidget(
        RepaintBoundary(
          child: CustomPaint(
            painter: _GlowPainter(sprite: sprite, center: center),
            size: const Size(120, 120),
          ),
        ),
      );
      return renderImage(tester, pixelRatio: 1);
    }

    /// The alpha-weighted centroid of every lit pixel: what a Gaussian blur
    /// leaves exactly where the unblurred shape was centred.
    Future<Offset> centroidOf(WidgetTester tester, Offset center) async {
      final image = await renderAt(tester, center);
      // toByteData() resolves through a platform-channel callback, which
      // flutter_test's fake-async test zone only pumps inside runAsync — the
      // same rule as toImage() itself (see harness.dart's renderImage),
      // just on a sibling call. Outside runAsync this hangs until the
      // framework's own 10-minute timeout rather than failing fast.
      late ByteData byteData;
      await tester.runAsync(() async => byteData = (await image.toByteData())!);
      final bytes = byteData.buffer.asUint8List();
      double sumX = 0, sumY = 0, sumA = 0;
      for (var y = 0; y < image.height; y++) {
        for (var x = 0; x < image.width; x++) {
          final a = bytes[(y * image.width + x) * 4 + 3].toDouble();
          sumX += x * a;
          sumY += y * a;
          sumA += a;
        }
      }
      expect(sumA, greaterThan(0), reason: 'nothing was drawn at all');
      return Offset(sumX / sumA, sumY / sumA);
    }

    testWidgets(
      'centres the core at the requested point, not offset by the margin',
      (tester) async {
        final centroid = await centroidOf(tester, const Offset(60, 60));
        expect(centroid.dx, closeTo(60, 1.5));
        expect(centroid.dy, closeTo(60, 1.5));
      },
    );

    testWidgets('follows an off-centre point the same way', (tester) async {
      final centroid = await centroidOf(tester, const Offset(30, 90));
      expect(centroid.dx, closeTo(30, 1.5));
      expect(centroid.dy, closeTo(90, 1.5));
    });
  });
}

class _GlowPainter extends CustomPainter {
  _GlowPainter({required this.sprite, required this.center});

  final GlowSprite sprite;
  final Offset center;

  @override
  void paint(Canvas canvas, Size size) {
    sprite.drawCentered(canvas, center, const Color(0xFFFFFFFF), Paint());
  }

  @override
  bool shouldRepaint(_GlowPainter old) => true;
}
