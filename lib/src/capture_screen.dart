import 'dart:async';
import 'dart:io';

import 'globals.dart';


Future<void> screenshot(final dynamic driver, String name,
    {Duration timeout = const Duration(seconds: 30),
    bool silent = false,
    bool waitUntilNoTransientCallbacks = true
    }) async {

    if (waitUntilNoTransientCallbacks) {
      await driver.waitUntilNoTransientCallbacks(timeout: timeout);
    }

    final pixels = await driver.screenshot() as List<int>;
    final testDir = '$kTempDir/$kTestScreenshotsDir';
    final file =
        await File('$testDir/$name.$kImageExtension').create(recursive: true);
    await file.writeAsBytes(pixels);
    if (!silent) print('Screenshot $name created');
}
