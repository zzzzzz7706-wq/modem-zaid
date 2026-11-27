import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:xml/xml.dart';
import '../../models/modem_models.dart';
import '../modem_detector.dart';
import 'modem_adapter.dart';
import 'notion_mifi_adapter.dart';

class _UapxcHttpRes {
  final int statusCode;
  final Map<String, String> headers;
  final String body;
  final String wire;

  const _UapxcHttpRes({
    required this.statusCode,
    required this.headers,
    required this.body,
    required this.wire,
  });
}

/// Hardware-verified adapter for PTC Yemen 4G CPE (`4G YEMEN` — `4G CPE`)
/// running Lintron / Marvell UAPXC (`lighttpd/1.4.35`, `PostXml` RPC via
/// `POST /xml_action.cgi?method=set` with `<RGW><param><method>call</method>...`).
class MarvellUapxcAdapter implements ModemAdapter {
  @override
  final String gatewayIp;

  @override
  final String localClientIp;

  final String detectedModelHint;

  String _username = 'admin';
  String _password = 'admin';
  String _realm = 'Highwmg';
  String _nonce = '1000';
  String _qop = 'auth';
  String _cookie = '';
  int _gnCount = 1;

  Future<void> _mutex = Future.value();
  int _pollTick = 0;

  XmlDocument? _cachedWifiDoc;
  XmlDocument? _cachedClientsDoc;
  XmlDocument? _cachedMacFilterDoc;
  XmlDocument? _cachedVersionDoc;
  XmlDocument? _cachedIccidDoc;
  XmlDocument? _cachedBandDoc;
  XmlDocument? _cachedSpeedDoc;

  MarvellUapxcAdapter({
    required this.gatewayIp,
    required this.localClientIp,
    this.detectedModelHint = 'Yemen 4G CPE',
  });

  @override
  ModemFamily get family => ModemFamily.marvellUapxc;

  @override
  String get protocolName => 'Yemen 4G CPE (Marvell UAPXC)';

  Future<T> _synchronized<T>(Future<T> Function() task) {
    final completer = Completer<T>();
    _mutex = _mutex.then((_) async {
      try {
        completer.complete(await task());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  static String _md5Hex(String s) =>
      md5.convert(utf8.encode(s)).toString().toLowerCase();

  static String _upperHex8(int v) =>
      v.toRadixString(16).toUpperCase().padLeft(8, '0');

  String _randomCnonce() {
    final rand = Random().nextInt(100001);
    final now = DateTime.now().microsecondsSinceEpoch;
    return _md5Hex('$rand$now').substring(0, 16);
  }

  String _buildAuthHeader(String method) {
    final ha1 = _md5Hex('$_username:$_realm:$_password');
    final ha2 = _md5Hex('$method:/cgi/xml_action.cgi');
    final cnonce = _randomCnonce();
    final nc = _upperHex8(_gnCount++);
    final resp = _md5Hex('$ha1:$_nonce:$nc:$cnonce:$_qop:$ha2');
    return 'Digest username="$_username", realm="$_realm", nonce="$_nonce", '
        'uri="/cgi/xml_action.cgi", response="$resp", qop=$_qop, '
        'nc=$nc, cnonce="$cnonce"';
  }

  static String _dechunk(String input) {
    final out = StringBuffer();
    int pos = 0;
    while (pos < input.length) {
      final rn = input.indexOf('\r\n', pos);
      if (rn == -1) break;
      final hexLen = input.substring(pos, rn).split(';').first.trim();
      final len = int.tryParse(hexLen, radix: 16);
      if (len == null) return input;
      if (len == 0) break;
      final start = rn + 2;
      final end = (start + len).clamp(0, input.length);
      out.write(input.substring(start, end));
      pos = end + 2;
    }
    final s = out.toString();
    return s.isEmpty ? input : s;
  }

  Future<_UapxcHttpRes> _rawRequest(
    String method,
    String pathAndQuery, {
    Map<String, String>? headers,
    String? body,
    Duration timeout = const Duration(seconds: 6),
    bool tolerateDisconnect = false,
  }) async {
    Socket? sock;
    try {
      sock = await ModemDetector.connectLanSocket(
        gatewayIp,
        80,
        localIp: localClientIp,
        timeout: timeout,
      );
      final bodyBytes = body != null ? utf8.encode(body) : const <int>[];
      final req = StringBuffer()
        ..write('$method $pathAndQuery HTTP/1.1\r\n')
        ..write('Host: $gatewayIp\r\n')
        ..write('Connection: close\r\n')
        ..write('Accept: */*\r\n');
      headers?.forEach((k, v) => req.write('$k: $v\r\n'));
      if (bodyBytes.isNotEmpty) {
        req.write('Content-Length: ${bodyBytes.length}\r\n');
      }
      req.write('\r\n');

      sock.add(utf8.encode(req.toString()));
      if (bodyBytes.isNotEmpty) sock.add(bodyBytes);
      await sock.flush();

      final builder = BytesBuilder(copy: false);
      try {
        await sock
            .listen((c) => builder.add(c))
            .asFuture<void>()
            .timeout(timeout, onTimeout: () {});
      } catch (_) {
        if (!tolerateDisconnect && builder.isEmpty) rethrow;
      }
      final bytes = builder.takeBytes();
      if (bytes.isEmpty) {
        return _UapxcHttpRes(
          statusCode: tolerateDisconnect ? 200 : 0,
          headers: const {},
          body: '',
          wire: '',
        );
      }

      final wire = utf8.decode(bytes, allowMalformed: true);
      final split = wire.indexOf('\r\n\r\n');
      final headPart = split != -1 ? wire.substring(0, split) : wire;
      var bodyPart = split != -1 ? wire.substring(split + 4) : '';

      final lines = headPart.split('\r\n');
      int code = 200;
      if (lines.isNotEmpty) {
        final m = RegExp(r'HTTP/\d\.\d\s+(\d{3})').firstMatch(lines.first);
        if (m != null) code = int.tryParse(m.group(1)!) ?? 200;
      }
      final hdrs = <String, String>{};
      for (int i = 1; i < lines.length; i++) {
        final idx = lines[i].indexOf(':');
        if (idx > 0) {
          hdrs[lines[i].substring(0, idx).trim().toLowerCase()] =
              lines[i].substring(idx + 1).trim();
        }
      }
      if ((hdrs['transfer-encoding'] ?? '').toLowerCase().contains('chunked')) {
        bodyPart = _dechunk(bodyPart);
      }
      return _UapxcHttpRes(
        statusCode: code,
        headers: hdrs,
        body: bodyPart,
        wire: wire,
      );
    } finally {
      try {
        sock?.destroy();
      } catch (_) {}
    }
  }

  Future<LoginOutcome> _attemptLoginUnlocked(
      String username, String password) async {
    _username = username.trim().isEmpty ? 'admin' : username.trim();
    _password = password;
    _gnCount = 1;

    try {
      final ch = await _rawRequest(
        'GET',
        '/login.cgi',
        headers: const {
          'Expires': '-1',
          'Cache-Control': 'no-store, no-cache, must-revalidate',
          'Pragma': 'no-cache',
        },
      );
      if (ch.statusCode == 0) {
        return LoginOutcome(
          success: false,
          wrongCredentials: false,
          message: 'تعذر الوصول إلى المودم ($gatewayIp) عبر الواي فاي.',
        );
      }
      final sc = ch.headers['set-cookie'];
      if (sc != null && sc.isNotEmpty) _cookie = sc.split(';').first;

      final www = ch.headers['www-authenticate'] ?? '';
      for (final m in RegExp(r'(\w+)\s*=\s*"?([^",\s]+)"?').allMatches(www)) {
        final k = m.group(1)?.toLowerCase();
        final v = m.group(2) ?? '';
        if (k == 'realm') _realm = v;
        if (k == 'nonce') _nonce = v;
        if (k == 'qop') _qop = v;
      }

      // Exact UAPXC doLogin formula from js/base/utils.js:
      // HA2 = hex_md5("GET:/cgi/xml_action.cgi") and &nc=00000001&temp=marvell
      final ha1 = _md5Hex('$_username:$_realm:$_password');
      final ha2 = _md5Hex('GET:/cgi/xml_action.cgi');
      final cnonce = _randomCnonce();
      const nc = '00000001';
      final digestRes = _md5Hex('$ha1:$_nonce:$nc:$cnonce:$_qop:$ha2');

      _gnCount = 1;
      final loginUrl = '/login.cgi?Action=Digest'
          '&username=${Uri.encodeComponent(_username)}'
          '&realm=${Uri.encodeComponent(_realm)}'
          '&nonce=${Uri.encodeComponent(_nonce)}'
          '&response=$digestRes'
          '&qop=${Uri.encodeComponent(_qop)}'
          '&cnonce=$cnonce'
          '&nc=$nc'
          '&temp=marvell';

      final authRes = await _rawRequest(
        'GET',
        loginUrl,
        headers: {
          'Authorization': _buildAuthHeader('GET'),
          'Expires': '-1',
          'Cache-Control': 'no-store, no-cache, must-revalidate',
          'Pragma': 'no-cache',
          if (_cookie.isNotEmpty) 'Cookie': _cookie,
        },
      );
      final sc2 = authRes.headers['set-cookie'];
      if (sc2 != null && sc2.isNotEmpty) _cookie = sc2.split(';').first;

      if (authRes.statusCode == 401 ||
          authRes.statusCode == 500 ||
          (!authRes.body.contains('200 OK') &&
              authRes.body.trim().isNotEmpty &&
              authRes.body.toLowerCase().contains('fail'))) {
        return const LoginOutcome(
          success: false,
          wrongCredentials: true,
          message: 'اسم المستخدم أو كلمة المرور غير صحيحة.',
        );
      }

      // Verify live RPC session using PostXml("sim", "get_sim_status")
      final testDoc =
          await _postRpcUnlocked('sim', 'get_sim_status', allowRelogin: false);
      if (testDoc != null) {
        return const LoginOutcome(success: true);
      }
      return const LoginOutcome(
        success: false,
        wrongCredentials: true,
        message: 'اسم المستخدم أو كلمة المرور غير صحيحة.',
      );
    } on SocketException {
      return LoginOutcome(
        success: false,
        wrongCredentials: false,
        message: 'انقطع الاتصال بالمودم ($gatewayIp) — تأكد من اتصال الواي فاي.',
      );
    } catch (_) {
      return LoginOutcome(
        success: false,
        wrongCredentials: false,
        message: 'تعذر إكمال تسجيل الدخول إلى المودم ($gatewayIp).',
      );
    }
  }

  @override
  Future<LoginOutcome> loginWithOutcome(String username, String password) {
    return _synchronized(() async {
      final first = await _attemptLoginUnlocked(username, password);
      if (first.success) return first;
      if (first.wrongCredentials &&
          password != password.trim() &&
          password.trim().isNotEmpty) {
        final retry = await _attemptLoginUnlocked(username, password.trim());
        if (retry.success) return retry;
      }
      return first;
    });
  }

  @override
  Future<void> logout() {
    return _synchronized(() async {
      try {
        await _rawRequest('GET', '/xml_action.cgi?Action=logout',
            timeout: const Duration(seconds: 2));
      } catch (_) {}
    });
  }

  static String _escapeXml(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  static String _findTag(XmlDocument? doc, String tag) {
    if (doc == null) return '';
    final els = doc.findAllElements(tag);
    if (els.isEmpty) return '';
    return els.first.innerText.trim();
  }

  static String _findInElement(XmlElement? el, String tag) {
    if (el == null) return '';
    final els = el.findAllElements(tag);
    if (els.isEmpty) return '';
    return els.first.innerText.trim();
  }

  static int _toInt(String s, [int fallback = 0]) {
    if (s.isEmpty) return fallback;
    return int.tryParse(s.replaceAll(RegExp(r'[^0-9\-]'), '')) ?? fallback;
  }

  /// Executes UAPXC `PostXml(objPath, objMethod, innerXml)` via `POST /xml_action.cgi?method=set`.
  Future<XmlDocument?> _postRpcUnlocked(
    String objPath,
    String objMethod, {
    String extraRgwXml = '',
    bool allowRelogin = true,
    bool tolerateDisconnect = false,
  }) async {
    try {
      final xmlPayload = '<?xml version="1.0" encoding="US-ASCII"?> '
          '<RGW><param>'
          '<method>call</method>'
          '<session>000</session>'
          '<obj_path>$objPath</obj_path>'
          '<obj_method>$objMethod</obj_method>'
          '</param>$extraRgwXml</RGW>';

      final res = await _rawRequest(
        'POST',
        '/xml_action.cgi?method=set',
        headers: {
          'Authorization': _buildAuthHeader('POST'),
          'Content-Type': 'application/xml; charset=UTF-8',
          if (_cookie.isNotEmpty) 'Cookie': _cookie,
        },
        body: xmlPayload,
        tolerateDisconnect: tolerateDisconnect,
      );

      if (tolerateDisconnect && res.body.trim().isEmpty) {
        return XmlDocument.parse('<RGW><setting_response>OK</setting_response></RGW>');
      }

      if ((res.statusCode == 401 || res.statusCode == 500) && allowRelogin) {
        final relog = await _attemptLoginUnlocked(_username, _password);
        if (relog.success) {
          return _postRpcUnlocked(
            objPath,
            objMethod,
            extraRgwXml: extraRgwXml,
            allowRelogin: false,
            tolerateDisconnect: tolerateDisconnect,
          );
        }
        return null;
      }

      var text = res.body.trim();
      final xmlIdx = text.indexOf('<?xml');
      final rgwIdx = text.indexOf('<RGW');
      if (xmlIdx > 0) {
        text = text.substring(xmlIdx);
      } else if (rgwIdx > 0) {
        text = text.substring(rgwIdx);
      }
      if (text.isEmpty) return null;

      final doc = XmlDocument.parse(text);
      final errCause = _findTag(doc, 'error_cause');
      if (errCause == '5') {
        if (allowRelogin) {
          final relog = await _attemptLoginUnlocked(_username, _password);
          if (relog.success) {
            return _postRpcUnlocked(
              objPath,
              objMethod,
              extraRgwXml: extraRgwXml,
              allowRelogin: false,
              tolerateDisconnect: tolerateDisconnect,
            );
          }
        }
        return null;
      }
      return doc;
    } catch (_) {
      return null;
    }
  }

  static String _formatSecs(String rawSecs) {
    final s = int.tryParse(rawSecs.trim()) ?? 0;
    if (s <= 0) return '';
    final h = (s ~/ 3600).toString().padLeft(2, '0');
    final m = ((s % 3600) ~/ 60).toString().padLeft(2, '0');
    final sec = (s % 60).toString().padLeft(2, '0');
    return '$h:$m:$sec';
  }

  static List<String> _decodeBands(int fddMask, int tddMask) {
    final bands = <String>[];
    const fddBits = {
      1: 1,
      3: 4,
      5: 16,
      7: 64,
      8: 128,
      20: 524288,
      28: 134217728,
    };
    const tddBits = {
      38: 32,
      40: 128,
      41: 256,
    };
    fddBits.forEach((b, mask) {
      if ((fddMask & mask) != 0) bands.add('B$b');
    });
    tddBits.forEach((b, mask) {
      if ((tddMask & mask) != 0) bands.add('B$b');
    });
    return bands;
  }

  @override
  Future<ModemStatus> fetchStatus({bool forceFullRefresh = false}) {
    return _synchronized(() async {
      final linkDoc = await _postRpcUnlocked('cm', 'get_link_context');
      if (linkDoc == null) {
        throw SocketException('انقطع الاتصال بالمودم ($gatewayIp)');
      }
      final engDoc = await _postRpcUnlocked('cm', 'get_eng_info');
      final trafDoc = await _postRpcUnlocked('statistics', 'stat_get_common_data');
      final runDoc = await _postRpcUnlocked('router', 'get_router_runtime');
      final batDoc = await _postRpcUnlocked('aoc', 'get_chg_info');

      final refreshSecondary = forceFullRefresh ||
          _cachedWifiDoc == null ||
          _cachedClientsDoc == null ||
          (_pollTick % 2 == 0);
      _pollTick++;

      if (refreshSecondary) {
        _cachedWifiDoc = await _postRpcUnlocked('wireless', 'wifi_get_detail');
        _cachedClientsDoc =
            await _postRpcUnlocked('statistics', 'get_all_clients_info');
        _cachedMacFilterDoc =
            await _postRpcUnlocked('wireless', 'wifi_get_mac_filter');
      }
      if (forceFullRefresh || _cachedVersionDoc == null) {
        _cachedVersionDoc = await _postRpcUnlocked('version', 'get_version');
        _cachedIccidDoc = await _postRpcUnlocked('cm', 'get_iccid');
        _cachedBandDoc = await _postRpcUnlocked('cm', 'get_band');
        _cachedSpeedDoc = await _postRpcUnlocked('cm', 'get_tpt_limit_value');
      }

      // 1. Battery (CPE units without battery return error_cause=3 or bat_online=0)
      final batErr = _findTag(batDoc, 'error_cause');
      final batOnline = _findTag(batDoc, 'bat_online');
      final batPresent = _findTag(batDoc, 'present');
      final hasBattery = batDoc != null &&
          batErr != '3' &&
          (batOnline == '1' || batPresent == '1');
      final batPct = hasBattery
          ? _toInt(_findTag(batDoc, 'capacity'), 0).clamp(0, 100)
          : 0;
      final isCharging = hasBattery &&
          (_findTag(batDoc, 'bat_status') == '1' ||
              _findTag(batDoc, 'power_source') == '1');

      // 2. Traffic & Runtime
      final rxBytes = _toInt(_findTag(trafDoc, 'total_rx_bytes'));
      final txBytes = _toInt(_findTag(trafDoc, 'total_tx_bytes'));
      final rxRate = _toInt(_findTag(trafDoc, 'rx_byte_per_sec')) * 8;
      final txRate = _toInt(_findTag(trafDoc, 'tx_byte_per_sec')) * 8;

      final days = _toInt(_findTag(runDoc, 'run_days'));
      final hours = _toInt(_findTag(runDoc, 'run_hours'));
      final mins = _toInt(_findTag(runDoc, 'run_min'));
      final secs = _toInt(_findTag(runDoc, 'run_sec'));
      final uptimeSeconds = days * 86400 + hours * 3600 + mins * 60 + secs;

      // 3. Cellular & Signal (exact formulas from js/panel/internet/eng_infor.js)
      final imei = _findTag(linkDoc, 'IMEI');
      final imsi = _findTag(linkDoc, 'IMSI');
      final iccid = _findTag(_cachedIccidDoc, 'ICCID');
      var opName = _findTag(linkDoc, 'roaming') == '1'
          ? _findTag(linkDoc, 'roaming_network_name')
          : _findTag(linkDoc, 'network_name');
      if (imsi.startsWith('42110') ||
          opName.contains('42110') ||
          opName.contains('中国电信') ||
          opName.toLowerCase().contains('yemen')) {
        opName = 'يمن فورجي (Yemen 4G)';
      }

      final sysMode = _findTag(linkDoc, 'sys_mode');
      final netType = switch (sysMode) {
        '3' => '4G+',
        '2' => '4G LTE',
        '1' => '3G',
        _ => '',
      };

      String bandStr = '';
      String rsrpStr = '-';
      String rsrqStr = '-';
      String sinrStr = '-';
      String rssiStr = '-';
      String pciStr = '-';
      String cellIdStr = '-';
      int sigBars = 0;
      int sigPct = 0;

      if (_findTag(engDoc, 'response_status') == 'OK') {
        final rawBand = _findTag(engDoc, 'band');
        if (rawBand.isNotEmpty && rawBand != '0') {
          bandStr = rawBand.toUpperCase().startsWith('B')
              ? rawBand.toUpperCase()
              : 'B$rawBand';
        }
        final pci = _findTag(engDoc, 'phy_cell_id');
        if (pci.isNotEmpty) pciStr = pci;
        final cid = _findTag(engDoc, 'cell_id');
        if (cid.isNotEmpty) cellIdStr = cid;

        final mainRsrp = int.tryParse(_findTag(engDoc, 'main_rsrp'));
        if (mainRsrp != null && mainRsrp != 255) {
          final dbm = mainRsrp > 0 ? (mainRsrp - 141) : mainRsrp;
          rsrpStr = '$dbm dBm';
          sigPct = (((dbm + 122) / 47.0) * 100).round().clamp(5, 100);
          sigBars = ((sigPct / 20).ceil()).clamp(1, 5);
        }
        final mainRsrq = int.tryParse(_findTag(engDoc, 'main_rsrq'));
        if (mainRsrq != null && mainRsrq != 255) {
          final db = mainRsrq > 0 ? ((mainRsrq - 40) / 2.0) : mainRsrq.toDouble();
          rsrqStr = '${db.toStringAsFixed(1)} dB';
        }
        final sinrRaw = _findTag(engDoc, 'sinr');
        if (sinrRaw.isNotEmpty && sinrRaw != '255') {
          sinrStr = '$sinrRaw dB';
        }
        final rssiIdx = int.tryParse(_findTag(engDoc, 'rssi'));
        if (rssiIdx != null && rssiIdx != 99) {
          final rDbm = rssiIdx > 0 ? (rssiIdx - 128) : rssiIdx;
          rssiStr = '$rDbm dBm';
        }
      }

      if (sigBars == 0 && (sysMode == '2' || sysMode == '3')) {
        // Fallback to link_context rssi index per dashboard.js lines 698-707
        final rIdx = _toInt(_findTag(linkDoc, 'rssi'), 0);
        if (rIdx >= 55) {
          sigBars = 4;
          sigPct = 90;
        } else if (rIdx >= 43) {
          sigBars = 3;
          sigPct = 72;
        } else if (rIdx >= 34) {
          sigBars = 2;
          sigPct = 50;
        } else if (rIdx >= 25) {
          sigBars = 1;
          sigPct = 28;
        }
      }

      final wanConnected = _findTag(linkDoc, 'connection_status') == '1';
      final wanIp = _findTag(linkDoc, 'ipv4_ip');

      final modemNumber = ModemStatus.extractFirstValidNumber(
        [
          _findTag(linkDoc, 'MSISDN'),
          _findTag(linkDoc, 'msisdn'),
          _findTag(linkDoc, 'mdn'),
          _findTag(linkDoc, 'phone_number'),
          _findTag(linkDoc, 'number'),
        ],
        imei: imei,
        iccid: iccid,
        imsi: imsi,
      );

      // 4. Wi-Fi Details
      String ssid = '';
      String wifiKey = '';
      bool hidden = false;
      int maxClients = 10;
      String encMode = 'WPA2-PSK';
      final wifi24Els = _cachedWifiDoc?.findAllElements('wifi_if_24G') ?? const [];
      if (wifi24Els.isNotEmpty) {
        final w24 = wifi24Els.first;
        final ssid0Els = w24.findAllElements('ssid0');
        final src = ssid0Els.isNotEmpty ? ssid0Els.first : w24;
        ssid = _findInElement(src, 'ssid');
        wifiKey = _findInElement(src, 'key');
        hidden = _findInElement(src, 'hidden') == '1';
        maxClients = _toInt(_findInElement(src, 'maxassoc'), 10);
        final rawEnc = _findInElement(src, 'encryption');
        if (rawEnc.contains('psk2')) {
          encMode = 'WPA2-PSK';
        } else if (rawEnc.contains('mixed')) {
          encMode = 'WPA/WPA2-MIXED';
        } else if (rawEnc.contains('psk')) {
          encMode = 'WPA-PSK';
        } else if (rawEnc == 'none') {
          encMode = 'OPEN';
        }
      }

      // 5. Connected, Historical & Blocked Devices
      final blockedSet = <String>{};
      final ap0Els = _cachedMacFilterDoc?.findAllElements('AP0') ?? const [];
      if (ap0Els.isNotEmpty) {
        final mode = _findInElement(ap0Els.first, 'macfilter');
        if (mode == 'deny') {
          final denyRaw = _findInElement(ap0Els.first, 'maclist_deny');
          for (final part in denyRaw.split(RegExp(r'[\s,]+'))) {
            final m = part.trim().toUpperCase();
            if (m.length >= 11) blockedSet.add(m);
          }
        }
      }

      final devices = <ConnectedDevice>[];
      String currentMac = '';
      final seenMacs = <String>{};
      int idx = 0;
      for (final item
          in _cachedClientsDoc?.findAllElements('one_client') ?? const <XmlElement>[]) {
        var name = _findInElement(item, 'name');
        try {
          name = Uri.decodeComponent(name);
        } catch (_) {}
        if (name.trim().isEmpty || name == 'unkown_marvell') name = 'جهاز متصل';
        final st = _findInElement(item, 'status'); // conn | dis_conn | block
        final typeRaw = _findInElement(item, 'type').toUpperCase();
        final ip = _findInElement(item, 'ip');
        final mac = _findInElement(item, 'mac').toUpperCase();
        if (mac.isEmpty) continue;
        seenMacs.add(mac);

        final isBlocked = st == 'block' || blockedSet.contains(mac);
        if (isBlocked) blockedSet.add(mac);
        final isOnline = st == 'conn';
        final isCurrent = ip.isNotEmpty && ip == localClientIp;
        if (isCurrent) currentMac = mac;

        devices.add(
          ConnectedDevice(
            index: idx++,
            name: name,
            ipAddress: ip.isEmpty ? '-' : ip,
            macAddress: mac,
            connectionType: typeRaw == 'USB' ? 'USB' : 'Wi-Fi',
            connectedDuration: _formatSecs(_findInElement(item, 'cur_conn_time')),
            isBlocked: isBlocked,
            isCurrentDevice: isCurrent,
            isConnected: isOnline,
            rxBytes: _toInt(_findInElement(item, 'total_rx_bytes')),
            txBytes: _toInt(_findInElement(item, 'total_tx_bytes')),
          ),
        );
      }

      for (final bMac in blockedSet) {
        if (!seenMacs.contains(bMac)) {
          devices.add(
            ConnectedDevice(
              index: idx++,
              name: 'جهاز محظور',
              ipAddress: '-',
              macAddress: bMac,
              isBlocked: true,
              isConnected: false,
            ),
          );
        }
      }

      final onlineCount = devices.where((d) => d.isConnected && !d.isBlocked).length;

      // 6. Band Lock & Speed Limit
      final bandMode = _findTag(_cachedBandDoc, 'bandmode');
      final fddMask = _toInt(_findTag(_cachedBandDoc, 'manual_fdd_band'));
      final tddMask = _toInt(_findTag(_cachedBandDoc, 'manual_tdd_band'));
      final selectedBands = _decodeBands(fddMask, tddMask);

      final limTime = _toInt(_findTag(_cachedSpeedDoc, 'limit_time'));
      final limRxKbps = _toInt(_findTag(_cachedSpeedDoc, 'limit_rx'));
      final limTxKbps = _toInt(_findTag(_cachedSpeedDoc, 'limit_tx'));
      final speedEnabled = limTime > 0 && limRxKbps > 0;

      final swVer = _findTag(_cachedVersionDoc, 'sw_version');
      final hwVer = _findTag(_cachedVersionDoc, 'hdware_ver');
      final routerMac = _findTag(_cachedVersionDoc, 'mac_addr');

      return ModemStatus(
        hasBattery: hasBattery,
        batteryPercent: batPct,
        isCharging: isCharging,
        rxBytes: rxBytes,
        txBytes: txBytes,
        totalBytes: rxBytes + txBytes,
        rxRateBps: rxRate,
        txRateBps: txRate,
        uptimeSeconds: uptimeSeconds,
        networkType: netType,
        operatorName: opName,
        signalBars: sigBars,
        signalPercent: sigPct,
        band: bandStr,
        rsrp: rsrpStr,
        rsrq: rsrqStr,
        sinr: sinrStr,
        rssi: rssiStr,
        pci: pciStr,
        cellId: cellIdStr,
        wanConnected: wanConnected,
        modemPhoneNumber: modemNumber,
        deviceModel: detectedModelHint,
        wanIp: wanIp.isEmpty ? '-' : wanIp,
        lanIp: gatewayIp,
        macAddress: routerMac.isEmpty ? '-' : routerMac.toUpperCase(),
        currentDeviceMac: currentMac,
        imei: imei.isEmpty ? '-' : imei,
        iccid: iccid.isEmpty ? '-' : iccid,
        imsi: imsi.isEmpty ? '-' : imsi,
        softwareVersion: swVer.isEmpty ? '-' : swVer,
        hardwareVersion: hwVer.isEmpty ? '-' : hwVer,
        ssid: ssid,
        wifiPassword: wifiKey,
        isHiddenSsid: hidden,
        securityMode: encMode,
        maxClients: maxClients,
        connectedDevicesCount: onlineCount,
        isManualBand: bandMode.toLowerCase() == 'manual',
        selectedBands: selectedBands,
        supportedBands: const ['B3', 'B28', 'B1', 'B7', 'B8', 'B20', 'B38', 'B40', 'B41'],
        speedLimitEnabled: speedEnabled,
        downloadLimitMbps: speedEnabled ? (limRxKbps / 1000).round().clamp(1, 150) : 10,
        uploadLimitMbps: speedEnabled ? (limTxKbps / 1000).round().clamp(1, 100) : 5,
        adminUsername: _username,
        adminPassword: _password,
        devices: devices,
        blockedMacs: blockedSet.toList(),
        capabilities: ModemCapabilities(
          hasBattery: hasBattery,
          hasSignalMetrics: true,
          hasBandLock: true,
          hasSpeedLimit: true,
          hasWifiEdit: true,
          hasMaxClients: true,
          hasHideSsid: true,
          hasLcdQrToggle: false,
          hasDeviceBlock: true,
          hasDeviceRename: false,
          hasReboot: true,
          hasPowerOff: true,
          hasAdminPassword: true,
          hasSms: true,
        ),
      );
    });
  }

  Future<bool> _setMacBlockInternal(String macAddress, bool block) {
    return _synchronized(() async {
      final normMac = macAddress.trim().toUpperCase();
      if (normMac.isEmpty) return false;

      // 1. Call statistics block_clients / unblock_clients (connectdevice_traffic.js)
      await _postRpcUnlocked(
        'statistics',
        block ? 'block_clients' : 'unblock_clients',
        extraRgwXml: '<statistics><clients_mac>$normMac</clients_mac></statistics>',
        tolerateDisconnect: true,
      );

      // 2. Also update wireless wifi_set_mac_filter so arbitrary/manual MACs are enforced
      final fltDoc = await _postRpcUnlocked('wireless', 'wifi_get_mac_filter');
      final currentDeny = <String>[];
      final ap0 = fltDoc?.findAllElements('AP0') ?? const [];
      if (ap0.isNotEmpty) {
        final raw = _findInElement(ap0.first, 'maclist_deny');
        for (final p in raw.split(RegExp(r'[\s,]+'))) {
          final m = p.trim().toUpperCase();
          if (m.length >= 11 && !currentDeny.contains(m)) currentDeny.add(m);
        }
      }
      if (block) {
        if (!currentDeny.contains(normMac)) currentDeny.add(normMac);
      } else {
        currentDeny.remove(normMac);
      }

      final newListStr = currentDeny.isEmpty ? '   ' : currentDeny.join(' ');
      final modeStr = currentDeny.isEmpty ? 'disable' : 'deny';
      await _postRpcUnlocked(
        'wireless',
        'wifi_set_mac_filter',
        extraRgwXml: '<wireless>'
            '<wifi_device>0</wifi_device>'
            '<macfilter>$modeStr</macfilter>'
            '<maclist_deny>$newListStr</maclist_deny>'
            '</wireless>',
        tolerateDisconnect: true,
      );

      // 3. Hardware verification after Wi-Fi reload
      for (int i = 0; i < 4; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 1200));
        final checkFlt = await _postRpcUnlocked('wireless', 'wifi_get_mac_filter');
        final checkCli =
            await _postRpcUnlocked('statistics', 'get_all_clients_info');
        if (checkFlt == null && checkCli == null) continue;

        _cachedMacFilterDoc = checkFlt ?? _cachedMacFilterDoc;
        _cachedClientsDoc = checkCli ?? _cachedClientsDoc;

        bool inFilter = false;
        final cAp0 = checkFlt?.findAllElements('AP0') ?? const [];
        if (cAp0.isNotEmpty && _findInElement(cAp0.first, 'macfilter') == 'deny') {
          inFilter = _findInElement(cAp0.first, 'maclist_deny')
              .toUpperCase()
              .contains(normMac);
        }
        bool inClientsBlock = false;
        for (final c
            in checkCli?.findAllElements('one_client') ?? const <XmlElement>[]) {
          if (_findInElement(c, 'mac').toUpperCase() == normMac &&
              _findInElement(c, 'status') == 'block') {
            inClientsBlock = true;
          }
        }
        if (block && (inFilter || inClientsBlock)) return true;
        if (!block && !inFilter && !inClientsBlock) return true;
      }
      return false;
    });
  }

  @override
  Future<bool> blockMacAddress(String macAddress) =>
      _setMacBlockInternal(macAddress, true);

  @override
  Future<bool> unblockMacAddress(String macAddress) =>
      _setMacBlockInternal(macAddress, false);

  @override
  Future<bool> setDeviceBlock({
    required ConnectedDevice device,
    required bool block,
  }) =>
      _setMacBlockInternal(device.macAddress, block);

  @override
  Future<bool> renameDevice({
    required ConnectedDevice device,
    required String newName,
  }) async =>
      false;

  @override
  Future<bool> updateWifi({
    required String ssid,
    required String password,
    required bool hideSsid,
    required int maxClients,
  }) {
    return _synchronized(() async {
      final extra = '<wireless>'
          '<wifi_device>0</wifi_device>'
          '<wifi_if_24G>'
          '<switch>on</switch>'
          '<ssid_index>0</ssid_index>'
          '<ssid>${_escapeXml(ssid)}</ssid>'
          '<hidden>${hideSsid ? 1 : 0}</hidden>'
          '<maxassoc>$maxClients</maxassoc>'
          '${password.isNotEmpty ? '<encryption>psk2+ccmp</encryption><key>${_escapeXml(password)}</key>' : ''}'
          '</wifi_if_24G>'
          '</wireless>';
      final doc = await _postRpcUnlocked(
        'wireless',
        'wifi_set_2.4g',
        extraRgwXml: extra,
        tolerateDisconnect: true,
      );
      _cachedWifiDoc = null;
      return doc != null && _findTag(doc, 'setting_response') != 'ERROR';
    });
  }

  @override
  Future<bool> setBandConfig({
    required bool manualMode,
    required String networkMode,
    required List<String> bands,
  }) {
    return _synchronized(() async {
      if (!manualMode) {
        final doc = await _postRpcUnlocked(
          'cm',
          'set_band',
          extraRgwXml: '<wan><bandmode>Auto</bandmode></wan>',
        );
        _cachedBandDoc = null;
        return doc != null && _findTag(doc, 'setting_response').contains('OK');
      }

      int fdd = 0;
      int tdd = 0;
      const fddMap = {
        'B1': 1,
        'B3': 4,
        'B5': 16,
        'B7': 64,
        'B8': 128,
        'B20': 524288,
        'B28': 134217728,
      };
      const tddMap = {
        'B38': 32,
        'B40': 128,
        'B41': 256,
      };
      for (final b in bands) {
        final key = b.toUpperCase();
        if (fddMap.containsKey(key)) fdd += fddMap[key]!;
        if (tddMap.containsKey(key)) tdd += tddMap[key]!;
      }
      if (fdd == 0 && tdd == 0) return false;

      final doc = await _postRpcUnlocked(
        'cm',
        'set_band',
        extraRgwXml: '<wan>'
            '<bandmode>Manual</bandmode>'
            '<manual_tdd_band>$tdd</manual_tdd_band>'
            '<manual_fdd_band>$fdd</manual_fdd_band>'
            '<manual_umts_band>0</manual_umts_band>'
            '</wan>',
      );
      _cachedBandDoc = await _postRpcUnlocked('cm', 'get_band');
      return doc != null && _findTag(doc, 'setting_response').contains('OK');
    });
  }

  @override
  Future<bool> setSpeedLimit({
    required bool enabled,
    required int downloadMbps,
    required int uploadMbps,
  }) {
    return _synchronized(() async {
      final timeVal = enabled ? 10 : 0;
      final rxKbps = enabled ? downloadMbps * 1000 : 0;
      final txKbps = enabled ? uploadMbps * 1000 : 0;
      final doc = await _postRpcUnlocked(
        'cm',
        'set_tpt_limit_value',
        extraRgwXml: '<wan>'
            '<limit_time>$timeVal</limit_time>'
            '<limit_tx>$txKbps</limit_tx>'
            '<limit_rx>$rxKbps</limit_rx>'
            '</wan>',
      );
      _cachedSpeedDoc = await _postRpcUnlocked('cm', 'get_tpt_limit_value');
      return doc != null && _findTag(doc, 'setting_response').contains('OK');
    });
  }

  @override
  Future<bool> setLcdQrCode(bool visibleOnModemScreen) async => false;

  @override
  Future<bool> changeAdminPassword(String newPassword) {
    return _synchronized(() async {
      final doc = await _postRpcUnlocked(
        'account',
        'set_account',
        extraRgwXml: '<account><user_management>'
            '<action>1</action>'
            '<username>${_escapeXml(_username)}</username>'
            '<password>${_escapeXml(newPassword)}</password>'
            '</user_management></account>',
      );
      final ok = doc != null && _findTag(doc, 'setting_response') != 'ERROR';
      if (ok) _password = newPassword;
      return ok;
    });
  }

  @override
  Future<bool> rebootModem() {
    return _synchronized(() async {
      final doc = await _postRpcUnlocked(
        'router',
        'router_call_reboot',
        tolerateDisconnect: true,
      );
      return doc != null;
    });
  }

  @override
  Future<bool> powerOffModem() {
    return _synchronized(() async {
      final doc = await _postRpcUnlocked(
        'router',
        'router_poweroff',
        tolerateDisconnect: true,
      );
      return doc != null;
    });
  }

  @override
  Future<List<SmsMessage>> fetchSmsInbox() {
    return _synchronized(() async {
      final list = <SmsMessage>[];
      for (final listType in [0, 3]) {
        final doc = await _postRpcUnlocked(
          'sms',
          'sms.list_by_type',
          extraRgwXml: '<sms_info><sms>'
              '<page_index>1</page_index>'
              '<list_type>$listType</list_type>'
              '</sms></sms_info>',
        );
        if (doc == null) continue;
        final count = _toInt(_findTag(doc, 'count'));
        for (int i = 1; i <= count; i++) {
          final els = doc.findAllElements('s$i');
          if (els.isEmpty) continue;
          final sEl = els.first;
          final id = _findInElement(sEl, 'id');
          final sender = _findInElement(sEl, 'address');
          final rawDate = _findInElement(sEl, 'date').split(',');
          final timeStr = rawDate.length >= 6
              ? '20${rawDate[0]}/${rawDate[1]}/${rawDate[2]} ${rawDate[3]}:${rawDate[4]}:${rawDate[5]}'
              : '';
          final unread = _findInElement(sEl, 'read') == '0';
          final body = NotionMifiAdapter.uniDecode(_findInElement(sEl, 'body'));
          list.add(
            SmsMessage(
              id: id.isEmpty ? '$listType-$i' : id,
              sender: sender,
              content: body,
              timestamp: timeStr,
              isUnread: unread,
            ),
          );
        }
      }
      return list;
    });
  }
}
