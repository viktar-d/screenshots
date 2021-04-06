
import 'package:path/path.dart';

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
}
