import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/main.dart';
import 'package:flutter_hbb/common.dart';
import 'dart:io';

enum SystemWindowTheme { light, dark }

/// The platform channel for RustDesk.
class RdPlatformChannel {
  RdPlatformChannel._();

  static final RdPlatformChannel _windowUtil = RdPlatformChannel._();

  static RdPlatformChannel get instance => _windowUtil;

  final MethodChannel _hostMethodChannel =
      MethodChannel("org.rustdesk.rustdesk/host");

  final MethodChannel _androidChannel = MethodChannel("mChannel");

  /// 获取 Android ANDROID_ID；失败返回空字符串
  Future<String> getAndroidId() async {
    if (!Platform.isAndroid) return "";
    try {
      final id = await _androidChannel.invokeMethod<String>("get_android_id");
      return id ?? "";
    } catch (_) {
      return "";
    }
  }

  /// Bump the position of the mouse cursor, if applicable
  Future<bool> bumpMouse({required int dx, required int dy}) async {
    // No debug output; this call is too chatty.

    bool? result = await _hostMethodChannel
      .invokeMethod("bumpMouse", {"dx": dx, "dy": dy});

    return result ?? false;
  }

  /// Change the theme of the system window
  Future<void> changeSystemWindowTheme(SystemWindowTheme theme) {
    assert(isMacOS);
    if (kDebugMode) {
      print(
          "[Window ${kWindowId ?? 'Main'}] change system window theme to ${theme.name}");
    }
    return _hostMethodChannel
        .invokeMethod("setWindowTheme", {"themeName": theme.name});
  }

  /// Terminate .app manually.
  Future<void> terminate() {
    assert(isMacOS);
    return _hostMethodChannel.invokeMethod("terminate");
  }

  Future<bool> checkOverlayPermission() async {
    if (!Platform.isAndroid) return true;
    try {
      final r = await _androidChannel.invokeMethod<bool>("check_overlay_permission");
      return r ?? false;
    } catch (_) {
      return false;
    }
  }
  
  Future<bool> requestOverlayPermission() async {
    if (!Platform.isAndroid) return false;
    try {
      final r = await _androidChannel.invokeMethod<bool>("request_overlay_permission");
      return r ?? false;
    } catch (_) {
      return false;
    }
  }
}
