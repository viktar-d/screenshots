import 'dart:io';

import 'config.dart';
import 'screens.dart';
import 'utils.dart' as utils;

/// Check emulators and simulators are installed, devices attached,
/// matching screen is available and tests exist.
Future<bool> isValidConfig(
    Config config,
    ScreenManager screens,
) async {
  var isValid = true;
  var showDeviceGuide = false;

  // validate tests
  for (final test in config.tests) {
    if (!isValidTestPaths(test)) {
      //printError('Invalid config: \'$test\' in $configPath');
      isValid = false;
    }
  }

  // validate android device
  for (var configDevice in config.androidDevices) {
    if (configDevice.frame) {
      // check screen available for this device
      if (!_isScreenAvailable(screens, configDevice.name)) {
        isValid = false;
      }
    }
  }

  // validate macOS
  if (Platform.isMacOS) {
    for (var configDevice in config.iosDevices) {
      if (configDevice.frame) {
        // check screen available for this device
        if (!_isScreenAvailable(screens, configDevice.name)) {
          isValid = false;
        }
      }
    }
  } else {
    // if not macOS
    if (config.iosDevices.isNotEmpty) {
      //printError('An iOS run cannot be configured on a non-macOS platform. Please modify $configPath');
      isValid = false;
    }
  }

  // validate device params
  if (showDeviceGuide) {
    //deviceGuide(screens, allDevices, allEmulators);
  }

  return isValid;
}

/// Checks all paths are valid.
/// Note: does not cover all uses cases.
bool isValidTestPaths(String driverArgs) {
  final driverPathRegExp = RegExp(r'--driver[= ]+([^\s]+)');
  final targetPathRegExp = RegExp(r'--target[= ]+([^\s]+)');
  final regExps = [driverPathRegExp, targetPathRegExp];

  bool pathExists(String path) {
    if (!File(path).existsSync()) {
      //printError('File \'$path\' not found.');
      return false;
    }
    return true;
  }

  // Remember any failed path during matching (if any matching)
  var isInvalidPath = false;
  var matchFound = false;

  for (final regExp in regExps) {
    final match = regExp.firstMatch(driverArgs);
    if (match != null) {
      matchFound = true;
      final path = match.group(1);
      isInvalidPath = isInvalidPath || !pathExists(path!);
    }
  }

  // if invalid path found during matching return, otherwise check default path
  return !(isInvalidPath
      ? isInvalidPath
      : matchFound ? isInvalidPath : !pathExists(driverArgs));
}

/// Checks if a simulator is installed, matching the device named in config file.
bool isSimulatorInstalled(Map simulators, String deviceName) {
  // check simulator installed
  bool isSimulatorInstalled = false;
  simulators.forEach((simulatorName, iOSVersions) {
    if (simulatorName == deviceName) {
      // check for duplicate installs
      final iOSVersionName = utils.getHighestIosVersion(iOSVersions);
      final udid = iOSVersions[iOSVersionName][0]['udid'];
      // check for device present with multiple os's
      // or with duplicate name
      if (iOSVersions.length > 1 || iOSVersions[iOSVersionName].length > 1) {
        //printStatus('Warning: \'$deviceName\' has multiple iOS versions.');
        //printStatus('       : Using \'$deviceName\' with iOS version $iOSVersionName (ID: $udid).');
      }

      isSimulatorInstalled = true;
    }
  });
  return isSimulatorInstalled;
}

// check screen is available for device
bool _isScreenAvailable(ScreenManager screens, String deviceName) {
  final screen = screens.getScreen(deviceName);
  if (screen == null || screen.isAndroidModelTypeScreen) {
    //printError('Screen not available for device \'$deviceName\' in $configPath.');
    //printError(
    //    '\n  Use a device with a supported screen or set \'frame: false\' for'
    //    '\n  device in $configPath.');
    //screenGuide(screens);
    //printStatus(
    //    '\n  If framing for device is required, request screen support by'
    //    '\n  creating an issue in:'
    //    '\n  https://github.com/mmcc007/screenshots/issues.');

    return false;
  }
  return true;
}
/*
void screenGuide(ScreenManager screens) {
  //printStatus('\nScreen Guide:');
  //printStatus('\n  Supported screens:');
  for (final os in ['android', 'ios']) {
    //printStatus('    $os:');
    for (String deviceName in screens.getSupportedDeviceNamesByOs(os)) {
      //printStatus('      $deviceName (${screens.getScreen(deviceName)['size']})');
    }
  }
}
 */


void _printSimulators() {
  /*
  final simulatorNames = utils.getIosSimulators().keys.toList();
  simulatorNames.sort((thisSim, otherSim) =>
      '$thisSim'.contains('iPhone') && !'$otherSim'.contains('iPhone')
          ? -1
          : thisSim.compareTo(otherSim));
  if (simulatorNames.isNotEmpty) {
    printStatus('\n  Installed simulators:');
    simulatorNames.forEach((simulatorName) =>
        printStatus('    $simulatorName'));
  }

   */
}

bool isValidFrame(dynamic frame) {
  return frame != null && (frame == true || frame == false);
}
