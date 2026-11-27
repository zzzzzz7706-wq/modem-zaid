import 'package:flutter/services.dart';

/// Real Wi-Fi link information reported by Android (`ConnectivityManager`).
class WifiLinkInfo {
  /// True when the phone is currently joined to ANY Wi-Fi network.
  final bool connected;

  /// Real DHCP default gateway of the Wi-Fi network (the modem's IP), e.g. `192.168.8.1`.
  final String gateway;

  /// The phone's own IPv4 address on the Wi-Fi network.
  final String localIp;

  /// DNS servers announced by the Wi-Fi network (often equal to the modem IP).
  final List<String> dnsServers;

  /// True when Android accepted binding the whole app process to Wi-Fi,
  /// so every socket (login, status, control) goes over Wi-Fi even when
  /// Mobile Data is ON and Wi-Fi reports "no internet".
  final bool processBound;

  const WifiLinkInfo({
    this.connected = false,
    this.gateway = '',
    this.localIp = '',
    this.dnsServers = const [],
    this.processBound = false,
  });

  /// Channel not available (e.g. unit tests / non-Android).
  static const unknown = WifiLinkInfo(connected: true);
}

/// Bridges to the native Android `MainActivity` channel `modemzaid/wifi_network`.
class WifiNetworkBinder {
  static const MethodChannel _channel = MethodChannel('modemzaid/wifi_network');

  /// Reads the real Wi-Fi gateway + local IP and (optionally) binds the app to Wi-Fi.
  static Future<WifiLinkInfo> query({bool bind = true}) async {
    try {
      final raw = await _channel
          .invokeMapMethod<String, dynamic>('getWifiInfo', {'bind': bind})
          .timeout(const Duration(seconds: 3));
      if (raw == null) return WifiLinkInfo.unknown;
      final dns = <String>[];
      final rawDns = raw['dns'];
      if (rawDns is List) {
        for (final d in rawDns) {
          final s = d?.toString() ?? '';
          if (s.isNotEmpty) dns.add(s);
        }
      }
      return WifiLinkInfo(
        connected: raw['connected'] == true,
        gateway: (raw['gateway'] ?? '').toString(),
        localIp: (raw['localIp'] ?? '').toString(),
        dnsServers: dns,
        processBound: raw['bound'] == true,
      );
    } on MissingPluginException {
      return WifiLinkInfo.unknown;
    } catch (_) {
      return WifiLinkInfo.unknown;
    }
  }

  /// Releases the Wi-Fi process binding (used before internet-only requests such
  /// as the balance inquiry so they may use Mobile Data when the modem has no credit).
  static Future<void> unbind() async {
    try {
      await _channel.invokeMethod<bool>('unbind');
    } catch (_) {}
  }
}
