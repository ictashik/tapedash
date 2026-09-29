/// One visit to the pump (CLAUDE.md 8.5).
class FillUp {
  const FillUp({
    this.id,
    required this.at,
    required this.litres,
    required this.amount,
    required this.fullTank,
    this.factor,
  });

  final int? id;
  final DateTime at;
  final double litres;

  /// What was paid, in the currency.
  final double amount;

  /// Whether the tank was filled to the top: only between two of these can the
  /// estimate be checked.
  final bool fullTank;

  /// The correction this fill-up worked out, if it was a full tank and there was
  /// an earlier one to compare with.
  final double? factor;

  /// What the fuel cost a litre.
  double get pricePerLitre => amount / litres;

  FillUp copyWith({int? id, double? factor}) => FillUp(
    id: id ?? this.id,
    at: at,
    litres: litres,
    amount: amount,
    fullTank: fullTank,
    factor: factor ?? this.factor,
  );
}

/// The fill-up log. It has an in-memory implementation for tests and a sqflite
/// one for the app (CLAUDE.md 6).
abstract interface class FillUpRepository {
  /// Every fill-up, oldest first.
  Future<List<FillUp>> all();

  /// Saves [fillUp] and returns it with its id.
  Future<FillUp> add(FillUp fillUp);

  Future<void> delete(int id);
}

class MemoryFillUpRepository implements FillUpRepository {
  final List<FillUp> _rows = [];
  int _next = 1;

  @override
  Future<List<FillUp>> all() async {
    final rows = List.of(_rows)..sort((a, b) => a.at.compareTo(b.at));
    return rows;
  }

  @override
  Future<FillUp> add(FillUp fillUp) async {
    final saved = fillUp.copyWith(id: _next++);
    _rows.add(saved);
    return saved;
  }

  @override
  Future<void> delete(int id) async => _rows.removeWhere((f) => f.id == id);
}
