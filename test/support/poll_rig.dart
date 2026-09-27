import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/obd/elm327/elm327_client.dart';
import 'package:tapedash/obd/poller.dart';
import 'package:tapedash/sim/adapter_quirks.dart';
import 'package:tapedash/sim/elm327_device.dart';
import 'package:tapedash/sim/elm327_simulator.dart';

import 'fake_transport.dart';
import 'table_ecu.dart';

/// The data of a car that answers every PID of CLAUDE.md 8.3.
Map<int, List<int>> fullCar() => {
  0x04: [0x3F], // load 24.7 %
  0x05: [0x7B], // coolant 83 C
  0x0B: [0x21], // MAP 33 kPa
  0x0C: [0x1A, 0xF8], // 1726 rpm
  0x0D: [0x32], // 50 km/h
  0x0F: [0x41], // intake air 25 C
  0x10: [0x03, 0xE8], // MAF 10 g/s
  0x11: [0x33], // throttle 20 %
  0x2F: [0xB2], // fuel level 69.8 %
  0x42: [0x37, 0x14], // 14.1 V
};

/// A poller on a simulated adapter with a table-driven ECU, on a fake clock:
/// the real client, the real adapter formatting and timing, and an ECU that a
/// test controls.
class PollRig {
  PollRig({
    Map<int, List<int>>? data,
    AdapterQuirks quirks = AdapterQuirks.none,
    bool isCan = true,
    PollConfig config = const PollConfig(),
    bool demandStandard = true,
    int seed = 1,
  }) {
    ecu = TableEcu(data ?? fullCar());
    transport = FakeTransport(clock: clock);
    simulator = Elm327Simulator(ecu: ecu, quirks: quirks, seed: seed);
    // The adapter is set up the way start-up leaves it: protocol 6, echo, line
    // feeds, spaces and headers off.
    for (final c in ['ATSP6', 'ATE0', 'ATL0', 'ATS0', 'ATH0']) {
      simulator.execute(c);
    }
    device = Elm327Device(
      simulator: simulator,
      scheduler: clock,
      seed: seed,
      onOutput: transport.receive,
    )..linkOpened();
    transport.onCommand = (line) => device.receive('$line\r');
    client = Elm327Client(transport: transport, scheduler: clock, clock: clock);
    poller = Poller(
      client: client,
      scheduler: clock,
      clock: clock,
      supported: ecu.data.keys.toSet(),
      isCan: isCan,
      config: config,
      onReading: readings.add,
    );
    if (demandStandard) {
      poller.demand(Poller.standardTiers(ecu.data.keys.toSet()));
    }
  }

  final clock = FakeClock();
  late final TableEcu ecu;
  late final FakeTransport transport;
  late final Elm327Simulator simulator;
  late final Elm327Device device;
  late final Elm327Client client;
  late final Poller poller;
  final List<PidReading> readings = [];

  void run(int seconds) => clock.advance(Duration(seconds: seconds));

  void runMs(int millis) => clock.advance(Duration(milliseconds: millis));

  /// How many readings of [pid] there have been.
  int count(int pid) => readings.where((r) => r.pid.id == pid).length;

  /// The requests that reached the ECU.
  List<List<int>> get requests => ecu.requests;

  void close() {
    poller.stop();
    client.dispose();
    transport.dispose();
  }
}
