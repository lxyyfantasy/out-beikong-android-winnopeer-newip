import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/utils/http_service.dart' as http;
import 'package:flutter_hbb/utils/platform_channel.dart';

class DeviceReporter {
  static const _timeout = Duration(seconds: 8);
  static const _deviceCodeKey = 'device_code';

  static String? _lastIp;
  static Timer? _timer;
  static bool _reporting = false;

  static void start() async {
    if (!Platform.isAndroid) return;
    // 已并入 /api/heartbeat，只保留 device_code 写入
    await _deviceCode();
  }

  static Future<String> _deviceCode() async {
    String stored = '';
    try {
      stored = (await bind.mainGetOption(key: _deviceCodeKey)).trim();
    } catch (_) {}

    String androidId = '';
    try {
      androidId = (await RdPlatformChannel.instance.getAndroidId()).trim();
    } catch (_) {}

    // 非空且跟已存值不一样，才覆盖原值
    if (androidId.isNotEmpty && androidId != stored) {
      try {
        await bind.mainSetOption(key: _deviceCodeKey, value: androidId);
      } catch (_) {}
    }

    return androidId.isNotEmpty ? androidId : stored;
  }

  static Future<void> reportDevice() async {
    if (_reporting) return;
    _reporting = true;
    try {
      final id = await bind.mainGetMyId();
      if (id.isEmpty) return;
      final ip = await _localIp();
      if (ip.isEmpty) return;
      final host = await middlewareHost();
      if (host.isEmpty) return;
      final deviceCode = await _deviceCode();

      final body = jsonEncode(
          {'device_id': id, 'ip': ip, 'device_code': deviceCode});
      final resp = await http
          .post(
            Uri.parse('http://$host:$kMiddlewarePort/api/report'),
            headers: {
              'Content-Type': 'application/json',
            },
            body: body,
          )
          .timeout(_timeout);
      if (resp.statusCode == 200) {
        _lastIp = ip;
      }
    } catch (e) {
      debugPrint('device report failed: $e');
    } finally {
      _reporting = false;
    }
  }

  static Future<String> _localIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      String fallback = '';
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final ip = addr.address;
          if (ip.startsWith('169.254.')) continue;
          if (_isPrivate(ip)) return ip;
          if (fallback.isEmpty && !addr.isLoopback) fallback = ip;
        }
      }
      return fallback;
    } catch (_) {
      return '';
    }
  }

  static bool _isPrivate(String ip) {
    if (ip.startsWith('192.168.')) return true;
    if (ip.startsWith('10.')) return true;
    if (ip.startsWith('172.')) {
      final parts = ip.split('.');
      if (parts.length >= 2) {
        final n = int.tryParse(parts[1]) ?? 0;
        if (n >= 16 && n <= 31) return true;
      }
    }
    return false;
  }
}