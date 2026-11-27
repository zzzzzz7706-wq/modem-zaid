import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:xml/xml.dart';
import '../../models/modem_models.dart';
import 'modem_adapter.dart';

class _RawHttpResponse {
  final int statusCode;
  final Map<String, String> headers;
  final String body;
  final String fullWireText;

  const _RawHttpResponse({
    required this.statusCode,
    required this.headers,
    required this.body,
    required this.fullWireText,
  });
}

/// Bulletproof adapter for Notion / Marvell / ASR XML-RPC MiFi routers
/// (L818A, Vortex Gen 1-4, SAM M50/M50 Pro, M028T, L02H, Falcon, Cool 4G).
/// Uses a serialized raw TCP socket HTTP engine (`Connection: close`) so
/// Mongoose/3.0 duplicate status headers & sequential Digest `nc` counters
/// work with 100% reliability on every single login and poll.
class NotionMifiAdapter implements ModemAdapter {
  @override
  final String gatewayIp;

  @override
  final String localClientIp;

  final String detectedModelHint;

  String _username = 'admin';
  String _password = 'admin';
  String _realm = 'Highwmg';
  String _nonce = '';
  String _qop = 'auth';
  String _cookie = '';
  int _gnCount = 1;
  bool _useBasicFallback = false;

  // Strict FIFO mutex so Digest `nc` never arrives out-of-order on Mongoose/Lighttpd
  Future<void> _mutex = Future.value();

  int _pollTick = 0;
  XmlDocument? _cachedWifiSecXml;
  XmlDocument? _cachedDevicesXml;
  XmlDocument? _cachedSpeedXml;
  XmlDocument? _cachedAdminXml;
  XmlDocument? _cachedWanXml;

  NotionMifiAdapter({
    required this.gatewayIp,
    required this.localClientIp,
    this.detectedModelHint = 'L818A 4G',
  });

  @override
  ModemFamily get family => ModemFamily.notionMifi;

  @override
  String get protocolName => 'Notion / Yemen 4G MiFi';

  Future<T> _synchronized<T>(Future<T> Function() task) {
    final completer = Completer<T>();
    _mutex = _mutex.then((_) async {
      try {
        final result = await task();
        completer.complete(result);
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  /// Sends an HTTP/1.1 request with `Connection: close` over a raw TCP socket
  /// to tolerate Mongoose/3.0 double `HTTP/1.1 200 OK` headers without throwing.
  Future<_RawHttpResponse> _rawRequest(
    String method,
    String pathAndQuery, {
    Map<String, String>? headers,
    String? body,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    Socket? socket;
    try {
      socket = await Socket.connect(gatewayIp, 80, timeout: timeout);
      final bodyBytes = body != null ? utf8.encode(body) : const <int>[];

      final reqBuf = StringBuffer();
      reqBuf.write('$method $pathAndQuery HTTP/1.1\r\n');
      reqBuf.write('Host: $gatewayIp\r\n');
      reqBuf.write('Connection: close\r\n');
      reqBuf.write('Accept: */*\r\n');
      if (headers != null) {
        headers.forEach((k, v) {
          reqBuf.write('$k: $v\r\n');
        });
      }
      if (bodyBytes.isNotEmpty) {
        reqBuf.write('Content-Length: ${bodyBytes.length}\r\n');
      }
      reqBuf.write('\r\n');

      socket.add(utf8.encode(reqBuf.toString()));
      if (bodyBytes.isNotEmpty) {
        socket.add(bodyBytes);
      }
      await socket.flush();

      final builder = BytesBuilder(copy: false);
      await socket
          .listen((chunk) => builder.add(chunk))
          .asFuture<void>()
          .timeout(timeout, onTimeout: () {});

      final rawBytes = builder.takeBytes();
      final wire = utf8.decode(rawBytes, allowMalformed: true);
      if (wire.isEmpty) {
        return const _RawHttpResponse(
          statusCode: 0,
          headers: {},
          body: '',
          fullWireText: '',
        );
      }

      final splitIdx = wire.indexOf('\r\n\r\n');
      final headerPart = splitIdx != -1 ? wire.substring(0, splitIdx) : wire;
      var bodyPart = splitIdx != -1 ? wire.substring(splitIdx + 4) : '';

      final lines = headerPart.split('\r\n');
      int code = 200;
      if (lines.isNotEmpty) {
        final statusMatch = RegExp(r'HTTP/\d\.\d\s+(\d{3})').firstMatch(lines.first);
        if (statusMatch != null) {
          code = int.tryParse(statusMatch.group(1)!) ?? 200;
        }
      }

      final parsedHeaders = <String, String>{};
      for (int i = 1; i < lines.length; i++) {
        final colon = lines[i].indexOf(':');
        if (colon > 0) {
          final k = lines[i].substring(0, colon).trim().toLowerCase();
          final v = lines[i].substring(colon + 1).trim();
          parsedHeaders[k] = v;
        }
      }

      // Strip chunked framing if server sent Transfer-Encoding: chunked
      if ((parsedHeaders['transfer-encoding'] ?? '').toLowerCase().contains('chunked')) {
        bodyPart = _decodeChunkedBody(bodyPart);
      }

      return _RawHttpResponse(
        statusCode: code,
        headers: parsedHeaders,
        body: bodyPart,
        fullWireText: wire,
      );
    } finally {
      try {
        socket?.destroy();
      } catch (_) {}
    }
  }

  static String _decodeChunkedBody(String input) {
    final out = StringBuffer();
    int pos = 0;
    while (pos < input.length) {
      final rn = input.indexOf('\r\n', pos);
      if (rn == -1) break;
      final hexLen = input.substring(pos, rn).split(';').first.trim();
      final chunkLen = int.tryParse(hexLen, radix: 16);
      if (chunkLen == null) {
        return input;
      }
      if (chunkLen == 0) break;
      final start = rn + 2;
      final end = (start + chunkLen).clamp(0, input.length);
      out.write(input.substring(start, end));
      pos = end + 2;
    }
    final res = out.toString();
    return res.isEmpty ? input : res;
  }

  static String _md5Hex(String input) {
    return md5.convert(utf8.encode(input)).toString().toLowerCase();
  }

  static String _upperHexCount(int value) {
    return value.toRadixString(16).toUpperCase().padLeft(8, '0');
  }

  static String uniDecode(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    final isHex4 = trimmed.length >= 4 &&
        trimmed.length % 4 == 0 &&
        RegExp(r'^[0-9a-fA-F]+$').hasMatch(trimmed);
    if (!isHex4) return trimmed;
    try {
      final units = <int>[];
      for (int i = 0; i < trimmed.length; i += 4) {
        final code = int.parse(trimmed.substring(i, i + 4), radix: 16);
        if (code == 0) continue;
        units.add(code);
      }
      if (units.isEmpty) return trimmed;
      return String.fromCharCodes(units);
    } catch (_) {
      return trimmed;
    }
  }

  static String uniEncode(String text) {
    final sb = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      sb.write(text.codeUnitAt(i).toRadixString(16).padLeft(4, '0'));
    }
    return sb.toString();
  }

  String _randomCnonce() {
    final rand = Random().nextInt(100001);
    final now = DateTime.now().microsecondsSinceEpoch;
    return _md5Hex('$rand$now').substring(0, 16);
  }

  String _buildAuthHeader(String method) {
    if (_useBasicFallback) {
      final token = base64Encode(utf8.encode('$_username:$_password'));
      return 'Basic $token';
    }
    final ha1 = _md5Hex('$_username:$_realm:$_password');
    final ha2 = _md5Hex('$method:/cgi/xml_action.cgi');
    final cnonce = _randomCnonce();
    final nc = _upperHexCount(_gnCount++);
    final response = _md5Hex('$ha1:$_nonce:$nc:$cnonce:$_qop:$ha2');
    return 'Digest username="$_username", realm="$_realm", nonce="$_nonce", '
        'uri="/cgi/xml_action.cgi", response="$response", qop=$_qop, '
        'nc=$nc, cnonce="$cnonce"';
  }

  Map<String, String> _headers(String method, {bool xmlPost = false}) {
    final map = <String, String>{
      'Authorization': _buildAuthHeader(method),
      'Expires': '-1',
      'Cache-Control': 'no-store, no-cache, must-revalidate',
      'Pragma': 'no-cache',
    };
    if (_cookie.isNotEmpty) {
      map['Cookie'] = _cookie;
    }
    if (xmlPost) {
      map['Content-Type'] = 'text/xml;charset=UTF-8';
    }
    return map;
  }

  Future<bool> _performLoginUnlocked(String username, String password) async {
    _username = username.trim().isEmpty ? 'admin' : username.trim();
    _password = password;
    _gnCount = 1;
    _useBasicFallback = false;

    try {
      final challengeRes = await _rawRequest(
        'GET',
        '/login.cgi',
        headers: const {
          'Expires': '-1',
          'Cache-Control': 'no-store, no-cache, must-revalidate',
          'Pragma': 'no-cache',
        },
      );

      final setCookie = challengeRes.headers['set-cookie'];
      if (setCookie != null && setCookie.isNotEmpty) {
        _cookie = setCookie.split(';').first;
      }

      final wwwAuth = challengeRes.headers['www-authenticate'] ?? '';
      if (wwwAuth.toLowerCase().contains('digest')) {
        final matches =
            RegExp(r'(\w+)\s*=\s*"?([^",\s]+)"?').allMatches(wwwAuth);
        for (final m in matches) {
          final k = m.group(1)?.toLowerCase();
          final v = m.group(2) ?? '';
          if (k == 'realm') _realm = v;
          if (k == 'nonce') _nonce = v;
          if (k == 'qop') _qop = v;
        }

        final ha1 = _md5Hex('$_username:$_realm:$_password');
        final ha2Protected = _md5Hex('GET:/cgi/protected.cgi');
        final cnonce = _randomCnonce();
        final digestRes =
            _md5Hex('$ha1:$_nonce:00000001:$cnonce:$_qop:$ha2Protected');

        _gnCount = 1;
        final loginPath = '/login.cgi?Action=Digest'
            '&username=${Uri.encodeComponent(_username)}'
            '&realm=${Uri.encodeComponent(_realm)}'
            '&nonce=${Uri.encodeComponent(_nonce)}'
            '&response=$digestRes'
            '&qop=${Uri.encodeComponent(_qop)}'
            '&cnonce=$cnonce'
            '&temp=MIFI';

        final authRes = await _rawRequest(
          'GET',
          loginPath,
          headers: _headers('GET'),
        );

        final sc2 = authRes.headers['set-cookie'];
        if (sc2 != null && sc2.isNotEmpty) {
          _cookie = sc2.split(';').first;
        }

        if (authRes.statusCode == 500 ||
            authRes.fullWireText.contains('HTTP/1.1 500')) {
          return false;
        }

        if (authRes.statusCode == 200 &&
            (authRes.fullWireText.contains('200 OK') ||
                authRes.headers.containsKey('login-type'))) {
          final verify = await _getXmlUnlocked('status1', allowRelogin: false);
          return verify != null;
        }

        final verify = await _getXmlUnlocked('status1', allowRelogin: false);
        return verify != null;
      } else {
        _useBasicFallback = true;
        final testXml = await _getXmlUnlocked('status1', allowRelogin: false);
        return testXml != null;
      }
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> login(String username, String password) {
    return _synchronized(() => _performLoginUnlocked(username, password));
  }

  @override
  Future<void> logout() {
    return _synchronized(() async {
      try {
        await _rawRequest(
          'GET',
          '/xml_action.cgi?Action=logout',
          headers: _headers('GET'),
          timeout: const Duration(seconds: 2),
        );
      } catch (_) {}
    });
  }

  Future<XmlDocument?> _getXmlUnlocked(
    String file, {
    bool allowRelogin = true,
  }) async {
    try {
      final res = await _rawRequest(
        'GET',
        '/xml_action.cgi?method=get&module=duster&file=$file',
        headers: _headers('GET'),
      );

      if ((res.statusCode == 401 || res.statusCode == 500) && allowRelogin) {
        if (await _performLoginUnlocked(_username, _password)) {
          return _getXmlUnlocked(file, allowRelogin: false);
        }
        return null;
      }

      var body = res.body.trim();
      final rgwStart = body.indexOf('<RGW');
      final xmlStart = body.indexOf('<?xml');
      if (xmlStart > 0) {
        body = body.substring(xmlStart);
      } else if (rgwStart > 0) {
        body = body.substring(rgwStart);
      }

      if (body.isEmpty || body.contains('E7683FTEFTA8HT08HFH09')) {
        if (allowRelogin && await _performLoginUnlocked(_username, _password)) {
          return _getXmlUnlocked(file, allowRelogin: false);
        }
        return null;
      }

      final doc = XmlDocument.parse(body);
      final loginStatus = _findText(doc.rootElement, 'login_status');
      if ((loginStatus == 'UNAUTHORIZED' || loginStatus == 'KICKOFF') &&
          allowRelogin) {
        if (await _performLoginUnlocked(_username, _password)) {
          return _getXmlUnlocked(file, allowRelogin: false);
        }
        return null;
      }
      return doc;
    } catch (_) {
      return null;
    }
  }

  Future<XmlDocument?> _getXml(String file) {
    return _synchronized(() => _getXmlUnlocked(file));
  }

  Future<bool> _postXml(String file, String innerRgwXml) {
    return _synchronized(() async {
      try {
        final payload =
            '<?xml version="1.0" encoding="US-ASCII"?> <RGW>$innerRgwXml</RGW>';
        var res = await _rawRequest(
          'POST',
          '/xml_action.cgi?method=set&module=duster&file=$file',
          headers: _headers('POST', xmlPost: true),
          body: payload,
          timeout: const Duration(seconds: 8),
        );

        if (res.statusCode == 401 ||
            res.statusCode == 500 ||
            res.body.contains('UNAUTHORIZED') ||
            res.body.contains('KICKOFF')) {
          if (await _performLoginUnlocked(_username, _password)) {
            res = await _rawRequest(
              'POST',
              '/xml_action.cgi?method=set&module=duster&file=$file',
              headers: _headers('POST', xmlPost: true),
              body: payload,
              timeout: const Duration(seconds: 8),
            );
          } else {
            return false;
          }
        }
        return res.statusCode >= 200 && res.statusCode < 400;
      } catch (_) {
        return false;
      }
    });
  }

  static String _findText(XmlElement parent, String tag) {
    final found = parent.findAllElements(tag);
    if (found.isEmpty) return '';
    return found.first.innerText.trim();
  }

  static int _parseInt(String s, [int fallback = 0]) {
    if (s.isEmpty) return fallback;
    final clean = s.replaceAll(RegExp(r'[^0-9\-]'), '');
    return int.tryParse(clean) ?? fallback;
  }

  static String _translateOperator({
    required String rawName,
    required String roamingPlmn,
    required String imsi,
  }) {
    final combined = '$rawName $roamingPlmn $imsi';
    if (combined.contains('42110') ||
        imsi.startsWith('42110') ||
        rawName.contains('中国电信') ||
        rawName.toLowerCase().contains('yemen 4g') ||
        rawName.toLowerCase().contains('ptc')) {
      return 'يمن فورجي (Yemen 4G)';
    }
    if (combined.contains('42103') || imsi.startsWith('42103')) {
      return 'يمن موبايل (Yemen Mobile)';
    }
    if (combined.contains('42101') || imsi.startsWith('42101')) {
      return 'سبأفون (Sabafon)';
    }
    if (combined.contains('42102') || imsi.startsWith('42102')) {
      return 'يو (YOU)';
    }
    if (rawName.isEmpty || RegExp(r'[\u4e00-\u9fff]').hasMatch(rawName)) {
      return 'يمن فورجي (Yemen 4G)';
    }
    return rawName;
  }

  @override
  Future<ModemStatus> fetchStatus({bool forceFullRefresh = false}) {
    return _synchronized(() async {
      final full =
          forceFullRefresh || _pollTick % 5 == 0 || _cachedWifiSecXml == null;
      _pollTick++;

      // 1. Primary status1 XML (already includes WanStatistics, battery, MSISDN, signal, LAN/WAN!)
      final statusDoc = await _getXmlUnlocked('status1');
      if (statusDoc == null) {
        throw Exception('تعذر قراءة بيانات المودم من $gatewayIp');
      }

      // 2. Strictly sequential secondary XML reads so Digest `nc` stays strictly ordered!
      if (full) {
        final wifiSec = await _getXmlUnlocked('uapxb_wlan_security_settings');
        if (wifiSec != null) _cachedWifiSecXml = wifiSec;

        final devs = await _getXmlUnlocked('device_management_all');
        if (devs != null) _cachedDevicesXml = devs;

        final spd = await _getXmlUnlocked('jm_custom');
        if (spd != null) _cachedSpeedXml = spd;

        final wanDoc = await _getXmlUnlocked('wan');
        if (wanDoc != null) _cachedWanXml = wanDoc;

        final adm = await _getXmlUnlocked('admin');
        if (adm != null) _cachedAdminXml = adm;
      }

      final root = statusDoc.rootElement;

      // Battery
      final batteryConnect = _findText(root, 'Battery_connect');
      final hasBat = batteryConnect != '0';
      final batteryPct =
          _parseInt(_findText(root, 'Battery_voltage'), 0).clamp(0, 100);
      final isCharging = _findText(root, 'Battery_charge') == '1' ||
          _findText(root, 'Battery_charging') == '1';

      // Uptime (prefer curconntime from active PDP context if run_days/hours are 0)
      final runDays = _parseInt(_findText(root, 'run_days'));
      final runHours = _parseInt(_findText(root, 'run_hours'));
      final runMinutes = _parseInt(_findText(root, 'run_minutes'));
      final runSeconds = _parseInt(_findText(root, 'run_seconds'));
      var uptimeSec =
          runDays * 86400 + runHours * 3600 + runMinutes * 60 + runSeconds;
      final pdpConnTime = _parseInt(_findText(root, 'curconntime'));
      if (uptimeSec == 0 && pdpConnTime > 0) {
        uptimeSec = pdpConnTime;
      }

      // Traffic bytes directly from status1 -> WanStatistics
      int rxBytes = 0;
      int txBytes = 0;
      final ws = root.findAllElements('WanStatistics');
      if (ws.isNotEmpty) {
        rxBytes = _parseInt(_findText(ws.first, 'rx'));
        txBytes = _parseInt(_findText(ws.first, 'tx'));
        if (rxBytes == 0 && txBytes == 0) {
          rxBytes = _parseInt(_findText(ws.first, 'rx_byte'));
          txBytes = _parseInt(_findText(ws.first, 'tx_byte'));
        }
      }
      final totalBytes = rxBytes + txBytes;
      final rxRate = _parseInt(_findText(root, 'rx_rate'));
      final txRate = _parseInt(_findText(root, 'tx_rate'));

      // Cellular & Signal
      final sysMode = _findText(root, 'sys_mode');
      final netType = (sysMode == '5' || sysMode == '15') ? '3G' : '4G';
      final imsi = _findText(root, 'IMSI');
      final operatorName = _translateOperator(
        rawName: _findText(root, 'network_name'),
        roamingPlmn: _findText(root, 'roaming_network_name'),
        imsi: imsi,
      );

      // RSRP & RSRQ (handle both negative dBm and 3GPP positive index 0..97)
      final rsrpRaw = _parseInt(_findText(root, 'rsrp'), 0);
      int? rsrpDbm;
      if (rsrpRaw < -40 && rsrpRaw >= -145) {
        rsrpDbm = rsrpRaw;
      } else if (rsrpRaw > 0 && rsrpRaw <= 97) {
        rsrpDbm = rsrpRaw - 140;
      }

      final rsrqRaw = _parseInt(_findText(root, 'rsrq'), 999);
      String rsrqDisplay = '-';
      if (rsrqRaw <= -3 && rsrqRaw >= -30) {
        rsrqDisplay = '$rsrqRaw dB';
      } else if (rsrqRaw >= 0 && rsrqRaw <= 34) {
        final db = (rsrqRaw * 0.5) - 19.5;
        rsrqDisplay = '${db.toStringAsFixed(1)} dB';
      }

      final sinrStr = _findText(root, 'sinr');
      final rssiRaw = _parseInt(_findText(root, 'rssi'));
      final pciStr = _findText(root, 'pci');
      final cellIdStr = _findText(root, 'cellid');

      String rawBand = _findText(root, 'band');
      if (rawBand.isEmpty && _cachedWanXml != null) {
        rawBand = _findText(_cachedWanXml!.rootElement, 'band');
      }
      String formattedBand = rawBand.isEmpty
          ? 'B28'
          : (rawBand.toUpperCase().startsWith('B')
              ? rawBand.toUpperCase()
              : 'B${rawBand.replaceAll(RegExp(r'[^0-9]'), '')}');
      if (formattedBand == 'B') formattedBand = rawBand;

      int signalPct = 75;
      if (rsrpDbm != null) {
        signalPct = (((rsrpDbm + 125) / 50.0) * 100).round().clamp(8, 100);
      } else if (rssiRaw > 0 && rssiRaw <= 99) {
        signalPct = ((rssiRaw / 45.0) * 100).round().clamp(10, 100);
      }
      final signalBars = ((signalPct / 20.0).ceil()).clamp(1, 5);

      String rssiDisplay = rssiRaw > 0 ? '$rssiRaw' : '-';
      if (sysMode == '17' && rssiRaw > 0 && rssiRaw < 98) {
        rssiDisplay = '${rssiRaw - 141} dBm';
      }

      bool wanConnected =
          _findText(root, 'wan_conn_status').toLowerCase() == 'connected';
      String wanIp = _findText(root, 'ipv4');
      for (final item in root.findAllElements('Item')) {
        if (_findText(item, 'success') == '1') {
          wanConnected = true;
          final pdpIp = _findText(item, 'ipv4');
          if (pdpIp.isNotEmpty && pdpIp != '0.0.0.0') {
            wanIp = pdpIp;
          }
          break;
        }
      }

      // Modem Phone Number (MSISDN - رقم المودم يمن فورجي)
      final rawMsisdn = _findText(root, 'MSISDN');
      final modemNumber = ModemStatus.normalizeModemNumber(rawMsisdn);

      // Device Info
      var modelName = _findText(root, 'device_name');
      if (modelName.isEmpty) modelName = detectedModelHint;
      final swVer = _findText(root, 'version_num');
      final hwVer = _findText(root, 'hardware_version');

      String lanIp = gatewayIp;
      final lanNodes = root.findAllElements('lan');
      if (lanNodes.isNotEmpty) {
        final lip = _findText(lanNodes.first, 'ip');
        if (lip.isNotEmpty && lip != '0.0.0.0') lanIp = lip;
      }
      final macAddr = _findText(root, 'mac');
      final imei = _findText(root, 'IMEI');
      final iccid = _findText(root, 'ICCID');

      // Wi-Fi Settings & Security
      String ssid = uniDecode(_findText(root, 'ssid'));
      int maxClients = _parseInt(_findText(root, 'max_clients'), 10);
      int connCount = _parseInt(_findText(root, 'nr_connected_dev'), 1);

      String wifiPassword = '';
      bool isHiddenSsid = false;
      String secMode = 'WPA2-PSK';
      String cipherMode = 'AES-CCMP';
      bool lcdQrEnabled = true;

      if (_cachedWifiSecXml != null) {
        final wRoot = _cachedWifiSecXml!.rootElement;
        final secSsid = uniDecode(_findText(wRoot, 'ssid'));
        if (secSsid.isNotEmpty) ssid = secSsid;
        isHiddenSsid = _findText(wRoot, 'ssid_bcast') == '0';
        lcdQrEnabled = _findText(wRoot, 'jm_lcd_hide_qr_code') == '0';
        final m = _findText(wRoot, 'mode');
        if (m.isNotEmpty && m != 'AES-CCMP' && m != 'TKIP') {
          secMode = m;
        }
        for (final tag in [
          secMode,
          'WPA2-PSK',
          'Mixed',
          'WPA2-WPA3',
          'WPA-PSK'
        ]) {
          final blocks = wRoot.findAllElements(tag);
          if (blocks.isNotEmpty) {
            final k = _findText(blocks.first, 'key');
            final c = _findText(blocks.first, 'mode');
            if (k.isNotEmpty) {
              wifiPassword = k;
              if (c.isNotEmpty) cipherMode = c;
              break;
            }
          }
        }
      }

      // Connected Devices
      final devices = <ConnectedDevice>[];
      if (_cachedDevicesXml != null) {
        int idx = 0;
        for (final item
            in _cachedDevicesXml!.rootElement.findAllElements('Item')) {
          String rawName = _findText(item, 'name');
          try {
            rawName = Uri.decodeComponent(rawName);
          } catch (_) {}
          if (rawName.isEmpty || rawName == 'unkown_marvell') {
            rawName = 'جهاز متصل ${idx + 1}';
          }
          final ip = _findText(item, 'ip_address');
          final mac = _findText(item, 'mac');
          final blocked = _findText(item, 'blocked') == '1';
          final connected = _findText(item, 'connected') == '1';
          final connType = _findText(item, 'conn_type');
          final nameType = _findText(item, 'name_type');
          final connTimeRaw = _findText(item, 'conn_time');
          String durationFormatted = '';
          if (connTimeRaw.contains(',')) {
            final parts = connTimeRaw.split(',');
            if (parts.length >= 3) {
              durationFormatted =
                  '${parts[0].padLeft(2, '0')}:${parts[1].padLeft(2, '0')}:${parts[2].padLeft(2, '0')}';
            }
          }
          if (mac.isNotEmpty && (connected || blocked)) {
            devices.add(
              ConnectedDevice(
                index: idx,
                name: rawName,
                ipAddress: ip.isEmpty ? '--' : ip,
                macAddress: mac,
                connectionType: connType.isEmpty ? 'Wi-Fi' : connType,
                connectedDuration: durationFormatted,
                isBlocked: blocked,
                isConnected: connected,
                isCurrentDevice: ip.isNotEmpty && ip == localClientIp,
                rawNameType: nameType.isEmpty ? '1' : nameType,
              ),
            );
          }
          idx++;
        }
      }
      final activeCount =
          devices.where((d) => d.isConnected && !d.isBlocked).length;
      if (activeCount > 0) connCount = activeCount;

      // Band Lock Settings
      bool isManualBand = false;
      String networkMode = 'auto';
      List<String> selectedBands = [];
      List<String> supportedBands = [
        'B3',
        'B28',
        'B1',
        'B5',
        'B7',
        'B8',
        'B20',
        'B38',
        'B40',
        'B41'
      ];
      final wanSource = _cachedWanXml?.rootElement ?? root;
      final nwMode = _findText(wanSource, 'NW_mode');
      if (nwMode == '2') {
        networkMode = '4g_only';
      } else if (nwMode == '1') {
        networkMode = '3g_only';
      } else {
        networkMode = 'auto';
      }
      final freqSel = _findText(wanSource, 'freqselete');
      isManualBand = freqSel == '2';

      final defList = _findText(wanSource, 'nettype_default_list');
      if (defList.isNotEmpty) {
        final parsedSupported = <String>[];
        for (final token in defList.split(',')) {
          final t = token.trim().toLowerCase();
          if (t.startsWith('4g')) {
            parsedSupported.add('B${t.substring(2)}');
          }
        }
        if (parsedSupported.isNotEmpty) supportedBands = parsedSupported;
      }

      final netTypeSel = _findText(wanSource, 'nettype');
      if (netTypeSel.isNotEmpty && netTypeSel != 'auto') {
        for (final token in netTypeSel.split(',')) {
          final t = token.trim().toLowerCase();
          if (t.startsWith('4g')) {
            selectedBands.add('B${t.substring(2)}');
          }
        }
      }

      // Speed Limit
      bool speedLimitEnabled = false;
      int dlLimit = 10;
      int ulLimit = 5;
      if (_cachedSpeedXml != null) {
        final sRoot = _cachedSpeedXml!.rootElement;
        speedLimitEnabled = _findText(sRoot, 'jm_speed_limit_mode') == '1';
        dlLimit = _parseInt(_findText(sRoot, 'jm_download_speed_limit'), 10);
        ulLimit = _parseInt(_findText(sRoot, 'jm_upload_speed_limit'), 5);
      }

      // Admin Credentials
      String adminUser = _username;
      String adminPass = _password;
      if (_cachedAdminXml != null) {
        final aRoot = _cachedAdminXml!.rootElement;
        final ru = _findText(aRoot, 'router_username');
        final rp = _findText(aRoot, 'router_password');
        if (ru.isNotEmpty) {
          try {
            adminUser = Uri.decodeComponent(ru);
          } catch (_) {
            adminUser = ru;
          }
        }
        if (rp.isNotEmpty) {
          try {
            adminPass = Uri.decodeComponent(rp);
          } catch (_) {
            adminPass = rp;
          }
        }
      }

      return ModemStatus(
        hasBattery: hasBat,
        batteryPercent: batteryPct,
        isCharging: isCharging,
        rxBytes: rxBytes,
        txBytes: txBytes,
        totalBytes: totalBytes,
        rxRateBps: rxRate,
        txRateBps: txRate,
        uptimeSeconds: uptimeSec,
        networkType: netType,
        operatorName: operatorName,
        signalBars: signalBars,
        signalPercent: signalPct,
        band: formattedBand,
        rsrp: rsrpDbm != null ? '$rsrpDbm dBm' : '-',
        rsrq: rsrqDisplay,
        sinr: sinrStr.isEmpty
            ? '-'
            : (sinrStr.contains('dB') ? sinrStr : '$sinrStr dB'),
        rssi: rssiDisplay,
        pci: pciStr.isEmpty ? '-' : pciStr,
        cellId: cellIdStr.isEmpty ? '-' : cellIdStr,
        wanConnected: wanConnected,
        modemPhoneNumber: modemNumber,
        deviceModel: modelName,
        wanIp: wanIp.isEmpty ? '-' : wanIp,
        lanIp: lanIp,
        macAddress: macAddr.isEmpty ? '-' : macAddr,
        imei: imei.isEmpty ? '-' : imei,
        iccid: iccid.isEmpty ? '-' : iccid,
        imsi: imsi.isEmpty ? '-' : imsi,
        softwareVersion: swVer.isEmpty ? '-' : swVer,
        hardwareVersion: hwVer.isEmpty ? '-' : hwVer,
        ssid: ssid.isEmpty ? 'Yemen4G' : ssid,
        wifiPassword: wifiPassword,
        isHiddenSsid: isHiddenSsid,
        securityMode: secMode,
        cipherMode: cipherMode,
        maxClients: maxClients,
        connectedDevicesCount: connCount,
        lcdQrEnabled: lcdQrEnabled,
        isManualBand: isManualBand,
        networkMode: networkMode,
        selectedBands: selectedBands,
        supportedBands: supportedBands,
        speedLimitEnabled: speedLimitEnabled,
        downloadLimitMbps: dlLimit,
        uploadLimitMbps: ulLimit,
        adminUsername: adminUser,
        adminPassword: adminPass,
        devices: devices,
        capabilities: ModemCapabilities(
          hasBattery: hasBat,
          hasSignalMetrics: true,
          hasBandLock: true,
          hasSpeedLimit: _cachedSpeedXml != null,
          hasWifiEdit: true,
          hasMaxClients: true,
          hasHideSsid: true,
          hasLcdQrToggle: true,
          hasDeviceBlock: true,
          hasDeviceRename: true,
          hasReboot: true,
          hasPowerOff: true,
          hasAdminPassword: true,
          hasSms: true,
        ),
      );
    });
  }

  @override
  Future<bool> updateWifi({
    required String ssid,
    required String password,
    required bool hideSsid,
    required int maxClients,
  }) async {
    String mode = 'WPA2-PSK';
    String cipher = 'AES-CCMP';
    if (_cachedWifiSecXml != null) {
      final m = _findText(_cachedWifiSecXml!.rootElement, 'mode');
      if (m == 'Mixed' ||
          m == 'WPA2-PSK' ||
          m == 'WPA2-WPA3' ||
          m == 'WPA3-SAE') {
        mode = m;
      }
      final block = _cachedWifiSecXml!.rootElement.findAllElements(mode);
      if (block.isNotEmpty) {
        final c = _findText(block.first, 'mode');
        if (c.isNotEmpty) cipher = c;
      }
    }

    final encodedSsid = uniEncode(ssid);
    final bcast = hideSsid ? '0' : '1';
    final escapedKey = const HtmlEscape().convert(password);

    final secXml = '<wlan_security>'
        '<ssid>$encodedSsid</ssid>'
        '<ssid_bcast>$bcast</ssid_bcast>'
        '<mode>$mode</mode>'
        '<$mode><key>$escapedKey</key><mode>$cipher</mode></$mode>'
        '</wlan_security>';

    final okSec = await _postXml('uapxb_wlan_security_settings', secXml);

    final basicXml =
        '<wlan_settings><max_clients>$maxClients</max_clients></wlan_settings>';
    await _postXml('uapxb_wlan_basic_settings', basicXml);

    _cachedWifiSecXml = null;
    return okSec;
  }

  @override
  Future<bool> setBandConfig({
    required bool manualMode,
    required String networkMode,
    required List<String> bands,
  }) async {
    String nwModeVal = '3';
    if (networkMode == '4g_only') nwModeVal = '2';
    if (networkMode == '3g_only') nwModeVal = '1';

    final freqVal = manualMode ? '2' : '1';
    String netTypeVal = 'auto';
    if (manualMode && bands.isNotEmpty) {
      netTypeVal = bands
          .map((b) => '4g${b.toUpperCase().replaceAll('B', '').trim()}')
          .join(',');
    }

    final xml = '<wan><cellular>'
        '<NW_mode>$nwModeVal</NW_mode>'
        '<freqselete>$freqVal</freqselete>'
        '<nettype>$netTypeVal</nettype>'
        '<prefer_mode>4</prefer_mode>'
        '</cellular></wan>';

    final ok = await _postXml('wan', xml);
    _cachedWanXml = null;
    return ok;
  }

  @override
  Future<bool> setSpeedLimit({
    required bool enabled,
    required int downloadMbps,
    required int uploadMbps,
  }) async {
    final dl = downloadMbps.clamp(1, 150);
    final ul = uploadMbps.clamp(1, 50);
    final xml = enabled
        ? '<jm_custom>'
            '<jm_speed_limit_mode>1</jm_speed_limit_mode>'
            '<jm_upload_speed_limit>$ul</jm_upload_speed_limit>'
            '<jm_download_speed_limit>$dl</jm_download_speed_limit>'
            '</jm_custom>'
        : '<jm_custom><jm_speed_limit_mode>0</jm_speed_limit_mode></jm_custom>';
    final ok = await _postXml('jm_custom', xml);
    _cachedSpeedXml = null;
    return ok;
  }

  @override
  Future<bool> setDeviceBlock({
    required ConnectedDevice device,
    required bool block,
  }) async {
    final encodedName = Uri.encodeComponent(device.name);
    final xml = '<device_management><known_devices_list>'
        '<Item index="0">'
        '<blocked>${block ? 1 : 0}</blocked>'
        '<mac>${device.macAddress}</mac>'
        '<name>$encodedName</name>'
        '<name_type>${device.rawNameType}</name_type>'
        '<con_type>${device.connectionType}</con_type>'
        '</Item>'
        '</known_devices_list></device_management>';
    final ok = await _postXml('device_management_all', xml);
    _cachedDevicesXml = null;
    return ok;
  }

  @override
  Future<bool> renameDevice({
    required ConnectedDevice device,
    required String newName,
  }) async {
    final encodedName = Uri.encodeComponent(newName.trim());
    final xml = '<device_management><known_devices_list>'
        '<Item index="0">'
        '<blocked>${device.isBlocked ? 1 : 0}</blocked>'
        '<mac>${device.macAddress}</mac>'
        '<name>$encodedName</name>'
        '<name_type>2</name_type>'
        '<con_type>${device.connectionType}</con_type>'
        '</Item>'
        '</known_devices_list></device_management>';
    final ok = await _postXml('device_management_all', xml);
    _cachedDevicesXml = null;
    return ok;
  }

  @override
  Future<bool> setLcdQrCode(bool visibleOnModemScreen) async {
    final val = visibleOnModemScreen ? '0' : '1';
    final xml =
        '<wlan_security><jm_lcd_hide_qr_code>$val</jm_lcd_hide_qr_code></wlan_security>';
    final ok = await _postXml('uapxb_wlan_security_settings', xml);
    _cachedWifiSecXml = null;
    return ok;
  }

  @override
  Future<bool> changeAdminPassword(String newPassword) async {
    final encUser = Uri.encodeComponent(_username);
    final encPass = Uri.encodeComponent(newPassword);
    final xml = '<management>'
        '<router_username>$encUser</router_username>'
        '<router_password>$encPass</router_password>'
        '</management>';
    final ok = await _postXml('admin', xml);
    if (ok) {
      _password = newPassword;
      _cachedAdminXml = null;
    }
    return ok;
  }

  @override
  Future<bool> rebootModem() async {
    final doc = await _getXml('reset');
    return doc != null;
  }

  @override
  Future<bool> powerOffModem() async {
    final doc = await _getXml('power_off');
    return doc != null;
  }

  @override
  Future<List<SmsMessage>> fetchSmsInbox() async {
    final doc = await _getXml('message');
    if (doc == null) return [];
    final list = <SmsMessage>[];
    int idx = 0;
    for (final item in doc.rootElement.findAllElements('Item')) {
      final from = uniDecode(_findText(item, 'from'));
      final subject = uniDecode(_findText(item, 'subject'));
      final received = _findText(item, 'received');
      final status = _findText(item, 'status');
      final id =
          _findText(item, 'index').isEmpty ? '$idx' : _findText(item, 'index');
      if (from.isNotEmpty || subject.isNotEmpty) {
        list.add(
          SmsMessage(
            id: id,
            sender: from.isEmpty ? 'Yemen 4G' : from,
            content: subject,
            timestamp: received,
            isUnread: status == '0',
          ),
        );
      }
      idx++;
    }
    return list;
  }
}
