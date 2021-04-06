import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:screenshots3/src/fastlane.dart';
import 'package:screenshots3/src/utils.dart';


import 'config.dart';
import 'daemon_client.dart';
import 'globals.dart';
import 'resources.dart' as resources;
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

class Screenshots {
  Screenshots({
    required this.config,
    required this.runMode,
    this.flavor = kNoFlavor,
    this.isBuild,
    this.verbose = false,
  });

  final String flavor;
  final bool? isBuild; // defaults to null
  final bool verbose;
  final Config config;

  final RunMode runMode;


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

    // validate config file
    if (!await validate.isValidConfig(config)) {
      return false;
    }

    // init
    await Directory(path.join(kTempDir, kTestScreenshotsDir)).create(recursive: true);

    if (!Platform.isWindows) await resources.unpackScripts();

    // run integration tests in each real device (or emulator/simulator) for
    // each locale and process screenshots
    await runTestsOnAll();

    return true;
  }



  /// Run the screenshot integration tests on current device, emulator or simulator.
  ///
  /// Each test is expected to generate a sequential number of screenshots.
  /// (to match order of appearance in Apple and Google stores)
  ///
  /// Assumes the integration tests capture the screen shots into a known directory using
  /// provided [capture_screen.screenshot()].
  Future<void> runTestsOnAll() async {
    final daemonClient = await DaemonClient.getInstance();

    for (final device in config.devices) {
      if (!Platform.isMacOS && device.deviceType == DeviceType.ios) continue;


      if (device.emulator) {
        await daemonClient.launchEmulator(device);
        final origLocale = await device.getLocale(config);

        for (final locale in config.locales) {
          await device.setLocale(config, locale);

          for (final orientation in device.orientations) {
            device.rotate(config, orientation);
            print('runningProcessTests');
            await runProcessTests(device, locale, orientation);
          }

          Fastlane.copyScreenshots(device, locale);
        }

        Fastlane.frameScreenshots(device, config.locales);

        await device.setLocale(config, origLocale);
        await device.shutdown(config);
      } else {
        final locale = await device.getLocale(config);

        await runProcessTests(device, locale, Orientation.Portrait);
        Fastlane.copyScreenshots(device, locale);
        Fastlane.frameScreenshots(device, <String>[locale]);
      }
    }

    await daemonClient.stop();
  }

  /// Runs tests and processes images.
  Future<void> runProcessTests(
    Device device,
    String locale,
    Orientation orientation,
  ) async {
    for (final testPath in config.tests) {
      final command = ['flutter', '-d', device.emulatorId!, 'drive'];

      final _isBuild = isBuild != null ? isBuild! : device.build;
      final isFlavor = flavor != kNoFlavor;

      /*
      if (!_isBuild) {
        command.add('--no-build');
      }

      if (isFlavor) {
        command.addAll(['--flavor', flavor]);
      }

       */

      command.addAll(testPath.split(' ')); // add test path or custom command
      //printStatus(
      //      'Running $testPath on \'$configDeviceName\' in locale $locale${isFlavor() ? ' with flavor $flavor' : ''}${!_isBuild() ? ' with no build' : ''}...');
      if (!_isBuild && isFlavor) {
        //printStatus(
        //    'Warning: flavor parameter \'$flavor\' is ignored because no build is set for this device');
      }
      print('starting: ${command.join(' ')}');
      cmd(command);
      // process screenshots
      //final imageProcessor = ImageProcessor(screenManager);
      //await imageProcessor.process(device, locale, runMode, orientation, archive);
    }
  }
}
