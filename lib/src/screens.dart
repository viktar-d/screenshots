import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:resource_portable/resource.dart';
import 'package:screenshots/src/utils.dart';
import 'package:yaml/yaml.dart';

import 'globals.dart';


class ScreenResources {
  final String statusbar;
  final String statusbarBlack;
  final String statusbarWhite;
  final String frame;
  final String? navbar;

  ScreenResources({
    required this.statusbar,
    required this.statusbarBlack,
    required this.statusbarWhite,
    required this.frame,
    this.navbar
  });

  static ScreenResources fromYaml(final Map<dynamic, dynamic> yaml) {
    return ScreenResources(
      statusbar: yaml['statusbar'] as String,
      statusbarBlack: yaml['statusbarBlack'] as String,
      statusbarWhite: yaml['statusbarWhite'] as String,
      frame: yaml['frame']  as String,
      navbar: yaml['navbar'] as String?,
    );
  }

  String get framePath => '$kTempDir/$frame';

  Future<void> unpack() async {
    await _unpackImage(statusbar);
    await _unpackImage(statusbarBlack);
    await _unpackImage(statusbarWhite);
    await _unpackImage(frame);

    if (navbar != null) {
      await _unpackImage(navbar!);
    }
  }

  Future<void> _unpackImage(String uri) async {
    final resource = Resource('package:screenshots/$uri');
    final resourceImage = await resource.readAsBytes();

    final dstPath = '$kTempDir/$uri';

    final file = await File(dstPath).create(recursive: true);
    await file.writeAsBytes(resourceImage, flush: true);
  }
}

class DeviceScreen {
  final DeviceType deviceType;
  final String destName;
  final List<String> devices;
  final double resize;
  final Tuple<int, int> offset;
  final Tuple<int, int> size;
  final ScreenResources? resources;

  DeviceScreen({
    required this.deviceType,
    required this.destName,
    required this.devices,
    this.resize = 1,
    this.offset = const Tuple<int, int>(0, 0),
    this.size = const Tuple<int, int>(1080, 1920),
    this.resources,
  });

  String get sizeString => '${size.first}x${size.second}';
  String get resizeString => '${resize * 100}%';
  String get offsetString {
    var value = '';
    if (offset.first >= 0) {
      value += '+';
    }
    value += '${offset.first}';

    if (offset.second >= 0) {
      value += '+';
    }
    value += '${offset.second}';

    return value;
  }


  static DeviceScreen fromYaml(final Map<dynamic, dynamic> yaml, DeviceType type) {
    final sizeString = yaml['size'] as String?;
    final resizeString = yaml['resize'] as String?;
    final offsetString = yaml['offset'] as String?;

    final resources = yaml['resources'];

    return DeviceScreen(
      deviceType: type,
      destName: yaml['destName'] as String,
      devices: List<String>.from(yaml['devices']),
      resize: resizeString == null ? 1 : _parseResize(resizeString),
      offset: offsetString == null ? Tuple<int, int>(0, 0) : _parseOffset(offsetString),
      size: sizeString == null ? Tuple<int, int>(1080, 1920) : _parseSize(sizeString),
      resources: resources == null ? null : ScreenResources.fromYaml(resources),
    );
  }

  static Tuple<int, int> _parseSize(String sizeString) {
    var parts = sizeString.split('x');

    return Tuple(int.parse(parts.first), int.parse(parts.last));
  }

  static Tuple<int, int> _parseOffset(String offsetString) {
    late int x, y;

    var current = offsetString[0];
    for (var i = 1; i < offsetString.length; i++) {
      final char = offsetString[i];

      if (char == '+' || char == '-') {
        x = int.parse(current);
        current = '';
      }
    }

    y = int.parse(current);

    return Tuple<int, int>(x, y);
  }

  static double _parseResize(String resizeString) {
    resizeString = resizeString.replaceAll('%', '');
    final value = double.parse(resizeString);

    return value / 100;
  }

  /// Test if screen is used for identifying android model type.
  bool get isAndroidModelTypeScreen => size == null;


}

/// Manage screens
class ScreenManager {
  static const _screensPath = 'resources/screens.yaml';

  final Map<String, DeviceScreen> screens;

  ScreenManager({
    this.screens = const {},
  });

  static Future<ScreenManager> fromResource() async {
    final resource = Resource('package:screenshots/$_screensPath');

    var screens = await resource.readAsString(encoding: utf8);
    var yaml = loadYaml(screens);

    return fromYaml(yaml);
  }

  static ScreenManager fromYaml(final Map<dynamic, dynamic> yaml) {
    var ios = yaml['ios'] as Map;
    var android = yaml['android'] as Map;

    var map = <String, DeviceScreen>{};

    for (var entry in ios.entries) {
      map[entry.key] = DeviceScreen.fromYaml(entry.value, DeviceType.ios);
    }

    for (var entry in android.entries) {
      map[entry.key] = DeviceScreen.fromYaml(entry.value, DeviceType.android);
    }

    return ScreenManager(screens: map);
  }

  DeviceScreen? getScreen(final String deviceName) {
    try {
      return screens.values.firstWhere((e) => e.devices.contains(deviceName));
    } on StateError {
      return null;
    }
  }

  List<String> getDeviceNamesForOs(DeviceType type) {
    final deviceNames = <String>[];

    screens
        .values
        // omit devices that have screens that are only used to identify android model type
        .where((e) => e.deviceType == type && !e.isAndroidModelTypeScreen)
        .forEach((e) => deviceNames.addAll(e.devices));

    // sort iPhone devices first
    deviceNames.sort((String a, String b) {
      if (a.contains('iPhone') && b.contains('iPad')) return -1;
      if (a.contains('iPad') && b.contains('iPhone')) return 1;

      return a.compareTo(b);
    });

    return deviceNames;
  }
}
