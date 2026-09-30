import 'dart:convert';

import 'dtc.dart';

/// Plain-English descriptions of fault codes, from the bundled `assets/dtc/dtc.json`
/// (written from scratch; see `assets/dtc/SOURCE.md`).
///
/// A code that is not in the file is never given a guessed description: it is said
/// to belong to a system, and, if it is one a car maker defines for itself, that
/// its meaning is the maker's.
class DtcDescriptions {
  const DtcDescriptions(this._byCode);

  /// The descriptions in [json], an object of code to text.
  factory DtcDescriptions.parse(String json) {
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    return DtcDescriptions({
      for (final e in decoded.entries) e.key.toUpperCase(): e.value as String,
    });
  }

  /// No descriptions at all: every code is described by its system.
  static const DtcDescriptions empty = DtcDescriptions({});

  final Map<String, String> _byCode;

  int get length => _byCode.length;

  /// The description of [dtc]: its own line, or what can be said of any code
  /// like it.
  String describe(Dtc dtc) => _byCode[dtc.code] ?? generic(dtc);

  /// Whether [dtc] has a description of its own.
  bool knows(Dtc dtc) => _byCode.containsKey(dtc.code);

  /// What is true of every code like [dtc]: its system, and whether the code is
  /// one every car shares or one the maker defines.
  static String generic(Dtc dtc) {
    final system = switch (dtc.system) {
      DtcSystem.powertrain => 'engine or transmission',
      DtcSystem.chassis => 'brakes, steering or suspension',
      DtcSystem.body => 'body electrics or airbags',
      DtcSystem.network => 'communication between the car\'s computers',
    };
    // The second character says who defines the code: 0 is the standard's own for
    // every system, and so is 2 for the powertrain; the rest are the maker's.
    final digit = dtc.code[1];
    final standard =
        digit == '0' || (dtc.system == DtcSystem.powertrain && digit == '2');
    return standard
        ? 'A fault in the $system. Its exact wording is in a workshop manual.'
        : 'A fault in the $system, in a code the car maker defines. '
              'Its meaning is in the maker\'s manual for this car.';
  }
}
