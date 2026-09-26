/// Whether a fault code is stored (Mode 03) or only pending (Mode 07).
enum DtcKind { stored, pending }

/// A fault code that appears in the car's memory part way through a drive
/// (CLAUDE.md 7.3), such as `P0420`.
class DtcInjection {
  const DtcInjection({
    required this.at,
    required this.code,
    this.kind = DtcKind.stored,
  });

  /// When it appears, from the start of the drive.
  final Duration at;

  /// A code such as P0420, C0300, B1000 or U0100.
  final String code;

  final DtcKind kind;
}

/// Something that goes wrong with the adapter link at a set time, whatever the
/// adapter's usual quirks (CLAUDE.md 7.3, `adapter_flaky`).
sealed class AdapterFault {
  const AdapterFault({required this.at});

  /// When it happens, from the start of the drive.
  final Duration at;
}

/// The link drops at [at] and comes back after [outage]. Until then, trying to
/// connect fails.
class AdapterDisconnect extends AdapterFault {
  const AdapterDisconnect({required super.at, required this.outage});

  final Duration outage;
}
