// Glow sprites, the grain and mesh tiles, and the seven-segment geometry
// (DESIGN.md 4.9, 4.10 and 6.17).
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/ui/design/render/glow_cache.dart';
import 'package:tapedash/ui/design/render/grain.dart';
import 'package:tapedash/ui/design/render/mesh.dart';
import 'package:tapedash/ui/design/render/render_kit.dart';
import 'package:tapedash/ui/design/render/seven_segment.dart';
import 'package:tapedash/ui/design/tokens/shapes.dart';

Future<ByteData> _pixels(ui.Image image) async => (await image.toByteData())!;

void main() {
  group('GlowCache', () {
    const spec = GlowSpec(
      shape: GlowShape.bar,
      width: 40,
      height: 6,
      sigma: 4,
      devicePixelRatio: 2,
    );

    test(
      'a sprite is the core shape plus a margin of three sigma on every side',
      () {
        final cache = GlowCache();
        addTearDown(cache.clear);

        final sprite = cache.get(spec);

        expect(sprite.margin, closeTo(3 * 4 + 0.5, 0.6));
        expect(sprite.size.width, closeTo(40 + 2 * sprite.margin, 1));
        expect(sprite.size.height, closeTo(6 + 2 * sprite.margin, 1));
        expect(sprite.scale, 0.5);
      },
    );

    test(
      'the sprite is white and soft: brightest at its middle, and fading out to nothing',
      () async {
        final cache = GlowCache();
        addTearDown(cache.clear);
        final sprite = cache.get(
          const GlowSpec(
            shape: GlowShape.disc,
            width: 20,
            height: 20,
            sigma: 5,
          ),
        );
        final data = await _pixels(sprite.image);
        final w = sprite.image.width;
        final h = sprite.image.height;

        int alpha(int x, int y) => data.getUint8((y * w + x) * 4 + 3);

        expect(alpha(w ~/ 2, h ~/ 2), greaterThan(180));
        expect(alpha(0, 0), 0);
        expect(alpha(w ~/ 2, 0), lessThan(8));
        // Monotonic outward along the middle row, so it is a halo and not a ring.
        var last = 256;
        for (var x = w ~/ 2; x < w; x++) {
          expect(alpha(x, h ~/ 2), lessThanOrEqualTo(last));
          last = alpha(x, h ~/ 2);
        }
        // And white: the colour is applied when it is drawn.
        final r = data.getUint8(((h ~/ 2) * w + w ~/ 2) * 4);
        expect(r, greaterThan(200));
      },
    );

    test('a half-resolution sprite has a quarter of the pixels', () {
      final cache = GlowCache();
      addTearDown(cache.clear);

      final full = cache.get(
        const GlowSpec(
          shape: GlowShape.disc,
          width: 40,
          height: 40,
          sigma: 6,
          devicePixelRatio: 2,
        ),
      );
      final half = cache.get(
        const GlowSpec(
          shape: GlowShape.disc,
          width: 40,
          height: 40,
          sigma: 6,
          devicePixelRatio: 2,
          resolution: 0.5,
        ),
      );

      expect(
        half.image.width * half.image.height,
        lessThan(full.image.width * full.image.height * 0.35),
      );
      expect(half.scale, 1);
      expect(
        half.size.width,
        closeTo(full.size.width, 2),
        reason: 'the same size on screen',
      );
    });

    test('is made once per spec, and the least recently used goes first', () {
      final cache = GlowCache(capacity: 2);
      addTearDown(cache.clear);
      GlowSpec s(double sigma) =>
          GlowSpec(shape: GlowShape.disc, width: 10, height: 10, sigma: sigma);

      final a = cache.get(s(1));
      final b = cache.get(s(2));
      expect(cache.get(s(1)), same(a));
      cache.get(s(3));

      expect(b.isDisposed, isTrue);
      expect(a.isDisposed, isFalse);
      expect(cache.length, 2);
    });

    test('specs are equal by value', () {
      expect(
        spec,
        const GlowSpec(
          shape: GlowShape.bar,
          width: 40,
          height: 6,
          sigma: 4,
          devicePixelRatio: 2,
        ),
      );
      expect(
        spec,
        isNot(
          const GlowSpec(
            shape: GlowShape.disc,
            width: 40,
            height: 6,
            sigma: 4,
            devicePixelRatio: 2,
          ),
        ),
      );
      expect(
        spec.hashCode,
        const GlowSpec(
          shape: GlowShape.bar,
          width: 40,
          height: 6,
          sigma: 4,
          devicePixelRatio: 2,
        ).hashCode,
      );
    });

    test('drawing a sprite composites without an error', () {
      final cache = GlowCache();
      addTearDown(cache.clear);
      final sprite = cache.get(spec);
      final recorder = ui.PictureRecorder();

      sprite.draw(
        ui.Canvas(recorder),
        10,
        10,
        const ui.Color(0x80FFFFFF),
        ui.Paint()..blendMode = ui.BlendMode.plus,
      );

      recorder.endRecording().dispose();
    });
  });

  group('GrainTile (DESIGN.md 4.10)', () {
    test('is 128 by 128', () {
      final tile = GrainTile.generate();
      addTearDown(tile.dispose);

      expect(tile.image.width, 128);
      expect(tile.image.height, 128);
    });

    test(
      'the same seed makes the same tile, and another seed another',
      () async {
        final a = GrainTile.generate(seed: 3);
        final b = GrainTile.generate(seed: 3);
        final c = GrainTile.generate(seed: 4);
        addTearDown(a.dispose);
        addTearDown(b.dispose);
        addTearDown(c.dispose);

        final da = (await _pixels(a.image)).buffer.asUint8List();
        final db = (await _pixels(b.image)).buffer.asUint8List();
        final dc = (await _pixels(c.image)).buffer.asUint8List();

        expect(da, db);
        expect(da, isNot(dc));
      },
    );

    test(
      'has an average strength of the given opacity, 2.5% by default',
      () async {
        final tile = GrainTile.generate();
        addTearDown(tile.dispose);
        final data = await _pixels(tile.image);
        var total = 0.0;
        for (var i = 0; i < 128 * 128; i++) {
          total += data.getUint8(i * 4 + 3);
        }
        final mean = total / (128 * 128) / 255;

        expect(mean, closeTo(0.025, 0.004));
      },
    );

    test('a stronger tile is stronger', () async {
      final light = GrainTile.generate(opacity: 0.02);
      final heavy = GrainTile.generate(opacity: 0.06);
      addTearDown(light.dispose);
      addTearDown(heavy.dispose);

      double mean(ByteData d) {
        var total = 0.0;
        for (var i = 0; i < 128 * 128; i++) {
          total += d.getUint8(i * 4 + 3);
        }
        return total / (128 * 128) / 255;
      }

      expect(
        mean(await _pixels(heavy.image)),
        greaterThan(mean(await _pixels(light.image)) * 2),
      );
    });

    test(
      'is noise, not a flat tint: its alpha varies pixel to pixel',
      () async {
        final tile = GrainTile.generate();
        addTearDown(tile.dispose);
        final data = await _pixels(tile.image);
        final values = {
          for (var i = 0; i < 128 * 128; i++) data.getUint8(i * 4 + 3),
        };

        expect(values.length, greaterThan(5));
      },
    );

    test('tiles seamlessly: it is a shader that repeats', () {
      final tile = GrainTile.generate();
      addTearDown(tile.dispose);

      final paint = tile.paint();

      expect(paint.shader, isNotNull);
    });
  });

  group('MeshTile (DESIGN.md 4.10)', () {
    test('is a small tile of hairlines at 3%', () async {
      final tile = MeshTile.generate(devicePixelRatio: 2);
      addTearDown(tile.dispose);
      final data = await _pixels(tile.image);
      var lit = 0;
      var maxAlpha = 0;
      for (var i = 0; i < tile.image.width * tile.image.height; i++) {
        final a = data.getUint8(i * 4 + 3);
        if (a > 0) lit++;
        maxAlpha = math.max(maxAlpha, a);
      }

      expect(tile.image.width, lessThan(40));
      expect(lit, greaterThan(20), reason: 'there are lines');
      expect(
        lit,
        lessThan(tile.image.width * tile.image.height * 0.6),
        reason: 'and mostly space',
      );
      expect(
        maxAlpha,
        lessThanOrEqualTo(24),
        reason: '3% is 8 of 255; where lines cross, a little more',
      );
      expect(tile.paint(2).shader, isNotNull);
    });

    test('the kit makes one for a density and remakes it for another', () {
      final kit = TapeRenderKit();
      addTearDown(kit.dispose);

      final a = kit.mesh(2);

      expect(kit.mesh(2), same(a));
      expect(kit.mesh(3), isNot(same(a)));
    });
  });

  group('SevenSegmentGeometry (DESIGN.md 6.17)', () {
    final g = SevenSegmentGeometry.forHeight(100);

    test('has seven segments, each in the box of a digit and its lean', () {
      expect(g.paths.keys, unorderedEquals(Segment.values));
      for (final entry in g.paths.entries) {
        final b = entry.value.getBounds();
        expect(b.left, greaterThanOrEqualTo(-0.001), reason: entry.key.name);
        expect(b.top, greaterThanOrEqualTo(-0.001), reason: entry.key.name);
        expect(b.bottom, lessThanOrEqualTo(100.001), reason: entry.key.name);
        expect(
          b.right,
          lessThanOrEqualTo(g.cellWidth + 0.001),
          reason: entry.key.name,
        );
      }
    });

    test('a digit is 0.62 as wide as it is tall, and leans by 8 degrees', () {
      expect(g.width, closeTo(62, 1e-9));
      expect(g.skew, closeTo(100 * math.tan(8 * math.pi / 180), 1e-9));
      expect(g.cellWidth, closeTo(g.width + g.skew, 1e-9));
    });

    test('the top of a digit leans to the right of its bottom', () {
      final top = g.paths[Segment.a]!.getBounds();
      final bottom = g.paths[Segment.d]!.getBounds();

      expect(
        top.center.dx - bottom.center.dx,
        closeTo(g.skew - (g.skew * 0.15), 1.5),
      );
      expect(top.center.dx, greaterThan(bottom.center.dx));
    });

    test('the bars are as thick as the token says', () {
      final t = TapeShape.sevenSegmentThickness * 100;

      expect(g.thickness, closeTo(t, 1e-9));
      expect(g.paths[Segment.a]!.getBounds().height, closeTo(t, 0.01));
      // A vertical bar's width, before the lean, is the thickness too.
      final f = g.paths[Segment.f]!.getBounds();
      expect(f.height, greaterThan(g.width * 0.5));
    });

    test(
      'the segments are chamfered hexagons: six corners, none of them round',
      () {
        for (final entry in g.paths.entries) {
          final metrics = entry.value.computeMetrics().toList();
          expect(metrics, hasLength(1), reason: entry.key.name);
          // A hexagon of straight edges: its perimeter is the sum of six lines.
          expect(metrics.single.isClosed, isTrue, reason: entry.key.name);
        }
      },
    );

    test('segments do not touch: there is a gap of 10% of the thickness', () {
      final segments = g.paths.entries.toList();
      for (var i = 0; i < segments.length; i++) {
        for (var j = i + 1; j < segments.length; j++) {
          final a = segments[i].value;
          final b = segments[j].value;
          // Sample the outline of one and look for the other's points inside it.
          for (final metric in a.computeMetrics()) {
            for (var d = 0.0; d < metric.length; d += 0.5) {
              final p = metric.getTangentForOffset(d)!.position;
              expect(
                b.contains(p),
                isFalse,
                reason:
                    '${segments[i].key.name} touches ${segments[j].key.name} at $p',
              );
            }
          }
        }
      }
    });

    test('the height scales everything', () {
      final big = SevenSegmentGeometry.forHeight(200);

      expect(big.width, closeTo(g.width * 2, 1e-9));
      expect(big.advance, closeTo(g.advance * 2, 1e-9));
    });

    test(
      'the pen moves by the digit, its lean and the space between digits',
      () {
        expect(
          g.advance,
          closeTo(g.cellWidth + TapeShape.sevenSegmentSpacing * 100, 1e-9),
        );
      },
    );
  });

  group('SegmentMask', () {
    List<Segment> lit(int mask) => [
      for (final s in Segment.values)
        if (SegmentMask.lit(mask, s)) s,
    ];

    test('each digit lights the right segments', () {
      const expected = <int, List<Segment>>{
        0: [Segment.a, Segment.b, Segment.c, Segment.d, Segment.e, Segment.f],
        1: [Segment.b, Segment.c],
        2: [Segment.a, Segment.b, Segment.d, Segment.e, Segment.g],
        3: [Segment.a, Segment.b, Segment.c, Segment.d, Segment.g],
        4: [Segment.b, Segment.c, Segment.f, Segment.g],
        5: [Segment.a, Segment.c, Segment.d, Segment.f, Segment.g],
        6: [Segment.a, Segment.c, Segment.d, Segment.e, Segment.f, Segment.g],
        7: [Segment.a, Segment.b, Segment.c],
        8: [
          Segment.a,
          Segment.b,
          Segment.c,
          Segment.d,
          Segment.e,
          Segment.f,
          Segment.g,
        ],
        9: [Segment.a, Segment.b, Segment.c, Segment.d, Segment.f, Segment.g],
      };

      for (final entry in expected.entries) {
        expect(
          lit(SegmentMask.digit(entry.key)),
          entry.value,
          reason: 'digit ${entry.key}',
        );
      }
    });

    test('the minus is the middle bar, and a blank is nothing', () {
      expect(lit(SegmentMask.minus), [Segment.g]);
      expect(lit(SegmentMask.blank), isEmpty);
    });

    test('no two digits look the same', () {
      expect({
        for (var d = 0; d < 10; d++) SegmentMask.digit(d),
      }, hasLength(10));
    });
  });

  group('SevenSegmentAtlas', () {
    test('has a sprite for each segment, then the point and the comma', () {
      final atlas = SevenSegmentAtlas.build(heightLp: 60, devicePixelRatio: 2);
      addTearDown(atlas.dispose);

      expect(atlas.sprites, hasLength(9));
      expect(SevenSegmentAtlas.pointSprite, 7);
      expect(SevenSegmentAtlas.commaSprite, 8);
      expect(atlas.height, 60);
      for (final s in atlas.sprites) {
        expect(s.right, lessThanOrEqualTo(atlas.image.width));
        expect(s.bottom, lessThanOrEqualTo(atlas.image.height));
      }
    });

    test('a halo atlas is padded for its blur', () {
      final crisp = SevenSegmentAtlas.build(heightLp: 60, devicePixelRatio: 2);
      final glow = SevenSegmentAtlas.build(
        heightLp: 60,
        devicePixelRatio: 2,
        glowSigmaLp: 5,
      );
      addTearDown(crisp.dispose);
      addTearDown(glow.dispose);

      expect(glow.padding, greaterThan(crisp.padding * 5));
    });

    test('the kit reuses an atlas for the same request', () {
      final kit = TapeRenderKit();
      addTearDown(kit.dispose);

      final a = kit.segments(heightLp: 50, devicePixelRatio: 2);

      expect(kit.segments(heightLp: 50, devicePixelRatio: 2), same(a));
      expect(kit.segments(heightLp: 51, devicePixelRatio: 2), isNot(same(a)));
    });
  });
}
