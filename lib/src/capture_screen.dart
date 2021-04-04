import 'dart:async';
import 'dart:io';

import 'globals.dart';
import 'package:flutter_driver/flutter_driver.dart';


Future<void> screenshot(final FlutterDriver driver, String name,
    {Duration timeout = const Duration(seconds: 30),
    bool silent = false,
    bool waitUntilNoTransientCallbacks = true
    }) async {

    if (waitUntilNoTransientCallbacks) {
      await driver.waitUntilNoTransientCallbacks(timeout: timeout);
    }

    final pixels = await driver.screenshot();
    final testDir = '$kTempDir/$kTestScreenshotsDir';
    final file =
        await File('$testDir/$name.$kImageExtension').create(recursive: true);
    await file.writeAsBytes(pixels);
    if (!silent) print('Screenshot $name created');
}
