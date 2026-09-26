import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/obd/transport/session_log.dart';

SessionEntry _e(int ms, SessionDirection d, String text) =>
    SessionEntry(Duration(milliseconds: ms), d, text);

void main() {
  group('escaping', () {
    test('printable ASCII is left alone', () {
      const text = 'ATZ 41 0C 1A F8 >?.,;:!"#\$%&\'()*+-/<=@[]^_{|}~';

      expect(SessionLog.escape(text), text);
    });

    test('carriage return, line feed and backslash are written out', () {
      expect(SessionLog.escape('a\rb\nc\\d'), r'a\rb\nc\\d');
    });

    test('other characters are hex escapes', () {
      expect(
        SessionLog.escape('\x00\x1B\x7F\x80\xFF'),
        r'\x00\x1B\x7F\x80\xFF',
      );
      // Written as code units: the formatter turns a \u escape in source into
      // the character, which would change what a raw string means.
      expect(SessionLog.escape(String.fromCharCode(0x20AC)), '\\u20AC');
      expect(
        SessionLog.escape(String.fromCharCodes([0xD83D, 0xDE00])),
        '\\uD83D\\uDE00',
      );
    });

    test('a trailing space is kept', () {
      expect(SessionLog.escape('41 0C 1A F8 '), '41 0C 1A F8 ');
    });

    test('an escaped string is always on one line', () {
      final all = String.fromCharCodes(List.generate(0x10000, (i) => i));

      expect(SessionLog.escape(all), isNot(contains('\n')));
      expect(SessionLog.escape(all), isNot(contains('\r')));
    });

    test('every character comes back from its escape', () {
      for (var unit = 0; unit <= 0xFFFF; unit++) {
        final text = String.fromCharCode(unit);
        expect(
          SessionLog.unescape(SessionLog.escape(text)),
          text,
          reason: 'U+${unit.toRadixString(16)}',
        );
      }
    });

    test('a surrogate pair comes back whole', () {
      const text = 'x\u{1F600}y';

      expect(SessionLog.unescape(SessionLog.escape(text)), text);
    });

    test('a broken escape is refused', () {
      for (final bad in [r'abc\', r'\q', r'\x4', r'\xZZ', r'\u12', r'\u12G4']) {
        expect(
          () => SessionLog.unescape(bad),
          throwsFormatException,
          reason: bad,
        );
      }
    });
  });

  group('format', () {
    test(
      'the first line says what it is, then the header, then the entries',
      () {
        const log = SessionLog(
          header: {'scenario': 'city_stop_go', 'seed': '1'},
          entries: [
            SessionEntry(Duration(seconds: 1), SessionDirection.sent, 'ATZ\r'),
          ],
        );

        expect(
          log.format(),
          '# tapedash-session v1\n'
          '# scenario: city_stop_go\n'
          '# seed: 1\n'
          '1.000 > ATZ\\r\n',
        );
      },
    );

    test('the example in the documentation is what it writes', () {
      final log = SessionLog(
        header: const {'scenario': 'city_stop_go'},
        entries: [
          _e(1000, SessionDirection.sent, 'ATZ\r'),
          _e(1000, SessionDirection.received, 'ATZ\r'),
          _e(1800, SessionDirection.received, '\r\rELM327 v1.5\r\n\r\n>'),
          _e(2010, SessionDirection.event, 'disconnected lost'),
        ],
      );

      expect(
        log.format(),
        '# tapedash-session v1\n'
        '# scenario: city_stop_go\n'
        '1.000 > ATZ\\r\n'
        '1.000 < ATZ\\r\n'
        '1.800 < \\r\\rELM327 v1.5\\r\\n\\r\\n>\n'
        '2.010 ! disconnected lost\n',
      );
    });

    test('times are seconds with three decimals', () {
      String time(Duration d) => SessionLog(
        entries: [SessionEntry(d, SessionDirection.event, 'x')],
      ).format().split('\n')[1].split(' ').first;

      expect(time(Duration.zero), '0.000');
      expect(time(const Duration(milliseconds: 5)), '0.005');
      expect(time(const Duration(milliseconds: 1234)), '1.234');
      expect(time(const Duration(minutes: 1, seconds: 1)), '61.000');
      expect(time(const Duration(hours: 1)), '3600.000');
      expect(time(const Duration(microseconds: 1999)), '0.001');
    });

    test('an empty log is just its first line', () {
      expect(const SessionLog().format(), '# tapedash-session v1\n');
    });
  });

  group('parse', () {
    final sample = SessionLog(
      header: const {'scenario': 'city_stop_go', 'profile': 'petrol_cvt_map'},
      entries: [
        _e(0, SessionDirection.event, 'connecting'),
        _e(400, SessionDirection.event, 'connected'),
        _e(1000, SessionDirection.sent, '010C1\r'),
        _e(1020, SessionDirection.received, '010C1\r'),
        _e(1040, SessionDirection.received, '41 0C 1A F8 \r\n'),
        _e(1040, SessionDirection.received, '\r\n>'),
        _e(1100, SessionDirection.received, 'ab\x00\xFF€\\ \r'),
        _e(90000, SessionDirection.sent, ' leading space'),
        _e(90001, SessionDirection.received, ''),
      ],
    );

    test('reading what was written gives it back', () {
      final back = SessionLog.parse(sample.format());

      expect(back.header, sample.header);
      expect(back.entries, sample.entries);
    });

    test('writing what was read gives the same text', () {
      final text = sample.format();

      expect(SessionLog.parse(text).format(), text);
    });

    test('a header value may contain a colon', () {
      final log = SessionLog.parse(
        '# tapedash-session v1\n# note: made at 12:30: cold\n',
      );

      expect(log.header, {'note': 'made at 12:30: cold'});
    });

    test('Windows line endings are accepted', () {
      final log = SessionLog.parse(sample.format().replaceAll('\n', '\r\n'));

      expect(log.entries, sample.entries);
      expect(log.header, sample.header);
    });

    test(
      'blank lines are skipped, and comments after the start are ignored',
      () {
        final log = SessionLog.parse(
          '# tapedash-session v1\n'
          '# scenario: a\n'
          '\n'
          '1.000 > ATI\\r\n'
          '# a comment: not a header\n'
          '\n'
          '1.010 < OK\n',
        );

        expect(log.header, {'scenario': 'a'});
        expect(log.entries.length, 2);
      },
    );

    test('an entry with no text is an empty string', () {
      final log = SessionLog.parse('# tapedash-session v1\n1.000 !\n');

      expect(log.entries.single, _e(1000, SessionDirection.event, ''));
    });

    test('only the marker\'s own space is dropped from the text', () {
      final log = SessionLog.parse('# tapedash-session v1\n1.000 >  two\n');

      expect(log.entries.single.text, ' two');
    });

    test('something that is not a session log is refused', () {
      for (final bad in [
        '',
        'hello',
        '1.000 > ATI\n',
        '# tapedash-session v2\n',
      ]) {
        expect(() => SessionLog.parse(bad), throwsFormatException, reason: bad);
      }
    });

    test('a bad entry is refused, and the message has its line number', () {
      for (final entry in [
        'hello',
        '1.5 > x',
        '1.000 ? x',
        'x.000 > x',
        '1.000 > bad\\q',
        '1.000 > cut\\x4',
      ]) {
        expect(
          () => SessionLog.parse('# tapedash-session v1\n$entry\n'),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('line 2'),
            ),
          ),
          reason: entry,
        );
      }
    });
  });
}
