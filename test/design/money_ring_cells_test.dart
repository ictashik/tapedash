// The money ring's cells (DESIGN.md 16.5): one a rupee until the ring is full, then
// packed into the smallest cell of 2, 5, 10... that fits, each showing the bucket
// most of its rupees fell in.
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/ui/design/components/money.dart';
import 'package:tapedash/ui/design/components/watch/money_ring.dart';
import 'package:tapedash/ui/design/tokens/watch.dart';

List<MoneyBlock> blocks(int n, [MoneyBucket b = MoneyBucket.normal]) => [
  for (var i = 0; i < n; i++) MoneyBlock(b),
];

void main() {
  const full = TapeWatch.moneyCells;

  test('no blocks is no cells, at ₹1 a cell, with nothing to say', () {
    final c = MoneyRingCells.of(const []);
    expect(c.cells, isEmpty);
    expect(c.scale, 1);
    expect(c.scaleLabel, isNull);
  });

  test('up to a full ring each rupee is one cell', () {
    for (final n in [1, 5, full]) {
      final c = MoneyRingCells.of(blocks(n));
      expect(c.scale, 1, reason: '$n');
      expect(c.cells.length, n);
      expect(c.scaleLabel, isNull);
    }
  });

  test('one rupee over a full ring packs the cells into ₹2', () {
    final c = MoneyRingCells.of(blocks(full + 1));
    expect(c.scale, 2);
    expect(c.cells.length, 37);
    expect(c.cells.length, lessThanOrEqualTo(full));
    expect(c.scaleLabel, '1 block = ₹2');
  });

  test('the scale steps through 2, 5, 10, 20, 50, 100 and always fits', () {
    final seen = <int>{};
    for (var n = 1; n <= 20000; n += 37) {
      final c = MoneyRingCells.of(blocks(n));
      expect(c.cells.length, lessThanOrEqualTo(full), reason: '$n');
      expect(c.cells.length, (n / c.scale).ceil(), reason: '$n');
      seen.add(c.scale);
    }
    expect(seen, containsAll([1, 2, 5, 10, 20, 50, 100, 200, 500]));
  });

  test('a packed cell shows the bucket most of its rupees fell in', () {
    // 80 blocks pack into ₹2 cells: [n, i] [i, i] ...
    final list = <MoneyBlock>[
      for (var i = 0; i < 80; i++)
        MoneyBlock(i < 40 ? MoneyBucket.normal : MoneyBucket.idling),
    ];
    final c = MoneyRingCells.of(list);
    expect(c.scale, 2);
    expect(c.cells.first, MoneyBucket.normal);
    expect(c.cells.last, MoneyBucket.idling);
  });

  test('on a tie the bucket worth noticing wins', () {
    final list = <MoneyBlock>[
      for (var i = 0; i < 80; i++)
        MoneyBlock(
          i.isEven ? MoneyBucket.normal : MoneyBucket.hardAcceleration,
        ),
    ];
    final c = MoneyRingCells.of(list);
    expect(c.scale, 2);
    expect(c.cells.every((b) => b == MoneyBucket.hardAcceleration), isTrue);
  });

  test('the cells are in the order the rupees were spent', () {
    final list = [
      MoneyBlock(MoneyBucket.normal),
      MoneyBlock(MoneyBucket.idling),
      MoneyBlock(MoneyBucket.highSpeed),
      MoneyBlock(MoneyBucket.hardAcceleration),
    ];
    expect(MoneyRingCells.of(list).cells, [
      MoneyBucket.normal,
      MoneyBucket.idling,
      MoneyBucket.highSpeed,
      MoneyBucket.hardAcceleration,
    ]);
  });
}
