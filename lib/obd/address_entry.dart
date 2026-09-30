/// What is typed for a WiFi adapter's address and port on the numpad (DESIGN.md
/// 7.11). Pure logic, so the screen only draws it. Typing is forgiving and never
/// wrong: a key that would make an impossible address is ignored, so what is on
/// screen is always the start of a real one.
class AddressEntry {
  AddressEntry({this.host = '', this.port = ''});

  /// The IPv4 address so far: up to four groups of up to three digits, with dots.
  String host;

  /// The port so far: up to five digits.
  String port;

  /// Which one the numpad types into.
  bool editingPort = false;

  /// A key from the numpad: a digit, '.', or 'back'.
  void press(String key) {
    if (editingPort) {
      _pressPort(key);
    } else {
      _pressHost(key);
    }
  }

  void _pressPort(String key) {
    if (key == 'back') {
      if (port.isNotEmpty) port = port.substring(0, port.length - 1);
      return;
    }
    if (key.length != 1 || !'0123456789'.contains(key)) return;
    if (port.length >= 5) return;
    if (port.isEmpty && key == '0') return; // no port starts with 0
    final next = port + key;
    if (int.parse(next) > 65535) return;
    port = next;
  }

  void _pressHost(String key) {
    if (key == 'back') {
      if (host.isNotEmpty) host = host.substring(0, host.length - 1);
      return;
    }
    if (key == '.') {
      if (host.isEmpty || host.endsWith('.')) return;
      if ('.'.allMatches(host).length >= 3) return;
      host += '.';
      return;
    }
    if (key.length != 1 || !'0123456789'.contains(key)) return;
    final groups = host.split('.');
    final last = groups.last;
    if (last.length >= 3) return;
    // No leading zeros, and no group over 255.
    if (last == '0') return;
    if (int.parse(last + key) > 255) return;
    host += key;
  }

  /// Whether [host] is a complete IPv4 address.
  bool get hostComplete {
    final groups = host.split('.');
    if (groups.length != 4) return false;
    return groups.every((g) {
      final n = int.tryParse(g);
      return n != null && n >= 0 && n <= 255;
    });
  }

  /// The port as a number, or null if none is typed.
  int? get portNumber => int.tryParse(port);

  bool get complete => hostComplete && portNumber != null;
}
