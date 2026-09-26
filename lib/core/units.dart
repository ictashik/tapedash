/// Kilometres in one mile. Exact by definition.
const double kmPerMile = 1.609344;

/// Litres in one US gallon. Exact by definition.
const double litresPerUsGallon = 3.785411784;

/// Litres in one imperial gallon. Exact by definition.
const double litresPerImperialGallon = 4.54609;

/// km/h to m/s, for the vehicle model's physics.
double kmhToMs(double kmh) => kmh / 3.6;

/// m/s to km/h.
double msToKmh(double ms) => ms * 3.6;

// TapeDash keeps every value in one canonical unit and converts only to show
// it: speed in km/h (what OBD-II reports), distance in km, volume in litres,
// fuel economy in km/L and temperature in degrees Celsius. The enums below are
// the units a user can choose to see them in (DESIGN.md 7.8, "Units and
// format"). A `symbol` reads like text, and a `label` is the uppercase form
// used on instruments (DESIGN.md 10).

/// A unit of speed.
enum SpeedUnit {
  kmh('km/h', 1),
  mph('mph', 1 / kmPerMile);

  const SpeedUnit(this.symbol, this._perKmh);

  final String symbol;
  final double _perKmh;

  String get label => symbol.toUpperCase();

  double fromKmh(double kmh) => kmh * _perKmh;

  double toKmh(double value) => value / _perKmh;
}

/// A unit of distance.
enum DistanceUnit {
  km('km', 1),
  mi('mi', 1 / kmPerMile);

  const DistanceUnit(this.symbol, this._perKm);

  final String symbol;
  final double _perKm;

  String get label => symbol.toUpperCase();

  double fromKm(double km) => km * _perKm;

  double toKm(double value) => value / _perKm;
}

/// A unit of fuel volume.
enum VolumeUnit {
  litre('L', 1),
  usGallon('gal', 1 / litresPerUsGallon),
  imperialGallon('gal', 1 / litresPerImperialGallon);

  const VolumeUnit(this.symbol, this._perLitre);

  final String symbol;
  final double _perLitre;

  String get label => symbol.toUpperCase();

  double fromLitres(double litres) => litres * _perLitre;

  double toLitres(double value) => value / _perLitre;
}

/// A unit of temperature.
enum TemperatureUnit {
  celsius('°C'),
  fahrenheit('°F');

  const TemperatureUnit(this.symbol);

  final String symbol;

  String get label => symbol;

  double fromCelsius(double celsius) => switch (this) {
    TemperatureUnit.celsius => celsius,
    TemperatureUnit.fahrenheit => celsius * 9 / 5 + 32,
  };

  double toCelsius(double value) => switch (this) {
    TemperatureUnit.celsius => value,
    TemperatureUnit.fahrenheit => (value - 32) * 5 / 9,
  };
}

/// A unit of fuel economy.
///
/// A higher number is more economical in every unit except [litresPer100Km],
/// where it is the other way round, because that one is the reciprocal of
/// distance per litre.
///
/// Zero economy is infinitely many litres per 100 km, and the other way round,
/// so those conversions return [double.infinity]. Formatting shows an infinite
/// value as the missing-value dash.
enum EconomyUnit {
  kmPerLitre('km/L'),
  litresPer100Km('L/100 km'),
  mpgUs('mpg'),
  mpgImperial('mpg');

  const EconomyUnit(this.symbol);

  final String symbol;

  String get label => symbol.toUpperCase();

  double fromKmPerLitre(double kmPerLitre) => switch (this) {
    EconomyUnit.kmPerLitre => kmPerLitre,
    EconomyUnit.litresPer100Km => _reciprocal100(kmPerLitre),
    EconomyUnit.mpgUs => kmPerLitre * litresPerUsGallon / kmPerMile,
    EconomyUnit.mpgImperial => kmPerLitre * litresPerImperialGallon / kmPerMile,
  };

  double toKmPerLitre(double value) => switch (this) {
    EconomyUnit.kmPerLitre => value,
    EconomyUnit.litresPer100Km => _reciprocal100(value),
    EconomyUnit.mpgUs => value * kmPerMile / litresPerUsGallon,
    EconomyUnit.mpgImperial => value * kmPerMile / litresPerImperialGallon,
  };

  static double _reciprocal100(double value) =>
      value <= 0 ? double.infinity : 100 / value;
}
