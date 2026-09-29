/// Which field the numpad types into.
enum PitStopField { litres, amount }

/// What is wrong with a fill-up as typed (CLAUDE.md 8.5, DESIGN.md 7.9).
enum PitStopIssue {
  litresMissing,
  amountMissing,

  /// More than the tank could hold, by a margin.
  litresTooMany,

  /// A price per litre that no fuel costs.
  priceImplausible,
}

/// The state of the Pit Stop form (DESIGN.md 7.9): two numbers typed on a numpad,
/// and whether the tank was filled to the top. Pure logic, so the widget is only
/// drawing it and the rules are tested.
///
/// Typing is forgiving and never wrong: a second decimal point, a third decimal
/// digit, a leading zero and too many digits are ignored, so what is on screen is
/// always a number that can be saved.
class PitStopForm {
  PitStopForm({this.tankLitres = 40, this.priceOnly = false}) {
    if (priceOnly) active = PitStopField.amount;
  }

  /// The tank's capacity, for judging the litres.
  final double tankLitres;

  /// The form only sets the price of a litre (no fill-up is logged): the one
  /// field is the price, held in [amountText].
  final bool priceOnly;

  String litresText = '';
  String amountText = '';
  PitStopField active = PitStopField.litres;
  bool fullTank = true;

  static const int maxLitresInteger = 3;
  static const int maxAmountInteger = 6;
  static const int maxDecimals = 2;

  /// A tank can be estimated wrongly, and a fill-up is a little more than the
  /// gauge said: up to this many times the tank is accepted.
  static const double tankMargin = 1.25;

  /// The price per litre of any fuel is within these.
  static const double minPrice = 0.1;
  static const double maxPrice = 1000;

  String get _activeText =>
      active == PitStopField.litres ? litresText : amountText;

  set _activeText(String v) {
    if (active == PitStopField.litres) {
      litresText = v;
    } else {
      amountText = v;
    }
  }

  /// A key pressed on the numpad: a digit, '.', or 'back'.
  void press(String key) {
    final text = _activeText;
    if (key == 'back') {
      _activeText = text.isEmpty ? text : text.substring(0, text.length - 1);
      return;
    }
    final maxInteger = active == PitStopField.litres
        ? maxLitresInteger
        : maxAmountInteger;
    if (key == '.') {
      if (text.contains('.')) return;
      _activeText = text.isEmpty ? '0.' : '$text.';
      return;
    }
    if (key.length != 1 || !'0123456789'.contains(key)) return;
    final dot = text.indexOf('.');
    if (dot >= 0) {
      if (text.length - dot - 1 >= maxDecimals) return;
    } else {
      if (text == '0') {
        // No leading zeros: 0 then 5 is 5.
        _activeText = key;
        return;
      }
      if (text.length >= maxInteger) return;
    }
    _activeText = text + key;
  }

  void clear() {
    litresText = '';
    amountText = '';
  }

  double? get litres => double.tryParse(litresText);
  double? get amount => double.tryParse(amountText);

  /// What the fuel cost a litre, once both are typed.
  double? get pricePerLitre {
    final l = litres;
    final a = amount;
    if (priceOnly) return a;
    if (l == null || a == null || l <= 0) return null;
    return a / l;
  }

  /// What is wrong, in the order to say it. Empty means it can be saved.
  List<PitStopIssue> issues() {
    final out = <PitStopIssue>[];
    final l = litres;
    final a = amount;
    if (!priceOnly && (l == null || l <= 0)) {
      out.add(PitStopIssue.litresMissing);
    }
    if (a == null || a <= 0) out.add(PitStopIssue.amountMissing);
    if (!priceOnly && l != null && l > tankLitres * tankMargin) {
      out.add(PitStopIssue.litresTooMany);
    }
    final p = pricePerLitre;
    if (p != null && (p < minPrice || p > maxPrice)) {
      out.add(PitStopIssue.priceImplausible);
    }
    return out;
  }

  bool get canSave => issues().isEmpty;
}
