import '../core/observable.dart';
import 'trip.dart';

/// The trips the screens browse (History, Review, Coach), read from the log and
/// kept current as trips end. It holds them all, demo trips included, since
/// History shows those with their badge; whatever counts trips towards a
/// statistic leaves the demo ones out itself (CLAUDE.md 7.6).
class TripLibrary {
  TripLibrary(this.repository);

  final TripRepository repository;

  final ObservableValue<List<Trip>> _trips = ObservableValue(const []);
  final ObservableValue<Trip?> _selected = ObservableValue(null);

  /// Every trip, newest first.
  Observable<List<Trip>> get trips => _trips;

  /// The trip Review shows: the one chosen in History, or the latest.
  Observable<Trip?> get selected => _selected;

  /// Trips that are not demo, for the statistics.
  List<Trip> get realTrips => [
    for (final t in _trips.value)
      if (!t.isDemo) t,
  ];

  /// Reads the log again. Keeps the selection if that trip is still there, and
  /// otherwise selects the latest.
  Future<void> refresh() async {
    final all = await repository.all(includeDemo: true);
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
