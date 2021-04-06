
import 'package:path/path.dart';
import 'package:screenshots3/src/utils.dart';

import 'config.dart';
import 'globals.dart';
import 'dart:io';


class Fastlane {
  Fastlane._internal();

  static void copyScreenshots(Device device, String locale) {
    final files = Directory('$kTempDir/$kTestScreenshotsDir')
        .listSync(recursive: false, followLinks: false)
        .whereType<File>();
    final directory = device.getDestDirectory(locale);

    directory.deleteSync(recursive: true);
    directory.createSync(recursive: true);

    for (final file in files) {
      file.renameSync('${directory.path}/${basename(file.path)}');
    }
  }

  static Future<void> frameScreenshots(Device device, List<String> locales) async {
    for (final locale in locales) {
      await _frameLocaleScreenshots(device, locale);
    }
  }

  static Future<void> _frameLocaleScreenshots(Device device, String locale) async {
    final directory = device.getDestDirectory(locale);

    // bundle exec fastlane run frameit force_device_type:"Samsung Galaxy S10"
    await cmd(
      ['bundle', 'exec', 'fastlane', 'run', 'frameit',
        'force_device_type:${device.phoneType}', 'path:.'],
      workingDirectory: directory.path
    );
  }
}
