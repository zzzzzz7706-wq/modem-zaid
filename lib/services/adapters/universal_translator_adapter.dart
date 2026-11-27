import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import '../../models/modem_models.dart';
import 'modem_adapter.dart';

/// Universal Smart Translator Adapter:
/// Connects to ANY unknown router/modem web server, authenticates via Basic,
/// Digest, JSON API, or HTML Form POST, crawls JSON/XML/JS/HTML status pages,
/// and translates all discovered router parameters & controls into our unified
/// Arabic ModemStatus without ever displaying raw web pages.
class UniversalTranslatorAdapter implements ModemAdapter {
  @override
  final String gatewayIp;

  @override
  final String localClientIp;

  final String detectedTitle;
  final http.Client _client = http.Client();

  String _username = 'admin';
  String _password = 'admin';
  String _cookie = '';
  String _authHeader = '';
  final DateTime _sessionStart = DateTime.now();

  UniversalTranslatorAdapter({
    required this.gatewayIp,
    required this.localClientIp,
    this.detectedTitle = 'مودم لاسلكي ذكي',
  });

  @override
  ModemFamily get family => ModemFamily.universalTranslated;

  @override
  String get protocolName => 'المترجم الذكي الشامل للمودمات';

  Map<String, String> get _headers => {
        if (_authHeader.isNotEmpty) 'Authorization': _authHeader,
        if (_cookie.isNotEmpty) 'Cookie': _cookie,
        'Referer': 'http://$gatewayIp/',
      };

  static const Map<String, String> _arabicKeyDictionary = {
    'ssid': 'اسم الشبكة اللاسلكية',
    'channel': 'قناة الواي فاي',
    'bandwidth': 'عرض النطاق',
    'encryption': 'تشفير الحماية',
    'wan_ip': 'عنوان IP الخارجي',
    'gateway': 'البوابة الافتراضية',
    'dns': 'خادم DNS',
    'dns1': 'خادم DNS الأساسي',
    'dns2': 'خادم DNS الثانوي',
    'subnet': 'قناع الشبكة',
    'netmask': 'قناع الشبكة الفرعية',
    'uptime': 'مدة التشغيل',
    'firmware': 'إصدار النظام',
    'version': 'رقم الإصدار',
    'mac': 'عنوان MAC',
    'imei': 'رقم IMEI',
    'imsi': 'رقم الشريحة IMSI',
    'iccid': 'الرقم التسلسلي للشريحة',
    'rsrp': 'قوة إشارة البرج RSRP',
    'rsrq': 'جودة الإشارة RSRQ',
    'sinr': 'نقاء الإشارة SINR',
    'rssi': 'مستوى الإشارة RSSI',
    'band': 'النطاق الترددي',
    'pci': 'معرف الخلية الفيزيائي PCI',
    'cell_id': 'معرف البرج Cell ID',
    'operator': 'مزود الخدمة',
    'isp': 'مزود الإنترنت',
    'cpu': 'استهلاك المعالج',
    'memory': 'استهلاك الذاكرة',
    'dhcp': 'خادم توزيع العناوين DHCP',
    'apn': 'نقطة الوصول APN',
  };

  @override
  Future<bool> login(String username, String password) async {
    _username = username.trim().isEmpty ? 'admin' : username.trim();
    _password = password;

    // 1. Probe root for Basic/Digest challenge or HTML form
    try {
      final res = await _client
          .get(Uri.parse('http://$gatewayIp/'))
          .timeout(const Duration(seconds: 4));
      final sc = res.headers['set-cookie'];
      if (sc != null && sc.isNotEmpty) _cookie = sc.split(';').first;

      final www = res.headers['www-authenticate'] ?? '';
      if (www.toLowerCase().contains('basic') || res.statusCode == 401) {
        final b64 = base64Encode(utf8.encode('$_username:$_password'));
        _authHeader = 'Basic $b64';
        final check = await _client
            .get(Uri.parse('http://$gatewayIp/'), headers: _headers)
            .timeout(const Duration(seconds: 4));
        if (check.statusCode < 400) return true;
      }

      // 2. Try common JSON/CGI login endpoints across Tenda, TP-Link, OpenWrt, StarSpeed, Falcon
      final passMd5 = md5.convert(utf8.encode(_password)).toString();
      final passB64 = base64Encode(utf8.encode(_password));

      final loginCandidates = <Map<String, dynamic>>[
        {
          'path': '/login/Auth',
          'body': {'username': _username, 'password': passB64},
        },
        {
          'path': '/cgi-bin/luci',
          'body': {'luci_username': _username, 'luci_password': _password},
        },
        {
          'path': '/goform/login',
          'body': {'username': _username, 'password': _password},
        },
        {
          'path': '/Forms/login_1',
          'body': {'Username': _username, 'Password': _password},
        },
        {
          'path': '/api/login',
          'json': true,
          'body': {'username': _username, 'password': _password, 'pwd': passMd5},
        },
      ];

      for (final cand in loginCandidates) {
        try {
          final uri = Uri.parse('http://$gatewayIp${cand['path']}');
          final isJson = cand['json'] == true;
          final r = await _client
              .post(
                uri,
                headers: {
                  ..._headers,
                  if (isJson) 'Content-Type': 'application/json',
                },
                body: isJson ? jsonEncode(cand['body']) : cand['body'],
              )
              .timeout(const Duration(seconds: 3));
          final cookie = r.headers['set-cookie'];
          if (cookie != null && cookie.isNotEmpty) {
            _cookie = cookie.split(';').first;
            return true;
          }
          if (r.statusCode == 200 &&
              !r.body.toLowerCase().contains('error') &&
              !r.body.toLowerCase().contains('invalid')) {
            return true;
          }
        } catch (_) {}
      }

      // Default Basic header for subsequent scraping
      _authHeader = 'Basic ${base64Encode(utf8.encode('$_username:$_password'))}';
      return res.statusCode < 500;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> logout() async {
    _cookie = '';
    _authHeader = '';
  }

  static String? _extractMatch(String content, List<RegExp> patterns) {
    for (final re in patterns) {
      final m = re.firstMatch(content);
      if (m != null && m.groupCount >= 1) {
        final v = m.group(1)?.trim() ?? '';
        if (v.isNotEmpty && v != 'null' && v != 'undefined') return v;
      }
    }
    return null;
  }

  @override
  Future<ModemStatus> fetchStatus({bool forceFullRefresh = false}) async {
    final endpoints = [
      '/',
      '/status.json',
      '/api/status',
      '/goform/getStatus',
      '/cgi-bin/status',
      '/status.xml',
      '/main.html',
    ];

    final combinedBuffer = StringBuffer();
    final translatedExtras = <String, String>{};

    for (final ep in endpoints) {
      try {
        final r = await _client
            .get(Uri.parse('http://$gatewayIp$ep'), headers: _headers)
            .timeout(const Duration(seconds: 2));
        if (r.statusCode >= 200 && r.statusCode < 400 && r.bodyBytes.isNotEmpty) {
          final text = utf8.decode(r.bodyBytes, allowMalformed: true);
          combinedBuffer.writeln(text);

          // Parse JSON keys if endpoint returned JSON
          if (text.trim().startsWith('{')) {
            try {
              final map = jsonDecode(text) as Map<String, dynamic>;
              map.forEach((k, v) {
                if (v != null && (v is String || v is num || v is bool)) {
                  final valStr = v.toString().trim();
                  if (valStr.isNotEmpty && valStr.length < 48) {
                    final arLabel = _translateKey(k);
                    translatedExtras[arLabel] = valStr;
                  }
                }
              });
            } catch (_) {}
          }
        }
      } catch (_) {}
    }

    final raw = combinedBuffer.toString();

    // Heuristic extraction of key modem fields across HTML/JS/XML/JSON
    final title = _extractMatch(raw, [
          RegExp(r'<title>([^<]{2,40})</title>', caseSensitive: false),
          RegExp(r'"(?:model|device_name|product_name)"\s*:\s*"([^"]+)"', caseSensitive: false),
        ]) ??
        detectedTitle;

    final ssid = _extractMatch(raw, [
          RegExp(r'"(?:ssid|SSID|SSID1|wifi_ssid)"\s*:\s*"([^"]+)"'),
          RegExp(r'<(?:ssid|SSID|WifiSsid)>([^<]+)</', caseSensitive: false),
          RegExp(r'var\s+ssid\s*=\s*["\x27]([^"\x27]+)["\x27]', caseSensitive: false),
        ]) ??
        'شبكة الواي فاي';

    final wanIp = _extractMatch(raw, [
          RegExp(r'"(?:wan_ip|wanIp|ipv4|WanIPAddress)"\s*:\s*"([0-9\.]{7,15})"'),
          RegExp(r'<(?:wan_ip|ipv4|WanIPAddress)>([0-9\.]{7,15})</', caseSensitive: false),
        ]) ??
        '-';

    final rsrp = _extractMatch(raw, [
          RegExp(r'"?(?:rsrp|lte_rsrp)"?\s*[:=>]\s*"?(-?\d{2,3})"?', caseSensitive: false),
        ]);
    final sinr = _extractMatch(raw, [
          RegExp(r'"?(?:sinr|snr|lte_snr)"?\s*[:=>]\s*"?(-?\d{1,2})"?', caseSensitive: false),
        ]);
    final band = _extractMatch(raw, [
          RegExp(r'"?(?:band|lte_band|active_band)"?\s*[:=>]\s*"?(B?\d{1,2})"?', caseSensitive: false),
        ]) ??
        '4G';
    final batStr = _extractMatch(raw, [
          RegExp(r'"?(?:battery|battery_pers|BatteryPercent|Battery_voltage)"?\s*[:=>]\s*"?(\d{1,3})"?'),
        ]);

    // Also extract JS variable assignments `var xxx = "yyy"` into translatedExtras
    for (final m in RegExp(r'var\s+([a-zA-Z0-9_]{3,24})\s*=\s*["\x27]([^"\x27]{1,35})["\x27]')
        .allMatches(raw)
        .take(20)) {
      final k = m.group(1)!;
      final v = m.group(2)!;
      if (_arabicKeyDictionary.containsKey(k.toLowerCase())) {
        translatedExtras[_arabicKeyDictionary[k.toLowerCase()]!] = v;
      }
    }

    final hasBat = batStr != null;
    final batPct = hasBat ? (int.tryParse(batStr) ?? 100).clamp(0, 100) : 100;

    int sigPct = 80;
    if (rsrp != null) {
      final rv = int.tryParse(rsrp) ?? -85;
      if (rv < -40 && rv >= -140) {
        sigPct = (((rv + 122) / 47.0) * 100).round().clamp(5, 100);
      }
    }

    final formattedBand = band.toUpperCase().startsWith('B') || band == '4G'
        ? band.toUpperCase()
        : 'B$band';

    final sessionSecs = DateTime.now().difference(_sessionStart).inSeconds;

    return ModemStatus(
      hasBattery: hasBat,
      batteryPercent: batPct,
      isCharging: false,
      uptimeSeconds: sessionSecs,
      networkType: '4G',
      operatorName: 'متصل بالشبكة',
      signalBars: ((sigPct / 20).ceil()).clamp(1, 5),
      signalPercent: sigPct,
      band: formattedBand,
      rsrp: rsrp != null ? '$rsrp dBm' : '-',
      sinr: sinr != null ? '$sinr dB' : '-',
      wanConnected: true,
      deviceModel: title,
      wanIp: wanIp,
      lanIp: gatewayIp,
      ssid: ssid,
      connectedDevicesCount: 1,
      adminUsername: _username,
      adminPassword: _password,
      devices: [
        ConnectedDevice(
          index: 0,
          name: 'هاتفك الحالي',
          ipAddress: localClientIp,
          macAddress: 'متصل عبر Wi-Fi',
          isCurrentDevice: true,
        ),
      ],
      translatedExtras: translatedExtras,
      capabilities: ModemCapabilities(
        hasBattery: hasBat,
        hasSignalMetrics: rsrp != null || sinr != null,
        hasBandLock: false,
        hasSpeedLimit: false,
        hasWifiEdit: true,
        hasMaxClients: false,
        hasHideSsid: true,
        hasLcdQrToggle: false,
        hasDeviceBlock: false,
        hasDeviceRename: false,
        hasReboot: true,
        hasPowerOff: false,
        hasAdminPassword: false,
        hasSms: false,
      ),
    );
  }

  String _translateKey(String rawKey) {
    final lower = rawKey.toLowerCase().trim();
    if (_arabicKeyDictionary.containsKey(lower)) {
      return _arabicKeyDictionary[lower]!;
    }
    for (final entry in _arabicKeyDictionary.entries) {
      if (lower.contains(entry.key)) return entry.value;
    }
    return rawKey.replaceAll('_', ' ');
  }

  @override
  Future<bool> updateWifi({
    required String ssid,
    required String password,
    required bool hideSsid,
    required int maxClients,
  }) async {
    for (final path in ['/goform/setWifi', '/api/wifi', '/cgi-bin/wireless']) {
      try {
        final r = await _client
            .post(
              Uri.parse('http://$gatewayIp$path'),
              headers: _headers,
              body: {
                'ssid': ssid,
                'password': password,
                'hide': hideSsid ? '1' : '0',
              },
            )
            .timeout(const Duration(seconds: 4));
        if (r.statusCode == 200) return true;
      } catch (_) {}
    }
    return false;
  }

  @override
  Future<bool> setBandConfig({
    required bool manualMode,
    required String networkMode,
    required List<String> bands,
  }) async =>
      false;

  @override
  Future<bool> setSpeedLimit({
    required bool enabled,
    required int downloadMbps,
    required int uploadMbps,
  }) async =>
      false;

  @override
  Future<bool> setDeviceBlock({
    required ConnectedDevice device,
    required bool block,
  }) async =>
      false;

  @override
  Future<bool> renameDevice({
    required ConnectedDevice device,
    required String newName,
  }) async =>
      false;

  @override
  Future<bool> setLcdQrCode(bool visibleOnModemScreen) async => false;

  @override
  Future<bool> changeAdminPassword(String newPassword) async => false;

  @override
  Future<bool> rebootModem() async {
    for (final path in ['/goform/reboot', '/cgi-bin/reboot', '/api/reboot', '/reboot.cgi']) {
      try {
        final r = await _client
            .post(Uri.parse('http://$gatewayIp$path'), headers: _headers)
            .timeout(const Duration(seconds: 4));
        if (r.statusCode < 400) return true;
      } catch (_) {}
    }
    return false;
  }

  @override
  Future<bool> powerOffModem() async => false;

  @override
  Future<List<SmsMessage>> fetchSmsInbox() async => [];
}
