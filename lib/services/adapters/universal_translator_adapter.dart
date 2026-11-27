import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import '../../models/modem_models.dart';
import '../modem_detector.dart';
import '../smart_modem_profiler.dart';
import 'modem_adapter.dart';

/// Universal Smart Self-Adapting Translator Adapter:
/// Connects to ANY router/modem (Alcatel/Speed 4G `/jrd/webapi`, Qualcomm QCMAP
/// `/cgi-bin/qcmap_auth`, OpenWrt `/ubus`, Jetpack MiFi, PTC ADSL/Fiber ONTs,
/// Huawei EMUI, TP-Link, Tenda, D-Link, and any modem introspected by
/// [SmartModemProfiler]) using discovered HTML forms, JS endpoints, and protocols.
class UniversalTranslatorAdapter implements ModemAdapter {
  @override
  final String gatewayIp;

  @override
  final String localClientIp;

  final String detectedTitle;
  final String baseScheme;
  final int port;
  final SmartModemProfile? profile;

  late final http.Client _client =
      ModemDetector.createLanHttpClient(localClientIp);

  String _username = 'admin';
  String _password = 'admin';
  String _cookie = '';
  String _authHeader = '';
  String _tclToken = '';
  String _qcmapToken = '';
  String _ubusSid = '';
  bool _isJrdWebApi = false;
  bool _isQcmap = false;
  bool _isUbus = false;
  final DateTime _sessionStart = DateTime.now();

  UniversalTranslatorAdapter({
    required this.gatewayIp,
    required this.localClientIp,
    this.detectedTitle = 'مودم لاسلكي',
    this.baseScheme = 'http',
    this.port = 80,
    this.profile,
  });

  String get _baseUrl {
    final defaultPort = baseScheme == 'https' ? 443 : 80;
    return port == defaultPort
        ? '$baseScheme://$gatewayIp'
        : '$baseScheme://$gatewayIp:$port';
  }

  @override
  ModemFamily get family => ModemFamily.universalTranslated;

  @override
  String get protocolName {
    if (_isJrdWebApi) return 'Alcatel / TCL / Speed 4G JSON-RPC';
    if (_isQcmap) return 'Qualcomm QCMAP 4G CGI';
    if (_isUbus) return 'OpenWrt / LuCI ubus';
    if (profile != null && profile!.detectedProtocol.isNotEmpty) {
      return profile!.detectedProtocol;
    }
    return 'المترجم الذكي التكيّفي للمودمات';
  }

  Map<String, String> get _headers => {
        if (_authHeader.isNotEmpty) 'Authorization': _authHeader,
        if (_cookie.isNotEmpty) 'Cookie': _cookie,
        if (_tclToken.isNotEmpty) '_TclRequestVerificationToken': _tclToken,
        'Referer': '$_baseUrl/',
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
    'dhcp': 'خادم توزيع العناوين DHCP',
    'apn': 'نقطة الوصول APN',
  };

  static String _xorTclEncode(String input) {
    const key = 'e5dl12XYVggihggafXWf0f2YSf2Xngd1';
    final out = StringBuffer();
    for (var i = 0; i < input.length; i++) {
      final c = input.codeUnitAt(i);
      final k = key.codeUnitAt(i % key.length);
      final enc = ((c ^ k) & 0x0f) + 0x36;
      final hi = (((c ^ k) >> 4) & 0x0f) + 0x63;
      if ((c & 0x01) != 0) {
        out.writeCharCode(enc);
        out.writeCharCode(hi);
      } else {
        out.writeCharCode(hi);
        out.writeCharCode(enc);
      }
    }
    return out.toString();
  }

  Future<Map<String, dynamic>?> _jrdCall(
    String method, [
    Map<String, dynamic> params = const {},
  ]) async {
    try {
      final r = await _client
          .post(
            Uri.parse('$_baseUrl/jrd/webapi'),
            headers: {
              ..._headers,
              'Content-Type': 'application/json; charset=UTF-8',
              '_TclRequestVerificationKey':
                  'KSDHSDFOGQ5WERYTUIQWERTYUISDFG1HJZXCVCXBN2GDSMNDHKVKFsVBNf',
            },
            body: jsonEncode({
              'jsonrpc': '2.0',
              'method': method,
              'params': params,
              'id': '1.0',
            }),
          )
          .timeout(const Duration(seconds: 4));
      final sc = r.headers['set-cookie'];
      if (sc != null && sc.isNotEmpty) _cookie = sc.split(';').first;
      final body = utf8.decode(r.bodyBytes, allowMalformed: true).trim();
      if (body.startsWith('{')) {
        final decoded = jsonDecode(body) as Map<String, dynamic>;
        if (decoded.containsKey('result') || decoded.containsKey('error')) {
          return decoded;
        }
      }
    } catch (_) {}
    return null;
  }

  static String _md5Hex(String s) =>
      md5.convert(utf8.encode(s)).toString().toLowerCase();

  String _buildDigestHeader(String wwwAuth, String method, String uriPath) {
    String realm = '';
    String nonce = '';
    String qop = '';
    for (final m in RegExp(r'(\w+)\s*=\s*"?([^",\s]+)"?').allMatches(wwwAuth)) {
      final k = m.group(1)?.toLowerCase();
      final v = m.group(2) ?? '';
      if (k == 'realm') realm = v;
      if (k == 'nonce') nonce = v;
      if (k == 'qop') qop = v;
    }
    final ha1 = _md5Hex('$_username:$realm:$_password');
    final ha2 = _md5Hex('$method:$uriPath');
    const nc = '00000001';
    const cnonce = '0a4f113b654321ab';
    final resp = qop.isNotEmpty
        ? _md5Hex('$ha1:$nonce:$nc:$cnonce:$qop:$ha2')
        : _md5Hex('$ha1:$nonce:$ha2');
    final qopPart =
        qop.isNotEmpty ? ', qop=$qop, nc=$nc, cnonce="$cnonce"' : '';
    return 'Digest username="$_username", realm="$realm", nonce="$nonce", '
        'uri="$uriPath", response="$resp"$qopPart';
  }

  Future<Map<String, dynamic>?> _qcmapCall(
    String page, [
    Map<String, String> extra = const {},
  ]) async {
    try {
      final r = await _client
          .post(
            Uri.parse('$_baseUrl/cgi-bin/qcmap_web_cgi'),
            headers: _headers,
            body: {
              'Page': page,
              'mask': '0',
              if (_qcmapToken.isNotEmpty) 'token': _qcmapToken,
              ...extra,
            },
          )
          .timeout(const Duration(seconds: 4));
      final body = utf8.decode(r.bodyBytes, allowMalformed: true).trim();
      final idx = body.indexOf('{');
      if (idx != -1) {
        final dec = jsonDecode(body.substring(idx));
        if (dec is Map<String, dynamic>) return dec;
      }
    } catch (_) {}
    return null;
  }

  Future<dynamic> _ubusCall(
    String object,
    String method, [
    Map<String, dynamic> params = const {},
  ]) async {
    try {
      final r = await _client
          .post(
            Uri.parse('$_baseUrl/ubus'),
            headers: {
              ..._headers,
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'jsonrpc': '2.0',
              'id': 1,
              'method': 'call',
              'params': [
                _ubusSid.isEmpty ? '00000000000000000000000000000000' : _ubusSid,
                object,
                method,
                params,
              ],
            }),
          )
          .timeout(const Duration(seconds: 4));
      final body = utf8.decode(r.bodyBytes, allowMalformed: true).trim();
      if (body.startsWith('{')) {
        final dec = jsonDecode(body) as Map<String, dynamic>;
        final res = dec['result'];
        if (res is List && res.length >= 2 && res[0] == 0) {
          return res[1];
        }
      }
    } catch (_) {}
    return null;
  }

  String _encodeByHint(String pwd, String hint) {
    switch (hint) {
      case 'base64':
        return base64Encode(utf8.encode(pwd));
      case 'md5_lower':
        return md5.convert(utf8.encode(pwd)).toString().toLowerCase();
      case 'sha256_lower':
        return sha256.convert(utf8.encode(pwd)).toString().toLowerCase();
      case 'sha256_upper':
        return sha256.convert(utf8.encode(pwd)).toString().toUpperCase();
      default:
        return pwd;
    }
  }

  @override
  Future<LoginOutcome> loginWithOutcome(String username, String password) async {
    _username = username.trim().isEmpty ? 'admin' : username.trim();
    _password = password;
    _isJrdWebApi = false;
    _isQcmap = false;
    _isUbus = false;
    _qcmapToken = '';
    _ubusSid = '';

    try {
      // 0. Check Inseego / Novatel Jetpack MiFi (/login gSecureToken + /srv/status)
      try {
        final jpLogin = await _client
            .get(Uri.parse('$_baseUrl/login'), headers: _headers)
            .timeout(const Duration(seconds: 3));
        final scJp = jpLogin.headers['set-cookie'];
        if (scJp != null && scJp.isNotEmpty) _cookie = scJp.split(';').first;
        final jpBody = utf8.decode(jpLogin.bodyBytes, allowMalformed: true);
        final tokMatch = RegExp(
                r'name\s*=\s*["\x27]gSecureToken["\x27][^>]*value\s*=\s*["\x27]([^"\x27]+)["\x27]|["\x27]gSecureToken["\x27]\s*[:=]\s*["\x27]([^"\x27]+)["\x27]')
            .firstMatch(jpBody);
        final gTok = (tokMatch?.group(1) ?? tokMatch?.group(2) ?? '').trim();
        if (gTok.isNotEmpty) {
          final shaPwd =
              sha1.convert(utf8.encode('$_password$gTok')).toString();
          final sub = await _client.post(
            Uri.parse('$_baseUrl/submitLogin/'),
            headers: _headers,
            body: {'shaPassword': shaPwd, 'gSecureToken': gTok},
          ).timeout(const Duration(seconds: 4));
          final scSub = sub.headers['set-cookie'];
          if (scSub != null && scSub.isNotEmpty) {
            _cookie = scSub.split(';').first;
          }
          final subBody =
              utf8.decode(sub.bodyBytes, allowMalformed: true).toLowerCase();
          if (sub.statusCode < 400 &&
              !subBody.contains('invalid') &&
              !subBody.contains('wrong') &&
              !subBody.contains('error')) {
            return const LoginOutcome(success: true);
          }
          return const LoginOutcome(
            success: false,
            wrongCredentials: true,
            message: 'كلمة المرور غير صحيحة.',
          );
        }
      } catch (_) {}

      // 1. Check Alcatel / TCL / Speed 4G JSON-RPC (/jrd/webapi)
      final sysInfo = await _jrdCall('GetSystemInfo');
      if (sysInfo != null && sysInfo['result'] is Map) {
        _isJrdWebApi = true;
        final loginAttempts = [
          {'UserName': _username, 'Password': _xorTclEncode(_password)},
          {'UserName': _xorTclEncode(_username), 'Password': _xorTclEncode(_password)},
          {'UserName': _username, 'Password': base64Encode(utf8.encode(_password))},
          {'UserName': _username, 'Password': _password},
        ];
        for (final params in loginAttempts) {
          final res = await _jrdCall('Login', params);
          if (res != null && res['result'] is Map) {
            final rMap = res['result'] as Map;
            final tok = (rMap['token'] ?? '').toString();
            if (tok.isNotEmpty) _tclToken = _xorTclEncode(tok);
            return const LoginOutcome(success: true);
          }
        }
        return const LoginOutcome(
          success: false,
          wrongCredentials: true,
          message: 'كلمة المرور غير صحيحة.',
        );
      }

      // 1b. Check Qualcomm QCMAP (/cgi-bin/qcmap_auth)
      try {
        final qRes = await _client.post(
          Uri.parse('$_baseUrl/cgi-bin/qcmap_auth'),
          headers: _headers,
          body: {
            'type': 'login',
            'pwd': _password,
            'timeout': '3600',
            'user': _username,
          },
        ).timeout(const Duration(seconds: 3));
        final qBody = utf8.decode(qRes.bodyBytes, allowMalformed: true).trim();
        if (qRes.statusCode == 200 && qBody.contains('token')) {
          final idx = qBody.indexOf('{');
          if (idx != -1) {
            final map = jsonDecode(qBody.substring(idx)) as Map<String, dynamic>;
            final tok = (map['token'] ?? '').toString();
            final result = (map['result'] ?? '').toString();
            if (tok.isNotEmpty && (result == '0' || result.toLowerCase() == 'success')) {
              _isQcmap = true;
              _qcmapToken = tok;
              return const LoginOutcome(success: true);
            }
            if (result.isNotEmpty && result != '0') {
              return const LoginOutcome(
                success: false,
                wrongCredentials: true,
                message: 'كلمة المرور غير صحيحة.',
              );
            }
          }
        }
      } catch (_) {}

      // 1c. Check OpenWrt / LuCI (/ubus)
      try {
        final uRes = await _ubusCall('session', 'login', {
          'username': _username,
          'password': _password,
        });
        if (uRes is Map && (uRes['ubus_rpc_session'] ?? '').toString().isNotEmpty) {
          _isUbus = true;
          _ubusSid = uRes['ubus_rpc_session'].toString();
          return const LoginOutcome(success: true);
        }
      } catch (_) {}

      final res = await _client
          .get(Uri.parse('$_baseUrl/'))
          .timeout(const Duration(seconds: 5));
      final sc = res.headers['set-cookie'];
      if (sc != null && sc.isNotEmpty) _cookie = sc.split(';').first;

      final www = res.headers['www-authenticate'] ?? '';
      if (www.toLowerCase().contains('digest')) {
        _authHeader = _buildDigestHeader(www, 'GET', '/');
        final check = await _client
            .get(Uri.parse('$_baseUrl/'), headers: _headers)
            .timeout(const Duration(seconds: 4));
        if (check.statusCode < 400) {
          return const LoginOutcome(success: true);
        }
        return const LoginOutcome(
          success: false,
          wrongCredentials: true,
          message: 'اسم المستخدم أو كلمة المرور غير صحيحة.',
        );
      }

      if (www.toLowerCase().contains('basic') || res.statusCode == 401) {
        final b64 = base64Encode(utf8.encode('$_username:$_password'));
        _authHeader = 'Basic $b64';
        final check = await _client
            .get(Uri.parse('$_baseUrl/'), headers: _headers)
            .timeout(const Duration(seconds: 4));
        if (check.statusCode < 400) {
          return const LoginOutcome(success: true);
        }
        return const LoginOutcome(
          success: false,
          wrongCredentials: true,
          message: 'اسم المستخدم أو كلمة المرور غير صحيحة.',
        );
      }

      // 2. Smart Dynamic HTML <form> Login using introspected SmartModemProfile
      final prof = profile;
      if (prof != null && prof.hasFormLogin && prof.loginAction.isNotEmpty) {
        final encodedPwd = _encodeByHint(_password, prof.passwordEncoding);
        final formBody = <String, String>{
          ...prof.hiddenFields,
          if (prof.usernameField.isNotEmpty) prof.usernameField: _username,
          if (prof.passwordField.isNotEmpty) prof.passwordField: encodedPwd,
        };
        try {
          final r = await _client
              .post(
                Uri.parse('$_baseUrl${prof.loginAction}'),
                headers: _headers,
                body: formBody,
              )
              .timeout(const Duration(seconds: 4));
          final cookie = r.headers['set-cookie'];
          if (cookie != null && cookie.isNotEmpty) {
            _cookie = cookie.split(';').first;
            return const LoginOutcome(success: true);
          }
          final bLow = utf8.decode(r.bodyBytes, allowMalformed: true).toLowerCase();
          if (r.statusCode < 400 &&
              !bLow.contains('invalid') &&
              !bLow.contains('wrong') &&
              !bLow.contains('incorrect')) {
            return const LoginOutcome(success: true);
          }
        } catch (_) {}
      }

      final passMd5 = md5.convert(utf8.encode(_password)).toString();
      final passSha256 = sha256.convert(utf8.encode(_password)).toString();
      final passB64 = base64Encode(utf8.encode(_password));

      final loginCandidates = <Map<String, dynamic>>[
        {
          'path': '/cgi-bin/http.cgi',
          'json': true,
          'body': {
            'cmd': 100,
            'cmdId': 'LOGIN',
            'method': 'POST',
            'username': _username,
            'password': _password,
            'passwd': passSha256,
          },
        },
        {
          'path': '/cgi-bin/lua.cgi',
          'json': true,
          'body': {
            'cmd': 100,
            'method': 'POST',
            'username': _username,
            'passwd': _password,
            'password': passSha256,
          },
        },
        {
          'path': '/login/Auth',
          'body': {'username': _username, 'password': passB64},
        },
        {
          'path': '/index/login.cgi',
          'body': {
            'Username': _username,
            'Password': passB64,
            'pass': passSha256,
          },
        },
        {
          'path': '/cgi-bin/luci',
          'body': {'luci_username': _username, 'luci_password': _password},
        },
        {
          'path': '/goform/login',
          'body': {'username': _username, 'password': passB64},
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
          final uri = Uri.parse('$_baseUrl${cand['path']}');
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
            return const LoginOutcome(success: true);
          }
          if (r.statusCode == 200 &&
              r.body.isNotEmpty &&
              !r.body.toLowerCase().contains('error') &&
              !r.body.toLowerCase().contains('invalid') &&
              !r.body.toLowerCase().contains('wrong') &&
              !r.body.toLowerCase().contains('fail')) {
            return const LoginOutcome(success: true);
          }
        } catch (_) {}
      }

      _authHeader = 'Basic ${base64Encode(utf8.encode('$_username:$_password'))}';
      return LoginOutcome(success: res.statusCode < 500);
    } catch (_) {
      return LoginOutcome(
        success: false,
        wrongCredentials: false,
        message: 'تعذر الوصول إلى المودم ($gatewayIp).',
      );
    }
  }

  @override
  Future<void> logout() async {
    if (_isJrdWebApi) {
      await _jrdCall('Logout');
    } else if (_isQcmap && _qcmapToken.isNotEmpty) {
      try {
        await _client.post(
          Uri.parse('$_baseUrl/cgi-bin/qcmap_auth'),
          headers: _headers,
          body: {'type': 'logout', 'token': _qcmapToken},
        );
      } catch (_) {}
    } else if (_isUbus && _ubusSid.isNotEmpty) {
      await _ubusCall('session', 'destroy');
    }
    _cookie = '';
    _authHeader = '';
    _tclToken = '';
    _qcmapToken = '';
    _ubusSid = '';
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

  Future<ModemStatus> _fetchJrdStatus() async {
    final infoRes = await _jrdCall('GetSystemInfo');
    final statusRes = await _jrdCall('GetSystemStatus');
    final simRes = await _jrdCall('GetSimStatus');
    final wlanRes = await _jrdCall('GetWlanSettings');
    final devRes = await _jrdCall('GetConnectedDeviceList');

    if (infoRes == null && statusRes == null) {
      throw SocketException('انقطع الاتصال بالمودم ($gatewayIp)');
    }

    final info = (infoRes?['result'] as Map?)?.cast<String, dynamic>() ?? {};
    final st = (statusRes?['result'] as Map?)?.cast<String, dynamic>() ?? {};
    final sim = (simRes?['result'] as Map?)?.cast<String, dynamic>() ?? {};
    final wlan = (wlanRes?['result'] as Map?)?.cast<String, dynamic>() ?? {};
    final devMap = (devRes?['result'] as Map?)?.cast<String, dynamic>() ?? {};

    final model = (info['DeviceName'] ?? info['SpreadName'] ?? detectedTitle)
        .toString()
        .trim();
    final imei = (info['IMEI'] ?? '-').toString();
    final iccid = (info['ICCID'] ?? sim['ICCID'] ?? '-').toString();
    final imsi = (sim['IMSI'] ?? '-').toString();
    final msisdn = ModemStatus.extractFirstValidNumber(
      [
        (info['MSISDN'] ?? '').toString(),
        (sim['MSISDN'] ?? '').toString(),
      ],
      imei: imei,
      iccid: iccid,
      imsi: imsi,
    );

    final batCap = int.tryParse((st['bat_cap'] ?? '').toString());
    final hasBat = batCap != null;
    final charging = (st['chg_state'] ?? '').toString() == '1';
    final sigStrength = int.tryParse((st['SignalStrength'] ?? '').toString()) ?? 0;
    final netName = (st['NetworkName'] ?? '').toString();
    final ssid = (wlan['Ssid'] ?? wlan['SSID'] ?? st['curr_24G_ssid'] ?? '').toString();
    final wifiKey = (wlan['WpaKey'] ?? wlan['PassPhrase'] ?? '').toString();

    final devices = <ConnectedDevice>[];
    final rawList = devMap['ConnectedList'];
    if (rawList is List) {
      for (var i = 0; i < rawList.length; i++) {
        final item = rawList[i];
        if (item is Map) {
          final ip = (item['IPAddress'] ?? '').toString();
          final mac = (item['MacAddress'] ?? '').toString().toUpperCase();
          final name = (item['DeviceName'] ?? 'جهاز متصل').toString();
          devices.add(
            ConnectedDevice(
              index: i,
              name: name,
              ipAddress: ip,
              macAddress: mac,
              isCurrentDevice: ip.isNotEmpty && ip == localClientIp,
            ),
          );
        }
      }
    }

    return ModemStatus(
      hasBattery: hasBat,
      batteryPercent: (batCap ?? 0).clamp(0, 100),
      isCharging: charging,
      uptimeSeconds: DateTime.now().difference(_sessionStart).inSeconds,
      networkType: (st['NetworkType'] ?? '').toString().isNotEmpty ? '4G' : '',
      operatorName: netName,
      signalBars: sigStrength.clamp(0, 5),
      signalPercent: (sigStrength * 20).clamp(0, 100),
      wanConnected: (st['ConnectionStatus'] ?? '').toString() == '2',
      modemPhoneNumber: msisdn,
      deviceModel: model,
      lanIp: gatewayIp,
      macAddress: (info['MacAddress'] ?? '-').toString(),
      imei: imei,
      iccid: iccid,
      imsi: imsi,
      softwareVersion: (info['SwVersion'] ?? '-').toString(),
      hardwareVersion: (info['HwVersion'] ?? '-').toString(),
      ssid: ssid,
      wifiPassword: wifiKey,
      connectedDevicesCount:
          devices.isNotEmpty ? devices.length : (int.tryParse((st['TotalConnNum'] ?? '0').toString()) ?? 0),
      adminUsername: _username,
      adminPassword: _password,
      devices: devices,
      capabilities: ModemCapabilities(
        hasBattery: hasBat,
        hasSignalMetrics: sigStrength > 0,
        hasBandLock: false,
        hasSpeedLimit: false,
        hasWifiEdit: true,
        hasMaxClients: true,
        hasHideSsid: true,
        hasLcdQrToggle: false,
        hasDeviceBlock: true,
        hasDeviceRename: false,
        hasReboot: true,
        hasPowerOff: false,
        hasAdminPassword: false,
        hasSms: true,
      ),
    );
  }

  Future<ModemStatus> _fetchQcmapStatus() async {
    final wwan = await _qcmapCall('GetWWANSTATS', {'family': '4'});
    final lan = await _qcmapCall('GetLANConfig');
    final wlan = await _qcmapCall('GetWLANStatus');
    final clients = await _qcmapCall('GetConnectedDevices');

    if (wwan == null && lan == null && wlan == null) {
      throw SocketException('انقطع الاتصال بالمودم ($gatewayIp)');
    }

    final rxBytes = int.tryParse((wwan?['bytes_rx'] ?? '0').toString()) ?? 0;
    final txBytes = int.tryParse((wwan?['bytes_tx'] ?? '0').toString()) ?? 0;
    final wanIp = (wwan?['public_ip'] ?? wwan?['wan_ip'] ?? '-').toString();
    final ssid = (wlan?['ssid'] ?? wlan?['SSID'] ?? '').toString();
    final devices = <ConnectedDevice>[];
    final rawList = clients?['connected_devices'] ?? clients?['devices'];
    if (rawList is List) {
      for (var i = 0; i < rawList.length; i++) {
        final item = rawList[i];
        if (item is Map) {
          final ip = (item['ip'] ?? item['ip_addr'] ?? '').toString();
          final mac = (item['mac'] ?? item['mac_addr'] ?? '').toString().toUpperCase();
          final name = (item['host_name'] ?? item['name'] ?? 'جهاز متصل').toString();
          devices.add(
            ConnectedDevice(
              index: i,
              name: name,
              ipAddress: ip,
              macAddress: mac,
              isCurrentDevice: ip.isNotEmpty && ip == localClientIp,
            ),
          );
        }
      }
    }

    return ModemStatus(
      rxBytes: rxBytes,
      txBytes: txBytes,
      totalBytes: rxBytes + txBytes,
      uptimeSeconds: DateTime.now().difference(_sessionStart).inSeconds,
      networkType: '4G',
      wanConnected: wanIp != '-' && wanIp.isNotEmpty && wanIp != '0.0.0.0',
      deviceModel: detectedTitle,
      wanIp: wanIp.isNotEmpty ? wanIp : '-',
      lanIp: gatewayIp,
      ssid: ssid,
      connectedDevicesCount: devices.isNotEmpty ? devices.length : 1,
      adminUsername: _username,
      adminPassword: _password,
      devices: devices,
      capabilities: ModemCapabilities(
        hasBattery: false,
        hasSignalMetrics: false,
        hasBandLock: false,
        hasSpeedLimit: false,
        hasWifiEdit: ssid.isNotEmpty,
        hasMaxClients: false,
        hasHideSsid: false,
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

  Future<ModemStatus> _fetchUbusStatus() async {
    final board = await _ubusCall('system', 'board');
    final info = await _ubusCall('system', 'info');
    if (board == null && info == null) {
      throw SocketException('انقطع الاتصال بالراوتر ($gatewayIp)');
    }
    final bMap = board is Map ? board : const {};
    final iMap = info is Map ? info : const {};
    final model = (bMap['model'] ?? bMap['hostname'] ?? detectedTitle).toString();
    final release = bMap['release'] is Map
        ? (bMap['release']['description'] ?? '-').toString()
        : '-';
    final uptime = int.tryParse((iMap['uptime'] ?? '0').toString()) ?? 0;

    return ModemStatus(
      uptimeSeconds: uptime,
      wanConnected: true,
      deviceModel: model,
      lanIp: gatewayIp,
      softwareVersion: release,
      adminUsername: _username,
      adminPassword: _password,
      capabilities: const ModemCapabilities(
        hasBattery: false,
        hasSignalMetrics: false,
        hasBandLock: false,
        hasSpeedLimit: false,
        hasWifiEdit: false,
        hasMaxClients: false,
        hasHideSsid: false,
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

  @override
  Future<ModemStatus> fetchStatus({bool forceFullRefresh = false}) async {
    if (_isJrdWebApi) {
      return _fetchJrdStatus();
    }
    if (_isQcmap) {
      return _fetchQcmapStatus();
    }
    if (_isUbus) {
      return _fetchUbusStatus();
    }

    final endpoints = <String>{
      '/',
      ...(profile?.statusEndpoints ?? const []),
      '/srv/status',
      '/api/system/deviceinfo',
      '/status.json',
      '/api/status',
      '/goform/getStatus',
      '/cgi-bin/status',
      '/status.xml',
      '/main.html',
    }.take(14).toList();

    final combinedBuffer = StringBuffer();
    final translatedExtras = <String, String>{};
    bool anyReached = false;

    for (final ep in endpoints) {
      try {
        final r = await _client
            .get(Uri.parse('$_baseUrl$ep'), headers: _headers)
            .timeout(const Duration(seconds: 2));
        if (r.statusCode > 0 && r.statusCode < 500) {
          anyReached = true;
        }
        if (r.statusCode >= 200 && r.statusCode < 400 && r.bodyBytes.isNotEmpty) {
          final text = utf8.decode(r.bodyBytes, allowMalformed: true);
          combinedBuffer.writeln(text);

          if (text.trim().startsWith('{')) {
            try {
              final map = jsonDecode(text) as Map<String, dynamic>;
              final inner = map['statusData'] is Map
                  ? (map['statusData'] as Map).cast<String, dynamic>()
                  : map;
              inner.forEach((k, v) {
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

    if (!anyReached) {
      throw SocketException('انقطع الاتصال بالراوتر ($gatewayIp)');
    }

    final raw = combinedBuffer.toString();

    final title = _extractMatch(raw, [
          RegExp(
              r'"(?:DeviceName|model|device_name|product_name|ModelName)"\s*:\s*"([^"]+)"',
              caseSensitive: false),
          RegExp(r'<title>([^<]{2,40})</title>', caseSensitive: false),
        ]) ??
        detectedTitle;

    final ssid = _extractMatch(raw, [
          RegExp(r'"(?:ssid|SSID|SSID1|wifi_ssid|statusBarWiFiName)"\s*:\s*"([^"]+)"'),
          RegExp(r'<(?:ssid|SSID|WifiSsid)>([^<]+)</', caseSensitive: false),
          RegExp(r'var\s+ssid\s*=\s*["\x27]([^"\x27]+)["\x27]',
              caseSensitive: false),
        ]) ??
        '';

    final wanIp = _extractMatch(raw, [
          RegExp(
              r'"(?:wan_ip|wanIp|ipv4|WanIPAddress|ExternalIPAddress|statusBarIpAddress)"\s*:\s*"([0-9\.]{7,15})"'),
          RegExp(r'<(?:wan_ip|ipv4|WanIPAddress|ExternalIPAddress)>([0-9\.]{7,15})</',
              caseSensitive: false),
        ]) ??
        '-';

    final imei = _extractMatch(raw, [
          RegExp(r'"?(?:imei|IMEI)"?\s*[:=>]\s*"?(\d{14,16})"?'),
        ]) ??
        '-';
    final iccid = _extractMatch(raw, [
          RegExp(r'"?(?:iccid|ICCID)"?\s*[:=>]\s*"?(\d{18,22})"?'),
        ]) ??
        '-';
    final imsi = _extractMatch(raw, [
          RegExp(r'"?(?:imsi|IMSI)"?\s*[:=>]\s*"?(\d{14,16})"?'),
        ]) ??
        '-';
    final msisdnRaw = _extractMatch(raw, [
          RegExp(
              r'"?(?:msisdn|MSISDN|mdn|phone_number|Mdn)"?\s*[:=>]\s*"?(\+?\d{8,14})"?'),
        ]) ??
        '';
    final modemNum = ModemStatus.extractFirstValidNumber(
      [msisdnRaw],
      imei: imei,
      iccid: iccid,
      imsi: imsi,
    );

    final rsrp = _extractMatch(raw, [
      RegExp(r'"?(?:rsrp|lte_rsrp|statusBarRsrp)"?\s*[:=>]\s*"?(-?\d{2,3})"?',
          caseSensitive: false),
    ]);
    final sinr = _extractMatch(raw, [
      RegExp(r'"?(?:sinr|snr|lte_snr|statusBarSnr)"?\s*[:=>]\s*"?(-?\d{1,2})"?',
          caseSensitive: false),
    ]);
    final bandRaw = _extractMatch(raw, [
      RegExp(r'"?(?:band|lte_band|active_band)"?\s*[:=>]\s*"?(B?\d{1,2})"?',
          caseSensitive: false),
    ]);
    final batStr = _extractMatch(raw, [
      RegExp(
          r'"?(?:battery|battery_pers|BatteryPercent|Battery_voltage|statusBarBatteryPercent)"?\s*[:=>]\s*"?(\d{1,3})"?'),
    ]);

    for (final m in RegExp(
            r'var\s+([a-zA-Z0-9_]{3,24})\s*=\s*["\x27]([^"\x27]{1,35})["\x27]')
        .allMatches(raw)
        .take(20)) {
      final k = m.group(1)!;
      final v = m.group(2)!;
      if (_arabicKeyDictionary.containsKey(k.toLowerCase())) {
        translatedExtras[_arabicKeyDictionary[k.toLowerCase()]!] = v;
      }
    }

    final hasBat = batStr != null;
    final batPct = hasBat ? (int.tryParse(batStr) ?? 0).clamp(0, 100) : 0;

    final hasSig = rsrp != null;
    int sigPct = 0;
    int sigBars = 0;
    if (rsrp != null) {
      final rv = int.tryParse(rsrp) ?? 0;
      if (rv < -40 && rv >= -140) {
        sigPct = (((rv + 122) / 47.0) * 100).round().clamp(5, 100);
        sigBars = ((sigPct / 20).ceil()).clamp(1, 5);
      }
    }

    final formattedBand = bandRaw == null || bandRaw.isEmpty
        ? ''
        : (bandRaw.toUpperCase().startsWith('B')
            ? bandRaw.toUpperCase()
            : 'B$bandRaw');

    final sessionSecs = DateTime.now().difference(_sessionStart).inSeconds;

    return ModemStatus(
      hasBattery: hasBat,
      batteryPercent: batPct,
      isCharging: false,
      uptimeSeconds: sessionSecs,
      networkType: formattedBand.isNotEmpty ? '4G' : '',
      operatorName: '',
      signalBars: sigBars,
      signalPercent: sigPct,
      band: formattedBand,
      rsrp: rsrp != null ? '$rsrp dBm' : '-',
      sinr: sinr != null ? '$sinr dB' : '-',
      wanConnected: wanIp != '-',
      modemPhoneNumber: modemNum,
      deviceModel: title,
      wanIp: wanIp,
      lanIp: gatewayIp,
      imei: imei,
      iccid: iccid,
      imsi: imsi,
      ssid: ssid,
      connectedDevicesCount: localClientIp.isNotEmpty ? 1 : 0,
      adminUsername: _username,
      adminPassword: _password,
      devices: localClientIp.isNotEmpty
          ? [
              ConnectedDevice(
                index: 0,
                name: 'هاتفك الحالي',
                ipAddress: localClientIp,
                macAddress: 'متصل حالياً',
                isCurrentDevice: true,
              ),
            ]
          : const [],
      translatedExtras: translatedExtras,
      capabilities: ModemCapabilities(
        hasBattery: hasBat,
        hasSignalMetrics: hasSig,
        hasBandLock: false,
        hasSpeedLimit: false,
        hasWifiEdit: ssid.isNotEmpty,
        hasMaxClients: false,
        hasHideSsid: ssid.isNotEmpty,
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
    if (_isJrdWebApi) {
      final res = await _jrdCall('SetWlanSettings', {
        'WlanAPMode': 0,
        'Ssid': ssid,
        'SsidHidden': hideSsid ? 1 : 0,
        'WpaKey': password,
        'MaxNumsta': maxClients,
      });
      if (res != null && res['error'] == null) return true;
    }
    if (_isQcmap) {
      final res = await _qcmapCall('SetWLANConfig', {
        'ssid': ssid,
        'passphrase': password,
      });
      if (res != null && (res['result'] == '0' || res['result'] == 0)) return true;
    }
    final wifiPaths = <String>{
      ...(profile?.wifiEndpoints ?? const []),
      '/goform/setWifi',
      '/api/wifi',
      '/cgi-bin/wireless',
    };
    for (final path in wifiPaths) {
      try {
        final r = await _client
            .post(
              Uri.parse('$_baseUrl$path'),
              headers: _headers,
              body: {
                'ssid': ssid,
                'SSID': ssid,
                'password': password,
                'key': password,
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
  Future<bool> blockMacAddress(String macAddress) async {
    if (_isJrdWebApi) {
      final res = await _jrdCall('SetDeviceUnlock', {
        'DeviceName': '',
        'MacAddress': macAddress.toUpperCase(),
        'Action': 1,
      });
      if (res != null && res['error'] == null) return true;
    }
    return false;
  }

  @override
  Future<bool> unblockMacAddress(String macAddress) async {
    if (_isJrdWebApi) {
      final res = await _jrdCall('SetDeviceUnlock', {
        'DeviceName': '',
        'MacAddress': macAddress.toUpperCase(),
        'Action': 0,
      });
      if (res != null && res['error'] == null) return true;
    }
    return false;
  }

  @override
  Future<bool> setDeviceBlock({
    required ConnectedDevice device,
    required bool block,
  }) =>
      block ? blockMacAddress(device.macAddress) : unblockMacAddress(device.macAddress);

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
    if (_isJrdWebApi) {
      final res = await _jrdCall('SetDeviceReboot');
      if (res != null && res['error'] == null) return true;
    }
    if (_isQcmap) {
      final res = await _qcmapCall('Reboot');
      if (res != null) return true;
    }
    if (_isUbus) {
      final res = await _ubusCall('system', 'reboot');
      if (res != null) return true;
    }
    final rebootPaths = <String>{
      ...(profile?.rebootEndpoints ?? const []),
      '/goform/reboot',
      '/goform/SysToolReboot',
      '/cgi-bin/reboot',
      '/api/reboot',
      '/reboot.cgi',
    };
    for (final path in rebootPaths) {
      try {
        final r = await _client
            .post(Uri.parse('$_baseUrl$path'), headers: _headers)
            .timeout(const Duration(seconds: 4));
        if (r.statusCode < 400) return true;
      } catch (_) {}
    }
    return false;
  }

  @override
  Future<bool> powerOffModem() async => false;

  @override
  Future<List<SmsMessage>> fetchSmsInbox() async {
    if (_isJrdWebApi) {
      final res = await _jrdCall('GetSMSListByContactNum', {
        'Page': 1,
        'ContactId': -1,
      });
      final list = res?['result']?['SMSList'];
      if (list is List) {
        return [
          for (var i = 0; i < list.length; i++)
            if (list[i] is Map)
              SmsMessage(
                id: (list[i]['SMSId'] ?? '$i').toString(),
                sender: (list[i]['PhoneNumber'] ?? 'غير معروف').toString(),
                content: (list[i]['SMSContent'] ?? '').toString(),
                timestamp: (list[i]['SMSTime'] ?? '').toString(),
                isUnread: (list[i]['SMSType'] ?? '').toString() == '1',
              ),
        ];
      }
    }
    return [];
  }
}
