import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:process/process.dart';


const ProcessManager processManager = LocalProcessManager();


Future<Process> startBackgroundProcess(
  final List<String> cmd,
  {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    Encoding? stdoutEncoding = systemEncoding,
    Encoding? errEncoding = systemEncoding,
  }
) async {
  return await processManager.start(cmd,
      includeParentEnvironment: includeParentEnvironment,
      runInShell: runInShell,
      mode: ProcessStartMode.detached
  );
}

/// This runs the command and streams stdout/stderr from the child process to
/// this process' stdout/stderr. Completes with the process's exit code.
///
/// If [filter] is null, no lines are removed.
///
/// If [filter] is non-null, all lines that do not match it are removed. If
/// [mapFunction] is present, all lines that match [filter] are also forwarded
/// to [mapFunction] for further processing.
Future<int> runCommandAndStreamOutput(
    List<String> cmd, {
      bool allowReentrantFlutter = false,
      String prefix = '',
      RegExp? filter,
      String Function(String)? mapFunction,
      Map<String, String> environment = const {},
    }) async {

  environment['FLUTTER_ALREADY_LOCKED'] = allowReentrantFlutter.toString();

  final process = await processManager.start(
    cmd,
    environment: environment,
  );

  final stdoutSubscription = process.stdout
      .transform<String>(utf8.decoder)
      .transform<String>(const LineSplitter())
      .where((String line) => filter == null || filter.hasMatch(line))
      .listen((String line) => mapFunction?.call(line));

  final stderrSubscription = process.stderr
      .transform<String>(utf8.decoder)
      .transform<String>(const LineSplitter())
      .where((String line) => filter == null || filter.hasMatch(line))
      .listen((String line) => mapFunction?.call(line));

  await Future.wait([stdoutSubscription.asFuture<String>(), stderrSubscription.asFuture<String>()]);
  await Future.wait([stdoutSubscription.cancel(), stderrSubscription.cancel()]);

  return await process.exitCode;
}
