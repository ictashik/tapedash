import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/obd/elm327/elm327_client.dart';
import 'package:tapedash/obd/elm327/elm327_init.dart';
import 'package:tapedash/obd/transport/sim_transport.dart';
import 'package:tapedash/obd/transport/transport.dart';
import 'package:tapedash/sim/adapter_quirks.dart';
import 'package:tapedash/sim/profiles.dart';
import 'package:tapedash/sim/scenarios.dart';
import 'package:tapedash/sim/simulated_car.dart';

import '../../../support/fake_transport.dart';
import '../../../support/scripted_adapter.dart';

Duration ms(int n) => Duration(milliseconds: n);

/// The replies of an adapter that behaves, on protocol 6, to a car with the
/// PIDs of `98 3B 80 01`, `00 02 00 01` and `40 00 00 00`.
Map<String, List<Say?>> _good({bool searching = true}) => {
  'ATZ': [const Say('ATZ\r\r\rELM327 v1.5\r\n\r\n>', afterMs: 800)],
  'ATE0': [const Say('ATE0\rOK\r\n\r\n>')],
  'ATL0': [Say.ok('OK')],
  'ATS0': [Say.ok('OK')],
  'ATH0': [Say.ok('OK')],
  'ATAT1': [Say.ok('OK')],
  'ATSP0': [Say.ok('OK')],
  'ATSP6': [Say.ok('OK')],
  '0100': [
    searching
        ? Say.ok('SEARCHING...\r41 00 98 3B 80 01 ', afterMs: 2400)
        : Say.ok('41 00 98 3B 80 01 '),
  ],
  '0120': [Say.ok('41 20 00 02 00 01 ')],
  '0140': [Say.ok('41 40 40 00 00 00 ')],
  'ATDPN': [Say.ok('A6')],
};

const _goodPids = {
  0x01, 0x04, 0x05, 0x0B, 0x0C, 0x0D, 0x0F, 0x10, 0x11, //
  0x2F,
  0x42,
};

class _Rig {
  _Rig(
    Map<String, List<Say?>> script, {
    InitOptions options = const InitOptions(),
  }) {
    transport = FakeTransport(clock: clock);
    client = Elm327Client(transport: transport, scheduler: clock, clock: clock);
    adapter = ScriptedAdapter(transport, clock, script);
    initializer = Elm327Initializer(
      client: client,
      scheduler: clock,
      options: options,
    );
  }

  final clock = FakeClock();
  late final FakeTransport transport;
  late final Elm327Client client;
  late final ScriptedAdapter adapter;
  late final Elm327Initializer initializer;
  final List<InitResult> results = [];

  InitResult get result => results.single;

  /// Runs the start-up until it is done, and says how long it took.
  Duration run({
    bool probeOnly = false,
    Duration limit = const Duration(minutes: 5),
  }) {
    initializer.run(results.add, probeOnly: probeOnly);
    while (results.isEmpty && clock.monotonic() < limit) {
      clock.advance(ms(10));
    }
    return clock.monotonic();
  }

  void close() {
    initializer.cancel();
    client.dispose();
    transport.dispose();
  }
}

void main() {
  group('an adapter that behaves', () {
    test('is started up with the commands of CLAUDE.md 8.1, in order', () {
      final rig = _Rig(_good());
      addTearDown(rig.close);

      rig.run();

      expect(rig.adapter.commands, [
        'ATZ',
        'ATE0',
        'ATL0',
        'ATS0',
        'ATH0',
        'ATAT1',
        'ATSP0',
        '0100',
        '0120',
        '0140',
        'ATDPN',
      ]);
    });

    test('and is ready, with what was found', () {
      final rig = _Rig(_good());
      addTearDown(rig.close);

      rig.run();

      expect(rig.result.status, InitStatus.ready);
      final info = rig.result.info!;
      expect(info.banner, 'ELM327 v1.5');
      expect(info.protocolNumber, '6');
      expect(info.isCan, isTrue);
      expect(info.supportedPids, _goodPids);
      expect(info.ecuCount, 1);
      expect(info.retries, 0);
      expect(info.warnings, isEmpty);
    });

    test(
      'after the settle delay, so the first command is not written at once',
      () {
        final rig = _Rig(_good());
        addTearDown(rig.close);

        rig.run();

        expect(rig.transport.writeTimes.first, ms(300));
      },
    );

    test('the settle can be changed', () {
      final rig = _Rig(
        _good(),
        options: const InitOptions(settle: Duration(seconds: 1)),
      );
      addTearDown(rig.close);

      rig.run();

      expect(rig.transport.writeTimes.first, ms(1000));
    });

    test('and takes as long as the adapter does', () {
      final rig = _Rig(_good());
      addTearDown(rig.close);

      final took = rig.run();

      // 0.3 s settle, 0.8 s reset, the search's 2.4 s, and a few small ones.
      expect(took.inMilliseconds, inInclusiveRange(3500, 4500));
    });

    test('a callback only once', () {
      final rig = _Rig(_good());
      addTearDown(rig.close);

      rig.run();
      rig.clock.advance(const Duration(minutes: 1));

      expect(rig.results.length, 1);
    });

    test('the protocol is read as A6 or as 6', () {
      for (final (said, want) in [
        ('A6', '6'),
        ('6', '6'),
        ('A0', '0'),
        ('3', '3'),
        ('B', 'B'),
      ]) {
        final script = _good()..['ATDPN'] = [Say.ok(said)];
        final rig = _Rig(script);

        rig.run();

        expect(rig.result.info!.protocolNumber, want, reason: said);
        rig.close();
      }
    });

    test('only protocols 6 to 9 are CAN', () {
      for (final (number, can) in [
        ('6', true),
        ('7', true),
        ('8', true),
        ('9', true),
        ('3', false),
        ('5', false),
        ('A', false),
        ('1', false),
      ]) {
        final script = _good()..['ATDPN'] = [Say.ok('A$number')];
        final rig = _Rig(script);

        rig.run();

        expect(rig.result.info!.isCan, can, reason: number);
        rig.close();
      }
    });

    test('with echo still on for everything, as a clone might', () {
      final script = <String, List<Say?>>{
        'ATZ': [const Say('ATZ\r\r\rELM327 v1.5\r\n\r\n>', afterMs: 800)],
        'ATE0': [const Say('ATE0\rOK\r\n\r\n>')],
        'ATL0': [const Say('ATL0\rOK\r\n\r\n>')],
        'ATS0': [const Say('ATS0\rOK\r\n\r\n>')],
        'ATH0': [const Say('ATH0\rOK\r\n\r\n>')],
        'ATAT1': [const Say('ATAT1\rOK\r\n\r\n>')],
        'ATSP0': [const Say('ATSP0\rOK\r\n\r\n>')],
        '0100': [
          const Say(
            '0100\rSEARCHING...\r\n41 00 98 3B 80 01 \r\n\r\n>',
            afterMs: 2400,
          ),
        ],
        '0120': [const Say('0120\r41 20 00 02 00 01 \r\n\r\n>')],
        '0140': [const Say('0140\r41 40 40 00 00 00 \r\n\r\n>')],
        'ATDPN': [const Say('ATDPN\rA6\r\n\r\n>')],
      };
      final rig = _Rig(script);
      addTearDown(rig.close);

      rig.run();

      expect(rig.result.isReady, isTrue);
      expect(rig.result.info!.supportedPids, _goodPids);
      expect(rig.result.info!.warnings, isEmpty);
    });

    test('two ECUs are counted', () {
      final script = _good()
        ..['0100'] = [
          Say.ok('41 00 98 3B 80 01 \r41 00 80 00 00 00 ', afterMs: 2400),
        ];
      final rig = _Rig(script);
      addTearDown(rig.close);

      rig.run();

      expect(rig.result.info!.ecuCount, 2);
    });
  });

  group('a protocol remembered from last time', () {
    test('is set directly, and the search is skipped', () {
      final script = _good(searching: false);
      final rig = _Rig(script, options: const InitOptions(knownProtocol: '6'));
      addTearDown(rig.close);

      final took = rig.run();

      expect(rig.adapter.commands, contains('ATSP6'));
      expect(rig.adapter.commands, isNot(contains('ATSP0')));
      expect(rig.result.isReady, isTrue);
      expect(took, lessThan(ms(2500)));
    });
  });

  group('the remembered protocol, with a script that knows it', () {
    Map<String, List<Say?>> script() => {
      ..._good(),
      'ATSP3': [Say.ok('OK')],
      '0100': [
        Say.ok('BUS INIT: ...ERROR', afterMs: 2500),
        Say.ok('SEARCHING...\r41 00 98 3B 80 01 ', afterMs: 2400),
      ],
    };

    test('a wrong one is replaced by a search, with a note', () {
      final rig = _Rig(
        script(),
        options: const InitOptions(knownProtocol: '3'),
      );
      addTearDown(rig.close);

      rig.run();

      expect(rig.adapter.commands.where((c) => c.startsWith('ATSP')), [
        'ATSP3',
        'ATSP0',
      ]);
      expect(rig.result.isReady, isTrue);
      expect(rig.result.info!.warnings, [
        'the remembered protocol did not work',
      ]);
    });

    test(
      'a wrong one with the ignition off too is waiting for the ignition',
      () {
        final s = script()
          ..['0100'] = [
            Say.ok('BUS INIT: ...ERROR', afterMs: 2500),
            Say.ok('SEARCHING...\rUNABLE TO CONNECT', afterMs: 5000),
          ];
        final rig = _Rig(s, options: const InitOptions(knownProtocol: '3'));
        addTearDown(rig.close);

        rig.run();

        expect(rig.result.status, InitStatus.waitingForIgnition);
      },
    );
  });

  group('the car does not answer', () {
    test(
      'UNABLE TO CONNECT is waiting for the ignition, with the adapter set up',
      () {
        final script = _good()
          ..['0100'] = [
            Say.ok('SEARCHING...\rUNABLE TO CONNECT', afterMs: 5000),
          ];
        final rig = _Rig(script);
        addTearDown(rig.close);

        rig.run();

        expect(rig.result.status, InitStatus.waitingForIgnition);
        expect(rig.result.isReady, isFalse);
        expect(rig.result.info!.banner, 'ELM327 v1.5');
        expect(rig.result.info!.supportedPids, isEmpty);
        expect(rig.result.failure, isNull);
      },
    );

    test('so are NO DATA, CAN ERROR and a K-line that will not start', () {
      for (final text in [
        'NO DATA',
        'CAN ERROR',
        'BUS INIT: ...ERROR',
        'BUS BUSY',
      ]) {
        final script = _good()..['0100'] = [Say.ok(text, afterMs: 200)];
        final rig = _Rig(script);

        rig.run();

        expect(rig.result.status, InitStatus.waitingForIgnition, reason: text);
        rig.close();
      }
    });

    test(
      'then a probe, without the set-up, finds it when the ignition is on',
      () {
        final script = _good()
          ..['0100'] = [
            Say.ok('SEARCHING...\rUNABLE TO CONNECT', afterMs: 5000),
            Say.ok('SEARCHING...\r41 00 98 3B 80 01 ', afterMs: 2400),
          ];
        final rig = _Rig(script);
        addTearDown(rig.close);
        rig.run();
        expect(rig.result.status, InitStatus.waitingForIgnition);
        rig.adapter.commands.clear();
        rig.results.clear();
        final probe = Elm327Initializer(
          client: rig.client,
          scheduler: rig.clock,
        );

        probe.run(rig.results.add, probeOnly: true);
        while (rig.results.isEmpty) {
          rig.clock.advance(ms(10));
        }

        expect(rig.adapter.commands, ['0100', '0120', '0140', 'ATDPN']);
        expect(rig.result.isReady, isTrue);
        expect(rig.result.info!.supportedPids, _goodPids);
      },
    );

    test(
      'a timeout on the first request is tried again, twice, then it is a failure',
      () {
        final script = _good()..['0100'] = [Say.silence];
        final rig = _Rig(script);
        addTearDown(rig.close);

        final took = rig.run();

        expect(rig.adapter.commands.where((c) => c == '0100').length, 3);
        expect(rig.result.status, InitStatus.failed);
        expect(rig.result.failure, InitFailure.noResponse);
        // Three waits of 12 s.
        expect(took, greaterThan(const Duration(seconds: 36)));
      },
    );

    test(
      'noise in the first answer is tried again, and is not the car saying no',
      () {
        final script = _good()
          ..['0100'] = [
            Say.ok('41 00 98 3\x7FB 80 01 ', afterMs: 2400),
            Say.ok('41 00 98 3B 80 01 '),
          ];
        final rig = _Rig(script);
        addTearDown(rig.close);

        rig.run();

        expect(rig.result.isReady, isTrue);
        expect(rig.result.info!.retries, 1);
        expect(rig.adapter.commands.where((c) => c == '0100').length, 2);
      },
    );

    test('STOPPED is tried again too', () {
      final script = _good()
        ..['0100'] = [Say.ok('STOPPED'), Say.ok('41 00 98 3B 80 01 ')];
      final rig = _Rig(script);
      addTearDown(rig.close);

      rig.run();

      expect(rig.result.isReady, isTrue);
    });

    test(
      'an adapter that resets itself is started up again from the beginning',
      () {
        final script = _good()
          ..['0100'] = [Say.ok('LV RESET'), Say.ok('41 00 98 3B 80 01 ')];
        final rig = _Rig(script);
        addTearDown(rig.close);

        rig.run();

        expect(rig.adapter.commands.where((c) => c == 'ATZ').length, 2);
        expect(rig.result.isReady, isTrue);
        expect(rig.result.info!.warnings, ['the adapter reset itself']);
      },
    );

    test('one that keeps resetting is a failure', () {
      final script = _good()..['0100'] = [Say.ok('LV RESET')];
      final rig = _Rig(script);
      addTearDown(rig.close);

      rig.run();

      expect(rig.adapter.commands.where((c) => c == 'ATZ').length, 2);
      expect(rig.result.failure, InitFailure.noResponse);
    });

    test('a PID search cut short is ready, with a note', () {
      final script = _good()..['0120'] = [Say.ok('NO DATA')];
      final rig = _Rig(script);
      addTearDown(rig.close);

      rig.run();

      expect(rig.result.isReady, isTrue);
      expect(rig.result.info!.warnings, ['the PID search was cut short']);
      expect(rig.result.info!.supportedPids, {
        0x01, 0x04, 0x05, 0x0B, 0x0C, 0x0D, 0x0F, 0x10, 0x11, //
      });
    });

    test('? for 0100 is an adapter that will not do', () {
      final script = _good()..['0100'] = [Say.ok('?')];
      final rig = _Rig(script);
      addTearDown(rig.close);

      rig.run();

      expect(rig.result.failure, InitFailure.incompatible);
    });
  });

  group('a settings command that goes wrong', () {
    test('a reply that is not OK is tried again', () {
      final script = _good()..['ATL0'] = [Say.ok('O\x7FK'), Say.ok('OK')];
      final rig = _Rig(script);
      addTearDown(rig.close);

      rig.run();

      expect(rig.adapter.commands.where((c) => c == 'ATL0').length, 2);
      expect(rig.result.isReady, isTrue);
      expect(rig.result.info!.retries, 1);
      expect(rig.result.info!.warnings, isEmpty);
    });

    test('a lost one is tried again after the timeout', () {
      final script = _good()..['ATS0'] = [Say.silence, Say.ok('OK')];
      final rig = _Rig(script);
      addTearDown(rig.close);

      final took = rig.run();

      expect(rig.result.isReady, isTrue);
      expect(rig.result.info!.retries, 1);
      expect(took, greaterThan(const Duration(seconds: 5)));
    });

    test(
      'echo, linefeeds and spaces that will not switch off are only a warning',
      () {
        for (final command in ['ATE0', 'ATL0', 'ATS0']) {
          final script = _good()..[command] = [Say.ok('?')];
          final rig = _Rig(script);

          rig.run();

          expect(rig.result.isReady, isTrue, reason: command);
          expect(rig.result.info!.warnings, [
            '$command is not understood',
          ], reason: command);
          expect(rig.result.info!.retries, 0, reason: 'a ? is not tried again');
          rig.close();
        }
      },
    );

    test('adaptive timing that is not understood is only a warning', () {
      final script = _good()..['ATAT1'] = [Say.ok('?')];
      final rig = _Rig(script);
      addTearDown(rig.close);

      rig.run();

      expect(rig.result.isReady, isTrue);
      expect(rig.result.info!.warnings, ['ATAT1 is not understood']);
    });

    test('one that never works is a warning, after the retries', () {
      final script = _good()..['ATL0'] = [Say.ok('junk\x7F')];
      final rig = _Rig(script);
      addTearDown(rig.close);

      rig.run();

      expect(rig.adapter.commands.where((c) => c == 'ATL0').length, 3);
      expect(rig.result.isReady, isTrue);
      expect(rig.result.info!.retries, 2);
      expect(rig.result.info!.warnings, ['ATL0 was not answered']);
    });

    test('headers that will not switch off end it: they cannot be read', () {
      final script = _good()..['ATH0'] = [Say.ok('?')];
      final rig = _Rig(script);
      addTearDown(rig.close);

      rig.run();

      expect(rig.result.status, InitStatus.failed);
      expect(rig.result.failure, InitFailure.incompatible);
      expect(rig.adapter.commands, isNot(contains('0100')));
    });

    test('a protocol that will not be taken ends it', () {
      final script = _good()..['ATSP0'] = [Say.ok('?')];
      final rig = _Rig(script);
      addTearDown(rig.close);

      rig.run();

      expect(rig.result.failure, InitFailure.incompatible);
    });

    test('a remembered protocol that is not understood ends it too', () {
      final script = _good()..['ATSP6'] = [Say.ok('?')];
      final rig = _Rig(script, options: const InitOptions(knownProtocol: '6'));
      addTearDown(rig.close);

      rig.run();

      expect(rig.result.failure, InitFailure.incompatible);
    });

    test('the number of retries can be changed', () {
      final script = _good()..['ATH0'] = [Say.ok('junk\x7F')];
      final rig = _Rig(script, options: const InitOptions(retries: 0));
      addTearDown(rig.close);

      rig.run();

      expect(rig.adapter.commands.where((c) => c == 'ATH0').length, 1);
      expect(rig.result.status, InitStatus.failed);
      expect(rig.result.failure, InitFailure.noResponse);
    });
  });

  group('the reset', () {
    test('a lost one is sent again after 4 s, and the retry is counted', () {
      final script = _good()
        ..['ATZ'] = [
          Say.silence,
          const Say('ATZ\r\r\rELM327 v1.5\r\n\r\n>', afterMs: 800),
        ];
      final rig = _Rig(script);
      addTearDown(rig.close);

      rig.run();

      expect(rig.result.isReady, isTrue);
      expect(rig.result.info!.retries, 1);
      // 0.3 s settle, 4 s wait, 0.1 s settle after a timeout.
      expect(rig.transport.writeTimes[1], ms(300 + 4000 + 100));
    });

    test('one that never answers is a failure after three tries', () {
      final script = _good()..['ATZ'] = [Say.silence];
      final rig = _Rig(script);
      addTearDown(rig.close);

      final took = rig.run();

      expect(rig.adapter.commands, ['ATZ', 'ATZ', 'ATZ']);
      expect(rig.result.status, InitStatus.failed);
      expect(rig.result.failure, InitFailure.noResponse);
      expect(took, greaterThan(const Duration(seconds: 12)));
    });

    test('an empty banner is not an answer', () {
      final script = _good()
        ..['ATZ'] = [Say.ok('ATZ'), const Say('ATZ\r\r\rELM327 v2.1\r\n\r\n>')];
      final rig = _Rig(script);
      addTearDown(rig.close);

      rig.run();

      expect(rig.result.info!.banner, 'ELM327 v2.1');
      expect(rig.result.info!.retries, 1);
    });

    test('a clone\'s odd banner is kept as it is', () {
      final script = _good()
        ..['ATZ'] = [const Say('ATZ\r\r\rELM327 v1.5 (clone)\r\n\r\n>')];
      final rig = _Rig(script);
      addTearDown(rig.close);

      rig.run();

      expect(rig.result.info!.banner, 'ELM327 v1.5 (clone)');
    });
  });

  group('the protocol number', () {
    test('ATDP is asked if ATDPN is not known', () {
      final script = _good()
        ..['ATDPN'] = [Say.ok('?')]
        ..['ATDP'] = [Say.ok('ISO 15765-4 (CAN 11/500)')];
      final rig = _Rig(script);
      addTearDown(rig.close);

      rig.run();

      expect(rig.result.info!.protocolNumber, '6');
      expect(rig.result.info!.isCan, isTrue);
      expect(rig.adapter.commands.last, 'ATDP');
    });

    test('if it cannot be found out, it is unknown, and not taken as CAN', () {
      final script = _good()
        ..['ATDPN'] = [Say.ok('?')]
        ..['ATDP'] = [Say.ok('?')];
      final rig = _Rig(script);
      addTearDown(rig.close);

      rig.run();

      expect(rig.result.isReady, isTrue);
      expect(rig.result.info!.protocolNumber, isNull);
      expect(rig.result.info!.isCan, isFalse);
      expect(rig.result.info!.warnings, [
        'the adapter would not say which protocol it uses',
      ]);
    });
  });

  group('the link going', () {
    test('during the settings ends it', () {
      final script = _good();
      final rig = _Rig(script);
      addTearDown(rig.close);
      rig.initializer.run(rig.results.add);

      rig.clock.advance(ms(1300));
      rig.transport.setState(
        const TransportState.disconnected(failure: TransportFailure.lost),
      );

      expect(rig.result.status, InitStatus.failed);
      expect(rig.result.failure, InitFailure.linkLost);
    });

    test('during the search ends it', () {
      final rig = _Rig(_good());
      addTearDown(rig.close);
      rig.initializer.run(rig.results.add);
      while (!rig.adapter.commands.contains('0100')) {
        rig.clock.advance(ms(10));
      }

      rig.transport.setState(const TransportState.disconnected());

      expect(rig.result.failure, InitFailure.linkLost);
    });

    test('at once, if there is no link to start with', () {
      final rig = _Rig(_good());
      addTearDown(rig.close);
      rig.transport.setState(const TransportState.disconnected());

      rig.run();

      expect(rig.result.failure, InitFailure.linkLost);
    });
  });

  group('cancelling', () {
    test('stops the start-up without a word', () {
      final rig = _Rig(_good());
      addTearDown(rig.close);
      rig.initializer.run(rig.results.add);
      rig.clock.advance(ms(1500));
      final written = rig.adapter.commands.length;

      rig.initializer.cancel();
      rig.clock.advance(const Duration(minutes: 1));

      expect(rig.results, isEmpty);
      expect(rig.adapter.commands.length, written, reason: 'not one more');
    });

    test('before the settle is up writes nothing', () {
      final rig = _Rig(_good());
      addTearDown(rig.close);
      rig.initializer.run(rig.results.add);

      rig.initializer.cancel();
      rig.clock.advance(const Duration(seconds: 10));

      expect(rig.adapter.commands, isEmpty);
      expect(rig.results, isEmpty);
    });
  });

  group('against the simulated cars', () {
    /// A car on a simulated link, and a client on it.
    ({
      FakeClock clock,
      SimulatedCar car,
      SimTransport transport,
      Elm327Client client,
      void Function() close,
    })
    setUp(String profile, AdapterQuirks quirks, {int seed = 1}) {
      final clock = FakeClock();
      final car = SimulatedCar(
        scenario: DriveScenarios.cityStopGo,
        profile: VehicleProfiles.byName(profile),
        scheduler: clock,
        seed: seed,
      )..start();
      final transport = SimTransport(
        car: car,
        scheduler: clock,
        quirks: quirks,
        seed: seed,
      );
      transport.connect().catchError((Object _) {});
      clock.advance(const Duration(seconds: 1));
      // Let the car start, so that the ignition is on.
      clock.advance(const Duration(seconds: 5));
      final client = Elm327Client(
        transport: transport,
        scheduler: clock,
        clock: clock,
      );
      return (
        clock: clock,
        car: car,
        transport: transport,
        client: client,
        close: () {
          client.dispose();
          car.stop();
          transport.dispose();
        },
      );
    }

    InitResult start(
      ({
        FakeClock clock,
        SimulatedCar car,
        SimTransport transport,
        Elm327Client client,
        void Function() close,
      })
      rig, {
      InitOptions options = const InitOptions(),
    }) {
      InitResult? result;
      Elm327Initializer(
        client: rig.client,
        scheduler: rig.clock,
        options: options,
      ).run((r) => result = r);
      final limit = rig.clock.monotonic() + const Duration(minutes: 3);
      while (result == null && rig.clock.monotonic() < limit) {
        rig.clock.advance(ms(10));
      }
      return result!;
    }

    for (final profile in VehicleProfiles.all) {
      test('${profile.name}: ready, with exactly its PIDs', () {
        final rig = setUp(profile.name, AdapterQuirks.none);
        addTearDown(rig.close);

        final result = start(rig);

        expect(result.isReady, isTrue);
        expect(result.info!.supportedPids, {0x01, ...profile.supportedPids});
        expect(result.info!.protocolNumber, '6');
        expect(result.info!.isCan, isTrue);
        expect(result.info!.banner, 'ELM327 v1.5');
        expect(result.info!.warnings, isEmpty);
        expect(result.info!.retries, 0);
      });
    }

    test('a Bluetooth clone that ignores adaptive timing is no harder', () {
      final rig = setUp('petrol_cvt_maf', AdapterQuirks.bluetoothClone);
      addTearDown(rig.close);

      final result = start(rig);

      expect(result.isReady, isTrue);
      expect(result.info!.retries, 0);
    });

    test('a clone that loses its first command costs one retry', () {
      final rig = setUp(
        'petrol_cvt_maf',
        AdapterQuirks.bluetoothClone.copyWith(dropFirstCommand: true),
      );
      addTearDown(rig.close);

      final result = start(rig);

      expect(result.isReady, isTrue);
      expect(result.info!.retries, 1);
    });

    test('a remembered protocol saves the search', () {
      final rig = setUp('petrol_cvt_maf', AdapterQuirks.none);
      addTearDown(rig.close);
      final started = rig.clock.monotonic();

      final result = start(rig, options: const InitOptions(knownProtocol: '6'));

      expect(result.isReady, isTrue);
      expect(rig.clock.monotonic() - started, lessThan(ms(2500)));
    });

    test('a wrong remembered protocol is found out and replaced', () {
      final rig = setUp('petrol_cvt_maf', AdapterQuirks.none);
      addTearDown(rig.close);

      final result = start(rig, options: const InitOptions(knownProtocol: '3'));

      expect(result.isReady, isTrue);
      expect(result.info!.protocolNumber, '6');
      expect(result.info!.warnings, ['the remembered protocol did not work']);
    });

    test(
      'a flaky adapter gets there nearly every time, and is never wrong',
      () {
        var ready = 0;
        var waiting = 0;
        for (var seed = 1; seed <= 40; seed++) {
          final rig = setUp('petrol_cvt_maf', AdapterQuirks.flaky, seed: seed);

          final result = start(rig);

          if (result.isReady) {
            ready++;
            expect(result.info!.supportedPids, {
              0x01,
              ...VehicleProfiles.petrolCvtMaf.supportedPids,
            }, reason: 'seed $seed');
          } else {
            expect(
              result.status,
              InitStatus.waitingForIgnition,
              reason: 'seed $seed: ${result.detail}',
            );
            waiting++;
          }
          rig.close();
        }

        // A random NO DATA at the wrong moment looks like an ECU that is off;
        // the session probes again a moment later.
        expect(ready, greaterThanOrEqualTo(30));
        expect(ready + waiting, 40);
      },
    );

    test(
      'an ECU that is off is waited for, and found when the ignition goes on',
      () {
        // The car is at the start of a cold start: ignition off.
        final clock = FakeClock();
        final car = SimulatedCar(
          scenario: DriveScenarios.coldStartIdle,
          scheduler: clock,
        );
        final transport = SimTransport(car: car, scheduler: clock);
        transport.connect().catchError((Object _) {});
        clock.advance(const Duration(seconds: 1));
        final client = Elm327Client(
          transport: transport,
          scheduler: clock,
          clock: clock,
        );
        addTearDown(() {
          client.dispose();
          car.stop();
          transport.dispose();
        });
        InitResult? result;

        Elm327Initializer(
          client: client,
          scheduler: clock,
        ).run((r) => result = r);
        while (result == null) {
          clock.advance(ms(10));
        }
        expect(result!.status, InitStatus.waitingForIgnition);

        // Turn the ignition on, and probe.
        car.start();
        clock.advance(const Duration(seconds: 3));
        result = null;
        Elm327Initializer(
          client: client,
          scheduler: clock,
        ).run((r) => result = r, probeOnly: true);
        while (result == null) {
          clock.advance(ms(10));
        }

        expect(result!.isReady, isTrue);
        expect(result!.info!.supportedPids, {
          0x01,
          ...VehicleProfiles.petrolCvtMaf.supportedPids,
        });
      },
    );
  });
}
