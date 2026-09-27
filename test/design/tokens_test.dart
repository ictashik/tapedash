// The tokens against the tables of DESIGN.md 4 and 5. A hex digit mistyped here
// would be wrong on every screen, so each value is checked against the spec.
import 'dart:ui';

import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/ui/design/tokens/colors.dart';
import 'package:tapedash/ui/design/tokens/livery.dart';
import 'package:tapedash/ui/design/tokens/motion_tokens.dart';
import 'package:tapedash/ui/design/tokens/spacing.dart';
import 'package:tapedash/ui/design/tokens/strokes.dart';
import 'package:tapedash/ui/design/tokens/typography.dart';

void main() {
  group('colours (DESIGN.md 4.3)', () {
    test('the neutrals', () {
      expect(TapeColors.voidColor, const Color(0xFF050607));
      expect(TapeColors.carbon900, const Color(0xFF0B0D10));
      expect(TapeColors.carbon800, const Color(0xFF11141A));
      expect(TapeColors.carbon700, const Color(0xFF1A1F27));
      expect(TapeColors.carbon600, const Color(0xFF252B35));
      expect(TapeColors.inkDim, const Color(0xFF7A838F));
      expect(TapeColors.inkMid, const Color(0xFF9AA3AF));
      expect(TapeColors.inkBright, const Color(0xFFE7ECF1));
      expect(TapeColors.inkHot, const Color(0xFFFFFFFF));
    });

    test('the etch colours are white at 5%, 9% and 16%', () {
      for (final (color, alpha) in [
        (TapeColors.etchFaint, 0.05),
        (TapeColors.etch, 0.09),
        (TapeColors.etchStrong, 0.16),
      ]) {
        expect(color.r, 1);
        expect(color.g, 1);
        expect(color.b, 1);
        expect(color.a, closeTo(alpha, 1 / 255));
      }
    });

    test('money is champagne', () {
      expect(TapeColors.moneyCore, const Color(0xFFF3CF86));
      expect(TapeColors.moneyDeep, const Color(0xFFD6A042));
      expect(TapeColors.moneyGlow, const Color(0xFFFFC45C));
    });

    test('state colours', () {
      expect(TapeColors.caution, const Color(0xFFFFB020));
      expect(TapeColors.critical, const Color(0xFFFF3355));
      expect(TapeColors.stale, TapeColors.inkDim);
    });

    test('the HUD colours (DESIGN.md 8)', () {
      expect(HudColor.green.color, const Color(0xFF5CFF7A));
      expect(HudColor.ion.color, const Color(0xFF5CE1FF));
      expect(HudColor.amber.color, const Color(0xFFFFB020));
      expect(HudColor.white.color, const Color(0xFFFFFFFF));
      expect(HudColor.values.first, HudColor.green, reason: 'the default');
    });
  });

  group('liveries (DESIGN.md 4.4)', () {
    test('there are four, ION first', () {
      expect(Liveries.all.map((l) => l.name), ['ION', 'EMBER', 'VFD', 'MONO']);
    });

    test('accents', () {
      expect(Liveries.ion.accentCore, const Color(0xFF5CE1FF));
      expect(Liveries.ion.accentDeep, const Color(0xFF1296FF));
      expect(Liveries.ion.accentGlow, const Color(0xFF2EC8FF));
      expect(Liveries.ember.accentCore, const Color(0xFFFF7A3D));
      expect(Liveries.ember.accentDeep, const Color(0xFFE8461C));
      expect(Liveries.ember.accentGlow, const Color(0xFFFF6A2B));
      expect(Liveries.vfd.accentCore, const Color(0xFF6BF7DC));
      expect(Liveries.vfd.accentDeep, const Color(0xFF1FC2A4));
      expect(Liveries.vfd.accentGlow, const Color(0xFF3DFFD5));
      expect(Liveries.mono.accentCore, const Color(0xFFF2F3F4));
      expect(Liveries.mono.accentDeep, const Color(0xFFA9AFB7));
      expect(Liveries.mono.accentGlow, const Color(0xFFFFFFFF));
    });

    test('numerals: Medium, SemiBold, seven-segment and Light', () {
      expect(Liveries.ion.numeralWeight, 500);
      expect(Liveries.ember.numeralWeight, 600);
      expect(Liveries.mono.numeralWeight, 300);
      expect(Liveries.vfd.numerals, NumeralFace.sevenSegment);
      for (final l in [Liveries.ion, Liveries.ember, Liveries.mono]) {
        expect(l.numerals, NumeralFace.saira, reason: l.name);
      }
    });

    test(
      'only VFD has ghost segments and the mesh, and only MONO has weak halos',
      () {
        expect(Liveries.vfd.ghostAlpha, 0.07);
        expect(Liveries.vfd.mesh, isTrue);
        for (final l in [Liveries.ion, Liveries.ember, Liveries.mono]) {
          expect(l.ghostAlpha, 0, reason: l.name);
          expect(l.mesh, isFalse, reason: l.name);
        }
        expect(Liveries.mono.haloScale, 0.4);
        for (final l in [Liveries.ion, Liveries.ember, Liveries.vfd]) {
          expect(l.haloScale, 1, reason: l.name);
        }
      },
    );

    test('byId finds each', () {
      for (final l in Liveries.all) {
        expect(Liveries.byId(l.id), same(l));
      }
    });
  });

  group('type scale (DESIGN.md 4.5)', () {
    test('at the design height of 360', () {
      final scale = TypeScale.forHeight(360);

      expect(scale.hero, closeTo(129.6, 1e-9));
      expect(scale.display, closeTo(72, 1e-9));
      expect(scale.primary, closeTo(43.2, 1e-9));
      expect(scale.secondary, closeTo(27, 1e-9));
      expect(scale.label, closeTo(12.96, 1e-9));
    });

    test('is clamped at both ends', () {
      final small = TypeScale.forHeight(100);
      expect(
        [
          small.hero,
          small.display,
          small.primary,
          small.secondary,
          small.label,
        ],
        [96, 56, 34, 22, 11],
      );
      final large = TypeScale.forHeight(2000);
      expect(
        [
          large.hero,
          large.display,
          large.primary,
          large.secondary,
          large.label,
        ],
        [220, 128, 72, 44, 16],
      );
    });

    test('each step is smaller than the last', () {
      for (final h in [240.0, 360.0, 480.0, 720.0]) {
        final s = TypeScale.forHeight(h);
        expect(s.hero, greaterThan(s.display));
        expect(s.display, greaterThan(s.primary));
        expect(s.primary, greaterThan(s.secondary));
        expect(s.secondary, greaterThan(s.label));
      }
    });
  });

  group('text styles', () {
    test('numerals are Saira, wide, tabular, and at the livery weight', () {
      final style = TapeType.numeral(size: 100, weight: 500);

      expect(style.fontFamily, TapeFontFamily.saira);
      expect(style.fontVariations, contains(const FontVariation('wght', 500)));
      expect(
        style.fontVariations,
        contains(const FontVariation('wdth', TapeType.numeralWidth)),
      );
      expect(style.fontFeatures, contains(const FontFeature.tabularFigures()));
    });

    test('a label is Barlow Semi Condensed Medium, tracked out by 12%', () {
      final style = TapeType.label(size: 20);

      expect(style.fontFamily, TapeFontFamily.barlowSemiCondensed);
      expect(style.fontWeight, FontWeight.w500);
      expect(style.letterSpacing, closeTo(2.4, 1e-9));
    });

    test('a button label is SemiBold, tracked out by 8%', () {
      final style = TapeType.button(size: 20);

      expect(style.fontWeight, FontWeight.w600);
      expect(style.letterSpacing, closeTo(1.6, 1e-9));
    });

    test('the wordmark is wide SemiBold, tracked out by 6%', () {
      final style = TapeType.wordmark(size: 50);

      expect(style.fontFamily, TapeFontFamily.saira);
      expect(style.fontVariations, contains(const FontVariation('wght', 600)));
      expect(style.letterSpacing, closeTo(3, 1e-9));
    });

    test('parked text is Barlow at the fixed sizes', () {
      expect(TapeType.headline().fontSize, 30);
      expect(TapeType.title().fontSize, 22);
      expect(TapeType.body().fontSize, 16);
      expect(TapeType.small().fontSize, 13);
      expect(TapeType.caption().fontSize, 12);
      for (final style in [
        TapeType.headline(),
        TapeType.title(),
        TapeType.body(),
        TapeType.small(),
        TapeType.caption(),
      ]) {
        expect(style.fontFamily, TapeFontFamily.barlow);
      }
      expect(TapeType.headline().fontWeight, FontWeight.w600);
      expect(TapeType.title().fontWeight, FontWeight.w600);
      expect(TapeType.body().fontWeight, FontWeight.w400);
    });
  });

  group('spacing and strokes (DESIGN.md 4.6 and 4.7)', () {
    test('the spacing scale is on a 4 lp base', () {
      expect(
        [
          TapeSpace.s1,
          TapeSpace.s2,
          TapeSpace.s3,
          TapeSpace.s4,
          TapeSpace.s6,
          TapeSpace.s8,
          TapeSpace.s12,
        ],
        [4, 8, 12, 16, 24, 32, 48],
      );
    });

    test('the margin is max(16, 0.045H)', () {
      expect(TapeSpace.margin(360), 16.2);
      expect(TapeSpace.margin(300), 16);
      expect(TapeSpace.margin(1000), 45);
    });

    test('the centre zone is min(0.5W, 1.25H)', () {
      expect(TapeSpace.centreWidth(640, 360), 320);
      expect(TapeSpace.centreWidth(800, 360), 400);
      expect(TapeSpace.centreWidth(2000, 360), 450);
    });

    test('strokes', () {
      expect(TapeStroke.fine, 1.5);
      expect(TapeStroke.regular, 2);
      expect(TapeStroke.bold, 3);
      expect(TapeStroke.hud, greaterThanOrEqualTo(5));
      expect(TapeStroke.icon, 1.75);
    });

    test('a hairline is one physical pixel', () {
      expect(TapeStroke.hairline(1), 1);
      expect(TapeStroke.hairline(2), 0.5);
      expect(TapeStroke.hairline(2.625), closeTo(0.381, 1e-3));
    });

    test('snapping puts a stroke on whole physical pixels', () {
      for (final dpr in [1.0, 2.0, 2.625, 3.0]) {
        for (final at in [10.13, 55.5, 100.99, 3.2]) {
          for (final width in [1 / dpr, 2.0]) {
            final snapped = TapeStroke.snap(at, width, dpr);
            final physicalWidth = (width * dpr).round();
            final edge = snapped * dpr - physicalWidth / 2;
            expect(
              edge,
              closeTo(edge.roundToDouble(), 1e-9),
              reason: 'at $at, width $width, dpr $dpr',
            );
          }
        }
      }
    });

    test('snapping moves a line by less than a pixel', () {
      expect(TapeStroke.snap(10.3, 0.5, 2), closeTo(10.25, 1e-9));
      expect(TapeStroke.snap(10.3, 1, 2), closeTo(10.5, 1e-9));
    });
  });

  group('motion tokens (DESIGN.md 5)', () {
    test('the springs', () {
      expect(TapeSprings.needle.stiffness, 260);
      expect(TapeSprings.needle.dampingRatio, 0.72);
      expect(TapeSprings.gauge.stiffness, 380);
      expect(TapeSprings.gauge.dampingRatio, 1);
      expect(TapeSprings.page.stiffness, 170);
      expect(TapeSprings.page.dampingRatio, 0.92);
      expect(TapeSprings.reveal.stiffness, 120);
      expect(TapeSprings.reveal.dampingRatio, 0.85);
      expect(TapeSprings.snap.stiffness, 600);
      expect(TapeSprings.snap.dampingRatio, 1);
    });

    test('reduce motion removes overshoot and touches nothing else', () {
      for (final s in TapeSprings.all) {
        final calm = s.withoutOvershoot;
        expect(calm.dampingRatio, 1, reason: s.name);
        expect(calm.stiffness, s.stiffness, reason: s.name);
      }
    });

    test('durations and curves', () {
      expect(TapeDurations.micro, const Duration(milliseconds: 120));
      expect(TapeDurations.quick, const Duration(milliseconds: 220));
      expect(TapeDurations.scene, const Duration(milliseconds: 480));
      expect(TapeDurations.cinematic, const Duration(milliseconds: 1200));
      expect(TapeCurves.enter, const Cubic(0.16, 1, 0.3, 1));
      expect(TapeCurves.exit, const Cubic(0.7, 0, 0.84, 0));
    });

    test('phosphor, stale data and the detent', () {
      expect(TapeMotion.phosphorRiseSeconds, 0.030);
      expect(TapeMotion.phosphorDecaySeconds, 0.180);
      expect(TapeMotion.staleAfter, const Duration(milliseconds: 1500));
      expect(TapeMotion.staleFade, const Duration(milliseconds: 600));
      expect(TapeMotion.staleRecover, const Duration(milliseconds: 200));
      expect(TapeMotion.detentStart, 0.3);
      expect(TapeMotion.detentEnd, 0.7);
      expect(TapeMotion.maxFrameSeconds, 0.05);
      expect(TapeMotion.maxFlashHz, 3);
    });
  });
}
