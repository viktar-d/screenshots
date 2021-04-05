
import 'package:screenshots3/screenshots.dart';

import 'globals.dart';
import 'utils.dart';

const kDefaultOrientation = 'Portrait';
enum Orientation { Portrait, LandscapeRight, PortraitUpsideDown, LandscapeLeft }

/// Change orientation of a running emulator or simulator.
/// (No known way of supporting real devices.)
void changeDeviceOrientation(Config config, Device device, Orientation orientation) {
  final androidOrientations = {
    Orientation.Portrait: '0',
    Orientation.LandscapeRight: '1',
    Orientation.PortraitUpsideDown: '2',
    Orientation.LandscapeLeft: '3'
  };

  final iosOrientations = {
    Orientation.Portrait: 'Portrait',
    Orientation.LandscapeRight: 'Landscape Right',
    Orientation.PortraitUpsideDown: 'Portrait Upside Down',
    Orientation.LandscapeLeft: 'Landscape Left'
  };

  const sim_orientation_script = 'sim_orientation.scpt';
  //printStatus('Setting orientation to $_orientation');
  switch (device.deviceType) {
    case DeviceType.android:
      cmd([
        //getAdbPath(androidSdk),
        config.adbPath,
        '-s',
        device.deviceId,
        'shell',
        'settings',
        'put',
        'system',
        'user_rotation',
        androidOrientations[orientation]!
      ]);
      break;
    case DeviceType.ios:
      // requires permission when run for first time
      cmd([
        'osascript',
        '$kTempDir/$sim_orientation_script',
        iosOrientations[orientation]!
      ]);
      break;
  }
}
