import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;


import 'archive.dart';
import 'config.dart';
import 'daemon_client.dart';
import 'fastlane.dart' as fastlane;
import 'globals.dart';
import 'orientation.dart';
import 'resources.dart' as resources;
import 'utils.dart' as utils;
import 'validate.dart' as validate;


String canonicalizedLocale(String aLocale) {
// Locales of length < 5 are presumably two-letter forms, or else malformed.
// We return them unmodified and if correct they will be found.
// Locales longer than 6 might be malformed, but also do occur. Do as
// little as possible to them, but make the '-' be an '_' if it's there.
// We treat C as a special case, and assume it wants en_ISO for formatting.
// TODO(alanknight): en_ISO is probably not quite right for the C/Posix
// locale for formatting. Consider adding C to the formats database.
  if (aLocale == 'C') return 'en_ISO';
  if (aLocale.length < 5) return aLocale;
  if (aLocale[2] != '-' && (aLocale[2] != '_')) return aLocale;
  var region = aLocale.substring(3);
// If it's longer than three it's something odd, so don't touch it.
  if (region.length <= 3) region = region.toUpperCase();
  return '${aLocale[0]}${aLocale[1]}_$region';
}

/// Run screenshots
Future<bool> screenshots({
  required Config config,
  RunMode runMode = RunMode.normal,
  String flavor = kNoFlavor,
  bool? isBuild,
  bool isVerbose = false
}) async {
  final screenshots = Screenshots(
    config: config,
    runMode: runMode,
    flavor: flavor,
    isBuild: isBuild,
    verbose: isVerbose
  );
  // run in context
  return screenshots.run();
}

class Screenshots {
  Screenshots({
    required this.config,
    required this.runMode,
    this.flavor = kNoFlavor,
    this.isBuild,
    this.verbose = false,
  }) {
    //archive = Archive(config.archiveDir!);
    archive = Archive('');
  }

  final String flavor;
  final bool? isBuild; // defaults to null
  final bool verbose;
  final Config config;

  final RunMode runMode;

  late Archive archive;

  /// Capture screenshots, process, and load into fastlane according to config file.
  ///
  /// For each locale and device or emulator/simulator:
  ///
  /// 1. If not a real device, start the emulator/simulator for current locale.
  /// 2. Run each integration test and capture the screenshots.
  /// 3. Process the screenshots including adding a frame if required.
  /// 4. Move processed screenshots to fastlane destination for upload to stores.
  /// 5. If not a real device, stop emulator/simulator.
  Future<bool> run() async {
    // start flutter daemon
    print('Starting flutter daemon...');

    // get all attached devices and running emulators/simulators
    // get all available unstarted android emulators
    // note: unstarted simulators are not properly included in this list
    //       so have to be handled separately

    // validate config file
    if (!await validate.isValidConfig(config)) {
      return false;
    }

    // init
    await Directory(path.join(kTempDir, kTestScreenshotsDir)).create(recursive: true);

    if (!Platform.isWindows) await resources.unpackScripts();
    if (runMode == RunMode.archive) {
      //printStatus('Archiving screenshots to ${archive.archiveDirPrefix}...');
    } else {
      await fastlane.clearFastlaneDirs(config, runMode);
    }

    // run integration tests in each real device (or emulator/simulator) for
    // each locale and process screenshots
    await runTestsOnAll();


    //printStatus('\n\nScreen images are available in:');
    if (runMode == RunMode.recording) {
      //_printScreenshotDirs(config.recordingDir);
    } else {
      if (runMode == RunMode.archive) {
        //printStatus('  ${archive.archiveDirPrefix}');
      } else {
        //_printScreenshotDirs(null);
        final isIosActive = config.isRunTypeActive(DeviceType.ios);
        final isAndroidActive = config.isRunTypeActive(DeviceType.android);
        if (isIosActive && isAndroidActive) {
          //printStatus('for upload to both Apple and Google consoles.');
        }
        if (isIosActive && !isAndroidActive) {
          //printStatus('for upload to Apple console.');
        }
        if (!isIosActive && isAndroidActive) {
          //printStatus('for upload to Google console.');
        }
        //printStatus('\nFor uploading and other automation options see:');
        //printStatus('  https://pub.dartlang.org/packages/fledge');
      }
    }
   // printStatus('\nscreenshots completed successfully.');
    return true;
  }

  void _printScreenshotDirs(String? dirPrefix) {
    final prefix = dirPrefix == null ? '' : '${dirPrefix}/';
    if (config.isRunTypeActive(DeviceType.ios)) {
      //printStatus('  ${prefix}ios/fastlane/screenshots');
    }
    if (config.isRunTypeActive(DeviceType.android)) {
      //printStatus('  ${prefix}android/fastlane/metadata/android');
    }
  }

  /// Run the screenshot integration tests on current device, emulator or simulator.
  ///
  /// Each test is expected to generate a sequential number of screenshots.
  /// (to match order of appearance in Apple and Google stores)
  ///
  /// Assumes the integration tests capture the screen shots into a known directory using
  /// provided [capture_screen.screenshot()].
  Future runTestsOnAll() async {
    /*
    final recordingDir = config.recordingDir;
    switch (runMode) {
      case RunMode.normal:
        break;
      case RunMode.recording:
        recordingDir == null
            ? throw 'Error: \'recording\' dir is not specified in your screenshots.yaml'
            : null;
        break;
      case RunMode.comparison:
        runMode == RunMode.comparison &&
                (recordingDir == null || !(await utils.isRecorded(recordingDir)))
            ? throw 'Error: a recording must be run before a comparison'
            : null;
        break;
      case RunMode.archive:
        config.archiveDir == null
            ? throw 'Error: \'archive\' dir is not specified in your screenshots.yaml'
            : null;
        break;
    }

     */

    final daemonClient = await DaemonClient.getInstance();

    for (final device in config.devices) {
      if (!Platform.isMacOS && device.deviceType == DeviceType.ios) continue;


      if (device.emulator) {
        final emulatorId = await daemonClient.launchEmulator(device);
        final origLocale = utils.getDeviceLocale(device);

        for (final locale in config.locales) {
          await setDeviceLocale(device, locale, daemonClient);

          for (final orientation in device.orientations) {
            changeDeviceOrientation(device, orientation);
            await runProcessTests(device, locale, orientation);
          }
        }

        if (device.deviceType == DeviceType.ios) {
          await setSimulatorLocale(device, origLocale);
          await shutdownSimulator(device.deviceId);
        } else {
          await setAndroidEmulatorLocale(device, origLocale);
          await shutdownAndroidEmulator(daemonClient, device.deviceId);
        }
      } else {
        final locale = utils.getDeviceLocale(device);

        await runProcessTests(device, locale, Orientation.Portrait);
      }
    }

    await daemonClient.stop();
  }

  /// Runs tests and processes images.
  Future runProcessTests(
    Device device,
    String locale,
    Orientation orientation,
  ) async {
    for (final testPath in config.tests) {
      final command = ['flutter', '-d', device.deviceId, 'drive'];

      final _isBuild = isBuild != null ? isBuild! : device.build;
      final isFlavor = flavor != kNoFlavor;

      if (_isBuild) {
        command.add('--no-build');
      }

      if (isFlavor) {
        command.addAll(['--flavor', flavor]);
      }

      command.addAll(testPath.split(' ')); // add test path or custom command
      //printStatus(
      //      'Running $testPath on \'$configDeviceName\' in locale $locale${isFlavor() ? ' with flavor $flavor' : ''}${!_isBuild() ? ' with no build' : ''}...');
      if (!_isBuild && isFlavor) {
        //printStatus(
        //    'Warning: flavor parameter \'$flavor\' is ignored because no build is set for this device');
      }
      await utils.streamCmd(command);
      // process screenshots
      //final imageProcessor = ImageProcessor(screenManager);
      //await imageProcessor.process(device, locale, runMode, orientation, archive);
    }
  }
}

Future<void> shutdownSimulator(String deviceId) async {
  utils.cmd(['xcrun', 'simctl', 'shutdown', deviceId]);
  // shutdown apparently needs time when restarting
  // see https://github.com/flutter/flutter/issues/10228 for race condition on simulator
  await Future<void>.delayed(Duration(milliseconds: 2000));
}

Future<void> startSimulator(DaemonClient daemonClient, String deviceId) async {
  utils.cmd(['xcrun', 'simctl', 'boot', deviceId]);
  await Future<void>.delayed(Duration(milliseconds: 2000));
  await daemonClient.waitForEmulatorToStart(deviceId);
}

Future<void> setDeviceLocale(Device device, String locale, DaemonClient daemonClient) async {
  if (device.deviceType == DeviceType.android) {
    await setAndroidEmulatorLocale(device, locale);
  } else {
    final changed = await setSimulatorLocale(device, locale);
    if (changed) {
      print('restarting simulator due to locale change...');

      await shutdownSimulator(device.deviceId);
      await startSimulator(daemonClient, device.deviceId);
    }
  }
}

/// Set the simulator locale.
/// (Startup managed elsewhere)
/// Returns true of locale changed.
Future<bool> setSimulatorLocale(Device device, String locale) async {
  // a running simulator
  final deviceLocale = utils.getIosSimulatorLocale(device.deviceId);
  //printTrace('\'$deviceName\' locale: $deviceLocale, test locale: $testLocale');
  if (canonicalizedLocale(locale) != canonicalizedLocale(deviceLocale)) {
    //printStatus('Changing locale from $deviceLocale to $testLocale on \'$deviceName\'...');
    await _changeSimulatorLocale(device.deviceId, locale);
    return true;
  }

  return false;
}

/// Set the locale of a running emulator.
Future<void> setAndroidEmulatorLocale(Device device, String locale) async {
  final deviceLocale = utils.getAndroidDeviceLocale(device.deviceId);
  //printTrace('\'$deviceName\' locale: $deviceLocale, test locale: $testLocale');
  if (canonicalizedLocale(deviceLocale) != canonicalizedLocale(locale)) {
    //          daemonClient.verbose = true;
    //printStatus('Changing locale from $deviceLocale to $testLocale on \'$deviceName\'...');
    changeAndroidLocale(device.deviceId, deviceLocale, locale);
    //          daemonClient.verbose = false;
    await utils.waitAndroidLocaleChange(device.deviceId, locale);
    // allow additional time before orientation change
//    await Future.delayed(Duration(milliseconds: 5000));
    await Future<void>.delayed(Duration(milliseconds: 1000));
  }
}

/// Change local of real android device or running emulator.
void changeAndroidLocale(
    String deviceId, String deviceLocale, String testLocale) {
  if (utils.cmd([
      //getAdbPath(androidSdk),
    'adb',
        '-s', deviceId, 'root']) ==
      'adbd cannot run as root in production builds\n') {
    //printError('Warning: locale will not be changed. Running in locale \'$deviceLocale\'.\n');
    //printError('To change locale you must use a non-production emulator (one that does not depend on Play Store). See:\n');
    //printError('    https://stackoverflow.com/questions/43923996/adb-root-is-not-working-on-emulator/45668555#45668555 for details.\n');
  }
  // adb shell "setprop persist.sys.locale fr_CA; setprop ctl.restart zygote"
  utils.cmd([
    //getAdbPath(androidSdk),
    'adb'
    '-s',
    deviceId,
    'shell',
    'setprop',
    'persist.sys.locale',
    testLocale,
    ';',
    'setprop',
    'ctl.restart',
    'zygote'
  ]);
}

/// Change locale of non-running simulator.
Future _changeSimulatorLocale(
    String name, String testLocale) async {
  await utils.streamCmd([
    '$kTempDir/resources/script/simulator-controller',
    name,
    'locale',
    testLocale
  ]);
}

/// Shutdown an android emulator.
Future<String> shutdownAndroidEmulator(
    DaemonClient daemonClient, String deviceId) async {
  utils.cmd([
    //getAdbPath(androidSdk),
    'adb',
    '-s', deviceId, 'emu', 'kill']);
//  await waitAndroidEmulatorShutdown(deviceId);
  final device = await daemonClient.waitForEvent(EventType.deviceRemoved);
  if (device['id'] != deviceId) {
    throw 'Error: device id \'$deviceId\' not shutdown';
  }
  return device['id'] as String;
}

///// Start android emulator in a CI environment.
//Future _startAndroidEmulatorOnCI(String emulatorId, String stagingDir) async {
//  // testing on CI/CD requires starting emulator in a specific way
//  final androidHome = platform.environment['ANDROID_HOME'];
//  await utils.streamCmd([
//    '$androidHome/emulator/emulator',
//    '-avd',
//    emulatorId,
//    '-no-audio',
//    '-no-window',
//    '-no-snapshot',
//    '-gpu',
//    'swiftshader',
//  ], mode: ProcessStartMode.detached);
//  // wait for emulator to start
//  await utils
//      .streamCmd(['$stagingDir/resources/script/android-wait-for-emulator']);
//}

