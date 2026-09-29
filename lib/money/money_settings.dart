import '../core/currency.dart';
import '../core/key_value_store.dart';
import '../core/observable.dart';

/// The fuel price and the currency (CLAUDE.md 8.5). The price is always entered
/// by the user, either directly or by a fill-up, and never fetched.
class MoneySettings {
  MoneySettings(this._store);

  static const _priceKey = 'money_price_per_litre';
  static const _currencyKey = 'money_currency';

  final KeyValueStore _store;
  final ObservableValue<double?> _price = ObservableValue(null);
  final ObservableValue<Currency> _currency = ObservableValue(Currency.inr);

  /// The price of a litre, or null until one is set: money views then show
  /// litres, with a prompt to add the price.
  Observable<double?> get price => _price;

  Observable<Currency> get currency => _currency;

  Future<void> load() async {
    _price.value = await _store.getDouble(_priceKey);
    final code = await _store.getString(_currencyKey);
    _currency.value = switch (code) {
      'USD' => Currency.usd,
      'GBP' => Currency.gbp,
      _ => Currency.inr,
    };
  }

  Future<void> setPrice(double? pricePerLitre) async {
    _price.value = pricePerLitre;
    if (pricePerLitre == null) {
      await _store.remove(_priceKey);
    } else {
      await _store.setDouble(_priceKey, pricePerLitre);
    }
  }

  Future<void> setCurrency(Currency currency) async {
    _currency.value = currency;
    await _store.setString(_currencyKey, currency.code);
  }
}
