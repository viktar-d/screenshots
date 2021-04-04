import 'dart:async';
import 'dart:io';

import 'package:path/path.dart';
import 'package:screenshots3/screenshots.dart';
import 'package:screenshots3/src/utils.dart';
import 'package:screenshots3/src/screens.dart';

import 'globals.dart';


final ImageMagick _kImageMagick = ImageMagick();

/// Currently active implementation of ImageMagick.
///
/// Override this in tests with a fake/mocked daemon client.
ImageMagick im = _kImageMagick;

class ImageMagick {
  static const _kThreshold = 0.76;
  static const kDiffSuffix = '-diff';
//const kThreshold = 0.5;

  // singleton
  static final ImageMagick _imageMagick = ImageMagick._internal();
  factory ImageMagick() {
    return _imageMagick;
  }
  ImageMagick._internal();

  static const _kCrop = '1000x40+0+0'; // default sample size and location to test for brightness


  static Future<void> frame(DeviceScreen screen, String path) async {
    final backgroundColor = screen.deviceType == DeviceType.ios ? 'xc:white' : 'xc:none';

    final cmdOptions = <String>[
      '-size ${screen.sizeString} $backgroundColor',
      '( $path -resize ${screen.resizeString} )',
      '-gravity center',
      '-geometry ${screen.offsetString}',
      '-composite',
      '( ${screen.resources!.framePath} -resize ${screen.resizeString} )',
      '-gravity center',
      '-composite',
      path
    ];

    _imageMagickCmd('convert', cmdOptions);
  }

  static Future<void> overlay(ScreenResources resources, String path) async {
    late final String statusbarPath;

    if (isThresholdExceeded(path, _kCrop)) {
      statusbarPath = '$kTempDir/${resources.statusbarBlack}';
    } else {
      statusbarPath = '$kTempDir/${resources.statusbarWhite}';
    }

    final cmdOptions = <String>[
      path,
      statusbarPath,
      '-gravity north',
      '-composite $path',
    ];

    _imageMagickCmd('convert', cmdOptions);
  }

  static Future<void> append(ScreenResources resources, String path) async {
    final cmdOptions = <String>[
      '-append',
      path,
      '$kTempDir/${resources.navbar}',
      path,
    ];

    _imageMagickCmd('convert', cmdOptions);
  }

  /// Checks if brightness of sample of image exceeds a threshold.
  /// Section is specified by [cropSizeOffset] which is of the form
  /// cropSizeOffset, eg, '1242x42+0+0'.
  static bool isThresholdExceeded(String imagePath, String cropSizeOffset,
      [double threshold = _kThreshold]) {
    //convert logo.png -crop $crop_size$offset +repage -colorspace gray -format "%[fx:(mean>$threshold)?1:0]" info:
    final result = cmd(_getPlatformCmd('convert', <String>[
      imagePath,
      '-crop',
      cropSizeOffset,
      '+repage',
      '-colorspace',
      'gray',
      '-format',
      '""%[fx:(mean>$threshold)?1:0]""',
      'info:'
    ])).replaceAll('"', ''); // remove quotes ""0""
    return result == '1';
  }

  bool compare(String comparisonImage, String recordedImage) {
    final diffImage = getDiffImagePath(comparisonImage);

    var returnCode = _imageMagickCmd('compare',
        <String>['-metric', 'mae', recordedImage, comparisonImage, diffImage]);

    if (returnCode == 0) {
      // delete no-diff diff image created by image magick
      File(diffImage).deleteSync();
    }
    return returnCode == 0;
  }

  /// Append diff suffix [kDiffSuffix] to [imagePath].
  String getDiffImagePath(String imagePath) {
    final diffName = dirname(imagePath) +
        '/' +
        basenameWithoutExtension(imagePath) +
        kDiffSuffix +
        extension(imagePath);
    return diffName;
  }

  void deleteDiffs(String dirPath) {
    var dir = Directory(dirPath);

    dir.listSync()
        .where((element) => basename(element.path).contains(kDiffSuffix))
        .forEach((diffImage) => File(diffImage.path).deleteSync());
  }

  /// Different command for windows (based on recommended installed version!)
  static List<String> _getPlatformCmd(String imCmd, List<String> imCmdArgs) {
    // windows uses ImageMagick v7 or later which by default does not
    // have the legacy commands.
    if (Platform.isWindows) {
      return [
        ...['magick'],
        ...[imCmd],
        ...imCmdArgs
      ];
    } else {
      return [
        ...[imCmd],
        ...imCmdArgs
      ];
    }
  }

  /// ImageMagick command
  static int _imageMagickCmd(String imCmd, List<String> imCmdArgs) {
    return runCmd(_getPlatformCmd(imCmd, imCmdArgs));
  }
}


/// Check Image Magick is installed.
Future<bool> isImageMagicInstalled() async {
  try {
    return runCmd(Platform.isWindows ? ['magick', '-version'] : ['convert', '-version']) == 0;
  } catch (e) {
    return false;
  }
}