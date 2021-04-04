import 'dart:async';
import 'dart:io';

import 'package:resource_portable/resource.dart';

import 'globals.dart';
import 'utils.dart';

/// Read scripts from resources and install in staging area.
Future unpackScripts() async {
  await unpackScript('resources/script/android-wait-for-emulator', kTempDir,);
  await unpackScript('resources/script/android-wait-for-emulator-to-stop', kTempDir);
  await unpackScript('resources/script/simulator-controller', kTempDir);
  await unpackScript('resources/script/sim_orientation.scpt', kTempDir);
}

/// Read script from resources and install in staging area.
Future unpackScript(String srcPath, String dstDir) async {
  final resource = Resource('package:screenshots3/$srcPath');
  final script = await resource.readAsString();

  final file = await File('$dstDir/$srcPath').create(recursive: true);
  await file.writeAsString(script, flush: true);
  // make executable
  cmd(['chmod', 'u+x', '$dstDir/$srcPath']);
}

/// Read an image from resources.
Future<List<int>> readResourceImage(String uri) async {
  final resource = Resource('package:screenshots3/$uri');
  return resource.readAsBytes();
}

/// Write an image to staging area.
Future<void> writeImage(List<int> image, String path) async {
  final file = await File(path).create(recursive: true);
  await file.writeAsBytes(image, flush: true);
}
