


import 'package:screenshots3/screenshots.dart';
import 'package:screenshots3/src/config.dart';
import 'package:screenshots3/src/daemon_client.dart';
import 'package:screenshots3/src/orientation.dart';

void main() async {
  Device dev = Device(
    emulator: true,
    name: "Galaxy S10",
    build: true,
    orientations: <Orientation>[Orientation.Portrait],
    destName: "phone",
    deviceType: DeviceType.android,
    phoneType: 'Samsung Galaxy S10',
    deviceId: 'Galaxy_S10',
  );

  DaemonClient client = await DaemonClient.getInstance();
  await client.devicesInfo;

  client.launchEmulator(dev);
}