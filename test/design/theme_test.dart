// The palette's rules for Daylight and Night (DESIGN.md 4.4), and the contrast
// rules of DESIGN.md 11 for every colour the design draws text in.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/ui/design/fidelity/fidelity_tier.dart';
import 'package:tapedash/ui/design/theme/contrast.dart';
import 'package:tapedash/ui/design/theme/palette.dart';
import 'package:tapedash/ui/design/theme/tape_theme.dart';
import 'package:tapedash/ui/design/tokens/colors.dart';
import 'package:tapedash/ui/design/tokens/livery.dart';
import 'package:tapedash/ui/design/tokens/motion_tokens.dart';

TapePalette _palette(Livery livery, [TapeMode mode = TapeMode.normal]) =>
    TapePalette(livery: livery, mode: mode);

/// A const widget that depends on the theme and counts its builds. Being const,
/// it is rebuilt only if the theme tells it to.
class _Probe extends StatelessWidget {
  const _Probe();

  static int builds = 0;

  @override
  Widget build(BuildContext context) {
    TapeTheme.of(context);
    builds++;
    return const SizedBox();
  }
}

void main() {
  group('contrast maths', () {
    test('black on white is 21:1, and a colour on itself is 1:1', () {
      expect(
        Contrast.ratio(const Color(0xFFFFFFFF), const Color(0xFF000000)),
        closeTo(21, 1e-9),
      );
      expect(
        Contrast.ratio(TapeColors.inkDim, TapeColors.inkDim),
        closeTo(1, 1e-9),
      );
    });

    test('is symmetric', () {
      expect(
        Contrast.ratio(TapeColors.inkDim, TapeColors.voidColor),
        Contrast.ratio(TapeColors.voidColor, TapeColors.inkDim),
      );
    });

    test('ink.dim is about 5:1 on void, as DESIGN.md 4.3 says', () {
      expect(
        Contrast.ratio(TapeColors.inkDim, TapeColors.voidColor),
        inInclusiveRange(5.0, 5.5),
      );
    });

    test('a translucent colour is composited before it is judged', () {
      final etch = Contrast.over(TapeColors.etchStrong, TapeColors.voidColor);

      expect(etch.a, 1);
      expect(etch.r, closeTo(0.16 + 0.0196 * 0.84, 0.01));
    });
  });

  group('contrast rules (DESIGN.md 11)', () {
    // Primary values: at least 7:1 on void, and 10:1 in Daylight.
    for (final livery in Liveries.all) {
      for (final mode in TapeMode.values) {
        final palette = _palette(livery, mode);
        final needed = mode == TapeMode.daylight ? 10.0 : 7.0;

        test(
          '${livery.name} ${mode.label}: primary values reach $needed:1',
          () {
            for (final (name, color) in [
              ('numeral', palette.numeral),
              ('ink.bright', palette.inkBright),
              ('money', palette.money),
              ('rupee', palette.rupee),
            ]) {
              expect(
                Contrast.ratio(color, palette.canvas),
                greaterThanOrEqualTo(needed),
                reason: name,
              );
            }
          },
        );

        test(
          '${livery.name} ${mode.label}: other text reaches 4.5:1 on void',
          () {
            for (final (name, color) in [
              ('label', palette.label),
              ('ink.dim', palette.inkDim),
              ('ink.mid', palette.inkMid),
              ('stale', palette.stale),
              ('caution', palette.caution),
              ('critical', palette.critical),
              ('accent.core', palette.accentCore),
            ]) {
              expect(
                Contrast.ratio(color, palette.canvas),
                greaterThanOrEqualTo(4.5),
                reason: name,
              );
            }
          },
        );

        test(
          '${livery.name} ${mode.label}: parked text reaches 4.5:1 on a panel',
          () {
            for (final surface in [palette.panel, palette.vignetteCentre]) {
              for (final (name, color) in [
                ('label', palette.label),
                ('ink.dim', palette.inkDim),
                ('ink.mid', palette.inkMid),
                ('ink.bright', palette.inkBright),
                ('accent.core', palette.accentCore),
              ]) {
                expect(
                  Contrast.ratio(color, surface),
                  greaterThanOrEqualTo(4.5),
                  reason: '$name on $surface',
                );
              }
            }
          },
        );
      }
    }

    test(
      'critical and stale are exempt from 7:1, but a bracket or glyph must go with them',
      () {
        // DESIGN.md 11: a saturated red cannot reach 7:1 on black, so the rule is
        // 4.5:1 with a non-colour cue. This pins the exemption to those two only.
        expect(
          Contrast.ratio(TapeColors.critical, TapeColors.voidColor),
          lessThan(7),
        );
        expect(
          Contrast.ratio(TapeColors.stale, TapeColors.voidColor),
          lessThan(7),
        );
        for (final c in [
          TapeColors.caution,
          TapeColors.moneyCore,
          TapeColors.moneyDeep,
          TapeColors.inkBright,
          TapeColors.inkMid,
        ]) {
          expect(
            Contrast.ratio(c, TapeColors.voidColor),
            greaterThanOrEqualTo(7),
            reason: '$c has no exemption',
          );
        }
      },
    );
  });

  group('Daylight (DESIGN.md 4.4)', () {
    test('turns halos off and strokes 50% thicker', () {
      for (final l in Liveries.all) {
        final p = _palette(l, TapeMode.daylight);
        expect(p.haloScale, 0, reason: l.name);
        expect(p.strokeScale, 1.5, reason: l.name);
      }
    });

    test('ink.dim becomes ink.mid, and labels become ink.bright', () {
      final p = _palette(Liveries.ion, TapeMode.daylight);

      expect(p.inkDim, TapeColors.inkMid);
      expect(p.label, TapeColors.inkBright);
      expect(p.stale, TapeColors.inkMid);
    });

    test(
      'EMBER numerals switch to ink.bright, and the accent keeps its fills',
      () {
        final p = _palette(Liveries.ember, TapeMode.daylight);

        expect(p.numeral, TapeColors.inkBright);
        expect(p.accentCore, Liveries.ember.accentCore);
        expect(p.accentDeep, Liveries.ember.accentDeep);
      },
    );

    test('an accent that already reaches 10:1 keeps its numerals', () {
      for (final l in [Liveries.ion, Liveries.vfd, Liveries.mono]) {
        expect(
          _palette(l, TapeMode.daylight).numeral,
          l.accentCore,
          reason: l.name,
        );
      }
    });

    test('the rupee sign goes from money.deep to money.core', () {
      expect(_palette(Liveries.ion).rupee, TapeColors.moneyDeep);
      expect(
        _palette(Liveries.ion, TapeMode.daylight).rupee,
        TapeColors.moneyCore,
      );
      expect(
        _palette(Liveries.ion, TapeMode.night).rupee,
        TapeColors.moneyDeep,
      );
    });
  });

  group('Night (DESIGN.md 4.4)', () {
    test('halves the halos, and MONO starts from 40%', () {
      expect(_palette(Liveries.ion, TapeMode.night).haloScale, 0.5);
      expect(
        _palette(Liveries.mono, TapeMode.night).haloScale,
        closeTo(0.2, 1e-9),
      );
      expect(_palette(Liveries.mono).haloScale, 0.4);
      expect(_palette(Liveries.ion).haloScale, 1);
    });

    test('dims the structure to 70% and leaves the labels alone', () {
      final day = _palette(Liveries.ion);
      final night = _palette(Liveries.ion, TapeMode.night);

      expect(night.etch.a, closeTo(day.etch.a * 0.7, 1e-9));
      expect(night.etchStrong.a, closeTo(day.etchStrong.a * 0.7, 1e-9));
      expect(night.etchFaint.a, closeTo(day.etchFaint.a * 0.7, 1e-9));
      expect(night.label, day.label);
      expect(night.inkDim, day.inkDim);
    });

    test(
      'keeps the glass edge at full strength, since it is not structure',
      () {
        expect(
          _palette(Liveries.ion, TapeMode.night).glassEdge,
          TapeColors.etchStrong,
        );
      },
    );

    test('allows ink.hot for needle cores only', () {
      expect(_palette(Liveries.ion, TapeMode.night).inkHotEverywhere, isFalse);
      expect(_palette(Liveries.ion).inkHotEverywhere, isTrue);
      expect(
        _palette(Liveries.ion, TapeMode.daylight).inkHotEverywhere,
        isTrue,
      );
    });

    test('does not change strokes', () {
      expect(_palette(Liveries.ion, TapeMode.night).strokeScale, 1);
    });
  });

  group('normal mode', () {
    test('uses the raw tokens', () {
      final p = _palette(Liveries.ion);

      expect(p.canvas, TapeColors.voidColor);
      expect(p.inkDim, TapeColors.inkDim);
      expect(p.label, TapeColors.inkDim);
      expect(p.etch, TapeColors.etch);
      expect(p.numeral, Liveries.ion.accentCore);
      expect(p.money, TapeColors.moneyCore);
      expect(p.strokeScale, 1);
    });

    test(
      'an unlit segment is carbon.700, so it is a ghost and not nothing',
      () {
        expect(_palette(Liveries.ion).track, TapeColors.carbon700);
      },
    );
  });

  group('TapeTheme', () {
    testWidgets('gives its data to the widgets below it', (tester) async {
      TapeThemeData? seen;
      await tester.pumpWidget(
        TapeTheme(
          data: TapeThemeData(livery: Liveries.ember, mode: TapeMode.night),
          child: Builder(
            builder: (context) {
              seen = TapeTheme.of(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(seen!.livery.id, LiveryId.ember);
      expect(seen!.palette.mode, TapeMode.night);
    });

    testWidgets(
      'rebuilds dependants when the data changes, and not when it does not',
      (tester) async {
        _Probe.builds = 0;
        Widget app(TapeThemeData data) =>
            TapeTheme(data: data, child: const _Probe());

        await tester.pumpWidget(app(TapeThemeData()));
        await tester.pumpWidget(app(TapeThemeData()));
        expect(_Probe.builds, 1, reason: 'an equal theme changes nothing');

        await tester.pumpWidget(app(TapeThemeData(livery: Liveries.vfd)));
        expect(_Probe.builds, 2);
      },
    );

    test(
      'defaults to ION, normal, Balanced, driver on the right, motion on',
      () {
        final theme = TapeThemeData();

        expect(theme.livery.id, LiveryId.ion);
        expect(theme.mode, TapeMode.normal);
        expect(theme.tier, FidelityTier.balanced);
        expect(theme.driverSide, DriverSide.right);
        expect(theme.reduceMotion, isFalse);
      },
    );

    test('reduce motion takes the overshoot out of every spring', () {
      final calm = TapeThemeData(reduceMotion: true);
      final normal = TapeThemeData();

      for (final spring in TapeSprings.all) {
        expect(calm.spring(spring).dampingRatio, 1, reason: spring.name);
        expect(normal.spring(spring).dampingRatio, spring.dampingRatio);
      }
    });

    test('copyWith changes one thing, and equality follows the fields', () {
      final base = TapeThemeData();
      final other = base.copyWith(tier: FidelityTier.lite);

      expect(other.tier, FidelityTier.lite);
      expect(other.livery.id, base.livery.id);
      expect(other, isNot(base));
      expect(base.copyWith(), base);
      expect(base.copyWith().hashCode, base.hashCode);
    });

    test('the tier profile is the theme tier\'s', () {
      expect(TapeThemeData(tier: FidelityTier.lite).profile.trailLength, 2);
      expect(TapeThemeData(tier: FidelityTier.full).profile.trailLength, 12);
    });
  });

  group('fidelity tiers (DESIGN.md 9.1)', () {
    test('each column of the table', () {
      final lite = FidelityTier.lite.profile;
      final balanced = FidelityTier.balanced.profile;
      final full = FidelityTier.full.profile;

      expect(
        [lite.trailLength, balanced.trailLength, full.trailLength],
        [2, 6, 12],
      );
      expect(
        [lite.rpmPerSegment, balanced.rpmPerSegment, full.rpmPerSegment],
        [200, 100, 100],
      );
      expect(
        [lite.maxStreaks, balanced.maxStreaks, full.maxStreaks],
        [0, 40, 120],
      );
      expect(
        [lite.parallax, balanced.parallax, full.parallax],
        [false, true, true],
      );
      expect(
        [lite.velocityStretch, balanced.velocityStretch, full.velocityStretch],
        [false, false, true],
      );
      expect(
        [lite.phosphor, balanced.phosphor, full.phosphor],
        [PhosphorScope.segments, PhosphorScope.all, PhosphorScope.all],
      );
      expect(
        [
          lite.halosOnHeroAndNeedleOnly,
          balanced.halosOnHeroAndNeedleOnly,
          full.halosOnHeroAndNeedleOnly,
        ],
        [true, false, false],
      );
      expect(
        [
          lite.halosAtHalfResolution,
          balanced.halosAtHalfResolution,
          full.halosAtHalfResolution,
        ],
        [true, false, false],
      );
      expect(
        [lite.shaderBloom, balanced.shaderBloom, full.shaderBloom],
        [false, false, true],
      );
    });

    test('frame rates: 60 with a 30 fallback, 60, and the display\'s own', () {
      expect(FidelityTier.lite.profile.targetFps, 60);
      expect(FidelityTier.lite.profile.fallbackFps, 30);
      expect(FidelityTier.balanced.profile.targetFps, 60);
      expect(FidelityTier.full.profile.targetFps, isNull);
    });

    test('a tier steps down one at a time, and Lite is the bottom', () {
      expect(FidelityTier.full.lower, FidelityTier.balanced);
      expect(FidelityTier.balanced.lower, FidelityTier.lite);
      expect(FidelityTier.lite.lower, isNull);
    });

    test('halos are the first thing cut: Lite draws the fewest', () {
      expect(
        FidelityTier.lite.profile.trailLength,
        lessThan(FidelityTier.balanced.profile.trailLength),
      );
      expect(
        FidelityTier.balanced.profile.trailLength,
        lessThan(FidelityTier.full.profile.trailLength),
      );
    });
  });
}
