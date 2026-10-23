import '../core/observable.dart';
import 'trip.dart';

/// The trips the screens browse (History, Review, Coach), read from the log and
/// kept current as trips end. Trips flagged simulated (`Trip.isDemo`: left in the
/// file by builds that had Demo Mode) are never listed and never counted.
class TripLibrary {
  TripLibrary(this.repository);

  final TripRepository repository;

  final ObservableValue<List<Trip>> _trips = ObservableValue(const []);
  final ObservableValue<Trip?> _selected = ObservableValue(null);

  /// Every trip, newest first.
  Observable<List<Trip>> get trips => _trips;

  /// The trip Review shows: the one chosen in History, or the latest.
  Observable<Trip?> get selected => _selected;

  /// Reads the log again. Keeps the selection if that trip is still there, and
  /// otherwise selects the latest.
  Future<void> refresh() async {
    final all = await repository.all();
    _trips.value = all;
    final keep = _selected.value == null
        ? null
        : all.where((t) => t.id == _selected.value!.id).firstOrNull;
    _selected.value = keep ?? (all.isEmpty ? null : all.first);
  }

  /// Chooses the trip Review shows.
  void select(Trip trip) => _selected.value = trip;

  /// The samples of [trip], in order.
  Future<List<TripSample>> samples(Trip trip) =>
      trip.id == null ? Future.value(const []) : repository.samples(trip.id!);

  /// Deletes every trip and its samples (Garage → Data).
  Future<void> deleteAll() async {
    for (final t in await repository.all(includeDemo: true)) {
      await repository.delete(t.id!);
    }
    await refresh();
  }
}
