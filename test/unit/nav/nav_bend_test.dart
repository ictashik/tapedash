import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/nav/nav_arrow.dart';
import 'package:tapedash/nav/nav_arrows.dart';
import 'package:tapedash/nav/nav_bend.dart';

NavArrow _real(String id, {int size = 126}) => NavArrow(
  id: id,
  width: size,
  height: size,
  alpha: File('test/fixtures/nav/arrows/$id.alpha').readAsBytesSync(),
);

void main() {
  group('the arrows Google Maps 25.33 drew', () {
    test('straight ahead is straight', () {
      expect(NavBendReader.of(_real('5c317d6e0e')), NavBend.straight);
    });

    test('a turn to the left is left', () {
      expect(NavBendReader.of(_real('5e259b7bb6')), NavBend.left);
    });

    test('a turn to the right is right', () {
      expect(NavBendReader.of(_real('e687a80d8d')), NavBend.right);
    });
  });

  group('the arrows Google Maps 26.42 drew (the human\'s phone, 135 px)', () {
    test('straight ahead, a turn left and a turn right', () {
      expect(
        NavBendReader.of(_real('762942fb95', size: 135)),
        NavBend.straight,
      );
      expect(NavBendReader.of(_real('3056e8deb3', size: 135)), NavBend.left);
      expect(NavBendReader.of(_real('26a50ee8c7', size: 135)), NavBend.right);
    });

    test('a sharp right is not read as a left turn', () {
      // The line leaning the wrong way would be worse than no lean: unknown draws it
      // straight, and Google\'s own arrow says "sharp right".
      final bend = NavBendReader.of(_real('3abbe8783c', size: 135));
      expect(bend, isNot(NavBend.left));
      expect(bend, NavBend.unknown);
    });
  });

  group('the arrows drawn in code', () {
    test('agree with the real ones about which way', () {
      expect(NavBendReader.of(NavArrows.forTurn(NavTurn.left)), NavBend.left);
      expect(NavBendReader.of(NavArrows.forTurn(NavTurn.right)), NavBend.right);
      expect(
        NavBendReader.of(NavArrows.forTurn(NavTurn.straight)),
        NavBend.straight,
      );
    });

    test('a U-turn and an arrival are not read as a turn or as straight', () {
      expect(
        NavBendReader.of(NavArrows.forTurn(NavTurn.uturn)),
        NavBend.unknown,
      );
      expect(
        NavBendReader.of(NavArrows.forTurn(NavTurn.arrive)),
        NavBend.unknown,
      );
    });
  });

  group('what it will not guess', () {
    NavArrow blank(int w, int h) =>
        NavArrow(id: 'blank$w', width: w, height: h, alpha: Uint8List(w * h));

    test('an empty picture is unknown', () {
      expect(NavBendReader.of(blank(126, 126)), NavBend.unknown);
    });

    test('a speck is unknown', () {
      final alpha = Uint8List(126 * 126);
      alpha[60 * 126 + 60] = 255;
      expect(
        NavBendReader.of(
          NavArrow(id: 'speck', width: 126, height: 126, alpha: alpha),
        ),
        NavBend.unknown,
      );
    });

    test('the same picture is read once, by its id', () {
      final a = _real('e687a80d8d');
      expect(identical(NavBendReader.of(a), NavBendReader.of(a)), isTrue);
    });
  });
}
