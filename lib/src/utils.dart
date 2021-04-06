import 'dart:convert';
import 'package:screenshots3/src/daemon_client.dart';

/// Creates a list of available iOS simulators.
/// (really just concerned with simulators for now).
/// Provides access to their IDs and status'.
Map<String, dynamic> getIosSimulators() {
  final simulators = cmd(['xcrun', 'simctl', 'list', 'devices', '--json']);
  final simulatorsInfo = jsonDecode(simulators)['devices'] as Map<String, dynamic>;
  return transformIosSimulators(simulatorsInfo);
}

/// Transforms latest information about iOS simulators into more convenient
/// format to index into by simulator name.
/// (also useful for testing)
Map<String, dynamic> transformIosSimulators(Map<String, dynamic> simsInfo) {
  // transform json to a Map of device name by a map of iOS versions by a list of
  // devices with a map of properties
  // ie, Map<String, Map<String, List<Map<String, String>>>>
  // In other words, just pop-out the device name for 'easier' access to
  // the device properties.
  final simsInfoTransformed = <String, dynamic>{};

  simsInfo.forEach((iOSName, dynamic sims) {
    // note: 'isAvailable' field does not appear consistently
    //       so using 'availability' as well
    bool isSimAvailable(Map<String, dynamic> sim) =>
        sim['availability'] == '(available)' || sim['isAvailable'] == true;

    for (final Map<String, dynamic> sim in sims) {
      // skip if simulator unavailable
      if (!isSimAvailable(sim)) continue;

      // init iOS versions map if not already present
      if (simsInfoTransformed[sim['name']] == null) {
        simsInfoTransformed[sim['name'] as String] = <String, dynamic>{};
      }

      // init iOS version simulator array if not already present
      // note: there can be multiple versions of a simulator with the same name
      //       for an iOS version, hence the use of an array.
      if (simsInfoTransformed[sim['name']][iOSName] == null) {
        simsInfoTransformed[sim['name']][iOSName] = <String>[];
      }

      // add simulator to iOS version simulator array
      simsInfoTransformed[sim['name']][iOSName].add(sim);
    }
  });
  return simsInfoTransformed;
}

// finds the iOS simulator with the highest available iOS version
Map<String, dynamic> getHighestIosSimulator(Map<String, dynamic> iosSims, String simName) {
  final iOSVersions = iosSims[simName] as Map<String, dynamic>;

  // get highest iOS version
  var iOSVersionName = getHighestIosVersion(iOSVersions);

  final iosVersionSims = iOSVersions[iOSVersionName] as List<Map<String, dynamic>>;

  if (iosVersionSims.isEmpty) {
    throw "Error: no simulators found for \'$simName\'";
  }
  // use the first device found for the iOS version
  return iosVersionSims[0];
}

// returns name of highest iOS version names
String getHighestIosVersion(Map<String, dynamic> iOSVersions) {
  // sort keys in iOS version order
  final iosVersionNames = iOSVersions.keys.toList();
  iosVersionNames.sort((v1, v2) {
    return v1.compareTo(v2);
  });

  // get the highest iOS version
  final iOSVersionName = iosVersionNames.last;
  return iOSVersionName;
}

/// Run command and return stdout as [string].
String cmd(List<String> cmd, {String? workingDirectory}) {
  print('calling cmd: ${cmd.join(' ')}');
  final result = DaemonClient.processManager.runSync(
    cmd,
    runInShell: true,
    workingDirectory: workingDirectory ?? '.',
    stdoutEncoding: utf8
  );
  if (result.exitCode != 0) {
    print('cmd error: ${result.stderr}');
  }

  return (result.stdout as String).trim();
}
