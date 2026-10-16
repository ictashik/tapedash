import 'adapter_quirks.dart';
import 'ecu.dart';
import 'sim_random.dart';
import 'simulated_car.dart';

/// One piece of what the adapter sends, and when.
class AdapterChunk {
  const AdapterChunk(this.after, this.text);

  /// When it goes out, counted from the moment the adapter started on the
  /// command. The echo is at zero; an answer comes later.
  final Duration after;
  final String text;

  @override
  String toString() => '${after.inMilliseconds}ms ${text.codeUnits}';
}

/// Everything the adapter sends in answer to one command line, in order.
class AdapterOutput {
  const AdapterOutput(this.chunks);

  final List<AdapterChunk> chunks;

  /// All of it as one string, as it would look once it had all arrived.
  String get text => chunks.map((c) => c.text).join();

  /// When the last of it goes out.
  Duration get duration => chunks.isEmpty ? Duration.zero : chunks.last.after;
}

/// An ELM327 adapter: it takes command lines and gives back the text a real one
/// sends (CLAUDE.md 7.4).
///
/// It does the adapter's job and nothing else: settings, the protocol search,
/// CAN formatting, error messages. The car's answers come from an [ObdEcu], and
/// the link's own latency is added by whatever carries the bytes.
///
/// **What it models.** ISO 15765-4 CAN at 500 kbaud, 11-bit (protocol 6, the
/// ECUs at 7E8, 7E9...) or 29-bit (protocol 7, at 18DAF110, 18DAF111...), with
/// one ECU or several. Every other protocol can be selected but the car does not
/// speak it, so the adapter reports what a real one would.
///
/// **More than one ECU.** Every ECU addressed answers. With headers on, each
/// frame is printed with its ECU's ID. When two ECUs answer with a message of
/// several frames, the adapter sends the flow control to one of them only, so
/// the other's message stops after its first frame: this is what the first real
/// recordings of a two-ECU car show (the first to answer is the one completed;
/// which of the two it is on a real car is not settled, and here it is the
/// first). `ATCRA` makes the adapter listen to one ECU, which then completes.
///
/// **Where the details come from.** The message formats and the AT commands are
/// from the ELM327 datasheet (ELM327DSJ v2.1). The datasheet is written for a
/// person at a terminal, so it does not settle a few byte-level conventions,
/// and these follow what real adapters are known to send. They are unverified
/// against hardware and are listed in `docs/DECISIONS.md`:
///  - the blank line before the prompt: every reply ends with an extra line
///    terminator and then `>`;
///  - the two `\r` before the banner after a reset;
///  - a space after the last byte of a data line when spaces are on, and a
///    space after the colon of a multi-frame line whatever the setting;
///  - `ATDP` naming the CAN protocols as `ISO 15765-4 (CAN 11/500)`.
///
/// **Timing.** The datasheet gives no figures, so how long the adapter takes is
/// an assumption: a reset takes 0.8 s, the search for a protocol 2.4 s, the ECU
/// answers in 20 ms, and adaptive timing waits 40 ms (AT1) or 25 ms (AT2) for
/// a second ECU that is not there. Without adaptive timing, or with a clone that
/// ignores it, the adapter waits its whole `ATST` timeout unless the request
/// says how many answers to expect.
class Elm327Simulator {
  Elm327Simulator({
    required this.ecu,
    this.extraEcus = const [],
    this.quirks = AdapterQuirks.none,
    this.version = 'ELM327 v1.5',
    this.linefeedsByDefault = true,
    this.carProtocol = 6,
    int seed = 1,
  }) : _random = SimRandom(seed).fork(3) {
    _restoreDefaults();
    _restoreProtocol();
  }

  /// An adapter on [car], with the ECUs and the protocol its profile has.
  factory Elm327Simulator.forCar(
    SimulatedCar car, {
    AdapterQuirks quirks = AdapterQuirks.none,
    String version = 'ELM327 v1.5',
    int seed = 1,
  }) {
    final ecus = SimulatedEcu.forCar(car);
    return Elm327Simulator(
      ecu: ecus.first,
      extraEcus: ecus.skip(1).toList(),
      quirks: quirks,
      version: version,
      carProtocol: car.profile.canProtocol,
      seed: seed,
    );
  }

  /// The car's first ECU, the one whose answer comes first.
  final ObdEcu ecu;

  /// The other ECUs on the bus, if the car has more than one. A request sent to
  /// the functional address reaches all of them, and each answers in its own
  /// frames.
  final List<ObdEcu> extraEcus;
  final AdapterQuirks quirks;

  /// What `ATZ` and `ATI` print.
  final String version;

  /// Whether the adapter ends lines with `\r\n` after a reset. The datasheet
  /// leaves it to a pin on the chip, and most adapters have it set.
  final bool linefeedsByDefault;

  /// The protocol the car speaks: 6, 11-bit CAN at 500 kbaud (the default), or
  /// 7, 29-bit CAN at 500 kbaud. These are the only two the simulator can
  /// answer on.
  final int carProtocol;

  final SimRandom _random;

  // Times. The datasheet gives none, so these are assumptions.
  static const Duration _resetTime = Duration(milliseconds: 800);
  static const Duration _warmStartTime = Duration(milliseconds: 250);
  static const Duration _ecuTime = Duration(milliseconds: 20);
  static const Duration _perFrameTime = Duration(milliseconds: 2);
  static const Duration _searchTime = Duration(milliseconds: 2400);
  static const Duration _quickConnectTime = Duration(milliseconds: 400);
  static const Duration _searchFailTime = Duration(seconds: 5);
  static const Duration _busInitFailTime = Duration(milliseconds: 2500);
  static const Duration _adaptiveWait1 = Duration(milliseconds: 40);
  static const Duration _adaptiveWait2 = Duration(milliseconds: 25);

  /// The protocols by number, as `ATDP` describes them.
  static const Map<int, String> protocolNames = {
    1: 'SAE J1850 PWM',
    2: 'SAE J1850 VPW',
    3: 'ISO 9141-2',
    4: 'ISO 14230-4 (KWP 5BAUD)',
    5: 'ISO 14230-4 (KWP FAST)',
    6: 'ISO 15765-4 (CAN 11/500)',
    7: 'ISO 15765-4 (CAN 29/500)',
    8: 'ISO 15765-4 (CAN 11/250)',
    9: 'ISO 15765-4 (CAN 29/250)',
    10: 'SAE J1939 (CAN 29/250)',
    11: 'USER1 (CAN 11/125)',
    12: 'USER2 (CAN 11/50)',
  };

  // The settings that ATZ, ATWS and ATD put back.
  late bool _echo;
  late bool _linefeeds;
  late bool _spaces;
  late bool _headers;
  late int _adaptiveTiming;
  late int _timeoutUnits;
  late String _header;
  String? _receiveFilter;
  late bool _allowLong;

  // Kept across ATZ, as the chip keeps them in its memory.
  bool _memory = true;
  int _storedProtocol = 0;
  bool _storedAuto = true;

  // The protocol setting: a number, and whether the adapter may search.
  int _protocol = 0;
  bool _auto = true;

  bool _connected = false;
  String? _lastCommand;

  /// Whether the adapter has a session open with the car.
  bool get isConnected => _connected;

  Duration get _timeout => Duration(milliseconds: _timeoutUnits * 4);

  String get _nl => _linefeeds ? '\r\n' : '\r';

  void _restoreDefaults() {
    _echo = true;
    _linefeeds = linefeedsByDefault;
    _spaces = true;
    _headers = false;
    _adaptiveTiming = 1;
    _timeoutUnits = 0x32;
    _header = _functionalHeader;
    _receiveFilter = null;
    _allowLong = false;
  }

  void _restoreProtocol() {
    _protocol = _storedProtocol;
    _auto = _storedAuto;
    _connected = false;
  }

  /// Runs one command line, given as the characters before its carriage
  /// return, and returns what the adapter sends back.
  AdapterOutput execute(String line) {
    // Every character is echoed as it arrives, so whether that happens depends
    // on the setting from before this command changes it.
    final echo = _echo ? '$line\r' : '';
    var command = _normalise(line);
    if (command.isEmpty) {
      // A lone carriage return repeats the last command.
      final last = _lastCommand;
      if (last == null) return _lines(echo, const []);
      command = last;
    } else {
      _lastCommand = command;
    }
    final reply = command.startsWith('AT')
        ? _runAt(command.substring(2), echo)
        : _runObd(command, echo);
    return _applyQuirks(reply, echo);
  }

  /// The adapter ignores spaces and case, and control characters.
  static String _normalise(String line) =>
      line.replaceAll(RegExp(r'[\s\x00]'), '').toUpperCase();

  // ------------------------------------------------------------ AT commands

  AdapterOutput _runAt(String command, String echo) {
    switch (command) {
      case 'Z':
        return _reset(echo, _resetTime);
      case 'WS':
        return _reset(echo, _warmStartTime);
      case 'D':
        _restoreDefaults();
        return _ok(echo);
      case 'E0':
      case 'E1':
        _echo = command == 'E1';
        return _ok(echo);
      case 'L0':
      case 'L1':
        _linefeeds = command == 'L1';
        return _ok(echo);
      case 'S0':
      case 'S1':
        _spaces = command == 'S1';
        return _ok(echo);
      case 'H0':
      case 'H1':
        _headers = command == 'H1';
        return _ok(echo);
      case 'M0':
      case 'M1':
        _memory = command == 'M1';
        return _ok(echo);
      case 'AL':
      case 'NL':
        _allowLong = command == 'AL';
        return _ok(echo);
      case 'FE':
      case 'BI':
        return _ok(echo);
      case 'PC':
        _connected = false;
        return _ok(echo);
      case 'AT0':
      case 'AT1':
      case 'AT2':
        _adaptiveTiming = int.parse(command.substring(2));
        return _ok(echo);
      case 'I':
        return _lines(echo, [version]);
      case '@1':
        return _lines(echo, ['OBDII to RS232 Interpreter']);
      case 'RV':
        return _lines(echo, ['${ecu.batteryVolts.toStringAsFixed(1)}V']);
      case 'DP':
        return _lines(echo, [_describeProtocol()]);
      case 'DPN':
        return _lines(echo, [_protocolNumber()]);
    }
    if (command.startsWith('SP')) {
      return _setProtocol(command, echo, save: true);
    }
    if (command.startsWith('TP')) {
      return _setProtocol(command, echo, save: false);
    }
    if (command.startsWith('ST')) {
      return _setTimeout(command.substring(2), echo);
    }
    if (command.startsWith('SH')) {
      return _setHeader(command.substring(2), echo);
    }
    if (command.startsWith('CRA')) {
      return _setReceiveFilter(command.substring(3), echo);
    }
    return _unknown(echo);
  }

  AdapterOutput _ok(String echo) => _lines(echo, const ['OK']);

  AdapterOutput _unknown(String echo) => _lines(echo, const ['?']);

  /// ATZ and ATWS: everything goes back to how it was at power-on, and the
  /// adapter says who it is. Two carriage returns come first.
  AdapterOutput _reset(String echo, Duration took) {
    _restoreDefaults();
    _restoreProtocol();
    final out = _Builder()
      ..add(Duration.zero, echo)
      ..add(took, '\r\r$version$_nl$_nl>');
    return out.build();
  }

  AdapterOutput _setProtocol(
    String command,
    String echo, {
    required bool save,
  }) {
    final argument = command.substring(2);
    final choice = _parseProtocol(argument);
    if (choice == null) return _unknown(echo);
    final (number, auto) = choice;
    _protocol = number;
    _auto = auto;
    _connected = false;
    if (save) {
      // SP 0 and SP A0 do not write to the memory, and SP 00 erases it.
      if (argument == '00') {
        _storedProtocol = 0;
        _storedAuto = true;
      } else if (number != 0) {
        _storedProtocol = number;
        _storedAuto = auto;
      }
    }
    return _ok(echo);
  }

  /// A protocol argument: `h` for one protocol only, `Ah` or `hA` to try it
  /// first and then search, and `0` to search from the start. `00` is also
  /// accepted, to erase the stored protocol.
  static (int, bool)? _parseProtocol(String argument) {
    if (argument == '0' || argument == '00') return (0, true);
    if (argument.length == 1) {
      final number = int.tryParse(argument, radix: 16);
      if (number == null || number < 1 || number > 12) return null;
      return (number, false);
    }
    if (argument.length == 2) {
      final String digit;
      if (argument[0] == 'A') {
        digit = argument[1];
      } else if (argument[1] == 'A') {
        digit = argument[0];
      } else {
        return null;
      }
      final number = int.tryParse(digit, radix: 16);
      if (number == null || number > 12) return null;
      return (number, true);
    }
    return null;
  }

  AdapterOutput _setTimeout(String argument, String echo) {
    final units = argument.length <= 2 && argument.isNotEmpty
        ? int.tryParse(argument, radix: 16)
        : null;
    if (units == null) return _unknown(echo);
    // Zero puts the default back.
    _timeoutUnits = units == 0 ? 0x32 : units;
    return _ok(echo);
  }

  AdapterOutput _setHeader(String argument, String echo) {
    final valid =
        RegExp(r'^[0-9A-F]+$').hasMatch(argument) &&
        (argument.length == 3 || argument.length == 6 || argument.length == 8);
    if (!valid) return _unknown(echo);
    _header = argument;
    return _ok(echo);
  }

  /// ATCRA with an ID makes the adapter show only the frames from that ID, and
  /// ATCRA alone puts every ECU back.
  AdapterOutput _setReceiveFilter(String argument, String echo) {
    if (quirks.noReceiveFilter) return _unknown(echo);
    if (argument.isEmpty) {
      _receiveFilter = null;
      return _ok(echo);
    }
    final valid =
        RegExp(r'^[0-9A-F]+$').hasMatch(argument) &&
        (argument.length == 3 || argument.length == 8);
    if (!valid) return _unknown(echo);
    _receiveFilter = argument;
    return _ok(echo);
  }

  String _protocolNumber() {
    final digit = _protocol.toRadixString(16).toUpperCase();
    return _auto ? 'A$digit' : digit;
  }

  String _describeProtocol() {
    if (_protocol == 0) return 'AUTO';
    final name = protocolNames[_protocol]!;
    return _auto ? 'AUTO, $name' : name;
  }

  // ---------------------------------------------------------- OBD requests

  AdapterOutput _runObd(String hex, String echo) {
    if (!RegExp(r'^[0-9A-F]+$').hasMatch(hex)) return _unknown(echo);

    // An odd number of digits means the last one is not part of the request:
    // it is how many answers to expect, so the adapter need not wait for more.
    var digits = hex;
    int? expected;
    if (digits.length.isOdd) {
      expected = int.parse(digits.substring(digits.length - 1), radix: 16);
      digits = digits.substring(0, digits.length - 1);
    }
    final request = <int>[
      for (var i = 0; i < digits.length; i += 2)
        int.parse(digits.substring(i, i + 2), radix: 16),
    ];
    // A CAN request is at most seven bytes unless long messages are allowed.
    if (request.isEmpty || (request.length > 7 && !_allowLong)) {
      return _unknown(echo);
    }
    // This clone does not pass on a request for several PIDs at once.
    if (quirks.noMultiPid && request.first == 0x01 && request.length > 2) {
      return _unknown(echo);
    }

    final out = _Builder()..add(Duration.zero, echo);
    final attempt = _connect();
    if (attempt.searching) out.add(Duration.zero, 'SEARCHING...$_nl');
    if (attempt.error != null) {
      return (out..add(attempt.took, '${attempt.error}$_nl$_nl>')).build();
    }

    // An ECU answers requests sent to it: to the functional address that every
    // ECU listens to, or to its own.
    final answers = <_Answer>[];
    for (final index in _addressedEcus()) {
      var payload = _bus[index].respond(request);
      if (payload != null &&
          quirks.noDataRate > 0 &&
          _random.chance(quirks.noDataRate)) {
        payload = null;
      }
      if (payload != null && _passesFilter(index)) {
        answers.add(_Answer(index, payload));
      }
    }
    if (answers.isEmpty) {
      // Nothing came back, so the adapter waited its whole timeout.
      return (out..add(attempt.took + _timeout, 'NO DATA$_nl$_nl>')).build();
    }

    // The flow control goes to the first ECU with a long message, and only to
    // it.
    var flowControlled = false;
    var frames = 1;
    for (final answer in answers) {
      final count = _isoTpFrames(answer.payload).length;
      if (count > 1 && !flowControlled) {
        flowControlled = answer.complete = true;
        frames = count > frames ? count : frames;
      }
    }
    final answered = attempt.took + _ecuTime + _perFrameTime * (frames - 1);
    out
      ..add(answered, _canLines(answers).map((l) => '$l$_nl').join())
      ..add(answered + _waitAfterAnswer(expected, answers.length), '$_nl>');
    return out.build();
  }

  // ------------------------------------------------------------------- the bus

  List<ObdEcu> get _bus => [ecu, ...extraEcus];

  bool get _is29Bit => carProtocol == 7 || carProtocol == 9;

  /// The header a request goes out with unless it is changed: the functional
  /// address, which every ECU listens to.
  String get _functionalHeader => _is29Bit ? 'DB33F1' : '7DF';

  /// The ID the ECU at [index] answers from.
  String _responseId(int index) => _is29Bit
      ? '18DAF1${_hexByte(0x10 + index)}'
      : (0x7E8 + index).toRadixString(16).toUpperCase();

  /// The header that addresses the ECU at [index] alone.
  String _physicalHeader(int index) => _is29Bit
      ? 'DA${_hexByte(0x10 + index)}F1'
      : (0x7E0 + index).toRadixString(16).toUpperCase();

  static String _hexByte(int value) =>
      value.toRadixString(16).toUpperCase().padLeft(2, '0');

  /// Which ECUs the current header reaches.
  List<int> _addressedEcus() {
    // A 29-bit header may be given with its leading 18, the priority byte.
    final header = _header.length == 8 && _header.startsWith('18')
        ? _header.substring(2)
        : _header;
    if (header == _functionalHeader) {
      return [for (var i = 0; i < _bus.length; i++) i];
    }
    for (var i = 0; i < _bus.length; i++) {
      if (header == _physicalHeader(i)) return [i];
    }
    return const [];
  }

  bool _passesFilter(int index) {
    if (_receiveFilter == null) return true;
    if (quirks.deadReceiveFilter) return false;
    return _receiveFilter == _responseId(index);
  }

  /// How long the adapter goes on listening after the answer, in case another
  /// ECU has more to say.
  Duration _waitAfterAnswer(int? expected, int answered) {
    if (expected != null && expected > 0 && answered >= expected) {
      return Duration.zero;
    }
    final adaptive = _adaptiveTiming != 0 && !quirks.ignoreAdaptiveTiming;
    if (adaptive && (expected == null || expected == 0)) {
      return _adaptiveTiming == 2 ? _adaptiveWait2 : _adaptiveWait1;
    }
    return _timeout;
  }

  /// Opens a session with the car if there is none, and says what happened.
  _Attempt _connect() {
    if (_connected) return const _Attempt(took: Duration.zero);
    final awake = ecu.isAwake;
    if (_auto) {
      if (!awake) {
        return const _Attempt(
          took: _searchFailTime,
          searching: true,
          error: 'UNABLE TO CONNECT',
        );
      }
      final quick = _protocol == carProtocol;
      _connected = true;
      _protocol = carProtocol;
      if (_memory) {
        _storedProtocol = carProtocol;
        _storedAuto = true;
      }
      return _Attempt(
        took: quick ? _quickConnectTime : _searchTime,
        searching: true,
      );
    }
    // Only this protocol will be tried.
    if (_protocol == carProtocol) {
      if (awake) {
        _connected = true;
        return const _Attempt(took: Duration.zero);
      }
      // Nobody on the bus acknowledges the request.
      return _Attempt(took: _timeout, error: 'CAN ERROR');
    }
    return switch (_protocol) {
      // These have to start a conversation, and the car does not answer.
      3 ||
      4 ||
      5 => const _Attempt(took: _busInitFailTime, error: 'BUS INIT: ...ERROR'),
      // 29-bit IDs on the right bus: the request is acknowledged, and ignored.
      1 || 2 || 7 => _Attempt(took: _timeout, error: 'NO DATA'),
      // Another bit rate: nothing on the bus can be received.
      _ => _Attempt(took: _timeout, error: 'CAN ERROR'),
    };
  }

  // -------------------------------------------------------- CAN formatting

  /// The lines the adapter prints for the ECUs' answers.
  ///
  /// With headers on, every frame has its ECU's ID in front, the first (or only)
  /// frame of each ECU first and then the later frames of the ECU that got flow
  /// control. With headers off, a message of one frame is its bytes; a longer one
  /// is its length, then the bytes in numbered lines (six in the first frame,
  /// seven in each one after it, the last padded), and the numbered lines after
  /// the first come once every ECU has begun.
  List<String> _canLines(List<_Answer> answers) {
    final first = <String>[];
    final later = <String>[];
    for (final answer in answers) {
      final payload = answer.payload;
      if (_headers) {
        final id = _spaces
            ? _spacedId(answer.index)
            : _responseId(answer.index);
        final frames = _isoTpFrames(payload);
        first.add('$id${_hex(frames.first)}');
        if (answer.complete) {
          later.addAll([for (final f in frames.skip(1)) '$id${_hex(f)}']);
        }
      } else if (payload.length <= 7) {
        first.add(_hex(payload));
      } else {
        final lines = _numberedLines(payload);
        first.addAll(lines.take(2));
        if (answer.complete) later.addAll(lines.skip(2));
      }
    }
    return [...first, ...later];
  }

  /// The ID with a space between its bytes, and one after.
  String _spacedId(int index) {
    final id = _responseId(index);
    if (!_is29Bit) return '$id ';
    return '${[for (var i = 0; i < id.length; i += 2) id.substring(i, i + 2)].join(' ')} ';
  }

  /// A message of several frames as the adapter prints it with headers off.
  List<String> _numberedLines(List<int> payload) {
    final lines = <String>[
      payload.length.toRadixString(16).toUpperCase().padLeft(3, '0'),
    ];
    var offset = 0;
    var sequence = 0;
    while (offset < payload.length) {
      final size = sequence == 0 ? 6 : 7;
      final end = offset + size < payload.length
          ? offset + size
          : payload.length;
      final bytes = payload.sublist(offset, end);
      while (bytes.length < size) {
        bytes.add(0);
      }
      final digit = (sequence & 0xF).toRadixString(16).toUpperCase();
      // A space follows the colon whether or not spaces are on: the datasheet's
      // example has one, and so does the other implementation checked against.
      lines.add('$digit: ${_hex(bytes)}');
      offset = end;
      sequence++;
    }
    return lines;
  }

  /// The CAN frames an ECU sends for a payload (ISO 15765-2), each padded to
  /// eight bytes: one single frame, or a first frame and consecutive frames.
  static List<List<int>> _isoTpFrames(List<int> payload) {
    List<int> padded(List<int> bytes) => [
      ...bytes,
      ...List<int>.filled(8 - bytes.length, 0),
    ];
    if (payload.length <= 7) {
      return [
        padded([payload.length, ...payload]),
      ];
    }
    final frames = <List<int>>[
      [0x10 | (payload.length >> 8), payload.length & 0xFF, ...payload.take(6)],
    ];
    var offset = 6;
    var sequence = 1;
    while (offset < payload.length) {
      final end = offset + 7 < payload.length ? offset + 7 : payload.length;
      frames.add(
        padded([0x20 | (sequence & 0xF), ...payload.sublist(offset, end)]),
      );
      offset = end;
      sequence++;
    }
    return frames;
  }

  /// Bytes as hex, with a space after each if spaces are on.
  String _hex(List<int> bytes) {
    final digits = [
      for (final b in bytes) b.toRadixString(16).toUpperCase().padLeft(2, '0'),
    ];
    return _spaces ? '${digits.join(' ')} ' : digits.join();
  }

  // ------------------------------------------------------------- assembling

  /// A reply of lines that arrives at once. After the lines comes a blank one,
  /// then the prompt; with nothing to say there is only the prompt.
  AdapterOutput _lines(String echo, List<String> lines) {
    final body = lines.isEmpty
        ? ''
        : '${lines.map((l) => '$l$_nl').join()}$_nl';
    return (_Builder()
          ..add(Duration.zero, echo)
          ..add(Duration.zero, '$body>'))
        .build();
  }

  /// What a flaky adapter does to a reply.
  AdapterOutput _applyQuirks(AdapterOutput reply, String echo) {
    var chunks = List<AdapterChunk>.of(reply.chunks);
    if (quirks.garbageRate > 0 && _random.chance(quirks.garbageRate)) {
      chunks = _withGarbage(chunks, echo);
    }
    if (quirks.missingPromptRate > 0 &&
        _random.chance(quirks.missingPromptRate) &&
        chunks.isNotEmpty) {
      final last = chunks.last;
      if (last.text.endsWith('>')) {
        chunks[chunks.length - 1] = AdapterChunk(
          last.after,
          last.text.substring(0, last.text.length - 1),
        );
      }
    }
    return AdapterOutput(chunks);
  }

  static const List<int> _garbage = [0x00, 0x1B, 0x7F, 0x80, 0xA0, 0xFF];

  /// A few stray bytes in the answer. They come after the echo, which is
  /// the adapter repeating what it was sent and so is never damaged.
  List<AdapterChunk> _withGarbage(List<AdapterChunk> chunks, String echo) {
    if (chunks.isEmpty) return chunks;
    var index = 0;
    var skip = 0;
    if (echo.isNotEmpty && chunks.first.text.startsWith(echo)) {
      if (chunks.first.text.length > echo.length) {
        skip = echo.length;
      } else if (chunks.length > 1) {
        index = 1;
      } else {
        skip = echo.length;
      }
    }
    final text = chunks[index].text;
    final at = skip + _random.nextInt(text.length - skip + 1);
    final stray = String.fromCharCodes([
      for (var i = 0, n = 1 + _random.nextInt(3); i < n; i++)
        _garbage[_random.nextInt(_garbage.length)],
    ]);
    return List<AdapterChunk>.of(chunks)
      ..[index] = AdapterChunk(
        chunks[index].after,
        '${text.substring(0, at)}$stray${text.substring(at)}',
      );
  }
}

/// One ECU's reply to a request.
class _Answer {
  _Answer(this.index, this.payload);

  /// Which ECU on the bus.
  final int index;
  final List<int> payload;

  /// Whether the adapter sent this ECU flow control, so that a message of
  /// several frames arrives whole.
  bool complete = false;
}

/// How an attempt to open a session with the car went.
class _Attempt {
  const _Attempt({required this.took, this.searching = false, this.error});

  /// How long it took, which is how long before the request itself can be
  /// answered, or before the error is printed.
  final Duration took;

  /// Whether the adapter printed `SEARCHING...`.
  final bool searching;

  /// What it printed instead of an answer, if it failed.
  final String? error;
}

/// Collects timed text, joining pieces that go out at the same time.
class _Builder {
  final List<AdapterChunk> _chunks = [];

  void add(Duration after, String text) {
    if (text.isEmpty) return;
    if (_chunks.isNotEmpty && _chunks.last.after == after) {
      final last = _chunks.removeLast();
      _chunks.add(AdapterChunk(after, last.text + text));
    } else {
      _chunks.add(AdapterChunk(after, text));
    }
  }

  AdapterOutput build() => AdapterOutput(List.unmodifiable(_chunks));
}
