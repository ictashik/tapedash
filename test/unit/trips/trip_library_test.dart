import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/trips/trip.dart';
import 'package:tapedash/trips/trip_library.dart';

Future<Trip> add(
  MemoryTripRepository repo,
  int day, {
  bool demo = false,
  int samples = 3,
}) async {
  final t = await repo.create(
    Trip(startedAt: DateTime(2026, 3, day), isDemo: demo, distanceKm: 1),
  );
  await repo.addSamples(t.id!, [
    for (var i = 0; i < samples; i++)
      TripSample(
        seconds: i.toDouble(),
        speedKmh: 30,
        rpm: 1500,
        throttle: 10,
        litresPerHour: 2,
      ),
  ]);
  return t;
}

void main() {
  test('it holds every trip, newest first, and selects the latest', () async {
    final repo = MemoryTripRepository();
    await add(repo, 1);
    await add(repo, 3);
    await add(repo, 2);
    final library = TripLibrary(repo);
    expect(library.trips.value, isEmpty);
    expect(library.selected.value, isNull);

    await library.refresh();
    expect([for (final t in library.trips.value) t.startedAt.day], [3, 2, 1]);
    expect(library.selected.value?.startedAt.day, 3);
  });

  test('demo trips are held, but are not real trips', () async {
    final repo = MemoryTripRepository();
    await add(repo, 1);
    await add(repo, 2, demo: true);
    final library = TripLibrary(repo);
    await library.refresh();
    expect(library.trips.value.length, 2);
    expect([for (final t in library.realTrips) t.startedAt.day], [1]);
  });

  test(
    'a refresh keeps the chosen trip, and falls back to the latest',
    () async {
      final repo = MemoryTripRepository();
      final older = await add(repo, 1);
      await add(repo, 2);
      final library = TripLibrary(repo);
      await library.refresh();

      library.select(older);
      await add(repo, 3);
      await library.refresh();
      expect(library.selected.value?.id, older.id);

      await repo.delete(older.id!);
      await library.refresh();
      expect(library.selected.value?.startedAt.day, 3);
    },
  );

  test(
    'samples are those of the trip, and none for a trip not saved',
    () async {
      final repo = MemoryTripRepository();
      final t = await add(repo, 1, samples: 5);
      final library = TripLibrary(repo);
      expect((await library.samples(t)).length, 5);
      expect(await library.samples(Trip(startedAt: DateTime(2026))), isEmpty);
    },
  );

  test('deleteAll empties the log and the selection', () async {
    final repo = MemoryTripRepository();
    await add(repo, 1);
    await add(repo, 2, demo: true);
    final library = TripLibrary(repo);
    await library.refresh();
    await library.deleteAll();
    expect(library.trips.value, isEmpty);
    expect(library.selected.value, isNull);
    expect(await repo.all(includeDemo: true), isEmpty);
  });
}
