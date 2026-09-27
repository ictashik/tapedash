// The render primitives: chamfered shapes, pixel snapping, the sprite batch and the
// glyph atlas (DESIGN.md 4.6, 4.7 and 9.3).
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/ui/design/render/chamfer.dart';
import 'package:tapedash/ui/design/render/glyph_atlas.dart';
import 'package:tapedash/ui/design/render/pixel.dart';
import 'package:tapedash/ui/design/render/sprite_batch.dart';
import 'package:tapedash/ui/design/tokens/typography.dart';

import 'support/harness.dart';

void main() {
  setUpAll(loadTapeFonts);

  group('Chamfer', () {
    const box = Rect.fromLTWH(10, 20, 100, 50);

    test('a square-cornered chamfer is the rectangle', () {
      final path = Chamfer.rect(box);

      expect(path.getBounds(), box);
      for (final p in [
        const Offset(10, 20),
        const Offset(110, 70),
        const Offset(60, 45),
      ]) {
        expect(path.contains(p), isTrue, reason: '$p');
      }
    });

    test('cuts a corner at 45 degrees by the given size', () {
      final path = Chamfer.rect(box, topLeft: 8);

      expect(path.getBounds(), box);
      expect(
        path.contains(const Offset(10.5, 20.5)),
        isFalse,
        reason: 'the corner is cut off',
      );
      expect(path.contains(const Offset(10.5, 30)), isTrue);
      expect(path.contains(const Offset(20, 20.5)), isTrue);
      // The cut is a diagonal from (10, 28) to (18, 20): a point on the near
      // side of it is out, and one on the far side is in.
      expect(path.contains(const Offset(13, 23)), isFalse);
      expect(path.contains(const Offset(16, 26)), isTrue);
    });

    test('all four corners can be cut, each by its own size', () {
      final path = Chamfer.rect(
        box,
        topLeft: 4,
        topRight: 8,
        bottomRight: 12,
        bottomLeft: 16,
      );

      expect(path.contains(const Offset(10.5, 20.5)), isFalse);
      expect(path.contains(const Offset(109.5, 20.5)), isFalse);
      expect(path.contains(const Offset(109.5, 69.5)), isFalse);
      expect(path.contains(const Offset(10.5, 69.5)), isFalse);
      expect(path.contains(const Offset(60, 45)), isTrue);
    });

    test(
      'a cut is limited to half the shorter side, so the cuts never cross',
      () {
        final path = Chamfer.all(const Rect.fromLTWH(0, 0, 40, 10), 100);

        expect(path.contains(const Offset(20, 5)), isTrue);
        expect(path.getBounds().width, 40);
      },
    );

    test(
      'the button shape cuts the top-left and bottom-right only (DESIGN.md 4.6)',
      () {
        final path = Chamfer.button(box, 8);

        expect(path.contains(const Offset(10.5, 20.5)), isFalse);
        expect(path.contains(const Offset(109.5, 69.5)), isFalse);
        expect(
          path.contains(const Offset(109.5, 20.5)),
          isTrue,
          reason: 'top-right is square',
        );
        expect(
          path.contains(const Offset(10.5, 69.5)),
          isTrue,
          reason: 'bottom-left is square',
        );
      },
    );

    test('rectInto reuses a path and resets it', () {
      final path = Path();
      Chamfer.rectInto(path, box, topLeft: 5);
      final first = path.getBounds();

      Chamfer.rectInto(path, const Rect.fromLTWH(0, 0, 10, 10));

      expect(first, box);
      expect(path.getBounds(), const Rect.fromLTWH(0, 0, 10, 10));
    });

    test(
      'brackets are open L shapes at the four corners, and enclose nothing',
      () {
        final path = Chamfer.brackets(box, 12);

        expect(path.getBounds(), box);
        expect(
          path.computeMetrics().length,
          4,
          reason: 'one stroke per corner',
        );
        for (final metric in path.computeMetrics()) {
          expect(metric.length, closeTo(24, 1e-6), reason: 'two arms of 12');
        }
        expect(path.contains(const Offset(60, 45)), isFalse);
      },
    );

    test('brackets shorten their arms to fit a small box', () {
      final path = Chamfer.brackets(const Rect.fromLTWH(0, 0, 10, 10), 12);

      for (final metric in path.computeMetrics()) {
        expect(metric.length, closeTo(10, 1e-6), reason: 'arms of 5');
      }
    });

    test('a polygon with cut corners keeps its shape and loses its points', () {
      final square = [
        const Offset(0, 0),
        const Offset(20, 0),
        const Offset(20, 20),
        const Offset(0, 20),
      ];
      final path = Chamfer.polygon(square, 4);

      expect(path.getBounds(), const Rect.fromLTWH(0, 0, 20, 20));
      expect(path.contains(const Offset(0.5, 0.5)), isFalse);
      expect(path.contains(const Offset(10, 10)), isTrue);
    });

    test('a polygon cut is limited to half an edge', () {
      final thin = [
        const Offset(0, 0),
        const Offset(20, 0),
        const Offset(20, 2),
        const Offset(0, 2),
      ];

      expect(Chamfer.polygon(thin, 50).getBounds().height, 2);
    });
  });

  group('Pixel', () {
    test('snaps to the nearest physical pixel', () {
      expect(Pixel.snap(10.3, 2), 10.5);
      expect(Pixel.snap(10.2, 2), 10.0);
      expect(Pixel.snap(10.24, 2), 10.0);
      expect(Pixel.snap(10.26, 2), 10.5);
      expect(Pixel.snap(10.3, 1), 10);
    });

    test('floors to a physical pixel', () {
      expect(Pixel.floor(10.49, 2), 10);
      expect(Pixel.floor(10.5, 2), 10.5);
    });

    test('snaps a rect by its edges', () {
      final r = Pixel.snapRect(const Rect.fromLTRB(1.3, 2.3, 10.7, 20.1), 2);

      expect(r, const Rect.fromLTRB(1.5, 2.5, 10.5, 20.0));
      expect(
        Pixel.snapOffset(const Offset(1.3, 2.3), 2),
        const Offset(1.5, 2.5),
      );
    });

    test('a snapped value is a whole number of physical pixels', () {
      for (final dpr in [1.0, 1.5, 2.0, 2.625, 3.0]) {
        for (final v in [0.1, 3.77, 10.5, 100.31]) {
          final snapped = Pixel.snap(v, dpr) * dpr;
          expect(snapped, closeTo(snapped.roundToDouble(), 1e-9));
        }
      }
    });
  });

  group('SpriteBatch', () {
    test('tint puts alpha in the top byte and leaves the colour', () {
      expect(SpriteBatch.tint(0x5CE1FF, 1), 0xFF5CE1FF);
      expect(SpriteBatch.tint(0x5CE1FF, 0), 0x005CE1FF);
      expect(SpriteBatch.tint(0x5CE1FF, 0.5) >>> 24, 128);
      expect(SpriteBatch.tint(0x5CE1FF, 2) >>> 24, 255, reason: 'clamped');
      expect(SpriteBatch.tint(0x5CE1FF, -1) >>> 24, 0, reason: 'clamped');
    });

    test('white is white at an alpha', () {
      expect(SpriteBatch.white(1), 0xFFFFFFFF);
      expect(SpriteBatch.white(0) & 0xFFFFFF, 0xFFFFFF);
    });

    test('fromColor keeps the colour and multiplies the alpha', () {
      const c = Color(0xFF5CE1FF);

      expect(SpriteBatch.fromColor(c, 1), 0xFF5CE1FF);
      expect(SpriteBatch.fromColor(c, 0.5) >>> 24, 128);
      expect(SpriteBatch.fromColor(const Color(0x80FFFFFF), 0.5) >>> 24, 64);
    });

    test('adds sprites up to its capacity and drops the rest', () {
      final batch = SpriteBatch(2);
      void add() => batch.add(
        left: 0,
        top: 0,
        right: 1,
        bottom: 1,
        x: 0,
        y: 0,
        scale: 1,
        color: 0xFFFFFFFF,
      );

      add();
      add();
      add();

      expect(batch.count, 2);
      batch.clear();
      expect(batch.count, 0);
    });
  });

  group('GlyphAtlas', () {
    const spec = GlyphAtlasSpec(sizeLp: 60, devicePixelRatio: 2, weight: 500);
    late GlyphAtlas atlas;

    setUp(() => atlas = GlyphAtlas.build(spec));
    tearDown(() => atlas.dispose());

    test('has every character of the numeral set, the rupee sign included', () {
      for (final rune in GlyphSet.numerals.runes) {
        expect(atlas.glyph(rune), isNotNull, reason: String.fromCharCode(rune));
      }
      expect(atlas.glyph(0x20B9), isNotNull);
      expect(
        atlas.glyph(0x2212),
        isNotNull,
        reason: 'the minus is U+2212, not a hyphen',
      );
      expect(atlas.glyph(0x2D), isNull, reason: 'a hyphen is not in the set');
    });

    test('every digit has the same advance: they are tabular', () {
      for (var d = 0; d < 10; d++) {
        expect(
          atlas.digit(d).advance,
          closeTo(atlas.digitAdvance, 1e-9),
          reason: '$d',
        );
      }
    });

    test('a digit is as wide as Saira says: about 0.71 em at wide Medium', () {
      expect(atlas.digitAdvance / 60, closeTo(0.712, 0.02));
    });

    test('the point and the comma are narrower than a digit', () {
      expect(atlas.glyph(0x2E)!.advance, lessThan(atlas.digitAdvance * 0.5));
      expect(atlas.glyph(0x2C)!.advance, lessThan(atlas.digitAdvance * 0.5));
    });

    test(
      'the scale is logical pixels per atlas pixel, so sprites are drawn 1:1',
      () {
        expect(atlas.scale, 0.5);
        expect(atlas.spec, spec);
      },
    );

    test('sprites share one height and one baseline, so glyphs line up', () {
      final heights = {for (final g in atlas.glyphs.values) g.bottom - g.top};

      expect(heights, hasLength(1));
      expect(atlas.cellHeight, closeTo(heights.single * atlas.scale, 1e-9));
      expect(atlas.baseline, lessThan(atlas.cellHeight));
      // The baseline leaves room above for the tallest digit and below for the comma.
      expect(atlas.baseline, greaterThan(60 * TapeType.digitAboveBaselineEm));
      expect(atlas.cellHeight - atlas.baseline, greaterThan(60 * 0.127));
    });

    test(
      'the image holds every sprite and is no wider than an old GPU allows',
      () {
        expect(atlas.image.width, lessThanOrEqualTo(2048));
        for (final g in atlas.glyphs.values) {
          expect(g.left, greaterThanOrEqualTo(0));
          expect(g.top, greaterThanOrEqualTo(0));
          expect(g.right, lessThanOrEqualTo(atlas.image.width));
          expect(g.bottom, lessThanOrEqualTo(atlas.image.height));
        }
      },
    );

    test('no two sprites overlap', () {
      final rects = [
        for (final g in atlas.glyphs.values)
          Rect.fromLTRB(g.left, g.top, g.right, g.bottom),
      ];
      for (var i = 0; i < rects.length; i++) {
        for (var j = i + 1; j < rects.length; j++) {
          expect(rects[i].overlaps(rects[j]), isFalse, reason: '$i and $j');
        }
      }
    });

    test('a bigger size is a bigger atlas, with proportional advances', () {
      final big = GlyphAtlas.build(
        const GlyphAtlasSpec(sizeLp: 120, devicePixelRatio: 2, weight: 500),
      );
      addTearDown(big.dispose);

      expect(
        big.digitAdvance,
        closeTo(atlas.digitAdvance * 2, atlas.digitAdvance * 0.02),
      );
      expect(big.image.width, greaterThan(atlas.image.width));
    });

    test('a heavier weight is a wider digit', () {
      final light = GlyphAtlas.build(
        const GlyphAtlasSpec(sizeLp: 60, devicePixelRatio: 2, weight: 300),
      );
      final bold = GlyphAtlas.build(
        const GlyphAtlasSpec(sizeLp: 60, devicePixelRatio: 2, weight: 700),
      );
      addTearDown(light.dispose);
      addTearDown(bold.dispose);

      expect(bold.digitAdvance, greaterThan(light.digitAdvance));
    });

    test(
      'a halo atlas has the same glyphs with room around them for the blur',
      () {
        final glow = GlyphAtlas.build(
          const GlyphAtlasSpec(
            sizeLp: 60,
            devicePixelRatio: 2,
            weight: 500,
            glowSigmaLp: 6,
          ),
        );
        addTearDown(glow.dispose);

        expect(
          glow.digitAdvance,
          closeTo(atlas.digitAdvance, 1e-9),
          reason: 'the same pen advance',
        );
        expect(glow.padding, greaterThan(atlas.padding * 5));
        expect(glow.cellHeight, greaterThan(atlas.cellHeight));
        expect(glow.spec.isGlow, isTrue);
        expect(atlas.spec.isGlow, isFalse);
      },
    );

    test('a half-resolution atlas is drawn at twice the scale', () {
      final half = GlyphAtlas.build(
        const GlyphAtlasSpec(
          sizeLp: 60,
          devicePixelRatio: 2,
          weight: 500,
          resolution: 0.5,
        ),
      );
      addTearDown(half.dispose);

      expect(half.scale, 1.0);
      expect(
        half.digitAdvance,
        closeTo(atlas.digitAdvance, atlas.digitAdvance * 0.03),
      );
      expect(half.image.width, lessThan(atlas.image.width));
    });

    test('disposing frees the image and says so', () {
      final other = GlyphAtlas.build(spec);

      other.dispose();
      other.dispose();

      expect(other.isDisposed, isTrue);
    });
  });

  group('GlyphAtlasSpec', () {
    test(
      'specs with the same values are equal, and any difference makes them unequal',
      () {
        const a = GlyphAtlasSpec(sizeLp: 60, devicePixelRatio: 2, weight: 500);

        expect(
          a,
          const GlyphAtlasSpec(sizeLp: 60, devicePixelRatio: 2, weight: 500),
        );
        expect(
          a.hashCode,
          const GlyphAtlasSpec(
            sizeLp: 60,
            devicePixelRatio: 2,
            weight: 500,
          ).hashCode,
        );
        expect(
          a,
          isNot(
            const GlyphAtlasSpec(sizeLp: 61, devicePixelRatio: 2, weight: 500),
          ),
        );
        expect(
          a,
          isNot(
            const GlyphAtlasSpec(sizeLp: 60, devicePixelRatio: 3, weight: 500),
          ),
        );
        expect(
          a,
          isNot(
            const GlyphAtlasSpec(sizeLp: 60, devicePixelRatio: 2, weight: 600),
          ),
        );
        expect(
          a,
          isNot(
            const GlyphAtlasSpec(
              sizeLp: 60,
              devicePixelRatio: 2,
              weight: 500,
              width: 100,
            ),
          ),
        );
        expect(
          a,
          isNot(
            const GlyphAtlasSpec(
              sizeLp: 60,
              devicePixelRatio: 2,
              weight: 500,
              glowSigmaLp: 3,
            ),
          ),
        );
        expect(
          a,
          isNot(
            const GlyphAtlasSpec(
              sizeLp: 60,
              devicePixelRatio: 2,
              weight: 500,
              resolution: 0.5,
            ),
          ),
        );
      },
    );
  });

  group('GlyphAtlasCache', () {
    GlyphAtlasSpec size(double s) => GlyphAtlasSpec(
      sizeLp: s,
      devicePixelRatio: 1,
      weight: 500,
      characters: '0123456789',
    );

    test('builds an atlas once and hands the same one back', () {
      final cache = GlyphAtlasCache();
      addTearDown(cache.clear);

      final first = cache.get(size(30));
      final second = cache.get(size(30));

      expect(second, same(first));
      expect(cache.length, 1);
    });

    test('keeps a different atlas for each spec', () {
      final cache = GlyphAtlasCache();
      addTearDown(cache.clear);

      expect(cache.get(size(30)), isNot(same(cache.get(size(31)))));
      expect(cache.length, 2);
    });

    test(
      'drops the least recently used beyond its capacity, and disposes it',
      () {
        final cache = GlyphAtlasCache(capacity: 2);
        addTearDown(cache.clear);
        final a = cache.get(size(20));
        final b = cache.get(size(21));
        cache.get(size(20)); // a is now the most recent

        cache.get(size(22));

        expect(cache.length, 2);
        expect(b.isDisposed, isTrue, reason: 'b was the least recently used');
        expect(a.isDisposed, isFalse);
      },
    );

    test('clear disposes everything', () {
      final cache = GlyphAtlasCache();
      final a = cache.get(size(20));

      cache.clear();

      expect(a.isDisposed, isTrue);
      expect(cache.length, 0);
    });

    test('rebuilds an atlas that was disposed behind its back', () {
      final cache = GlyphAtlasCache();
      addTearDown(cache.clear);
      final a = cache.get(size(20))..dispose();

      final again = cache.get(size(20));

      expect(again, isNot(same(a)));
      expect(again.isDisposed, isFalse);
    });
  });
}
