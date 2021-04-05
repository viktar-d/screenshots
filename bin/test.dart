


import 'package:screenshots3/screenshots.dart';
import 'package:screenshots3/src/config.dart';
import 'package:screenshots3/src/daemon_client.dart';
import 'package:screenshots3/src/orientation.dart';
import 'package:screenshots3/src/run.dart';

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

  final config = Config(tests: [], locales: [], devices: [dev], sdkPath: 'C:\\src\\android-sdk');

  await setDeviceLocale(config, dev, 'en-US', client);
}