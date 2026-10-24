/// The exchange file's constants (docs/EXCHANGE.md).
abstract final class Tdx {
  /// The major version this code writes and the newest it reads.
  static const int version = 1;

  /// What the header says made it.
  static const String app = 'tapedash';

  /// A plain file, and a compressed one.
  static const String extension = 'tdx';
  static const String gzipExtension = 'tdx.gz';

  /// What is refused (docs/EXCHANGE.md 1): a file over this many bytes, one that
  /// expands past [maxExpandedBytes], a line over [maxLineBytes].
  static const int maxFileBytes = 256 << 20;
  static const int maxExpandedBytes = 512 << 20;
  static const int maxLineBytes = 4 << 20;

  /// A trip's samples are cut into lines of this many rows.
  static const int samplesPerLine = 2000;

  /// The columns of a `samples` line, in the order the writer gives them: seconds
  /// from the start, km/h, rpm, throttle %, litres an hour, latitude, longitude,
  /// load %, coolant °C and module volts.
  static const List<String> sampleColumns = [
    's',
    'kmh',
    'rpm',
    'thr',
    'lph',
    'lat',
    'lon',
    'load',
    'clt',
    'v',
  ];

  /// The columns a row cannot do without.
  static const Set<String> requiredColumns = {'s', 'kmh', 'rpm', 'thr', 'lph'};
}

/// What a file holds (docs/EXCHANGE.md 1, the header's `scopes`).
enum TdxScope {
  /// The portable setup: the car, the price, the adapter, the coach, the look.
  profile,

  /// Settings that belong to one screen: the HUD, the held fidelity tier, the
  /// engine sound. Never in a default export.
  device,

  /// Finished trips and their samples.
  trips,

  /// The fill-up log.
  fillups,

  /// The battery's resting voltage log.
  rest;

  /// The scopes of a default export: everything that is the same car's.
  static const Set<TdxScope> portable = {profile, trips, fillups, rest};

  /// The scope named [name], or null.
  static TdxScope? named(String name) {
    for (final s in values) {
      if (s.name == name) return s;
    }
    return null;
  }
}

/// Where a file was made.
class TdxDeviceInfo {
  const TdxDeviceInfo({required this.id, required this.kind, this.name = ''});

  /// A short random id for the install, so that two files from one device can be
  /// told from two from two.
  final String id;

  /// `phone` or `watch`.
  final String kind;

  final String name;

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind,
    if (name.isNotEmpty) 'name': name,
  };

  static TdxDeviceInfo fromJson(Object? json) {
    if (json is! Map) return const TdxDeviceInfo(id: '', kind: 'phone');
    return TdxDeviceInfo(
      id: json['id'] is String ? json['id'] as String : '',
      kind: json['kind'] == 'watch' ? 'watch' : 'phone',
      name: json['name'] is String ? json['name'] as String : '',
    );
  }
}
