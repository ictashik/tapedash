import 'package:sqflite/sqflite.dart';

import '../money/fill_up.dart';

/// The fill-up log in SQLite (CLAUDE.md 6).
class SqfliteFillUpRepository implements FillUpRepository {
  SqfliteFillUpRepository(this._db);

  final Database _db;

  @override
  Future<List<FillUp>> all() async {
    final rows = await _db.query('fill_ups', orderBy: 'at ASC');
    return [
      for (final r in rows)
        FillUp(
          id: r['id']! as int,
          at: DateTime.fromMillisecondsSinceEpoch(r['at']! as int),
          litres: (r['litres']! as num).toDouble(),
          amount: (r['amount']! as num).toDouble(),
          fullTank: r['full_tank'] == 1,
          factor: (r['factor'] as num?)?.toDouble(),
        ),
    ];
  }

  @override
  Future<FillUp> add(FillUp f) async {
    final id = await _db.insert('fill_ups', {
      'at': f.at.millisecondsSinceEpoch,
      'litres': f.litres,
      'amount': f.amount,
      'full_tank': f.fullTank ? 1 : 0,
      'factor': f.factor,
    });
    return f.copyWith(id: id);
  }

  @override
  Future<void> delete(int id) async {
    await _db.delete('fill_ups', where: 'id = ?', whereArgs: [id]);
  }
}
