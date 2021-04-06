// @dart=2.8

import 'dart:io';

import 'package:args/args.dart';
import 'package:screenshots3/screenshots.dart';
import 'package:screenshots3/src/daemon_client.dart';
import 'package:screenshots3/src/globals.dart';
import 'package:screenshots3/src/run.dart';


const usage =
    'usage: screenshots [-h] [-c <config file>] [-m <normal|recording|comparison|archive>] [-f <flavor>] [-b <true|false>] [-v]';
const sampleUsage = 'sample usage: screenshots';

void main(List<String> arguments) async {
  ArgResults argResults;

  final configArg = 'config';
  final modeArg = 'mode';
  final flavorArg = 'flavor';
  final buildArg = 'build';
  final helpArg = 'help';
  final verboseArg = 'verbose';
  final argParser = ArgParser(allowTrailingOptions: false)
    ..addOption(configArg,
        abbr: 'c',
        defaultsTo: kConfigFileName,
        help: 'Path to config file.',
        valueHelp: kConfigFileName)
    ..addOption(modeArg,
        abbr: 'm',
        defaultsTo: 'normal',
        help:
            'If mode is recording, screenshots will be saved for later comparison. \nIf mode is comparison, screenshots will be compared with recorded.\nIf mode is archive, screenshots will be archived (and cannot be uploaded via fastlane).',
        allowed: ['normal', 'recording', 'comparison', 'archive'],
        valueHelp: 'normal|recording|comparison|archive')
    ..addOption(flavorArg,
        abbr: 'f', help: 'Flavor name.', valueHelp: 'flavor name')
    ..addOption(buildArg,
        abbr: 'b',
        help:
            'Force build and install of app for all devices.\nOverride settings in screenshots.yaml (if any).',
        allowed: ['true', 'false'],
        valueHelp: 'true|false')
    ..addFlag(verboseArg,
        abbr: 'v',
        help: 'Noisy logging, including all shell commands executed.',
        negatable: false)
    ..addFlag(helpArg,
        abbr: 'h', help: 'Display this help information.', negatable: false);
  try {
    argResults = argParser.parse(arguments);
  } on ArgParserException catch (e) {
    _handleError(argParser, e.toString());
  }

  // show help
  if (argResults[helpArg] as bool) {
    _showUsage(argParser);
    exit(0);
  }

  // confirm os
  if (!['windows', 'linux', 'macos'].contains(Platform.operatingSystem)) {
    stderr.writeln('Error: unsupported os: ${Platform.operatingSystem}');
    exit(1);
  }

  // validate args
  if (!await File(argResults[configArg] as String).exists()) {
    _handleError(argParser, 'File not found: ${argResults[configArg]}');
  }

  final daemonClient = await DaemonClient.getInstance();
  final devices = await daemonClient.devicesInfo;

  final config = Config.loadFromFile(argResults[configArg] as String, devices);

  final screenshots = Screenshots(
    config: config,
    runMode: RunMode.normal, //argResults[modeArg],
    flavor: argResults[flavorArg] as String,
    isBuild: argResults.wasParsed(buildArg)
        ? argResults[buildArg] == 'true' ? true : false
        : null,
    verbose: argResults.wasParsed(verboseArg) ? true : false,
  );

  final success = await screenshots.run();

  exit(success ? 0 : 1);
}

void _handleError(ArgParser argParser, String msg) {
  stderr.writeln(msg);
  _showUsage(argParser);
}

void _showUsage(ArgParser argParser) {
  print('$usage');
  print('\n$sampleUsage\n');
  print(argParser.usage);
  exit(2);
}
