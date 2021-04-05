import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:screenshots3/screenshots.dart';
import 'package:screenshots3/src/globals.dart';
import 'package:screenshots3/src/utils.dart';
import 'package:screenshots3/src/utils/process.dart';

enum EventType { deviceRemoved }


class RunningDevice {
  final String deviceId;
  final DeviceType deviceType;
  final bool isEmulator;

  RunningDevice(this.deviceId, this.deviceType, this.isEmulator);
}

/// Starts and communicates with flutter daemon.
class DaemonClient {
  late Process _process;

  static final DaemonClient _client = DaemonClient._internal();

  DaemonClient._internal();

  static Future<DaemonClient> getInstance() async {
    await _client.init();
    return _client;
  }

  int _messageId = 0;
  bool _connected = false;

  Completer<bool>? _waitForConnection;
  Completer<String>? _waitForResponse;
  Completer<String>? _waitForEvent;

  List<RunningDevice> _iosDevices = <RunningDevice>[]; // contains model of device, used by screenshots

  late StreamSubscription<String> _stdOutListener;
  late StreamSubscription<List<int>> _stdErrListener;

  /// Start flutter tools daemon.
  Future<void> init() async {
    if (!_connected) {
      _process = await processManager.start(
        <String>['flutter', 'daemon'],
      );

      _listen();
      _waitForConnection = Completer<bool>();
      _connected = await _waitForConnection!.future;

      await _sendCommandWaitResponse('device.enable');
      // maybe should check if iOS run type is active
      if (Platform.isMacOS) _iosDevices = getIosDevices();
    }
  }

  void _listen() {
    _stdOutListener = _process.stdout
        .transform<String>(utf8.decoder)
        .transform<String>(LineSplitter())
        .listen((String line) async {
      //printTrace('<== $line');
      print('<== $line');
      // todo: decode json
      if (line.contains('daemon.connected')) {
        _waitForConnection?.complete(true);
      } else {
        // get response
        if (line.contains('"result":') ||
            line.contains('"error":') ||
            line == '[{"id":${_messageId - 1}}]') {
          _waitForResponse?.complete(line);
        } else {
          // get event
          if (line.contains('[{"event":')) {
            if (line.contains('"event":"daemon.logMessage"')) {
              //printTrace('Warning: ignoring log message: $line');
            } else {
              _waitForEvent?.complete(line);
            }
          } else if (line != 'Starting device daemon...') {
            throw 'Error: unexpected response from daemon: $line';
          }
        }
      }
    });

    _stdErrListener = _process.stderr.listen(stderr.add);
  }

  Future<List<RunningDevice>> get devicesInfo async {
    final results = <RunningDevice>[];
    final emulators = await _sendCommandWaitResponse('emulator.getEmulators');

    for (var emulator in emulators) {
      final type = emulator['platform'] == 'ios' ? DeviceType.ios : DeviceType.android;
      results.add(RunningDevice(emulator['name'] as String, type, true));
    }

    final devices = await runningDevices;
    results.addAll(devices
        .where((device) => device.deviceType != DeviceType.android || !device.isEmulator));

    return results;
  }

  Future<List<RunningDevice>> get runningDevices async {
    final results = <RunningDevice>[];

    final devices = await _sendCommandWaitResponse('device.getDevices');
    print(devices.toString());
    for (var device in devices) {
      if (device['platform'] == 'ios' && device['emulator'] == false) {
        final iosDevice = _iosDevices.firstWhere((item) => item.deviceId == device['id']);
        results.add(iosDevice);
      } else {
        final type = device['platform'] == 'ios' ? DeviceType.ios : DeviceType.android;
        results.add(RunningDevice(device['name'] as String, type, device['emulator'] as bool));
      }
    }

    return results;
  }

  Future<void> waitForEmulatorToStart(String deviceId) async {
    var started = false;

    while (!started) {
      final devices = await runningDevices;
      started = devices.any(
              (device) => device.deviceId == deviceId && device.isEmulator);

      await Future<void>.delayed(Duration(milliseconds: 1000));
    }
  }

  Future<String> launchEmulator(Device device) {
    if (device.deviceType == DeviceType.android) {
      return _launchAndroidEmulator(device);
    } else {
      return _launchIosSimulator(device);
    }
  }

  Future<String> _launchIosSimulator(Device device) async {
    final simulator = getHighestIosSimulator(getIosSimulators(), device.deviceId);
    final deviceId = simulator['udid'] as String;

    cmd(['xcrun', 'simctl', 'boot', deviceId]);
    await Future<void>.delayed(Duration(seconds: 2));
    await waitForEmulatorToStart(deviceId);

    return deviceId;
  }

  /// Launch an emulator and return device id.
  Future<String> _launchAndroidEmulator(Device device) async {
    _waitForEvent = Completer<String>();

    _sendCommand('emulator.launch', <String, dynamic>{'emulatorId': device.deviceId});

    // wait for expected device-added-emulator event
    // Note: future does not complete if emulator already running
    final results = await Future.wait([_waitForResponse!.future, _waitForEvent!.future]);
    // process the response
    _processResponse(results[0], 'emulator.launch');
    // process the event
    final event = results[1];
    final eventInfo = jsonDecode(event) as List<dynamic>;
    if (eventInfo.length != 1 ||
        eventInfo[0]['event'] != 'device.added' ||
        eventInfo[0]['params']['emulator'] != true) {
      throw 'Error: emulator ${device.deviceId} not started: $event';
    }

    return Future.value(eventInfo[0]['params']['id'] as String);
  }

  /// Wait for an event of type [EventType] and return event info.
  Future<Map<String, dynamic>> waitForEvent(EventType eventType) async {
    _waitForEvent = Completer<String>();

    final eventInfo = jsonDecode(await _waitForEvent!.future) as Map<String, dynamic>;

    switch (eventType) {
      case EventType.deviceRemoved:
        // event info is a device descriptor
        if (eventInfo.length != 1 ||
            eventInfo[0]['event'] != 'device.removed') {
          throw 'Error: expected: $eventType, received: $eventInfo';
        }
        break;
      default:
        throw 'Error: unexpected event: $eventInfo';
    }
    return Future.value(eventInfo[0]['params'] as Map<String, dynamic>);
  }

  int _exitCode = 0;

  /// Stop daemon.
  Future<int> stop() async {
    if (!_connected) throw 'Error: not connected to daemon.';
    await _sendCommandWaitResponse('daemon.shutdown');
    _connected = false;
    _exitCode = await _process.exitCode;
    await _stdOutListener.cancel();
    await _stdErrListener.cancel();
    return _exitCode;
  }


  void _sendCommand(String method, [Map<String, dynamic> params = const <String, dynamic>{}]) {
    if (!_connected) throw StateError('Not connected to daemon');

    _waitForResponse = Completer<String>();

    final command = <String, dynamic>{
      'method': method,
    };
    command['params'] = params;
    command['id'] = _messageId++;

    final commandString = '[${json.encode(command)}]';
    print('==> $commandString');
    _process.stdin.writeln(commandString);
  }

  Future<List<dynamic>> _sendCommandWaitResponse(String method, {
    Map<String, dynamic> params = const <String, dynamic>{},
  }) async {
    _sendCommand(method, params);
//    printTrace('waiting for response: $command');
    final response = await _waitForResponse!.future;
//    printTrace('response: $response');
    return _processResponse(response, method);
  }

  List<dynamic> _processResponse(String response, String command) {
    if (response.contains('result')) {
      final respExp = RegExp(r'result":(.*)}\]');
      return jsonDecode(respExp.firstMatch(response)!.group(1)!) as List<dynamic>;
    } else if (response.contains('error')) {
      // todo: handle errors separately
      throw 'Error: command $command failed:\n ${jsonDecode(response)[0]['error']}';
    } else {
      return jsonDecode(response) as List<dynamic>;
    }
  }
}

/// Get attached ios devices with id and model.
List<RunningDevice> getIosDevices() {
  final regExp = RegExp(r'Found (\w+) \(\w+, (.*), \w+, \w+\)');
  final noAttachedDevices = 'no attached devices';
  final iosDeployDevices =
      cmd(['sh', '-c', 'ios-deploy -c || echo "$noAttachedDevices"'])
          .trim()
          .split('\n')
          .sublist(1);
  if (iosDeployDevices.isEmpty || iosDeployDevices[0] == noAttachedDevices) {
    return [];
  }

  return iosDeployDevices.where((line) {
      final match = regExp.firstMatch(line);
      return match != null && match.groupCount >= 2;
  }).map((line) {
      final matches = regExp.firstMatch(line);
      return RunningDevice(matches!.group(2)!, DeviceType.ios, false);
  }).toList();
}