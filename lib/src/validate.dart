import 'dart:io';

import 'config.dart';

/// Check emulators and simulators are installed, devices attached,
/// matching screen is available and tests exist.
Future<bool> isValidConfig(
    Config config,
) async {
  var isValid = true;

  // validate tests
  for (final test in config.tests) {
    if (!isValidTestPaths(test)) {
      //printError('Invalid config: \'$test\' in $configPath');
      isValid = false;
    }
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
bool isSimulatorInstalled(Map<String, dynamic> simulators, String deviceName) {
  // check simulator installed
  var isSimulatorInstalled = false;
  simulators.forEach((simulatorName, dynamic iOSVersions) {
    if (simulatorName == deviceName) {
      // check for duplicate installs
      //final iOSVersionName = utils.getHighestIosVersion(iOSVersions as Map<String, dynamic>);
      // check for device present with multiple os's
      // or with duplicate name
      //if (iOSVersions.length > 1 || iOSVersions[iOSVersionName].length > 1) {
        //printStatus('Warning: \'$deviceName\' has multiple iOS versions.');
        //printStatus('       : Using \'$deviceName\' with iOS version $iOSVersionName (ID: $udid).');
      //}

      isSimulatorInstalled = true;
    }
  });
  return isSimulatorInstalled;
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
