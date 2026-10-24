import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/clock.dart';
import '../core/observable.dart';
import '../exchange/exchange_service.dart';
import '../exchange/tdx_format.dart';
import '../platform/exchange_files.dart';
import '../platform/exchange_host.dart';
import 'app_services.dart';
import 'exchange_profile.dart';

/// What the screens say about the exchange.
@immutable
class ExchangeStatus {
  const ExchangeStatus({
    this.busy = false,
    this.sentence,
    this.ok = true,
    this.inboxFiles = 0,
    this.offered = const [],
    this.outboxPath,
  });

  final bool busy;

  /// What the last export or import did, in a sentence, or null before any.
  final String? sentence;
  final bool ok;

  /// How many files wait in `inbox/`.
  final int inboxFiles;

  /// What the setup in the last file would change, when it was offered and not yet
  /// applied: shown with a button.
  final List<String> offered;

  /// Where an export was written, for a person to find.
  final String? outboxPath;

  ExchangeStatus copyWith({
    bool? busy,
    Object? sentence = _keep,
    bool? ok,
    int? inboxFiles,
    List<String>? offered,
    Object? outboxPath = _keep,
  }) => ExchangeStatus(
    busy: busy ?? this.busy,
    sentence: identical(sentence, _keep) ? this.sentence : sentence as String?,
    ok: ok ?? this.ok,
    inboxFiles: inboxFiles ?? this.inboxFiles,
    offered: offered ?? this.offered,
    outboxPath: identical(outboxPath, _keep)
        ? this.outboxPath
        : outboxPath as String?,
  );

  static const Object _keep = Object();

  @override
  bool operator ==(Object other) =>
      other is ExchangeStatus &&
      other.busy == busy &&
      other.sentence == sentence &&
      other.ok == ok &&
      other.inboxFiles == inboxFiles &&
      listEquals(other.offered, offered) &&
      other.outboxPath == outboxPath;

  @override
  int get hashCode => Object.hash(
    busy,
    sentence,
    ok,
    inboxFiles,
    Object.hashAll(offered),
    outboxPath,
  );
}

/// Moves the app's data out and in (docs/EXCHANGE.md): Garage's rows, the watch's
/// Data row and adb's launch request all go through here.
///
/// It owns no data of its own. It joins the pure [ExchangeService] to the folder the
/// files live in, the platform's picker and share sheet, and the app's settings, and
/// it keeps the sentence the screens show. **Nothing here runs while the car is
/// moving** except an export, which is read-only: an import that changed the log
/// under a trip being recorded is not worth the risk.
class ExchangeCoordinator {
  ExchangeCoordinator({
    required this.app,
    required this.files,
    required this.host,
    required this.clock,
    required this.installId,
    required this.deviceKind,
    required this.deviceName,
    required this.appVersion,
  }) {
    service = ExchangeService(
      trips: app.trips,
      fills: app.fills,
      rest: app.restVoltage,
      profile: ExchangeProfile(app),
      device: TdxDeviceInfo(id: installId, kind: deviceKind, name: deviceName),
      appVersion: appVersion,
      onFillUpsChanged: app.ledger.rebuild,
    );
  }

  final AppServices app;
  final ExchangeFiles files;
  final ExchangeHost host;
  final Clock clock;

  /// A short random id for this install, kept so that two files from one device
  /// say so.
  final String installId;

  /// `phone` or `watch`.
  final String deviceKind;
  String deviceName;
  final String appVersion;

  /// Says what the device calls itself, once it has told: it goes in the header of
  /// what is exported from now on.
  void nameDevice(String name) {
    deviceName = name;
    service.device = TdxDeviceInfo(id: installId, kind: deviceKind, name: name);
  }

  late final ExchangeService service;

  final ObservableValue<ExchangeStatus> _status = ObservableValue(
    const ExchangeStatus(),
  );

  /// What the screens show.
  Observable<ExchangeStatus> get status => _status;

  /// Counts up whenever an import changed the log, so that whoever holds a copy of
  /// it (the trip library, the money page's last fill-up) reads it again.
  final ValueNotifier<int> changes = ValueNotifier(0);

  /// Whether the car is moving: kept by the drive screen that is on. An import
  /// waits for it to stop.
  final ValueNotifier<bool> moving = ValueNotifier(false);

  Map<String, Object?>? _offered;

  /// Whether a picker and a share sheet exist here (a phone has both, a watch neither).
  Future<({bool canPick, bool canShare})> capabilities() => host.capabilities();

  /// Counts the files in `inbox/` again.
  Future<void> refresh() async {
    final n = (await files.inbox()).length;
    _status.value = _status.value.copyWith(inboxFiles: n);
  }

  /// Writes the portable data to `outbox/` and, if [share] and the phone has a
  /// share sheet, hands it to the sheet.
  Future<ExportSummary?> exportAll({
    Set<TdxScope>? scopes,
    bool share = false,
  }) async {
    if (_status.value.busy) return null;
    final wanted = scopes ?? TdxScope.portable;
    _status.value = _status.value.copyWith(busy: true, offered: const []);
    final gzipIt = wanted.contains(TdxScope.trips);
    final name = ExchangeFiles.fileName(
      what: _what(wanted),
      at: clock.now(),
      kind: deviceKind,
      gzip: gzipIt,
    );
    final file = await files.newOutboxFile(name);
    if (file == null) {
      _fail('This device has nowhere to write the file.');
      return null;
    }
    final sink = file.openWrite();
    final zip = gzipIt
        ? gzip.encoder.startChunkedConversion(_Sink(sink))
        : null;
    try {
      final summary = await service.export(
        scopes: wanted,
        emit: zip?.add ?? sink.add,
        now: clock.now(),
      );
      zip?.close();
      await sink.flush();
      await sink.close();
      final holdsData =
          (summary.counts['profile'] ?? 0) +
              (summary.counts['device'] ?? 0) +
              summary.trips +
              summary.fillUps +
              (summary.counts['rest'] ?? 0) >
          0;
      if (!holdsData) {
        // Only a header and a footer: say so, and leave no empty file about.
        await file.delete();
        _status.value = _status.value.copyWith(
          busy: false,
          sentence: summary.sentence,
          ok: true,
          outboxPath: null,
        );
        return summary;
      }
      await _writeResult({...summary.toJson(), 'file': file.path});
      var sentence = summary.sentence;
      if (share && await host.shareFile(file.path)) {
        // The sheet is open: what the person does there is theirs.
      } else {
        sentence = '$sentence Saved in the outbox folder.';
      }
      _status.value = _status.value.copyWith(
        busy: false,
        sentence: sentence,
        ok: true,
        outboxPath: file.path,
      );
      return summary;
    } on Object catch (error) {
      try {
        await sink.close();
      } on Object {
        // The file is in a bad state already; it is removed below.
      }
      if (file.existsSync()) await file.delete();
      _fail('The export did not finish: $error');
      return null;
    }
  }

  /// Reads every file in `inbox/`, and moves each to `done/` once it has been read.
  Future<List<ImportReport>> importInbox({bool applyProfile = false}) async {
    if (_status.value.busy) return const [];
    final inbox = await files.inbox();
    if (inbox.isEmpty) {
      _status.value = _status.value.copyWith(
        sentence: 'There is nothing in the inbox folder.',
        ok: true,
        inboxFiles: 0,
      );
      return const [];
    }
    final reports = <ImportReport>[];
    for (final file in inbox) {
      final report = await _import(file, applyProfile: applyProfile);
      reports.add(report);
      if (report.ok) await files.markDone(file);
    }
    await refresh();
    return reports;
  }

  /// Asks the phone's file picker for a file and reads it.
  Future<ImportReport?> importPicked({bool applyProfile = false}) async {
    if (_status.value.busy) return null;
    final path = await host.pickFile();
    if (path == null) return null;
    final file = File(path);
    final report = await _import(file, applyProfile: applyProfile);
    // A file the picker copied is ours to remove.
    try {
      if (file.existsSync()) await file.delete();
    } on Object {
      // A cache file that stays is harmless.
    }
    return report;
  }

  /// Applies the setup that the last import found and did not apply.
  Future<void> applyOffered() async {
    final offered = _offered;
    if (offered == null) return;
    if (moving.value) {
      _status.value = _status.value.copyWith(
        sentence: 'The setup waits until the car has stopped.',
      );
      return;
    }
    await ExchangeProfile(app).applyProfile(offered);
    _offered = null;
    _status.value = _status.value.copyWith(
      sentence: 'The setup was applied.',
      ok: true,
      offered: const [],
    );
    changes.value++;
  }

  /// Does what adb asked at the launch (docs/EXCHANGE.md 5).
  Future<void> handleRequest(ExchangeRequest request) async {
    if (request.isExport) {
      await exportAll(scopes: request.scopes);
    } else {
      await importInbox(applyProfile: request.applyProfile);
    }
  }

  /// Takes the request that came with the launch, if any, and does it.
  Future<void> checkRequest() async {
    final request = await host.takeRequest();
    if (request != null) await handleRequest(request);
  }

  Future<ImportReport> _import(File file, {required bool applyProfile}) async {
    _status.value = _status.value.copyWith(busy: true, offered: const []);
    ImportReport report;
    try {
      report = await service.import(
        file.openRead,
        options: ImportOptions(
          applyProfile: applyProfile,
          // Trips come in at any time, the setup only while parked.
          canApplySettings: !moving.value,
        ),
      );
    } on Object catch (error) {
      report = ImportReport()..error = 'The import did not finish: $error';
    }
    if (report.tripsAdded + report.fillUpsAdded + report.restAdded > 0 ||
        report.profile == ProfileOutcome.applied) {
      changes.value++;
    }
    _offered = report.offeredProfile;
    await _writeResult({
      ...report.toJson(),
      'file': file.uri.pathSegments.last,
    });
    _status.value = _status.value.copyWith(
      busy: false,
      sentence: report.sentence,
      ok: report.ok,
      offered: report.profile == ProfileOutcome.offered
          ? report.profileChanges
          : const [],
    );
    return report;
  }

  /// Says what was done in result.json, for a script. A device that cannot write it
  /// (a full disk) has still done the work, so that is not an error.
  Future<void> _writeResult(Map<String, Object?> json) async {
    try {
      await files.writeResult(json);
    } on FileSystemException catch (error) {
      debugPrint('Could not write result.json: $error');
    }
  }

  void _fail(String why) {
    _status.value = _status.value.copyWith(
      busy: false,
      sentence: why,
      ok: false,
    );
  }

  static String _what(Set<TdxScope> scopes) {
    if (scopes.length == TdxScope.portable.length &&
        scopes.containsAll(TdxScope.portable)) {
      return 'all';
    }
    return [
      for (final s in TdxScope.values)
        if (scopes.contains(s)) s.name,
    ].join('+');
  }

  void dispose() {
    changes.dispose();
    moving.dispose();
  }
}

class _Sink implements Sink<List<int>> {
  _Sink(this._sink);
  final IOSink _sink;

  @override
  void add(List<int> data) => _sink.add(data);

  @override
  void close() {}
}
