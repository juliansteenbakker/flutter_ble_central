// Runs the interop harness across two devices and reports what each call did.
//
// One device plays the peripheral and the other the central, so a run answers
// one cell of the matrix: iPhone to Mac, Android tablet to Mac, iPhone to
// Windows, and so on. Run it from the root of flutter_ble_central:
//
//     dart run tool/interop_test.dart
//
// It lists the attached devices twice — once to pick the peripheral, once to
// pick the central — then launches
// `flutter_ble_peripheral/example/lib/interop_harness.dart` on the first and
// `example/lib/interop_harness.dart` on the second, and reads the `HARNESS|`
// lines both print.
//
// The peripheral serves three characteristics: the Nordic UART pair and one
// that is readable, writable and notifying at once, declared with a 16 bit
// uuid. Between them the run covers a filtered scan and what a filter leaves
// out, discovery of a layout larger than a pair, a short uuid resolving to the
// same characteristic as its long form, and an echo coming back on the
// characteristic it was written to rather than on whichever one notifies.
//
// What it cannot cover, since a scripted run cannot background or kill an app
// and go on talking to it: background scanning and advertising, the state
// restoration that hands a relaunched app its connection or advertisement back,
// and running with no activity attached. Those stay manual.
//
// Options:
//   --peripheral <id>   Skip the first prompt and use this device.
//   --central <id>      Skip the second prompt and use this device.
//   --peripheral-path   Where flutter_ble_peripheral is checked out.
//                       Defaults to ../flutter_ble_peripheral.
//   --bonding           Also run the pairing calls on platforms that serve
//                       them. Off by default: pairing needs someone to answer
//                       a system dialog and leaves a bond behind.
//   --keep-running      Leave both apps running when the checks finish.
//
// Everything both apps print is kept under .dart_tool/interop_test/, since a
// failure is usually explained by a native log line rather than by the check
// that failed.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  final options = _Options.parse(arguments);

  final centralExample = Directory('example');
  if (!centralExample.existsSync()) {
    _fail('Run this from the root of flutter_ble_central.');
  }
  final peripheralExample = Directory(
    '${options.peripheralPath}/example',
  );
  if (!peripheralExample.existsSync()) {
    _fail(
      'No peripheral example at ${peripheralExample.path}. '
      'Pass --peripheral-path.',
    );
  }

  final devices = await _listDevices();
  if (devices.length < 2) {
    _fail(
      'Two devices are needed and ${devices.length} were found. '
      'BLE does not work in a simulator.',
    );
  }

  final peripheralDevice = options.peripheralId != null
      ? _byId(devices, options.peripheralId!)
      : _prompt(devices, 'Which device should be the PERIPHERAL?');
  final centralDevice = options.centralId != null
      ? _byId(devices, options.centralId!)
      : _prompt(
          devices.where((d) => d.id != peripheralDevice.id).toList(),
          'Which device should be the CENTRAL?',
        );

  if (peripheralDevice.id == centralDevice.id) {
    _fail('The peripheral and the central have to be different devices.');
  }

  stdout
    ..writeln()
    ..writeln('Peripheral : ${peripheralDevice.describe}')
    ..writeln('Central    : ${centralDevice.describe}')
    ..writeln();

  final runner = _Run(
    peripheralDirectory: peripheralExample.path,
    centralDirectory: centralExample.path,
    peripheralDevice: peripheralDevice,
    centralDevice: centralDevice,
    bonding: options.bonding,
    keepRunning: options.keepRunning,
  );

  exitCode = await runner.go();
}

/// What the command line asked for.
class _Options {
  _Options({
    required this.peripheralPath,
    required this.peripheralId,
    required this.centralId,
    required this.bonding,
    required this.keepRunning,
  });

  factory _Options.parse(List<String> arguments) {
    String? valueOf(String name) {
      final index = arguments.indexOf('--$name');
      if (index == -1 || index + 1 >= arguments.length) return null;
      return arguments[index + 1];
    }

    return _Options(
      peripheralPath: valueOf('peripheral-path') ?? '../flutter_ble_peripheral',
      peripheralId: valueOf('peripheral'),
      centralId: valueOf('central'),
      bonding: arguments.contains('--bonding'),
      keepRunning: arguments.contains('--keep-running'),
    );
  }

  final String peripheralPath;
  final String? peripheralId;
  final String? centralId;
  final bool bonding;
  final bool keepRunning;
}

/// `flutter` is a batch file on Windows, which cannot be spawned by name.
final _flutter = Platform.isWindows ? 'flutter.bat' : 'flutter';

/// One device `flutter devices` reported.
class _Device {
  _Device(this.id, this.name, this.platform);

  final String id;
  final String name;
  final String platform;

  String get describe => '$name  ($platform)';
}

/// The attached devices BLE can actually run on.
Future<List<_Device>> _listDevices() async {
  final result = await Process.run(_flutter, ['devices', '--machine']);
  if (result.exitCode != 0) {
    _fail('flutter devices failed:\n${result.stderr}');
  }

  final raw = jsonDecode(result.stdout as String) as List<dynamic>;
  return raw
      .cast<Map<String, dynamic>>()
      .map(
        (device) => _Device(
          device['id'] as String,
          device['name'] as String,
          device['targetPlatform'] as String? ?? 'unknown',
        ),
      )
      // A browser has no Bluetooth radio to lend, and a simulator's is fake.
      .where((device) => !device.platform.startsWith('web'))
      .toList();
}

_Device _byId(List<_Device> devices, String id) {
  for (final device in devices) {
    if (device.id == id) return device;
  }
  _fail('No attached device with id $id.');
}

/// Asks which device to use, and keeps asking until the answer is one of them.
_Device _prompt(List<_Device> devices, String question) {
  stdout
    ..writeln()
    ..writeln(question);
  for (var i = 0; i < devices.length; i++) {
    stdout.writeln('  ${i + 1}. ${devices[i].describe}');
  }

  while (true) {
    stdout.write('> ');
    final answer = stdin.readLineSync();
    if (answer == null) _fail('No answer; stopping.');
    final choice = int.tryParse(answer.trim());
    if (choice != null && choice >= 1 && choice <= devices.length) {
      return devices[choice - 1];
    }
    stdout.writeln('Pick a number between 1 and ${devices.length}.');
  }
}

Never _fail(String message) {
  stderr.writeln(message);
  exit(2);
}

/// One check the central reported.
class _Check {
  _Check(this.name, this.outcome, this.detail);

  final String name;
  final String outcome;
  final String detail;
}

/// Launches both halves, follows what they report, and prints the outcome.
class _Run {
  _Run({
    required this.peripheralDirectory,
    required this.centralDirectory,
    required this.peripheralDevice,
    required this.centralDevice,
    required this.bonding,
    required this.keepRunning,
  });

  final String peripheralDirectory;
  final String centralDirectory;
  final _Device peripheralDevice;
  final _Device centralDevice;
  final bool bonding;
  final bool keepRunning;

  final _checks = <_Check>[];
  final _peripheralEvents = <String>[];

  /// Where the raw output of each half is kept, for the failures whose
  /// explanation is a native log line rather than the check itself.
  final _logDirectory = Directory('.dart_tool/interop_test');
  final _logs = <String, IOSink>{};

  Process? _peripheral;
  Process? _central;

  /// Runs the pair and answers the exit code the whole thing deserves.
  Future<int> go() async {
    _logDirectory.createSync(recursive: true);
    try {
      final peripheralReady = Completer<bool>();
      _peripheral = await _launch(
        directory: peripheralDirectory,
        device: peripheralDevice,
        label: 'peripheral',
        onLine: (kind, fields) =>
            _onPeripheralLine(kind, fields, peripheralReady),
      );

      stdout.writeln('Starting the peripheral on ${peripheralDevice.name}...');
      final ready = await peripheralReady.future.timeout(
        const Duration(minutes: 5),
        onTimeout: () => false,
      );
      if (!ready) {
        stderr.writeln('The peripheral never came up.');
        return 1;
      }
      stdout.writeln('Peripheral is advertising.\n');

      final done = Completer<bool>();
      _central = await _launch(
        directory: centralDirectory,
        device: centralDevice,
        label: 'central',
        extraArguments:
            bonding ? const ['--dart-define=HARNESS_BONDING=true'] : const [],
        onLine: (kind, fields) => _onCentralLine(kind, fields, done),
      );

      stdout.writeln('Running the checks on ${centralDevice.name}...\n');
      final finished = await done.future.timeout(
        const Duration(minutes: 10),
        onTimeout: () => false,
      );

      _summarise(finished: finished);
      final failed = _checks.where((c) => c.outcome == 'FAIL').length;
      return finished && failed == 0 ? 0 : 1;
    } finally {
      if (!keepRunning) {
        await _stop(_central);
        await _stop(_peripheral);
      } else {
        stdout.writeln('\nBoth apps left running (--keep-running).');
      }
      for (final log in _logs.values) {
        await log.flush();
        await log.close();
      }
      stdout.writeln('Full output of both halves: ${_logDirectory.path}/');
    }
  }

  /// Starts one half and feeds every `HARNESS|` line it prints to [onLine].
  Future<Process> _launch({
    required String directory,
    required _Device device,
    required String label,
    required void Function(String kind, List<String> fields) onLine,
    List<String> extraArguments = const [],
  }) async {
    final log = File('${_logDirectory.path}/$label.log').openWrite();
    _logs[label] = log;

    final process = await Process.start(
      _flutter,
      [
        'run',
        '-d',
        device.id,
        '-t',
        'lib/interop_harness.dart',
        '--debug',
        ...extraArguments,
      ],
      workingDirectory: directory,
    );

    void consume(Stream<List<int>> stream) {
      stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        log.writeln(line);
        final marker = line.indexOf('HARNESS|');
        if (marker == -1) return;
        final fields = line.substring(marker + 'HARNESS|'.length).split('|');
        if (fields.isEmpty) return;
        onLine(fields.first, fields.sublist(1));
      });
    }

    consume(process.stdout);
    consume(process.stderr);
    return process;
  }

  void _onPeripheralLine(
    String kind,
    List<String> fields,
    Completer<bool> ready,
  ) {
    switch (kind) {
      case 'READY':
        if (!ready.isCompleted) ready.complete(true);
      case 'LAYOUT':
        // What the peripheral says it serves, printed before the run so a
        // failing discovery check can be read against it.
        stdout.writeln('  peripheral serves ${fields.length} '
            'characteristics: ${fields.join(', ')}');
      case 'FATAL':
        stderr.writeln('Peripheral: ${fields.join(' ')}');
        if (!ready.isCompleted) ready.complete(false);
      case 'WAITING':
        _waitOnce('peripheral', fields.join(' '));
      case 'EVENT':
        _peripheralEvents.add(fields.join(' '));
    }
  }

  void _onCentralLine(String kind, List<String> fields, Completer<bool> done) {
    switch (kind) {
      case 'CHECK':
        if (fields.length < 3) return;
        final check = _Check(fields[0], fields[1], fields.sublist(2).join('|'));
        _checks.add(check);
        final mark = _mark(check.outcome);
        stdout.writeln(
          '  $mark ${check.name.padRight(38)} ${check.detail}',
        );
      case 'WAITING':
        _waitOnce('central', fields.join(' '));
      case 'FATAL':
        stderr.writeln('Central: ${fields.join(' ')}');
      case 'DONE':
        if (!done.isCompleted) done.complete(true);
    }
  }

  /// Says once, per half, that it is waiting on someone at the device.
  final _waiting = <String>{};

  void _waitOnce(String half, String message) {
    if (!_waiting.add(half)) return;
    stdout.writeln('  ...$half: $message');
  }

  static String _mark(String outcome) => switch (outcome) {
        'PASS' => '✓',
        'FAIL' => '✗',
        'SKIP' => '–',
        _ => 'i',
      };

  void _summarise({required bool finished}) {
    final passed = _checks.where((c) => c.outcome == 'PASS').length;
    final failed = _checks.where((c) => c.outcome == 'FAIL').toList();
    final skipped = _checks.where((c) => c.outcome == 'SKIP').length;
    final noted = _checks.where((c) => c.outcome == 'INFO').length;

    stdout
      ..writeln()
      ..writeln('${peripheralDevice.platform} peripheral  ->  '
          '${centralDevice.platform} central')
      ..writeln('$passed passed, ${failed.length} failed, '
          '$skipped skipped, $noted noted');

    if (failed.isNotEmpty) {
      stdout.writeln('\nFailed:');
      for (final check in failed) {
        stdout.writeln('  ${check.name}: ${check.detail}');
      }
    }

    if (_peripheralEvents.isNotEmpty) {
      stdout.writeln('\nWhat the peripheral saw:');
      for (final event in _peripheralEvents) {
        stdout.writeln('  $event');
      }
    }

    if (!finished) {
      stdout.writeln(
        '\nThe central never reported finishing, so the list above is '
        'whatever it managed before it stopped.',
      );
    }
  }

  /// Asks `flutter run` to quit, and kills it if it will not.
  Future<void> _stop(Process? process) async {
    if (process == null) return;
    try {
      process.stdin.writeln('q');
      await process.stdin.flush();
    } on Object {
      // Already gone.
    }
    await process.exitCode.timeout(
      const Duration(seconds: 20),
      onTimeout: () {
        process.kill();
        return -1;
      },
    );
  }
}
