import 'dart:io';

import 'package:screenshots3/src/daemon_client.dart';
import 'package:screenshots3/src/orientation.dart';
import 'package:yaml/yaml.dart';

import 'globals.dart';

const kEnvConfigPath = 'SCREENSHOTS_YAML';

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

  String getDestPath(String locale, String androidModelType) {
    locale = locale.replaceAll('_', '-');

    if (deviceType == DeviceType.android) {
      return 'android/fastlane/metadata/android/$locale/images/${androidModelType}Screenshots';
    } else {
      return 'ios/fastlane/screenshots/$locale';
    }
  }

  static Device fromYaml(
      final String deviceName,
      final Map<dynamic, dynamic> yaml,
      final DeviceType type,
      final List<RunningDevice> availableDevices
  ) {
    final device = availableDevices.firstWhere((element) {
      if (element.deviceType != type) return false;
      print(element.deviceId);

      if (element.isEmulator && element.deviceType == DeviceType.android) {
        return element
            .deviceId
            .replaceAll('_', '-')
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

  Config({
    required this.tests,
    required this.locales,
    this.devices = const [],
  });

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