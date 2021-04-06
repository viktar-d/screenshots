import 'dart:convert';
import 'dart:io';

import 'package:resource_portable/resource.dart';
import 'package:screenshots3/src/daemon_client.dart';
import 'package:screenshots3/src/run.dart';
import 'package:screenshots3/src/utils.dart';
import 'package:yaml/yaml.dart';

import 'globals.dart';

const kEnvConfigPath = 'SCREENSHOTS_YAML';

const kDefaultOrientation = 'Portrait';
enum Orientation { Portrait, LandscapeRight, PortraitUpsideDown, LandscapeLeft }

class Device {
  final DeviceType deviceType;
  final String name;
  final String destName;
  final String phoneType;
  final bool frame;
  final List<Orientation> orientations;
  final bool build;
  final String deviceId;
  final bool emulator;

  String? emulatorId;

  Device({
    required this.deviceType,
    required this.name,
    required this.destName,
    required this.phoneType,
    required this.deviceId,
    required this.emulator,
    this.frame = true,
    this.orientations = const [Orientation.Portrait],
    this.build = true,
  });

  Directory getDestDirectory(String locale) {
    locale = locale.replaceAll('_', '-');

    late final String path;
    if (deviceType == DeviceType.android) {
      path = 'android/fastlane/metadata/android/$locale/images/${deviceType}Screenshots';
    } else {
      path = 'ios/fastlane/screenshots/$locale';
    }

    return Directory(path);
  }

  Future<void> shutdown(Config config) async {
    if (emulatorId == null) throw StateError('Device is not running');

    if (deviceType == DeviceType.android) {
      await _shutdownEmulator(config);
    } else {
      _shutdownSimulator();
    }
  }

  Future<void> _shutdownEmulator(Config config) async {
    cmd([config.adbPath, '-s', emulatorId!, 'emu', 'kill']);

    final client = await DaemonClient.getInstance();
    final device = await client.waitForEvent(EventType.deviceRemoved);

    if (device['id'] != emulatorId) {
      throw StateError('Device id $emulatorId was not shutdown');
    }
  }

  void rotate(Config config, Orientation orientation) {
    if (emulatorId == null) throw StateError('Device is not running');

    if (deviceType == DeviceType.android) {
      _rotateAndroid(config, orientation);
    } else {
      _rotateIOS(orientation);
    }
  }

  void _rotateAndroid(Config config, Orientation orientation) {
    late String orientationString;
    switch (orientation) {
      case Orientation.Portrait:
        orientationString = '0';
        break;
      case Orientation.LandscapeRight:
        orientationString = '1';
        break;
      case Orientation.PortraitUpsideDown:
        orientationString = '2';
        break;
      case Orientation.LandscapeLeft:
        orientationString = '3';
        break;
    }

    try {
      cmd([config.adbPath, '-s', emulatorId!, 'shell', 'settings', 'put',
        'system', 'accelerometer_rotation', '0']);
      cmd([config.adbPath, '-s', emulatorId!, 'shell', 'settings', 'put',
        'system', 'user_rotation', orientationString]);
    } catch (_) {}
  }

  void _rotateIOS(Orientation orientation) {
    late String orientationString;
    switch (orientation) {
      case Orientation.Portrait:
        orientationString = 'Portrait';
        break;
      case Orientation.LandscapeRight:
        orientationString = 'Landscape Right';
        break;
      case Orientation.PortraitUpsideDown:
        orientationString = 'Portrait Upside Down';
        break;
      case Orientation.LandscapeLeft:
        orientationString = 'Landscape Left';
        break;
    }

    cmd(['osascript', '$kTempDir/sim_orientation.scpt', orientationString]);
  }

  Future<String> getLocale(Config config) async {
    if (emulatorId == null) throw StateError('Device is not running');

    if (deviceType == DeviceType.android) {
      return _getAndroidLocale(config);
    } else {
      return await _getIOSLocale(config);
    }
  }

  String _getAndroidLocale(Config config) {
    var locale = cmd([config.adbPath, '-s', emulatorId!, 'shell', 'getprop', 'persist.sys.locale']);

    if (locale.isEmpty) {
      locale = cmd([config.adbPath, '-s', emulatorId!, 'shell', 'getprop ro.product.locale']);
    }

    return locale;
  }

  Future<String> _getIOSLocale(Config config) async {
    final env = Platform.environment;
    final globalPreferencesPath = '${env['HOME']}/Library/Developer/CoreSimulator/${emulatorId!}/data/Library/Preferences/.GlobalPreferences.plist';
    final globalPreferences = File(globalPreferencesPath);

    if (!globalPreferences.existsSync()) {
      final resource = Resource('package:screenshots3/resources/defaultGlobalPreferences.plist');
      globalPreferences.writeAsStringSync(await resource.readAsString());
      cmd(['plutil', '-convert', 'binary1', globalPreferences.path]);
    }

    final localeInfo = jsonDecode(
      cmd(['plutil', '-convert', 'json', '-o', '-', globalPreferencesPath])
    ) as Map<String, dynamic>;

    return localeInfo['AppLocale'] as String;
  }

  Future<void> setLocale(Config config, String locale) async {
    if (deviceType == DeviceType.android) {
      _setAndroidEmulatorLocale(config, locale);
    } else {
      final changed = await _setSimulatorLocale(config, locale);
      if (changed) {
        print('restarting simulator due to locale change...');

        _shutdownSimulator();
        await _startSimulator();
      }
    }
  }

  void _setAndroidEmulatorLocale(Config config, String locale) {
    final deviceLocale = _getAndroidLocale(config);

    if (canonicalizedLocale(deviceLocale) != canonicalizedLocale(locale)) {
      if (cmd([config.adbPath, '-s', emulatorId!, 'root'])
          == 'adbd cannot run as root in production builds\n') {
        throw StateError('Cannot change locale of production emulator');
      }

      cmd([config.adbPath, '-s', emulatorId!, 'shell', 'setprop',
        'persist.sys.locale', locale, ';', 'setprop', 'ctl.restart', 'zygote']);
    }
  }

  Future<bool> _setSimulatorLocale(Config config, String locale) async {
    final deviceLocale = await _getIOSLocale(config);

    if (canonicalizedLocale(deviceLocale) != canonicalizedLocale(locale)) {
      cmd([
        '$kTempDir/resources/script/simulator-controller',
        emulatorId!, 'locale', locale
      ]);

      return true;
    }

    return false;
  }

  void _shutdownSimulator() {
    cmd(['xcrun', 'simctl', 'shutdown', emulatorId!]);
  }

  Future<void> _startSimulator() async {
    cmd(['xcrun', 'simctl', 'boot', emulatorId!]);

    final client = await DaemonClient.getInstance();
    await client.waitForEmulatorToStart(emulatorId!);
  }


  static Device fromYaml(
      final String deviceName,
      final Map<dynamic, dynamic> yaml,
      final DeviceType type,
      final List<RunningDevice> availableDevices
  ) {
    final device = availableDevices.firstWhere((element) {
      if (element.deviceType != type) return false;

      if (element.isEmulator && element.deviceType == DeviceType.android) {
        return element
            .deviceId
            .toUpperCase()
            .contains(deviceName.toUpperCase());
      } else {
        return element.deviceId.contains(deviceName);
      }
    }, orElse: () => throw StateError('No device found with name $deviceName'));

    var defaultFrame = true;
    final orientationStringList = List<String>.of(yaml['orientation'] as List<String>? ?? ['Portrait']);
    final orientations = <Orientation>[];

    for (var orientationString in orientationStringList) {
      switch (orientationString) {
        case 'Portrait':
          orientations.add(Orientation.Portrait);
          defaultFrame &= true;
          break;
        case 'LandscapeRight':
          orientations.add(Orientation.LandscapeRight);
          defaultFrame = false;
          break;
        case 'LandscapeLeft':
          orientations.add(Orientation.LandscapeLeft);
          defaultFrame = false;
          break;
        case 'PortraitUpsideDown':
          orientations.add(Orientation.PortraitUpsideDown);
          defaultFrame &= true;
          break;
        default:
          throw ArgumentError('Invalid orientation value: $orientationString');
      }
    }

    return Device(
      deviceType: type,
      name: deviceName,
      phoneType: yaml['deviceFrame'] as String,
      destName: yaml['deviceType'] as String? ?? 'phone',
      frame: yaml['frame'] as bool? ?? defaultFrame,
      orientations: orientations,
      build: yaml['build'] as bool? ?? true,
      deviceId: device.deviceId,
      emulator: device.isEmulator,
    );
  }
}


class Config {
  final List<String> tests;
  final List<String> locales;

  final List<Device> devices;
  final String? sdkPath;

  Config({
    required this.tests,
    required this.locales,
    this.devices = const [],
    this.sdkPath
  });

  String get adbPath {
    final separator = Platform.pathSeparator;
    final extension = Platform.isWindows ? '.exe' : '';

    return sdkPath == null
        ? 'adb$extension'
        : '$sdkPath${separator}platform-tools${separator}adb$extension';
  }

  static Config fromYaml(final Map<dynamic, dynamic> yaml, List<RunningDevice> availableDevices) {
    final deviceMap = yaml['devices']['android'] as Map<dynamic, dynamic>? ?? <dynamic, dynamic>{};
    if (Platform.isMacOS) {
      deviceMap.addAll(yaml['devices']['ios'] as Map<dynamic, dynamic>? ?? <dynamic, dynamic>{});
    }

    final devices = <Device>[];

    for (final item in deviceMap.entries) {
      final value = item.value as Map<dynamic, dynamic>? ?? <dynamic, dynamic>{};
      final key = item.key as String;

      devices.add(
        Device.fromYaml(key, value, DeviceType.android, availableDevices)
      );
    }

    return Config (
      tests: List<String>.from(yaml['test'] as List<dynamic>? ?? <dynamic>[]),
      locales: List<String>.from(yaml['locales'] as List<dynamic>? ?? <dynamic>[]),
      devices: devices,
      sdkPath: yaml['sdkPath'] as String?
    );
  }

  List<Device> get iosDevices =>
      devices.where((e) => e.deviceType == DeviceType.ios).toList();

  List<Device> get androidDevices =>
      devices.where((e) => e.deviceType == DeviceType.android).toList();

  List<String> get deviceNames => devices.map((e) => e.name).toList();

  static Config fromString(final String yamlString, List<RunningDevice> availableDevices) {
    final yaml = loadYaml(yamlString) as Map<dynamic, dynamic>;
    return fromYaml(yaml, availableDevices);
  }

  static Config loadFromFile(final String path, List<RunningDevice> availableDevices) {
    var file = File(path);

    if (!file.existsSync()) {
      throw ArgumentError('Config file $path not found');
    }

    return fromString(file.readAsStringSync(), availableDevices);
  }

  Device getDevice(String deviceName) => devices.firstWhere(
      (device) => device.name == deviceName,
      orElse: () => throw 'Error: no device configured for \'$deviceName\'');

  /// Check for active run type.
  /// Run types can only be one of [DeviceType].
  bool isRunTypeActive(DeviceType runType) {
    return devices.any((element) => element.deviceType == runType);
  }
}