


import 'package:screenshots/screenshots.dart';
import 'package:screenshots/src/config.dart';
import 'package:screenshots/src/daemon_client.dart';

void main() async {
  final dev = Device(
    emulator: true,
    name: "Galaxy S10",
    build: true,
    orientations: <Orientation>[Orientation.Portrait],
    destName: "phone",
    deviceType: DeviceType.android,
    phoneType: 'Samsung Galaxy S10',
    deviceId: 'Galaxy_S10',
  );

  final client = await DaemonClient.getInstance();
  await client.devicesInfo;

  await client.launchEmulator(dev);
  print('launched');

  final config = Config(tests: [], locales: [], devices: [dev], sdkPath: 'C:\\src\\android-sdk');

  //dev.rotate(config, Orientation.Portrait);
  await dev.setLocale(config, 'en-US');
}