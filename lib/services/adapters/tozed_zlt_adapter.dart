import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import '../../models/modem_models.dart';
import '../modem_detector.dart';
import 'modem_adapter.dart';

/// Dedicated adapter for Tozed / ZLT / Star Speed 4G / Olax / SAM / Vortex
/// modems running JSON CGI over `/cgi-bin/http.cgi` or `/cgi-bin/lua.cgi`.
class TozedZltAdapter implements ModemAdapter {
  @override
  final String gatewayIp;

  @override
  final String localClientIp;

  final String endpointPath;
  final String modelHint;
  final String preferredEncoding;

  late final http.Client _client =
      ModemDetector.createLanHttpClient(localClientIp);

  String _username = 'admin';
  String _password = 'admin';
  String _sessionId = '';
  String _cookie = '';
  final DateTime _sessionStart = DateTime.now();

  TozedZltAdapter({
    required this.gatewayIp,
    required this.localClientIp,
    this.endpointPath = '/cgi-bin/http.cgi',
    this.modelHint = 'Star Speed / ZLT 4G',
    this.preferredEncoding = '',
  });

  @override
  ModemFamily get family => ModemFamily.tozedZlt;

  @override
  String get protocolName => endpointPath.contains('lua.cgi')
      ? 'Tozed / ZLT / Star Speed (Lua CGI)'
      : 'Tozed / ZLT / Star Speed (HTTP CGI)';

  String get _url => 'http://$gatewayIp$endpointPath';

  Map<String, String> get _headers => {
        'Content-Type': 'application/json; charset=UTF-8',
        'Referer': 'http://$gatewayIp/',
        'X-Requested-With': 'XMLHttpRequest',
        if (_cookie.isNotEmpty) 'Cookie': _cookie,
      };

  void _saveCookies(Map<String, String> headers) {
    final sc = headers['set-cookie'];
    if (sc == null || sc.isEmpty) return;
    final parts = sc
        .split(RegExp(r',(?=[^;]+=[^;]+)'))
        .map((c) => c.split(';').first.trim())
        .where((s) => s.contains('='))
        .toList();
    if (parts.isNotEmpty) _cookie = parts.join('; ');
  }

  Future<Map<String, dynamic>?> _call(
    int cmd, {
    String method = 'GET',
    Map<String, dynamic> extra = const {},
  }) async {
    try {
      final payload = <String, dynamic>{
        'cmd': cmd,
        'method': method,
        if (_sessionId.isNotEmpty) 'sessionId': _sessionId,
        ...extra,
      };
      final res = await _client
          .post(Uri.parse(_url), headers: _headers, body: jsonEncode(payload))
          .timeout(const Duration(seconds: 5));
      _saveCookies(res.headers);
      final body = utf8.decode(res.bodyBytes, allowMalformed: true).trim();
      final idx = body.indexOf('{');
      if (idx == -1) return null;
      final decoded = jsonDecode(body.substring(idx));
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return null;
  }

  static String _pickStr(Map<String, dynamic> map, List<String> keys) {
    for (final k in keys) {
      final v = map[k];
      if (v != null) {
        final s = v.toString().trim();
        if (s.isNotEmpty && s != 'null' && s != 'undefined') return s;
      }
    }
    return '';
  }

  static int _pickInt(Map<String, dynamic> map, List<String> keys, [int def = 0]) {
    final s = _pickStr(map, keys).replaceAll(RegExp(r'[^0-9\-]'), '');
    return int.tryParse(s) ?? def;
  }

  static Map<String, dynamic> _flattenData(Map<String, dynamic>? resp) {
    if (resp == null) return const {};
    final out = <String, dynamic>{...resp};
    final inner = resp['data'];
    if (inner is Map) {
      inner.forEach((k, v) => out[k.toString()] = v);
    }
    return out;
  }

  @override
  Future<LoginOutcome> loginWithOutcome(String username, String password) async {
    _username = username.trim().isEmpty ? 'admin' : username.trim();
    _password = password;
    _sessionId = '';

    final passB64 = base64Encode(utf8.encode(_password));
    final passMd5 = md5.convert(utf8.encode(_password)).toString().toLowerCase();
    final passSha = sha256.convert(utf8.encode(_password)).toString().toLowerCase();
    final passShaUp = passSha.toUpperCase();

    final encodedList = <String>[
      if (preferredEncoding == 'base64') passB64,
      if (preferredEncoding == 'md5_lower') passMd5,
      if (preferredEncoding == 'sha256_lower') passSha,
      if (preferredEncoding == 'sha256_upper') passShaUp,
      _password,
      passB64,
      passMd5,
      passSha,
      passShaUp,
    ].toSet().toList();

    bool reached = false;
    for (final enc in encodedList) {
      final resp = await _call(
        100,
        method: 'POST',
        extra: {
          'username': _username,
          'passwd': enc,
          'password': enc,
          'sessionId': '',
        },
      );
      if (resp == null) continue;
      reached = true;
      final flat = _flattenData(resp);
      final sid = _pickStr(flat, ['sessionId', 'session_id', 'token', 'sid']);
      final okFlag = resp['success'] == true ||
          resp['result'] == 0 ||
          resp['result'] == '0' ||
          resp['status'] == 'ok' ||
          (resp['message'] ?? '').toString().toUpperCase() == 'OK';
      if (sid.isNotEmpty) {
        _sessionId = sid;
        return const LoginOutcome(success: true);
      }
      if (okFlag && _cookie.isNotEmpty) {
        return const LoginOutcome(success: true);
      }
      if (okFlag) {
        return const LoginOutcome(success: true);
      }
    }

    if (!reached) {
      return LoginOutcome(
        success: false,
        wrongCredentials: false,
        message: 'تعذر الوصول إلى المودم ($gatewayIp) عبر الواي فاي.',
      );
    }
    return const LoginOutcome(
      success: false,
      wrongCredentials: true,
      message: 'اسم المستخدم أو كلمة المرور غير صحيحة.',
    );
  }

  @override
  Future<void> logout() async {
    await _call(101, method: 'POST', extra: {'action': 'logout'});
    _sessionId = '';
    _cookie = '';
  }

  @override
  Future<ModemStatus> fetchStatus({bool forceFullRefresh = false}) async {
    final results = await Future.wait([
      _call(1),   // Network / Signal / Battery / WAN
      _call(16),  // Device Info (IMEI/ICCID/Model/FW)
      _call(2),   // Wi-Fi Settings
      _call(3),   // Connected Devices
    ]);

    if (results.every((r) => r == null)) {
      throw SocketException('انقطع الاتصال بالمودم ($gatewayIp)');
    }

    final merged = <String, dynamic>{};
    for (final r in results) {
      merged.addAll(_flattenData(r));
    }

    // Fallback secondary command IDs used by some lua.cgi firmwares
    if (_pickStr(merged, ['SSID', 'ssid', 'wifi_ssid']).isEmpty) {
      final w2 = await _call(102);
      merged.addAll(_flattenData(w2));
    }

    final model = _pickStr(merged, [
      'device_name',
      'model_name',
      'model',
      'board_type',
      'product_name',
    ]);
    final imei = _pickStr(merged, ['imei', 'IMEI', 'modem_imei']);
    final iccid = _pickStr(merged, ['iccid', 'ICCID', 'sim_iccid']);
    final imsi = _pickStr(merged, ['imsi', 'IMSI', 'sim_imsi']);
    final msisdn = ModemStatus.extractFirstValidNumber(
      [
        _pickStr(merged, ['msisdn', 'MSISDN', 'phone_number', 'mdn', 'sim_num']),
      ],
      imei: imei,
      iccid: iccid,
      imsi: imsi,
    );

    final rsrpStr = _pickStr(merged, ['rsrp', 'RSRP', 'lte_rsrp', 'signal_rsrp']);
    final rsrqStr = _pickStr(merged, ['rsrq', 'RSRQ', 'lte_rsrq']);
    final sinrStr = _pickStr(merged, ['sinr', 'SINR', 'snr', 'lte_snr']);
    final rssiStr = _pickStr(merged, ['rssi', 'RSSI', 'lte_rssi']);
    final pciStr = _pickStr(merged, ['pci', 'PCI', 'lte_pci']);
    final cellIdStr = _pickStr(merged, ['cell_id', 'cellId', 'cellid', 'eci']);
    final bandRaw = _pickStr(merged, ['band', 'lte_band', 'active_band', 'band_info']);
    final operatorName = _pickStr(merged, ['operator', 'network_provider', 'spn', 'plmn_name']);
    final netType = _pickStr(merged, ['network_type', 'sys_mode', 'rat']);

    int sigBars = _pickInt(merged, ['signal_lvl', 'signalbar', 'signal_bars', 'rssi_level']);
    int sigPct = 0;
    final rsrpVal = int.tryParse(rsrpStr.replaceAll(RegExp(r'[^0-9\-]'), ''));
    if (rsrpVal != null && rsrpVal < -40 && rsrpVal >= -140) {
      sigPct = (((rsrpVal + 122) / 47.0) * 100).round().clamp(5, 100);
      if (sigBars == 0) sigBars = (sigPct / 20).ceil().clamp(1, 5);
    } else if (sigBars > 0) {
      sigPct = (sigBars * 20).clamp(0, 100);
    }

    final batRaw = _pickStr(merged, ['battery_percent', 'battery_pers', 'bat_cap', 'battery']);
    final hasBat = batRaw.isNotEmpty;
    final batPct = hasBat ? (int.tryParse(batRaw.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0).clamp(0, 100) : 0;
    final charging = _pickStr(merged, ['battery_charging', 'chg_state', 'charging']) == '1';

    final rxBytes = _pickInt(merged, ['rx_bytes', 'realtime_rx_bytes', 'total_rx_bytes']);
    final txBytes = _pickInt(merged, ['tx_bytes', 'realtime_tx_bytes', 'total_tx_bytes']);
    final rxRate = _pickInt(merged, ['rx_speed', 'rx_rate', 'realtime_rx_thrpt']);
    final txRate = _pickInt(merged, ['tx_speed', 'tx_rate', 'realtime_tx_thrpt']);
    final uptime = _pickInt(
      merged,
      ['uptime', 'realtime_time', 'sys_uptime'],
      DateTime.now().difference(_sessionStart).inSeconds,
    );

    final ssid = _pickStr(merged, ['ssid', 'SSID', 'wifi_ssid', 'SSID1']);
    final wifiPass = _pickStr(merged, ['key', 'wifi_password', 'passwd_2g', 'wpa_key', 'passphrase']);
    final hiddenStr = _pickStr(merged, ['hide_ssid', 'broadcast', 'wifi_hide']);
    final isHidden = hiddenStr == '1' || hiddenStr.toLowerCase() == 'true';
    final maxClients = _pickInt(merged, ['max_clients', 'max_sta', 'wifi_max_num'], 16);

    final wanIp = _pickStr(merged, ['wan_ip', 'wanIp', 'ipv4_addr', 'ip_addr']);
    final mac = _pickStr(merged, ['mac', 'lan_mac', 'wifi_mac', 'mac_addr']);
    final fw = _pickStr(merged, ['fw_version', 'software_version', 'sw_version', 'version']);
    final hw = _pickStr(merged, ['hw_version', 'hardware_version']);

    // Connected devices extraction
    final devices = <ConnectedDevice>[];
    final rawDevList = merged['device_list'] ??
        merged['sta_list'] ??
        merged['dhcp_list'] ??
        merged['clients'] ??
        results[3]?['data'];
    if (rawDevList is List) {
      for (var i = 0; i < rawDevList.length; i++) {
        final item = rawDevList[i];
        if (item is Map) {
          final ip = (item['ip'] ?? item['ip_addr'] ?? item['ipAddress'] ?? '').toString();
          final dMac = (item['mac'] ?? item['mac_addr'] ?? item['macAddress'] ?? '')
              .toString()
              .toUpperCase();
          final name = (item['hostname'] ?? item['name'] ?? item['device_name'] ?? 'جهاز متصل')
              .toString()
              .trim();
          devices.add(
            ConnectedDevice(
              index: i,
              name: name.isEmpty ? 'جهاز متصل' : name,
              ipAddress: ip,
              macAddress: dMac,
              isCurrentDevice: ip.isNotEmpty && ip == localClientIp,
            ),
          );
        }
      }
    }

    final formattedBand = bandRaw.isEmpty
        ? ''
        : (bandRaw.toUpperCase().startsWith('B') ? bandRaw.toUpperCase() : 'B$bandRaw');

    return ModemStatus(
      hasBattery: hasBat,
      batteryPercent: batPct,
      isCharging: charging,
      rxBytes: rxBytes,
      txBytes: txBytes,
      totalBytes: rxBytes + txBytes,
      rxRateBps: rxRate,
      txRateBps: txRate,
      uptimeSeconds: uptime,
      networkType: netType.isNotEmpty ? netType : (formattedBand.isNotEmpty ? '4G' : ''),
      operatorName: operatorName,
      signalBars: sigBars.clamp(0, 5),
      signalPercent: sigPct,
      band: formattedBand,
      rsrp: rsrpStr.isNotEmpty ? '$rsrpStr dBm' : '-',
      rsrq: rsrqStr.isNotEmpty ? '$rsrqStr dB' : '-',
      sinr: sinrStr.isNotEmpty ? '$sinrStr dB' : '-',
      rssi: rssiStr.isNotEmpty ? '$rssiStr dBm' : '-',
      pci: pciStr.isNotEmpty ? pciStr : '-',
      cellId: cellIdStr.isNotEmpty ? cellIdStr : '-',
      wanConnected: wanIp.isNotEmpty && wanIp != '0.0.0.0',
      modemPhoneNumber: msisdn,
      deviceModel: model.isNotEmpty ? model : modelHint,
      wanIp: wanIp.isNotEmpty ? wanIp : '-',
      lanIp: gatewayIp,
      macAddress: mac.isNotEmpty ? mac : '-',
      imei: imei.isNotEmpty ? imei : '-',
      iccid: iccid.isNotEmpty ? iccid : '-',
      imsi: imsi.isNotEmpty ? imsi : '-',
      softwareVersion: fw.isNotEmpty ? fw : '-',
      hardwareVersion: hw.isNotEmpty ? hw : '-',
      ssid: ssid,
      wifiPassword: wifiPass,
      isHiddenSsid: isHidden,
      maxClients: maxClients,
      connectedDevicesCount: devices.isNotEmpty
          ? devices.length
          : _pickInt(merged, ['sta_num', 'connected_num', 'client_num']),
      adminUsername: _username,
      adminPassword: _password,
      devices: devices,
      supportedBands: const ['B1', 'B3', 'B5', 'B7', 'B8', 'B20', 'B28', 'B38', 'B40', 'B41'],
      capabilities: ModemCapabilities(
        hasBattery: hasBat,
        hasSignalMetrics: rsrpStr.isNotEmpty || sigBars > 0,
        hasBandLock: true,
        hasSpeedLimit: false,
        hasWifiEdit: true,
        hasMaxClients: true,
        hasHideSsid: true,
        hasLcdQrToggle: false,
        hasDeviceBlock: true,
        hasDeviceRename: false,
        hasReboot: true,
        hasPowerOff: false,
        hasAdminPassword: true,
        hasSms: true,
      ),
    );
  }

  @override
  Future<bool> updateWifi({
    required String ssid,
    required String password,
    required bool hideSsid,
    required int maxClients,
  }) async {
    for (final cmd in [2, 102]) {
      final resp = await _call(
        cmd,
        method: 'POST',
        extra: {
          'ssid': ssid,
          'SSID': ssid,
          'key': password,
          'wifi_password': password,
          'hide_ssid': hideSsid ? '1' : '0',
          'broadcast': hideSsid ? '0' : '1',
          'max_clients': maxClients,
        },
      );
      if (resp != null && (resp['success'] == true || resp['result'] == 0)) {
        return true;
      }
    }
    return false;
  }

  @override
  Future<bool> setBandConfig({
    required bool manualMode,
    required String networkMode,
    required List<String> bands,
  }) async {
    final cleanBands = bands
        .map((b) => b.toUpperCase().replaceAll('B', '').trim())
        .where((b) => b.isNotEmpty)
        .toList();
    final resp = await _call(
      166,
      method: 'POST',
      extra: {
        'lock_band_enable': manualMode ? '1' : '0',
        'band_list': cleanBands.join(','),
        'network_mode': networkMode == '4g_only'
            ? 'LTE'
            : (networkMode == '3g_only' ? 'WCDMA' : 'AUTO'),
      },
    );
    return resp != null && (resp['success'] == true || resp['result'] == 0);
  }

  @override
  Future<bool> setSpeedLimit({
    required bool enabled,
    required int downloadMbps,
    required int uploadMbps,
  }) async =>
      false;

  @override
  Future<bool> blockMacAddress(String macAddress) async {
    final resp = await _call(
      105,
      method: 'POST',
      extra: {
        'action': 'add',
        'mode': 'deny',
        'mac': macAddress.toUpperCase(),
      },
    );
    return resp != null && (resp['success'] == true || resp['result'] == 0);
  }

  @override
  Future<bool> unblockMacAddress(String macAddress) async {
    final resp = await _call(
      105,
      method: 'POST',
      extra: {
        'action': 'delete',
        'mac': macAddress.toUpperCase(),
      },
    );
    return resp != null && (resp['success'] == true || resp['result'] == 0);
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
  Future<bool> changeAdminPassword(String newPassword) async {
    final resp = await _call(
      107,
      method: 'POST',
      extra: {
        'old_passwd': _password,
        'new_passwd': newPassword,
        'username': _username,
      },
    );
    if (resp != null && (resp['success'] == true || resp['result'] == 0)) {
      _password = newPassword;
      return true;
    }
    return false;
  }

  @override
  Future<bool> rebootModem() async {
    for (final cmd in [6, 106]) {
      final resp = await _call(cmd, method: 'POST', extra: {'action': 'reboot'});
      if (resp != null && (resp['success'] == true || resp['result'] == 0)) {
        return true;
      }
    }
    return false;
  }

  @override
  Future<bool> powerOffModem() async => false;

  @override
  Future<List<SmsMessage>> fetchSmsInbox() async {
    final resp = await _call(20, method: 'GET');
    final raw = resp?['data'] ?? resp?['sms_list'];
    if (raw is! List) return [];
    final list = <SmsMessage>[];
    for (var i = 0; i < raw.length; i++) {
      final item = raw[i];
      if (item is Map) {
        list.add(
          SmsMessage(
            id: (item['id'] ?? '$i').toString(),
            sender: (item['number'] ?? item['sender'] ?? 'غير معروف').toString(),
            content: (item['content'] ?? item['message'] ?? '').toString(),
            timestamp: (item['date'] ?? item['time'] ?? '').toString(),
            isUnread: (item['status'] ?? '').toString() == '0',
          ),
        );
      }
    }
    return list;
  }
}
