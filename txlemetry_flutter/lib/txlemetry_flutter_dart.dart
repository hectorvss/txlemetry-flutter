import 'dart:io';

import 'src/txlemetry_desktop_app_info.dart';
import 'src/txlemetry_desktop_storage.dart';
import 'src/txlemetry_desktop_time_zone.dart';
import 'src/txlemetry_flutter_desktop.dart';
import 'src/txlemetry_flutter_platform_interface.dart';

/// Registers the Windows and Linux implementation of the plugin, which runs
/// in Dart: there is no native Txlemetry SDK for these platforms.
class TxlemetryFlutterDart {
  TxlemetryFlutterDart._();

  /// Installs the implementation for the running app as the platform
  /// instance. Called by the plugin registrant of Windows and Linux apps.
  static void registerWith() {
    final environment = Platform.environment;
    TxlemetryFlutterPlatformInterface.instance = TxlemetryFlutterDesktop(
      appDirectory: DesktopStorage.appDirectory,
      appInfo: DesktopAppInfo.fromPlatform(),
      timezone: DesktopTimeZone.read(environment),
    );
  }
}
