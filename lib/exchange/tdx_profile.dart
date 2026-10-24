/// The portable setup (docs/EXCHANGE.md 1, the `profile` line) and the settings that
/// belong to one screen (the `device` line), checked.
///
/// A profile is a nested map of plain values. [TdxProfile.clean] keeps what is
/// valid and drops, and says why, what is not: an unknown key, a value out of its
/// range, a name that is not one of the choices. It never throws, and it never
/// invents: a part that is missing stays missing and so is left as it is when the
/// profile is applied.
///
/// The names it allows are written out here, in a directory that may not import
/// the screens' enums. `test/unit/app/exchange_profile_test.dart` fails if they ever
/// differ from the enums they stand for.
abstract final class TdxProfile {
  static const List<String> fuelTypes = ['petrol', 'diesel'];
  static const List<String> blends = ['e0', 'e10', 'e20'];
  static const List<String> currencies = ['INR', 'USD', 'GBP'];
  static const List<String> adapterKinds = ['bluetoothClassic', 'ble', 'wifi'];
  static const List<String> sources = ['obd', 'gps'];
  static const List<String> presets = ['gentle', 'normal', 'sporty'];
  static const List<String> liveries = ['ion', 'ember', 'vfd', 'mono'];
  static const List<String> driverSides = ['left', 'right'];
  static const List<String> ignitions = ['off', 'subtle', 'full'];
  static const List<String> hudColors = ['green', 'ion', 'amber', 'white'];
  static const List<String> hudLayouts = ['drive', 'driveMoney', 'money'];
  static const List<String> tiers = ['lite', 'balanced', 'full'];
  static const List<String> modes = ['auto', 'normal', 'daylight', 'night'];

  /// The HUD's scale, as `TapeHud` allows it.
  static const double hudScaleMin = 0.6;
  static const double hudScaleMax = 1.4;

  /// The portable profile in [raw], cleaned.
  static CleanProfile cleanProfile(Object? raw) {
    final problems = <String>[];
    final out = <String, Object?>{};
    if (raw is! Map) {
      return CleanProfile(out, const ['the profile is not a map']);
    }
    final r = _Reader(raw, problems);

    final vehicle = r.section('vehicle');
    if (vehicle != null) {
      final v = <String, Object?>{};
      _put(v, 'fuelType', vehicle.choice('fuelType', fuelTypes));
      _put(v, 'displacementL', vehicle.number('displacementL', 0.3, 10));
      _put(v, 'tankL', vehicle.number('tankL', 5, 200));
      _put(v, 'blend', vehicle.choice('blend', blends));
      if (v.isNotEmpty) out['vehicle'] = v;
    }
    final money = r.section('money');
    if (money != null) {
      final m = <String, Object?>{};
      _put(m, 'pricePerLitre', money.number('pricePerLitre', 0.1, 10000));
      _put(m, 'currency', money.choice('currency', currencies));
      if (m.isNotEmpty) out['money'] = m;
    }
    if (raw.containsKey('adapter')) {
      final adapter = r.section('adapter');
      if (adapter != null) {
        final a = <String, Object?>{};
        final kind = adapter.choice('kind', adapterKinds);
        final address = adapter.text('address', 64);
        if (kind != null && address != null && address.isNotEmpty) {
          a['kind'] = kind;
          a['address'] = address;
          _put(a, 'name', adapter.text('name', 64));
          _put(a, 'port', adapter.integer('port', 1, 65535));
          out['adapter'] = a;
        } else {
          problems.add('the adapter has no kind or no address');
        }
      }
    }
    _put(out, 'source', r.choice('source', sources));
    final coach = r.section('coach');
    if (coach != null) {
      final c = <String, Object?>{};
      _put(c, 'preset', coach.choice('preset', presets));
      _put(c, 'speedLimitKmh', coach.number('speedLimitKmh', 30, 250));
      if (c.isNotEmpty) out['coach'] = c;
    }
    final look = r.section('look');
    if (look != null) {
      final l = <String, Object?>{};
      _put(l, 'livery', look.choice('livery', liveries));
      _put(l, 'driverSide', look.choice('driverSide', driverSides));
      _put(l, 'cluster', look.integer('cluster', 0, 4));
      _put(l, 'ignition', look.choice('ignition', ignitions));
      _put(l, 'reduceMotion', look.flag('reduceMotion'));
      if (l.isNotEmpty) out['look'] = l;
    }
    return CleanProfile(out, problems);
  }

  /// The device-specific settings in [raw], cleaned.
  static CleanProfile cleanDevice(Object? raw) {
    final problems = <String>[];
    final out = <String, Object?>{};
    if (raw is! Map) {
      return CleanProfile(out, const ['the settings are not a map']);
    }
    final r = _Reader(raw, problems);

    final hud = r.section('hud');
    if (hud != null) {
      final h = <String, Object?>{};
      _put(h, 'color', hud.choice('color', hudColors));
      _put(h, 'layout', hud.choice('layout', hudLayouts));
      _put(h, 'flipH', hud.flag('flipH'));
      _put(h, 'flipV', hud.flag('flipV'));
      _put(h, 'position', hud.number('position', -1, 1));
      _put(h, 'scale', hud.number('scale', hudScaleMin, hudScaleMax));
      if (h.isNotEmpty) out['hud'] = h;
    }
    _put(out, 'tier', r.choice('tier', tiers));
    _put(out, 'mode', r.choice('mode', modes));
    final sound = r.section('sound');
    if (sound != null) {
      final s = <String, Object?>{};
      _put(s, 'enabled', sound.flag('enabled'));
      _put(s, 'profile', sound.text('profile', 32));
      _put(s, 'volume', sound.number('volume', 0, 1));
      _put(s, 'speaker', sound.flag('speaker'));
      if (s.isNotEmpty) out['sound'] = s;
    }
    _put(out, 'compatibility', r.flag('compatibility'));
    _put(out, 'recordSessions', r.flag('recordSessions'));
    return CleanProfile(out, problems);
  }

  static void _put(Map<String, Object?> into, String key, Object? value) {
    if (value != null) into[key] = value;
  }
}

/// A profile with only what was valid, and the reasons for what was dropped.
class CleanProfile {
  const CleanProfile(this.values, this.problems);

  final Map<String, Object?> values;
  final List<String> problems;

  bool get isEmpty => values.isEmpty;
}

/// Reads one map of a profile, noting what it cannot use.
class _Reader {
  _Reader(this._map, this._problems, [this._path = '']);

  final Map<Object?, Object?> _map;
  final List<String> _problems;
  final String _path;

  String _name(String key) => _path.isEmpty ? key : '$_path.$key';

  _Reader? section(String key) {
    final v = _map[key];
    if (v == null) return null;
    if (v is! Map) {
      _problems.add('${_name(key)} is not a map');
      return null;
    }
    return _Reader(v, _problems, _name(key));
  }

  String? choice(String key, List<String> allowed) {
    final v = _map[key];
    if (v == null) return null;
    if (v is String && allowed.contains(v)) return v;
    _problems.add('${_name(key)} is not one of ${allowed.join(', ')}');
    return null;
  }

  double? number(String key, num lo, num hi) {
    final v = _map[key];
    if (v == null) return null;
    if (v is num && v.isFinite && v >= lo && v <= hi) return v.toDouble();
    _problems.add('${_name(key)} is not a number from $lo to $hi');
    return null;
  }

  int? integer(String key, int lo, int hi) {
    final v = _map[key];
    if (v == null) return null;
    if (v is int && v >= lo && v <= hi) return v;
    if (v is double && v.isFinite && v == v.roundToDouble()) {
      final n = v.toInt();
      if (n >= lo && n <= hi) return n;
    }
    _problems.add('${_name(key)} is not a whole number from $lo to $hi');
    return null;
  }

  bool? flag(String key) {
    final v = _map[key];
    if (v == null) return null;
    if (v is bool) return v;
    _problems.add('${_name(key)} is not true or false');
    return null;
  }

  String? text(String key, int longest) {
    final v = _map[key];
    if (v == null) return null;
    if (v is String && v.length <= longest) return v;
    _problems.add('${_name(key)} is not text of at most $longest characters');
    return null;
  }
}
