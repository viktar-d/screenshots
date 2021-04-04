import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:screenshots3/src/daemon_client.dart';
import 'package:screenshots3/src/orientation.dart';
import 'package:screenshots3/src/utils.dart';
import 'package:yaml/yaml.dart';

import 'globals.dart';
import 'screens.dart';
import 'utils.dart' as utils;

const kEnvConfigPath = 'SCREENSHOTS_YAML';

class Device {
  final DeviceType deviceType;
  final String name;
  final bool frame;
  final List<Orientation> orientations;
  final bool build;
  final String deviceId;
  final bool emulator;

  Device({
    required this.deviceType,
    required this.name,
    required this.deviceId,
    required this.emulator,
    this.frame = true,
    this.orientations = const [Orientation.Portrait],
    this.build = true,
  }) {
    for (var orientation in orientations) {
      if (orientation == Orientation.LandscapeLeft ||
          orientation == Orientation.LandscapeRight) {
        if (frame == true) {
          throw ArgumentError(
              'Cannot set frame=true if orientation is landscape');
        }
      }
    }
  }

  String getDestPath(String locale, String androidModelType) {
    locale = locale.replaceAll('_', '-');

    if (deviceType == DeviceType.android) {
      return 'android/fastlane/metadata/android/$locale/images/${androidModelType}Screenshots';
    } else {
      return 'ios/fastlane/screenshots/$locale';
    }
  }

  static Device fromYaml(Map<dynamic, dynamic> yaml, DeviceType type, List<RunningDevice> availableDevices) {

    final deviceName = yaml['name'];

    final device = availableDevices.firstWhere((element) {
      if (element.deviceType != type) return false;

      if (element.isEmulator && element.deviceType == DeviceType.android) {
        return element
            .deviceId
            .replaceAll('_', '-')
            .toUpperCase()
            .contains(deviceName.toUpperCase());
      } else {
        return element.deviceId.contains(deviceName);
      }
    });

    var defaultFrame = true;
    final orientationStringList = List<String>.of(yaml['orientation'] ?? ['Portrait']);
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
      frame: yaml['frame'] ?? defaultFrame,
      orientations: orientations,
      build: yaml['build'] ?? true,
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

    final iosDevices = yaml['devices']['ios'] ?? [];
    final androidDevices = yaml['devices']['android'] ?? [];

    final devices = <Device>[];

    devices.addAll(androidDevices.map((yaml) => Device.fromYaml(yaml, DeviceType.android, availableDevices)));
    if (Platform.isMacOS) {
      devices.addAll(iosDevices.map((yaml) =>
          Device.fromYaml(yaml, DeviceType.ios, availableDevices)));
    }

    return Config (
      tests: List<String>.from(yaml['test']),
      locales: List<String>.from(yaml['locales']),
      devices: devices,
    );
  }

  List<Device> get iosDevices =>
      devices.where((e) => e.deviceType == DeviceType.ios).toList();

  List<Device> get androidDevices =>
      devices.where((e) => e.deviceType == DeviceType.android).toList();

  List<String> get deviceNames => devices.map((e) => e.name).toList();

  static Config fromString(final String yamlString, List<RunningDevice> availableDevices) {
    var yaml = loadYaml(yamlString);
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