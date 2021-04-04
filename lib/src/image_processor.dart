import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:screenshots3/src/config.dart';
import 'package:screenshots3/src/image_magick.dart';
import 'package:screenshots3/src/orientation.dart';

import 'archive.dart';
import 'globals.dart';
import 'screens.dart';
import 'utils.dart' as utils;

class ImageProcessor {
  static const _kDefaultIosBackground = 'xc:white';
  static const kDefaultAndroidBackground = 'xc:none'; // transparent
  static const _kCrop = '1000x40+0+0'; // default sample size and location to test for brightness

  final ScreenManager _screens;

  ImageProcessor(this._screens);

  /// Process screenshots.
  ///
  /// If android, screenshot is overlaid with a status bar and appended with
  /// a navbar.
  ///
  /// If ios, screenshot is overlaid with a status bar.
  ///
  /// If 'frame' in config file is true, screenshots are placed within image of device.
  ///
  /// After processing, screenshots are handed off for upload via fastlane.
  Future<bool> process(
      Device device,
    String locale,
    RunMode runMode,
    Orientation orientation,
    Archive archive,
  ) async {
    final screen = _screens.getScreen(device.name);
    final screenshotsDir = '$kTempDir/$kTestScreenshotsDir';
    final screenshotPaths = Directory(screenshotsDir).listSync();
    if (screen == null) {
      //printStatus('Warning: \'$deviceName\' images will not be processed');
    } else {
      // add frame if required
      if (device.frame && screen.resources != null) {
        //final status = logger.startProgress('Processing screenshots from test...',
        //    timeout: Duration(minutes: 4));

        // unpack images for screen from package to local tmpDir area
        await screen.resources?.unpack();

        // add status and nav bar and frame for each screenshot
        if (screenshotPaths.isEmpty) {
          //printStatus('Warning: no screenshots found in $screenshotsDir');
        }
        for (final screenshotPath in screenshotPaths) {
          // add status bar for each screenshot
          await overlay(screen.resources!, screenshotPath.path);

          if (screen.deviceType == DeviceType.android) {
            // add nav bar for each screenshot
            await append(screen.resources!, screenshotPath.path);
          }

          await ImageMagick.frame(screen, screenshotPath.path);
        }
        //status.stop();
      } else {
        //printStatus('Warning: framing is not enabled');
      }
    }

    // move to final destination for upload to stores via fastlane
    if (screenshotPaths.isNotEmpty) {
      final androidModelType = screen?.destName ?? 'phone';
      final destDir = device.getDestPath(locale, androidModelType);

      /*
      runMode == RunMode.recording
          ? dstDir = '${_config.recordingDir}/$dstDir'
          : null;
      runMode == RunMode.archive
          ? dstDir = archive.dstDir(deviceType, locale)
          : null;

       */
      // prefix screenshots with name of device before moving
      // (useful for uploading to apple via fastlane)
      final prefix = '${device.name}-${utils.getStringFromEnum(orientation)}-';
      await utils.prefixFilesInDir(screenshotsDir, prefix);

      //printStatus('Moving screenshots to $dstDir');
      utils.moveFiles(screenshotsDir, destDir);

      /*
      if (runMode == RunMode.comparison) {
        final recordingDir = '${_config.recordingDir}/$dstDir';
        //printStatus('Running comparison with recorded screenshots in $recordingDir ...');
        final failedCompare =
            await compareImages(deviceName, recordingDir, dstDir);
        if (failedCompare.isNotEmpty) {
          showFailedCompare(failedCompare);
          throw 'Error: comparison failed.';
        }
      }
       */
    }
    return true; // for testing
  }

  static void showFailedCompare(Map failedCompare) {
    //printError('Comparison failed:');

    failedCompare.forEach((screenshotName, result) {
      //printError('${result['comparison']} is not equal to ${result['recording']}');
      //printError('       Differences can be found in ${result['diff']}');
    });
  }

  static Future<Map> compareImages(
      String deviceName, String recordingDir, String comparisonDir) async {
    Map failedCompare = {};
    final recordedImages = Directory(recordingDir).listSync();
    Directory(comparisonDir)
        .listSync()
        .where((screenshot) =>
            p.basename(screenshot.path).contains(deviceName) &&
            !p.basename(screenshot.path).contains(ImageMagick.kDiffSuffix))
        .forEach((screenshot) {
      final screenshotName = p.basename(screenshot.path);
      final recordedImageEntity = recordedImages.firstWhere(
          (image) => p.basename(image.path) == screenshotName,
          orElse: () =>
              throw 'Error: screenshot $screenshotName not found in $recordingDir');

      if (!im.compare(screenshot.path, recordedImageEntity.path)) {
        failedCompare[screenshotName] = {
          'recording': recordedImageEntity.path,
          'comparison': screenshot.path,
          'diff': im.getDiffImagePath(screenshot.path)
        };
      }
    });
    return failedCompare;
  }

  /// Overlay status bar over screenshot.
  static Future<void> overlay(ScreenResources resources, String screenshotPath) async {
    final tmpDir = Directory.systemTemp.path;

    late final String statusbarPath;
    // select black or white status bar based on brightness of area to be overlaid
    if (im.isThresholdExceeded(screenshotPath, _kCrop)) {
      statusbarPath = '$tmpDir/${resources.statusbarBlack}';
    } else {
      statusbarPath = '$tmpDir/${resources.statusbarWhite}';
    }

    final options = {
      'screenshotPath': screenshotPath,
      'statusbarPath': statusbarPath,
    };
    await im.convert('overlay', options);
  }

  /// Append android navigation bar to screenshot.
  static Future<void> append(ScreenResources screenResources, String screenshotPath) async {
    final tmpDir = Directory.systemTemp.path;

    final screenshotNavbarPath = '$tmpDir/${screenResources.navbar}';
    final options = {
      'screenshotPath': screenshotPath,
      'screenshotNavbarPath': screenshotNavbarPath,
    };

    await im.convert('append', options);
  }
}
