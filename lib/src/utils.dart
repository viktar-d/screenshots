import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart';
import 'package:screenshots/src/config.dart';
import 'package:screenshots/src/utils/process.dart';

import 'globals.dart';

class Tuple<A, B> {
  final A first;
  final B second;

  const Tuple(this.first, this.second);
}

class Tuple3<A, B, C> {
  final A first;
  final B second;
  final C third;

  Tuple3(this.first, this.second, this.third);
}

/// Move files from [srcDir] to [dstDir].
/// If dstDir does not exist, it is created.
void moveFiles(String srcDir, String dstDir) {
  if (!Directory(dstDir).existsSync()) {
    Directory(dstDir).createSync(recursive: true);
  }
  Directory(srcDir).listSync().forEach((file) {
    file.renameSync('$dstDir/${basename(file.path)}');
  });
}


/// Creates a list of available iOS simulators.
/// (really just concerned with simulators for now).
/// Provides access to their IDs and status'.
Map getIosSimulators() {
  final simulators = cmd(['xcrun', 'simctl', 'list', 'devices', '--json']);
  final simulatorsInfo = jsonDecode(simulators)['devices'];
  return transformIosSimulators(simulatorsInfo);
}

/// Transforms latest information about iOS simulators into more convenient
/// format to index into by simulator name.
/// (also useful for testing)
Map transformIosSimulators(Map simsInfo) {
  // transform json to a Map of device name by a map of iOS versions by a list of
  // devices with a map of properties
  // ie, Map<String, Map<String, List<Map<String, String>>>>
  // In other words, just pop-out the device name for 'easier' access to
  // the device properties.
  Map simsInfoTransformed = {};

  simsInfo.forEach((iOSName, sims) {
    // note: 'isAvailable' field does not appear consistently
    //       so using 'availability' as well
    isSimAvailable(sim) =>
        sim['availability'] == '(available)' || sim['isAvailable'] == true;
    for (final sim in sims) {
      // skip if simulator unavailable
      if (!isSimAvailable(sim)) continue;

      // init iOS versions map if not already present
      if (simsInfoTransformed[sim['name']] == null) {
        simsInfoTransformed[sim['name']] = {};
      }

      // init iOS version simulator array if not already present
      // note: there can be multiple versions of a simulator with the same name
      //       for an iOS version, hence the use of an array.
      if (simsInfoTransformed[sim['name']][iOSName] == null) {
        simsInfoTransformed[sim['name']][iOSName] = [];
      }

      // add simulator to iOS version simulator array
      simsInfoTransformed[sim['name']][iOSName].add(sim);
    }
  });
  return simsInfoTransformed;
}

// finds the iOS simulator with the highest available iOS version
Map getHighestIosSimulator(Map iosSims, String simName) {
  final Map iOSVersions = iosSims[simName];

  // get highest iOS version
  var iOSVersionName = getHighestIosVersion(iOSVersions);

  final iosVersionSims = iosSims[simName][iOSVersionName];
  if (iosVersionSims.length == 0) {
    throw "Error: no simulators found for \'$simName\'";
  }
  // use the first device found for the iOS version
  return iosVersionSims[0];
}

// returns name of highest iOS version names
String getHighestIosVersion(Map iOSVersions) {
  // sort keys in iOS version order
  final iosVersionNames = iOSVersions.keys.toList();
  iosVersionNames.sort((v1, v2) {
    return v1.compareTo(v2);
  });

  // get the highest iOS version
  final iOSVersionName = iosVersionNames.last;
  return iOSVersionName;
}

///// Create list of avds,
//List<String> getAvdNames() {
//  return cmd([getEmulatorPath(androidSdk), '-list-avds']).split('\n');
//}

///// Get the highest available avd version for the android emulator.
//String getHighestAVD(String deviceName) {
//  final emulatorName = deviceName.replaceAll(' ', '_');
//  final avds =
//      getAvdNames().where((name) => name.contains(emulatorName)).toList();
//  // sort list in android API order
//  avds.sort((v1, v2) {
//    return v1.compareTo(v2);
//  });
//
//  return avds.last;
//}

/// Adds prefix to all files in a directory
Future prefixFilesInDir(String dirPath, String prefix) async {
    await for (final file in Directory(dirPath).list(recursive: false, followLinks: false)) {
      final path = file.path;
      await file.rename('${dirname(path)}/$prefix${basename(path)}');
    }
}

/// Converts [_enum] value to [String].
String getStringFromEnum(dynamic _enum) => _enum.toString().split('.').last;

String getDeviceLocale(Device device) {
  if (device.deviceType == DeviceType.android) {
    return getAndroidDeviceLocale(device.deviceId);
  } else {
    return getIosSimulatorLocale(device.deviceId);
  }
}

/// Returns locale of currently attached android device.
String getAndroidDeviceLocale(String deviceId) {
// ro.product.locale is available on first boot but does not update,
// persist.sys.locale is empty on first boot but updates with locale changes
  var locale = cmd([
    'adb', //getAdbPath(androidSdk),
    '-s',
    deviceId,
    'shell',
    'getprop',
    'persist.sys.locale'
  ]).trim();
  if (locale.isEmpty) {
    locale = cmd([
      'adb', //getAdbPath(androidSdk),
      '-s',
      deviceId,
      'shell',
      'getprop ro.product.locale'
    ]).trim();
  }
  return locale;
}

/// Returns locale of simulator with udid [udId].
String getIosSimulatorLocale(String udId) {
  final env = Platform.environment;
  final globalPreferencesPath =
      '${env['HOME']}/Library/Developer/CoreSimulator/Devices/$udId/data/Library/Preferences/.GlobalPreferences.plist';

  // create file if missing (iOS 13)
  final globalPreferences = File(globalPreferencesPath);
  if (!globalPreferences.existsSync()) {
    final contents = '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>AKLastIDMSEnvironment</key>
	<integer>0</integer>
	<key>AddingEmojiKeybordHandled</key>
	<true/>
	<key>AppleITunesStoreItemKinds</key>
	<array>
		<string>itunes-u</string>
		<string>movie</string>
		<string>album</string>
		<string>ringtone</string>
		<string>software-update</string>
		<string>booklet</string>
		<string>tone</string>
		<string>music-video</string>
		<string>tv-episode</string>
		<string>tv-season</string>
		<string>song</string>
		<string>podcast</string>
		<string>software</string>
		<string>audiobook</string>
		<string>podcast-episode</string>
		<string>wemix</string>
		<string>eBook</string>
		<string>mix</string>
		<string>artist</string>
		<string>document</string>
	</array>
	<key>AppleKeyboards</key>
	<array>
		<string>en_US@sw=QWERTY;hw=Automatic</string>
		<string>emoji@sw=Emoji</string>
		<string>en_US@sw=QWERTY;hw=Automatic</string>
	</array>
	<key>AppleKeyboardsExpanded</key>
	<integer>1</integer>
	<key>AppleLanguages</key>
	<array>
		<string>en</string>
	</array>
	<key>AppleLanguagesDidMigrate</key>
	<string>15C107</string>
	<key>AppleLocale</key>
	<string>en_US</string>
	<key>ApplePasscodeKeyboards</key>
	<array>
		<string>en_US@sw=QWERTY;hw=Automatic</string>
		<string>emoji@sw=Emoji</string>
		<string>en_US@sw=QWERTY;hw=Automatic</string>
	</array>
	<key>PKKeychainVersionKey</key>
	<integer>4</integer>
</dict>
</plist>
    ''';
    globalPreferences.writeAsStringSync(contents);
    cmd(['plutil', '-convert', 'binary1', globalPreferences.path]);
  }
  final localeInfo = jsonDecode(
      cmd(['plutil', '-convert', 'json', '-o', '-', globalPreferencesPath]));
  final locale = localeInfo['AppleLocale'];
  return locale;
}

///// Get android emulator id from a running emulator with id [deviceId].
///// Returns emulator id as [String].
//String getAndroidEmulatorId(String deviceId) {
//  // get name of avd of running emulator
//  return cmd([getAdbPath(androidSdk), '-s', deviceId, 'emu', 'avd', 'name'])
//      .split('\r\n')
//      .map((line) => line.trim())
//      .first;
//}
//
///// Find android device id with matching [emulatorId].
///// Returns matching android device id as [String].
//String findAndroidDeviceId(String emulatorId) {
//  /// Get the list of running android devices by id.
//  List<String> getAndroidDeviceIds() {
//    return cmd([getAdbPath(androidSdk), 'devices'])
//        .trim()
//        .split('\n')
//        .sublist(1) // remove first line
//        .map((device) => device.split('\t').first)
//        .toList();
//  }
//
//  final devicesIds = getAndroidDeviceIds();
//  if (devicesIds.isEmpty) return null;
//  return devicesIds.firstWhere(
//      (deviceId) => emulatorId == getAndroidEmulatorId(deviceId),
//      orElse: () => null);
//}

///// Stop an android emulator.
//Future stopAndroidEmulator(String deviceId, String stagingDir) async {
//  cmd([getAdbPath(), '-s', deviceId, 'emu', 'kill']);
//  // wait for emulator to stop
//  await streamCmd([
//    '$stagingDir/resources/script/android-wait-for-emulator-to-stop',
//    deviceId
//  ]);
//}

/// Wait for android device/emulator locale to change.
Future<String> waitAndroidLocaleChange(String deviceId, String toLocale) async {
  final regExp = RegExp(
      'ContactsProvider: Locale has changed from .* to \\[${toLocale.replaceFirst('-', '_')}\\]|ContactsDatabaseHelper: Switching to locale \\[${toLocale.replaceFirst('-', '_')}\\]');
//  final regExp = RegExp(
//      'ContactsProvider: Locale has changed from .* to \\[${toLocale.replaceFirst('-', '_')}\\]');
//  final regExp = RegExp(
//      'ContactsProvider: Locale has changed from .* to \\[${toLocale.replaceFirst('-', '_')}\\]|ContactsDatabaseHelper: Locale change completed');
  final line =
      await waitSysLogMsg(deviceId, regExp, toLocale.replaceFirst('-', '_'));
  return line;
}


/// Wait for message to appear in sys log and return first matching line
Future<String> waitSysLogMsg(
    String deviceId, RegExp regExp, String locale) async {
  cmd([
    //getAdbPath(androidSdk),
    'adb',
    '-s', deviceId, 'logcat', '-c']);
//  await Future.delayed(Duration(milliseconds: 1000)); // wait for log to clear
  await Future.delayed(Duration(milliseconds: 500)); // wait for log to clear
  // -b main ContactsDatabaseHelper:I '*:S'
  final delegate = await processManager.start([
    'adb', //getAdbPath(androidSdk),
    '-s',
    deviceId,
    'logcat',
    '-b',
    'main',
    '*:S',
    'ContactsDatabaseHelper:I',
    'ContactsProvider:I',
    '-e',
    locale
  ]);

  return await delegate.stdout
    .transform(Utf8Decoder(allowMalformed: true))
    .transform(const LineSplitter())
    .firstWhere((line) => regExp.hasMatch(line));
}


/// Run command and return stdout as [string].
String cmd(List<String> cmd, {String? workingDirectory}) {
  final result = processManager.runSync(
    cmd,
    workingDirectory: workingDirectory,
    runInShell: true
  );
  //if (!silent) printStatus(result.stdout);
  if (result.exitCode != 0) {
    //if (silent) printError(result.stdout);
    //printError(result.stderr);
    throw 'command failed: exitcode=${result.exitCode}, cmd=\'${cmd.join(" ")}\', workingDir=$workingDirectory';
  }
  // return stdout
  return result.stdout;
}

/// Run command and return exit code as [int].
///
/// Allows failed exit code.
int runCmd(List<String> cmd) {
  final result = processManager.runSync(cmd);
  if (result.exitCode != 0) {
    //printTrace(result.stdout);
    //printTrace(result.stderr);
  }
  return result.exitCode;
}

/// Execute command with arguments [cmd] in a separate process
/// and stream stdout/stderr.
Future<void> streamCmd(
  List<String> cmd, {
  String? workingDirectory,
  Map<String, String> environment = const {},
}) async {
  var exitCode = await runCommandAndStreamOutput(
      cmd,
      workingDirectory: workingDirectory,
      environment: environment
  );
  if (exitCode != 0) {
    throw 'command failed: exitcode=$exitCode, cmd=\'${cmd.join(" ")}\', workingDirectory=$workingDirectory';
  }
}
