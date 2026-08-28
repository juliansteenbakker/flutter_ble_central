/*
 * Copyright (c) 2026. Julian Steenbakker.
 * All rights reserved. Use of this source code is governed by a
 * BSD-style license that can be found in the LICENSE file.
 */

// Checks, or updates, the example code shared with flutter_ble_peripheral.
//
//     dart run tool/sync_example_shell.dart           # report drift, exit 1
//     dart run tool/sync_example_shell.dart --write   # copy this repo's over
//
// The two example apps are the same instrument with one hue swapped. The shell
// and the game are identical in both, but an example cannot depend on a
// package that does not exist on pub, and a path dependency on a sibling
// repository breaks for anyone who clones only one. So the files are copied,
// and this keeps the copies honest.

import 'dart:io';

/// The paths, relative to a repository root, that must match byte for byte.
const sharedPaths = [
  'example/lib/shell/access.dart',
  'example/lib/shell/hex.dart',
  'example/lib/shell/instrument_app.dart',
  'example/lib/shell/link_meter.dart',
  'example/lib/shell/panel.dart',
  'example/lib/shell/shell.dart',
  'example/lib/shell/theme.dart',
  'example/lib/pong/court.dart',
  'example/lib/pong/engine.dart',
  'example/lib/pong/game.dart',
  'example/lib/pong/pong.dart',
  'example/lib/pong/protocol.dart',
  'example/lib/pong/scoreboard.dart',
  'example/lib/pong/transport.dart',
  'example/test/pong_test.dart',
  'example/assets/fonts/Archivo.ttf',
  'example/assets/fonts/IBMPlexMono-Regular.ttf',
  'example/assets/fonts/IBMPlexMono-SemiBold.ttf',
  'example/assets/fonts/OFL-Archivo.txt',
  'example/assets/fonts/OFL-IBMPlexMono.txt',
];

void main(List<String> arguments) {
  final write = arguments.contains('--write');
  final other = _peripheralPath(arguments);

  if (!Directory(other).existsSync()) {
    stderr.writeln(
      'flutter_ble_peripheral not found at $other.\n'
      'Pass --peripheral-path=<dir> if it is somewhere else.',
    );
    exit(2);
  }

  final drifted = <String>[];
  for (final path in sharedPaths) {
    final ours = File(path);
    final theirs = File('$other/$path');

    if (!ours.existsSync()) {
      stderr.writeln('missing here: $path');
      exit(2);
    }

    if (theirs.existsSync() &&
        _sameBytes(ours.readAsBytesSync(), theirs.readAsBytesSync())) {
      continue;
    }

    drifted.add(path);
    if (write) {
      theirs.parent.createSync(recursive: true);
      ours.copySync(theirs.path);
    }
  }

  if (drifted.isEmpty) {
    stdout.writeln('${sharedPaths.length} shared files match.');
    return;
  }

  if (write) {
    stdout.writeln('Copied ${drifted.length} file(s) to $other:');
    for (final path in drifted) {
      stdout.writeln('  $path');
    }
    return;
  }

  stderr.writeln('${drifted.length} shared file(s) differ from $other:');
  for (final path in drifted) {
    stderr.writeln('  $path');
  }
  stderr.writeln("\nRun with --write to copy this repository's over.");
  exit(1);
}

String _peripheralPath(List<String> arguments) {
  for (final argument in arguments) {
    if (argument.startsWith('--peripheral-path=')) {
      return argument.split('=').last;
    }
  }
  return '../flutter_ble_peripheral';
}

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) return false;
  }
  return true;
}
