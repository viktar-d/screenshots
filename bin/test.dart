

import 'dart:io';

import 'package:screenshots3/src/globals.dart';
import 'package:screenshots3/screenshots.dart';
import 'package:screenshots3/src/daemon_client.dart';

void main() async {
  final daemonClient = await DaemonClient.getInstance();
  final devices = await daemonClient.devicesInfo;

  final config = Config.loadFromFile('./screenshots.yaml', devices);


  final success = await screenshots(
    config: config,
    runMode: RunMode.normal, //argResults[modeArg],
    isBuild: true,
  );

  exit(success ? 0 : 1);
}