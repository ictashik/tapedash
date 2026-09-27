// Rolling numerals (DESIGN.md 6.1): drawn from the glyph atlas, anchored on the
// ones column, repainting from their source and never rebuilding for data.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/ui/design/components/rolling_numerals.dart';
import 'package:tapedash/ui/design/motion/numeral_source.dart';
import 'package:tapedash/ui/design/render/render_kit.dart';
import 'package:tapedash/ui/design/theme/palette.dart';
import 'package:tapedash/ui/design/theme/tape_theme.dart';
import 'package:tapedash/ui/design/tokens/glow.dart';
import 'package:tapedash/ui/design/tokens/livery.dart';

import '../design/support/harness.dart';

/// A source of a number that a test moves by hand.
class _Number extends ChangeNotifier implements NumeralSource {
  _Number(this._value, {this.has = true});

  double _value;
  double _staleness = 0;
  bool has;
  int listeners = 0;

  bool get isListened => listeners > 0;

  @override
  void addListener(VoidCallback listener) {
    listeners++;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    listeners--;
    super.removeListener(listener);
  }

  @override
  double get value => _value;
  set value(double v) {
    _value = v;
    notifyListeners();
  }

  @override
  double get staleness => _staleness;
  set staleness(double v) {
    _staleness = v;
    notifyListeners();
  }

  @override
  bool get hasValue => has;
}

/// Counts how many times it is built.
class _Builds extends StatelessWidget {
  const _Builds({required this.child});

  static int count = 0;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    count++;
    return child;
  }
}

/// The RGBA pixels of [image], with a way to read a pixel and a region.
class _Pixels {
  _Pixels(this.width, this.height, this.data);

  final int width;
  final int height;
  final ByteData data;

  static Future<_Pixels> of(WidgetTester tester, ui.Image image) async {
    late _Pixels pixels;
    await tester.runAsync(() async {
      final bytes = await image.toByteData();
      pixels = _Pixels(image.width, image.height, bytes!);
    });
    return pixels;
  }

  int rgba(int x, int y) => data.getUint32((y * width + x) * 4);

  /// The pixels of a region, as one list.
  List<int> region(int left, int top, int right, int bottom) => [
    for (var y = top; y < bottom; y++)
      for (var x = left; x < right; x++) rgba(x, y),
  ];

  /// How many pixels in the region are not the canvas colour.
  int litIn(int left, int top, int right, int bottom) {
    final canvas = rgba(0, 0);
    var n = 0;
    for (var y = top; y < bottom; y++) {
      for (var x = left; x < right; x++) {
        if (rgba(x, y) != canvas) n++;
      }
    }
    return n;
  }
}

void main() {
  setUpAll(loadTapeFonts);

  late TapeRenderKit kit;

  setUp(() => kit = TapeRenderKit());
  tearDown(() => kit.dispose());

  Widget app(
    Widget child, {
    TapeThemeData? theme,
    Alignment alignment = Alignment.center,
  }) => tapeHarness(
    kit: kit,
    theme: theme,
    child: Align(alignment: alignment, child: child),
  );

  const size = 60.0;
  const format3 = NumeralFormat(integerDigits: 3);

  RenderRollingNumerals render(WidgetTester tester) =>
      tester.renderObject<RenderRollingNumerals>(find.byType(RollingNumerals));

  group('layout', () {
    testWidgets('is a fixed box for its digits, whatever the value', (
      tester,
    ) async {
      setWindow(tester, const Size(640, 360));
      final small = _Number(7);
      addTearDown(small.dispose);
      await tester.pumpWidget(
        app(RollingNumerals(source: small, format: format3, size: size)),
      );
      final before = tester.getSize(find.byType(RollingNumerals));

      small.value = 987;
      await tester.pump();

      expect(tester.getSize(find.byType(RollingNumerals)), before);
    });

    testWidgets('is as wide as its digits, and as tall as two pitches', (
      tester,
    ) async {
      setWindow(tester, const Size(640, 360));
      final n = _Number(1);
      addTearDown(n.dispose);
      await tester.pumpWidget(
        app(RollingNumerals(source: n, format: format3, size: size)),
      );

      final box = tester.getSize(find.byType(RollingNumerals));
      final digit = render(tester).columnX(0) - render(tester).columnX(1);

      expect(box.width, closeTo(3 * digit, 0.01));
      expect(box.height, closeTo(NumeralMetrics(size).boxHeight, 1e-9));
      expect(digit, greaterThan(size * 0.6), reason: 'a wide numeral');
      expect(digit, lessThan(size * 0.9));
    });

    testWidgets(
      'digits step by one advance, right to left from the ones column',
      (tester) async {
        setWindow(tester, const Size(640, 360));
        final n = _Number(1);
        addTearDown(n.dispose);
        await tester.pumpWidget(
          app(RollingNumerals(source: n, format: format3, size: size)),
        );
        final r = render(tester);

        final step = r.columnX(0) - r.columnX(1);
        expect(r.columnX(1) - r.columnX(2), closeTo(step, 1e-9));
        expect(r.columnX(2), 0, reason: 'the leftmost digit starts the box');
        expect(r.columnX(0) + step, closeTo(box(tester).width, 0.01));
      },
    );

    testWidgets('decimals sit after a point, and the last is the ones column', (
      tester,
    ) async {
      setWindow(tester, const Size(640, 360));
      final n = _Number(12.3);
      addTearDown(n.dispose);
      await tester.pumpWidget(
        app(
          RollingNumerals(
            source: n,
            format: const NumeralFormat(integerDigits: 2, decimals: 1),
            size: size,
          ),
        ),
      );
      final r = render(tester);

      expect(
        r.columnX(0),
        greaterThan(r.columnX(1)),
        reason: 'the tenths are to the right',
      );
      expect(
        r.columnX(0) + (r.columnX(1) - r.columnX(2)),
        closeTo(box(tester).width, 0.01),
      );
      // The point takes room, but less than a digit.
      final pointGap =
          r.columnX(0) - r.columnX(1) - (r.columnX(1) - r.columnX(2));
      expect(pointGap, inExclusiveRange(0, size * 0.4));
    });

    testWidgets('the digits sit on a baseline a Row can align to', (
      tester,
    ) async {
      setWindow(tester, const Size(640, 360));
      final n = _Number(1);
      addTearDown(n.dispose);
      await tester.pumpWidget(
        app(RollingNumerals(source: n, format: format3, size: size)),
      );

      expect(
        render(tester).computeDistanceToActualBaseline(TextBaseline.alphabetic),
        closeTo(NumeralMetrics(size).baseline, 1e-9),
      );
    });

    testWidgets(
      'Indian grouping puts a separator after the third and every second digit',
      (tester) async {
        setWindow(tester, const Size(640, 360));
        final n = _Number(1);
        addTearDown(n.dispose);
        await tester.pumpWidget(
          app(
            RollingNumerals(
              source: n,
              format: const NumeralFormat(
                integerDigits: 7,
                grouping: DigitGrouping.indian,
              ),
              size: size,
            ),
          ),
        );
        final r = render(tester);

        // 12,34,567: separators between digits 3 and 2, and 5 and 4, and 7 and 6.
        final withSeparators = box(tester).width;
        final plain = 7 * (r.columnX(0) - r.columnX(1));
        expect(withSeparators, greaterThan(plain));
        expect(r.separatorX(3), greaterThan(r.columnX(3)));
        expect(r.separatorX(3), lessThanOrEqualTo(r.columnX(2)));
        expect(DigitGrouping.indian.separatorAfter(3), isTrue);
        expect(DigitGrouping.indian.separatorAfter(4), isFalse);
        expect(DigitGrouping.indian.separatorAfter(5), isTrue);
        expect(DigitGrouping.indian.separatorAfter(2), isFalse);
        expect(DigitGrouping.western.separatorAfter(3), isTrue);
        expect(DigitGrouping.western.separatorAfter(5), isFalse);
        expect(DigitGrouping.western.separatorAfter(6), isTrue);
        expect(DigitGrouping.none.separatorAfter(3), isFalse);
      },
    );
  });

  group('drawing', () {
    testWidgets('draws its digits in the accent, on the void', (tester) async {
      setWindow(tester, const Size(640, 360));
      final n = _Number(88);
      addTearDown(n.dispose);
      await tester.pumpWidget(
        app(RollingNumerals(source: n, format: format3, size: size)),
      );
      final pixels = await _Pixels.of(tester, await renderImage(tester));

      var accent = 0;
      for (var y = 0; y < pixels.height; y++) {
        for (var x = 0; x < pixels.width; x++) {
          if (pixels.rgba(x, y) == 0x5CE1FFFF) accent++;
        }
      }

      expect(pixels.rgba(0, 0), 0x050607FF, reason: 'the canvas is void');
      expect(accent, greaterThan(200), reason: 'solid ION accent pixels');
    });

    testWidgets('draws nothing until it has a value', (tester) async {
      setWindow(tester, const Size(640, 360));
      final n = _Number(88, has: false);
      addTearDown(n.dispose);
      await tester.pumpWidget(
        app(RollingNumerals(source: n, format: format3, size: size)),
      );
      final pixels = await _Pixels.of(tester, await renderImage(tester));

      expect(pixels.litIn(0, 0, pixels.width, pixels.height), 0);
    });

    testWidgets('draws each role in its colour', (tester) async {
      setWindow(tester, const Size(640, 360));
      for (final (role, colour) in [
        (NumeralRole.money, 0xF3CF86FF),
        (NumeralRole.bright, 0xE7ECF1FF),
        (NumeralRole.caution, 0xFFB020FF),
        (NumeralRole.critical, 0xFF3355FF),
      ]) {
        final n = _Number(88);
        await tester.pumpWidget(
          app(
            RollingNumerals(source: n, format: format3, size: size, role: role),
          ),
        );
        final pixels = await _Pixels.of(tester, await renderImage(tester));
        var found = 0;
        for (var y = 0; y < pixels.height; y++) {
          for (var x = 0; x < pixels.width; x++) {
            if (pixels.rgba(x, y) == colour) found++;
          }
        }
        expect(found, greaterThan(200), reason: role.name);
        n.dispose();
      }
    });

    testWidgets('a stale value fades to the stale colour', (tester) async {
      setWindow(tester, const Size(640, 360));
      final n = _Number(88);
      addTearDown(n.dispose);
      await tester.pumpWidget(
        app(RollingNumerals(source: n, format: format3, size: size)),
      );

      n.staleness = 1;
      await tester.pump();
      final pixels = await _Pixels.of(tester, await renderImage(tester));

      var stale = 0;
      var accent = 0;
      for (var y = 0; y < pixels.height; y++) {
        for (var x = 0; x < pixels.width; x++) {
          final p = pixels.rgba(x, y);
          if (p == 0x7A838FFF) stale++;
          if (p == 0x5CE1FFFF) accent++;
        }
      }
      expect(stale, greaterThan(200));
      expect(accent, 0);
    });

    testWidgets(
      'a negative value shows a minus sign when it is signed, and not otherwise',
      (tester) async {
        setWindow(tester, const Size(640, 360));
        final n = _Number(-42);
        addTearDown(n.dispose);

        await tester.pumpWidget(
          app(
            RollingNumerals(
              source: n,
              format: const NumeralFormat(integerDigits: 3, signed: true),
              size: size,
            ),
          ),
        );
        final signed = await _Pixels.of(tester, await renderImage(tester));

        await tester.pumpWidget(
          app(RollingNumerals(source: n, format: format3, size: size)),
        );
        final unsigned = await _Pixels.of(tester, await renderImage(tester));

        int lit(_Pixels p) => p.litIn(0, 0, p.width, p.height);
        expect(
          lit(signed),
          greaterThan(lit(unsigned)),
          reason: 'the sign is extra ink',
        );
      },
    );
  });

  group('anchoring (DESIGN.md 4.5)', () {
    testWidgets('the ones digit is drawn at the same place for 7, 77 and 107', (
      tester,
    ) async {
      setWindow(tester, const Size(640, 360));
      final n = _Number(7);
      addTearDown(n.dispose);
      await tester.pumpWidget(
        app(
          RollingNumerals(source: n, format: format3, size: size),
          alignment: Alignment.topLeft,
        ),
      );
      final r = render(tester);
      final dpr = tester.view.devicePixelRatio;
      final left = (r.columnX(0) * dpr).floor();
      final right = ((r.columnX(0) + (r.columnX(0) - r.columnX(1))) * dpr)
          .ceil();
      final top = 0;
      final bottom = (NumeralMetrics(size).boxHeight * dpr).ceil();

      final regions = <double, List<int>>{};
      for (final v in [7.0, 77.0, 107.0, 507.0]) {
        n.value = v;
        await tester.pump();
        final pixels = await _Pixels.of(tester, await renderImage(tester));
        regions[v] = pixels.region(left, top, right, bottom);
      }

      expect(regions[7.0], regions[77.0]);
      expect(regions[7.0], regions[107.0]);
      expect(regions[7.0], regions[507.0]);
      expect(
        regions[7.0]!.where((p) => p != 0x050607FF),
        isNotEmpty,
        reason: 'and it is really there',
      );
    });

    testWidgets('a digit and its neighbour stay put as the value climbs', (
      tester,
    ) async {
      setWindow(tester, const Size(640, 360));
      final n = _Number(100);
      addTearDown(n.dispose);
      await tester.pumpWidget(
        app(
          RollingNumerals(source: n, format: format3, size: size),
          alignment: Alignment.topLeft,
        ),
      );
      final r = render(tester);
      final dpr = tester.view.devicePixelRatio;
      // The hundreds digit does not move while the tens and ones roll from 100 to 199.
      final left = (r.columnX(2) * dpr).floor();
      final right = ((r.columnX(2) + (r.columnX(0) - r.columnX(1))) * dpr)
          .ceil();
      final bottom = (NumeralMetrics(size).boxHeight * dpr).ceil();

      final seen = <List<int>>[];
      for (final v in [100.0, 123.0, 150.0, 187.0, 199.0]) {
        n.value = v;
        await tester.pump();
        seen.add(
          (await _Pixels.of(
            tester,
            await renderImage(tester),
          )).region(left, 0, right, bottom),
        );
      }

      for (final region in seen.skip(1)) {
        expect(region, seen.first);
      }
    });
  });

  group('repainting (DESIGN.md 9.3)', () {
    testWidgets('a new value repaints and does not rebuild', (tester) async {
      setWindow(tester, const Size(640, 360));
      _Builds.count = 0;
      final n = _Number(10);
      addTearDown(n.dispose);
      await tester.pumpWidget(
        app(
          _Builds(
            child: RollingNumerals(source: n, format: format3, size: size),
          ),
        ),
      );
      final first = await _Pixels.of(tester, await renderImage(tester));
      expect(_Builds.count, 1);

      for (var v = 11.0; v < 60; v += 7) {
        n.value = v;
        await tester.pump();
      }
      final last = await _Pixels.of(tester, await renderImage(tester));

      expect(_Builds.count, 1, reason: 'no widget was rebuilt for data');
      expect(
        last.region(0, 0, last.width, last.height),
        isNot(first.region(0, 0, first.width, first.height)),
      );
    });

    testWidgets('it is its own repaint boundary', (tester) async {
      setWindow(tester, const Size(640, 360));
      final n = _Number(1);
      addTearDown(n.dispose);
      await tester.pumpWidget(
        app(RollingNumerals(source: n, format: format3, size: size)),
      );

      expect(render(tester).isRepaintBoundary, isTrue);
    });

    testWidgets('it lets go of its source when removed', (tester) async {
      setWindow(tester, const Size(640, 360));
      final n = _Number(1);
      addTearDown(n.dispose);
      await tester.pumpWidget(
        app(RollingNumerals(source: n, format: format3, size: size)),
      );
      expect(n.isListened, isTrue);

      await tester.pumpWidget(app(const SizedBox()));

      expect(n.isListened, isFalse);
    });

    testWidgets('changing the source moves the listener', (tester) async {
      setWindow(tester, const Size(640, 360));
      final a = _Number(1);
      final b = _Number(2);
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      await tester.pumpWidget(
        app(RollingNumerals(source: a, format: format3, size: size)),
      );
      await tester.pumpWidget(
        app(RollingNumerals(source: b, format: format3, size: size)),
      );

      expect(a.isListened, isFalse);
      expect(b.isListened, isTrue);
    });
  });

  group('halos (DESIGN.md 4.4 and 4.9)', () {
    Future<double> haloOf(
      WidgetTester tester,
      TapeThemeData theme, {
      double halo = TapeGlow.heroHalo,
    }) async {
      final n = _Number(88);
      addTearDown(n.dispose);
      await tester.pumpWidget(
        app(
          RollingNumerals(source: n, format: format3, size: size, halo: halo),
          theme: theme,
        ),
      );
      return render(tester).haloStrength;
    }

    testWidgets('a hero readout has a 30% halo', (tester) async {
      setWindow(tester, const Size(640, 360));

      expect(await haloOf(tester, TapeThemeData()), closeTo(0.30, 1e-9));
      expect(render(tester).hasHalo, isTrue);
    });

    testWidgets('Daylight turns it off, and Night halves it', (tester) async {
      setWindow(tester, const Size(640, 360));

      expect(await haloOf(tester, TapeThemeData(mode: TapeMode.daylight)), 0);
      expect(render(tester).hasHalo, isFalse);
      expect(
        await haloOf(tester, TapeThemeData(mode: TapeMode.night)),
        closeTo(0.15, 1e-9),
      );
    });

    testWidgets('MONO halos are at 40%', (tester) async {
      setWindow(tester, const Size(640, 360));

      expect(
        await haloOf(tester, TapeThemeData(livery: Liveries.mono)),
        closeTo(0.30 * 0.4, 1e-9),
      );
    });

    testWidgets('a readout that asks for none has none', (tester) async {
      setWindow(tester, const Size(640, 360));

      expect(await haloOf(tester, TapeThemeData(), halo: 0), 0);
      expect(render(tester).hasHalo, isFalse);
    });

    testWidgets('a halo adds light around the digits', (tester) async {
      setWindow(tester, const Size(640, 360));
      final n = _Number(88);
      addTearDown(n.dispose);
      await tester.pumpWidget(
        app(RollingNumerals(source: n, format: format3, size: size)),
      );
      final plain = await _Pixels.of(tester, await renderImage(tester));

      await tester.pumpWidget(
        app(RollingNumerals(source: n, format: format3, size: size, halo: 1)),
      );
      final glowing = await _Pixels.of(tester, await renderImage(tester));

      int lit(_Pixels p) => p.litIn(0, 0, p.width, p.height);
      expect(lit(glowing), greaterThan(lit(plain) * 1.2));
    });
  });

  group('the theme', () {
    testWidgets(
      'EMBER numerals are ember, and in Daylight they go ink.bright',
      (tester) async {
        setWindow(tester, const Size(640, 360));
        final n = _Number(88);
        addTearDown(n.dispose);

        int count(_Pixels p, int colour) {
          var c = 0;
          for (var y = 0; y < p.height; y++) {
            for (var x = 0; x < p.width; x++) {
              if (p.rgba(x, y) == colour) c++;
            }
          }
          return c;
        }

        await tester.pumpWidget(
          app(
            RollingNumerals(source: n, format: format3, size: size),
            theme: TapeThemeData(livery: Liveries.ember),
          ),
        );
        final normal = await _Pixels.of(tester, await renderImage(tester));
        expect(count(normal, 0xFF7A3DFF), greaterThan(200));

        await tester.pumpWidget(
          app(
            RollingNumerals(source: n, format: format3, size: size),
            theme: TapeThemeData(
              livery: Liveries.ember,
              mode: TapeMode.daylight,
            ),
          ),
        );
        final day = await _Pixels.of(tester, await renderImage(tester));
        expect(count(day, 0xE7ECF1FF), greaterThan(200));
        expect(count(day, 0xFF7A3DFF), 0);
      },
    );

    testWidgets('the weight follows the livery: MONO is lighter than EMBER', (
      tester,
    ) async {
      setWindow(tester, const Size(640, 360));
      final n = _Number(88);
      addTearDown(n.dispose);

      Future<int> ink(Livery livery) async {
        await tester.pumpWidget(
          app(
            RollingNumerals(source: n, format: format3, size: size),
            theme: TapeThemeData(livery: livery),
          ),
        );
        final p = await _Pixels.of(tester, await renderImage(tester));
        return p.litIn(0, 0, p.width, p.height);
      }

      final ember = await ink(Liveries.ember);
      final ion = await ink(Liveries.ion);
      final mono = await ink(Liveries.mono);

      expect(mono, lessThan(ion));
      expect(ion, lessThan(ember));
    });

    testWidgets('an atlas is built once per size and weight, and reused', (
      tester,
    ) async {
      setWindow(tester, const Size(640, 360));
      final n = _Number(88);
      addTearDown(n.dispose);

      await tester.pumpWidget(
        app(RollingNumerals(source: n, format: format3, size: size)),
      );
      final after = kit.atlases.length;
      n.value = 5;
      await tester.pump();
      await tester.pumpWidget(
        app(RollingNumerals(source: n, format: format3, size: size)),
      );

      expect(after, 1);
      expect(kit.atlases.length, 1);
    });
  });
}

Size box(WidgetTester tester) => tester.getSize(find.byType(RollingNumerals));
