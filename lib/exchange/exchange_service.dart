import 'dart:async';

import '../insights/rest_voltage_log.dart';
import '../money/fill_up.dart';
import '../trips/trip.dart';
import 'tdx_format.dart';
import 'tdx_reader.dart';
import 'tdx_writer.dart';

/// The app's setup, as plain maps (docs/EXCHANGE.md 1), for the exchange to read
/// and write without knowing how the app keeps it. `lib/app/exchange_profile.dart`
/// is the one that does.
abstract interface class ProfileAccess {
  /// The portable setup: the car, the price, the adapter, the coach, the look.
  Future<Map<String, Object?>> readProfile();

  /// The settings of this one screen.
  Future<Map<String, Object?>> readDevice();

  /// What applying [clean] (already checked) would change, one short line each,
  /// for the screen that asks first.
  Future<List<String>> describeProfile(Map<String, Object?> clean);

  Future<void> applyProfile(Map<String, Object?> clean);

  Future<void> applyDevice(Map<String, Object?> clean);
}

/// What an import is allowed to do.
class ImportOptions {
  const ImportOptions({
    this.applyProfile = false,
    this.applyDevice = false,
    this.canApplySettings = true,
    this.dryRun = false,
  });

  /// Apply the file's setup. Off unless asked: a setup arriving by adb must not
  /// change the livery, the adapter or the price by accident.
  final bool applyProfile;

  /// Apply the file's per-screen settings. Off unless asked, and a file made for
  /// another screen's settings is never applied to this one by default.
  final bool applyDevice;

  /// False while the car is moving: trips and fill-ups still come in, a setup
  /// waits.
  final bool canApplySettings;

  /// Check and count, and change nothing.
  final bool dryRun;
}

/// What happened to a file's setup.
enum ProfileOutcome {
  /// The file had none.
  none,

  /// It had one and it was not applied: it is for the person to say.
  offered,

  /// It was applied.
  applied,

  /// It was to be applied and the car was moving.
  deferred,
}

/// What an import did, in numbers and in a sentence (docs/EXCHANGE.md 3, 6).
class ImportReport {
  ImportReport();

  /// A reason the whole file was refused, in a sentence, or null.
  String? error;

  int tripsAdded = 0;
  int tripsSkipped = 0;
  int samplesAdded = 0;
  int fillUpsAdded = 0;
  int fillUpsSkipped = 0;
  int restAdded = 0;

  /// Lines that were good JSON of a known type and could not be used, the first
  /// few reasons, and lines of a type this version does not know.
  int rejected = 0;
  List<String> rejections = const [];
  int ignored = 0;
  int droppedRows = 0;

  ProfileOutcome profile = ProfileOutcome.none;

  /// What the file's setup would change, or did.
  List<String> profileChanges = const [];

  /// The file's setup, checked, when it was offered and not applied, so that a
  /// screen can apply it on a tap without reading the file again. Not in the JSON.
  Map<String, Object?>? offeredProfile;
  List<String> profileProblems = const [];

  bool dryRun = false;

  TdxHeaderRecord? header;
  DateTime? firstTrip;
  DateTime? lastTrip;

  bool get ok => error == null;

  int get added => tripsAdded + fillUpsAdded + restAdded;

  /// The report as the app says it: plain, without a number the person did not
  /// ask for.
  String get sentence {
    if (error != null) return error!;
    final parts = <String>[];
    String n(int count, String one, String many) =>
        '$count ${count == 1 ? one : many}';
    final verb = dryRun ? 'Would add' : 'Added';
    final added = <String>[
      if (tripsAdded > 0) n(tripsAdded, 'trip', 'trips'),
      if (fillUpsAdded > 0) n(fillUpsAdded, 'fill-up', 'fill-ups'),
      if (restAdded > 0) n(restAdded, 'battery reading', 'battery readings'),
    ];
    if (added.isNotEmpty) {
      parts.add('$verb ${_list(added)}.');
    }
    final skipped = tripsSkipped + fillUpsSkipped;
    if (skipped > 0) {
      parts.add(
        skipped == 1 ? '1 was already here.' : '$skipped were already here.',
      );
    }
    switch (profile) {
      case ProfileOutcome.applied:
        parts.add('The setup in the file was applied.');
      case ProfileOutcome.offered:
        parts.add('The file has a setup, and it has not been applied.');
      case ProfileOutcome.deferred:
        parts.add('The file has a setup. It waits until the car has stopped.');
      case ProfileOutcome.none:
        break;
    }
    if (rejected > 0) {
      parts.add(
        rejected == 1
            ? '1 line could not be used.'
            : '$rejected lines could not be used.',
      );
    }
    if (parts.isEmpty) return 'Nothing new in this file.';
    return parts.join(' ');
  }

  static String _list(List<String> items) => items.length <= 1
      ? items.join()
      : '${items.sublist(0, items.length - 1).join(', ')} and ${items.last}';

  /// What `result.json` holds, for a script to read (docs/EXCHANGE.md 4).
  Map<String, Object?> toJson() => {
    'operation': 'import',
    'ok': ok,
    'error': error,
    'dryRun': dryRun,
    'sentence': sentence,
    'tripsAdded': tripsAdded,
    'tripsSkipped': tripsSkipped,
    'samplesAdded': samplesAdded,
    'fillUpsAdded': fillUpsAdded,
    'fillUpsSkipped': fillUpsSkipped,
    'restAdded': restAdded,
    'rejected': rejected,
    'rejections': rejections,
    'ignored': ignored,
    'droppedRows': droppedRows,
    'profile': profile.name,
    'profileChanges': profileChanges,
    'profileProblems': profileProblems,
  };
}

/// What an export wrote.
class ExportSummary {
  ExportSummary({
    required this.counts,
    required this.bytes,
    required this.scopes,
  });

  /// Lines of each type: profile, device, trip, samples, fillup, rest.
  final Map<String, int> counts;
  final int bytes;
  final Set<TdxScope> scopes;

  int get trips => counts['trip'] ?? 0;
  int get fillUps => counts['fillup'] ?? 0;

  String get sentence {
    final parts = <String>[
      if (trips > 0) '$trips trip${trips == 1 ? '' : 's'}',
      if (fillUps > 0) '$fillUps fill-up${fillUps == 1 ? '' : 's'}',
      if ((counts['profile'] ?? 0) > 0) 'the setup',
    ];
    return parts.isEmpty
        ? 'Nothing to export yet.'
        : 'Exported ${parts.join(', ')}.';
  }

  Map<String, Object?> toJson() => {
    'operation': 'export',
    'ok': true,
    'sentence': sentence,
    'counts': counts,
    'bytes': bytes,
    'scopes': [for (final s in scopes) s.name],
  };
}

/// Moves the app's data out to an exchange file and in from one
/// (docs/EXCHANGE.md). Pure Dart: where the bytes go, and what the setup is made of,
/// are handed in.
class ExchangeService {
  ExchangeService({
    required this.trips,
    required this.fills,
    required this.rest,
    required this.profile,
    required this.device,
    required this.appVersion,
    this.onFillUpsChanged,
    this.onRestChanged,
  });

  final TripRepository trips;
  final FillUpRepository fills;
  final RestVoltageLog rest;
  final ProfileAccess profile;

  /// Where this is: the id of the install, and a phone or a watch. The name may
  /// come a moment after the service is made, once the device has been asked.
  TdxDeviceInfo device;
  final String appVersion;

  /// Called after fill-ups came in, so that the calibration and the tank count
  /// are rebuilt from them.
  final Future<void> Function()? onFillUpsChanged;
  final Future<void> Function()? onRestChanged;

  /// Writes [scopes] to [emit]. Trips that are not finished, and simulated ones,
  /// are left out (docs/EXCHANGE.md 1).
  Future<ExportSummary> export({
    required Set<TdxScope> scopes,
    required void Function(List<int> bytes) emit,
    required DateTime now,
  }) async {
    var bytes = 0;
    final writer = TdxWriter((b) {
      bytes += b.length;
      emit(b);
    });
    writer.header(
      appVersion: appVersion,
      created: now,
      device: device,
      scopes: scopes,
    );
    if (scopes.contains(TdxScope.profile)) {
      final values = await profile.readProfile();
      if (values.isNotEmpty) writer.profile(values);
    }
    if (scopes.contains(TdxScope.device)) {
      final values = await profile.readDevice();
      if (values.isNotEmpty) writer.device(values);
    }
    if (scopes.contains(TdxScope.trips)) {
      final finished = [
        for (final t in await trips.all())
          if (!t.isOpen && !t.isDemo) t,
      ]..sort((a, b) => a.startedAt.compareTo(b.startedAt));
      for (final t in finished) {
        writer.trip(t, await trips.samples(t.id!));
      }
    }
    if (scopes.contains(TdxScope.fillups)) {
      for (final f in await fills.all()) {
        writer.fillUp(f);
      }
    }
    if (scopes.contains(TdxScope.rest) && rest.readings.isNotEmpty) {
      writer.rest(rest.readings);
    }
    writer.finish();
    return ExportSummary(counts: writer.counts, bytes: bytes, scopes: scopes);
  }

  /// Checks the file [open] gives, and then adds what is new in it
  /// (docs/EXCHANGE.md 2, 3). [open] is called twice, once to check and once to
  /// apply, so that nothing is held in memory. It never throws for a bad file: the
  /// reason is in the report.
  Future<ImportReport> import(
    Stream<List<int>> Function() open, {
    ImportOptions options = const ImportOptions(),
  }) async {
    final report = ImportReport()..dryRun = options.dryRun;
    TdxScan scan;
    try {
      scan = await TdxReader.scan(open());
    } on TdxException catch (e) {
      return report..error = e.message;
    } on Object {
      return report
        ..error =
            'This file could not be read. Check that it was copied whole.';
    }
    report
      ..header = scan.header
      ..rejected = scan.rejected
      ..rejections = scan.rejections
      ..ignored = scan.ignored
      ..droppedRows = scan.droppedRows
      ..profileProblems = scan.profileProblems
      ..firstTrip = scan.firstTrip
      ..lastTrip = scan.lastTrip;

    final haveTrips = {
      for (final t in await trips.all(includeDemo: true))
        t.startedAt.millisecondsSinceEpoch,
    };
    final haveFills = {for (final f in await fills.all()) _fillKey(f)};
    Map<String, Object?>? setup;
    Map<String, Object?>? screen;
    TdxTripRecord? pending;
    final samples = <TripSample>[];

    Future<void> flush() async {
      final p = pending;
      if (p == null) return;
      pending = null;
      if (!options.dryRun) await trips.createWithSamples(p.trip, [...samples]);
      report
        ..tripsAdded += 1
        ..samplesAdded += samples.length;
      samples.clear();
    }

    final readings = <RestReading>[];
    try {
      await for (final r in TdxReader.records(open())) {
        if (r is! TdxSamplesRecord) await flush();
        switch (r) {
          case TdxTripRecord():
            if (haveTrips.add(r.key)) {
              pending = r;
              samples.clear();
            } else {
              report.tripsSkipped++;
            }
          case TdxSamplesRecord():
            if (pending != null && pending!.key == r.tripKey) {
              samples.addAll(r.samples);
            }
          case TdxFillUpRecord():
            if (haveFills.add(_fillKey(r.fillUp))) {
              if (!options.dryRun) await fills.add(r.fillUp);
              report.fillUpsAdded++;
            } else {
              report.fillUpsSkipped++;
            }
          case TdxRestRecord():
            readings.addAll(r.readings);
          case TdxProfileRecord():
            setup = r.clean.values;
          case TdxDeviceRecord():
            screen = r.clean.values;
          case TdxHeaderRecord() ||
              TdxEndRecord() ||
              TdxUnknownRecord() ||
              TdxRejectedRecord():
            break;
        }
      }
      await flush();
    } on TdxException catch (e) {
      // The file changed between the two readings: say so and stop.
      return report..error = e.message;
    }

    if (readings.isNotEmpty) {
      report.restAdded = options.dryRun
          ? readings
                .where(
                  (r) => !rest.readings.any(
                    (h) =>
                        h.at.millisecondsSinceEpoch ==
                        r.at.millisecondsSinceEpoch,
                  ),
                )
                .length
          : await rest.merge(readings);
      if (report.restAdded > 0 && !options.dryRun) await onRestChanged?.call();
    }
    if (report.fillUpsAdded > 0 && !options.dryRun) {
      await onFillUpsChanged?.call();
    }

    if (setup != null && setup.isNotEmpty) {
      report.profileChanges = await profile.describeProfile(setup);
      if (!options.applyProfile) {
        report.profile = ProfileOutcome.offered;
        report.offeredProfile = setup;
      } else if (!options.canApplySettings) {
        report.profile = ProfileOutcome.deferred;
        report.offeredProfile = setup;
      } else {
        if (!options.dryRun) await profile.applyProfile(setup);
        report.profile = ProfileOutcome.applied;
      }
    }
    if (screen != null &&
        screen.isNotEmpty &&
        options.applyDevice &&
        options.canApplySettings &&
        !options.dryRun) {
      await profile.applyDevice(screen);
    }
    return report;
  }

  static String _fillKey(FillUp f) =>
      '${f.at.millisecondsSinceEpoch}:${f.litres.toStringAsFixed(3)}';
}
