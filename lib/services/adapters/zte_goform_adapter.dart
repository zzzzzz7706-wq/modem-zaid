import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import '../../models/modem_models.dart';
import 'modem_adapter.dart';

/// Adapter for ZTE / ZLT / Olax / Sanechips CGI modems
/// (ZTE MF927, MF293N, ZLT M30/M90 Pro, Olax MT80/MT80 Pro/MF982).
class ZteGoformAdapter implements ModemAdapter {
  @override
  final String gatewayIp;

  @override
  final String localClientIp;

  final String modelHint;
  final http.Client _client = http.Client();
  String _cookie = '';
  String _username = 'admin';
  String _password = 'admin';

  ZteGoformAdapter({
    required this.gatewayIp,
    required this.localClientIp,
    this.modelHint = 'ZTE / Olax 4G',
  });

  @override
  ModemFamily get family => ModemFamily.zteGoform;

  @override
  String get protocolName => 'ZTE / Olax Goform CGI';

  Map<String, String> get _headers => {
        'Referer': 'http://$gatewayIp/index.html',
        'X-Requested-With': 'XMLHttpRequest',
        if (_cookie.isNotEmpty) 'Cookie': _cookie,
      };

  Future<Map<String, dynamic>> _getCmd(List<String> cmds) async {
    try {
      final cmdParam = cmds.join(',');
      final uri = Uri.parse(
        'http://$gatewayIp/goform/goform_get_cmd_process?isTest=false&multi_data=1&cmd=${Uri.encodeComponent(cmdParam)}',
      );
      final res =
          await _client.get(uri, headers: _headers).timeout(const Duration(seconds: 5));
      final sc = res.headers['set-cookie'];
      if (sc != null && sc.isNotEmpty) _cookie = sc.split(';').first;
      final body = utf8.decode(res.bodyBytes, allowMalformed: true).trim();
      if (body.startsWith('{')) {
        return jsonDecode(body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return {};
  }

  Future<bool> _setCmd(Map<String, String> fields) async {
    try {
      final adData = await _getCmd(['RD', 'wa_inner_version', 'cr_version']);
      final rd = (adData['RD'] ?? '').toString();
      final bodyFields = Map<String, String>.from(fields);
      bodyFields['isTest'] = 'false';
      if (rd.isNotEmpty) {
        final v1 = '${adData['wa_inner_version'] ?? ''}${adData['cr_version'] ?? ''}';
        final h1 = md5.convert(utf8.encode(v1)).toString();
        final ad = md5.convert(utf8.encode('$h1$rd')).toString();
        bodyFields['AD'] = ad;
      }

      final uri = Uri.parse('http://$gatewayIp/goform/goform_set_cmd_process');
      final res = await _client
          .post(uri, headers: _headers, body: bodyFields)
          .timeout(const Duration(seconds: 6));
      final sc = res.headers['set-cookie'];
      if (sc != null && sc.isNotEmpty) _cookie = sc.split(';').first;
      final text = utf8.decode(res.bodyBytes, allowMalformed: true);
      return text.contains('success') || text.contains('"0"') || res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> login(String username, String password) async {
    _username = username.trim().isEmpty ? 'admin' : username.trim();
    _password = password;

    // Try Base64 password (standard ZTE) and SHA256 hex (newer ZTE/ZLT/Olax)
    final b64Pass = base64Encode(utf8.encode(_password));
    final shaPass = sha256.convert(utf8.encode(_password)).toString().toUpperCase();

    for (final encoded in [b64Pass, shaPass]) {
      try {
        final uri = Uri.parse('http://$gatewayIp/goform/goform_set_cmd_process');
        final res = await _client.post(
          uri,
          headers: _headers,
          body: {
            'isTest': 'false',
            'goformId': 'LOGIN',
            'password': encoded,
            'username': _username,
          },
        ).timeout(const Duration(seconds: 5));
        final sc = res.headers['set-cookie'];
        if (sc != null && sc.isNotEmpty) _cookie = sc.split(';').first;
        final text = utf8.decode(res.bodyBytes, allowMalformed: true);
        if (text.contains('"0"') || text.contains('success')) {
          return true;
        }
      } catch (_) {}
    }

    final check = await _getCmd(['modem_main_state', 'SSID1']);
    return check.isNotEmpty;
  }

  @override
  Future<void> logout() async {
    await _setCmd({'goformId': 'LOGOUT'});
  }

  static int _toInt(dynamic val, [int fallback = 0]) {
    if (val == null) return fallback;
    final clean = val.toString().replaceAll(RegExp(r'[^0-9\-]'), '');
    return int.tryParse(clean) ?? fallback;
  }

  @override
  Future<ModemStatus> fetchStatus({bool forceFullRefresh = false}) async {
    final data = await _getCmd([
      'battery_value',
      'battery_pers',
      'battery_vol_percent',
      'battery_charging',
      'signalbar',
      'network_type',
      'network_provider',
      'lte_rsrp',
      'lte_rsrq',
      'lte_snr',
      'lte_rssi',
      'lte_pci',
      'cell_id',
      'wan_active_band',
      'lte_ca_pcell_band',
      'realtime_tx_bytes',
      'realtime_rx_bytes',
      'realtime_tx_thrpt',
      'realtime_rx_thrpt',
      'realtime_time',
      'ppp_status',
      'wan_ipaddr',
      'lan_ipaddr',
      'mac_address',
      'imei',
      'sim_iccid',
      'sim_imsi',
      'msisdn',
      'LocalNumber',
      'wa_inner_version',
      'hardware_version',
      'model_name',
      'SSID1',
      'WPAPSK1',
      'HideSSID',
      'AuthMode',
      'MAX_Access_num',
      'sta_count',
      'lte_band_lock',
    ]);

    Map<String, dynamic> devData = {};
    try {
      devData = await _getCmd(['station_list']);
    } catch (_) {}

    final batVal = _toInt(
      data['battery_vol_percent'] ?? data['battery_pers'] ?? data['battery_value'],
      -1,
    );
    final hasBat = batVal >= 0;
    final batPct = hasBat ? batVal.clamp(0, 100) : 100;
    final charging = (data['battery_charging'] ?? '').toString() == '1';

    final rx = _toInt(data['realtime_rx_bytes']);
    final tx = _toInt(data['realtime_tx_bytes']);
    final rxRate = _toInt(data['realtime_rx_thrpt']);
    final txRate = _toInt(data['realtime_tx_thrpt']);
    final uptime = _toInt(data['realtime_time']);

    final bars = _toInt(data['signalbar'], 4).clamp(0, 5);
    final rsrpVal = _toInt(data['lte_rsrp'], 0);
    int sigPct = bars * 20;
    if (rsrpVal < -40 && rsrpVal >= -140) {
      sigPct = (((rsrpVal + 122) / 47.0) * 100).round().clamp(5, 100);
    }

    String rawBand =
        (data['wan_active_band'] ?? data['lte_ca_pcell_band'] ?? 'B28').toString();
    if (rawBand.isNotEmpty && !rawBand.toUpperCase().startsWith('B')) {
      final numPart = rawBand.replaceAll(RegExp(r'[^0-9]'), '');
      if (numPart.isNotEmpty) rawBand = 'B$numPart';
    }

    final devices = <ConnectedDevice>[];
    final stList = devData['station_list'];
    if (stList is List) {
      int idx = 0;
      for (final item in stList) {
        if (item is Map) {
          final ip = (item['ip_addr'] ?? '').toString();
          final mac = (item['mac_addr'] ?? '').toString();
          final host = (item['hostname'] ?? 'جهاز ${idx + 1}').toString();
          devices.add(
            ConnectedDevice(
              index: idx,
              name: host,
              ipAddress: ip.isEmpty ? '--' : ip,
              macAddress: mac,
              isCurrentDevice: ip.isNotEmpty && ip == localClientIp,
            ),
          );
          idx++;
        }
      }
    }

    final connCount = devices.isNotEmpty
        ? devices.length
        : _toInt(data['sta_count'], 1);

    final netRaw = (data['network_type'] ?? 'LTE').toString().toUpperCase();
    final netType = netRaw.contains('3G') || netRaw.contains('WCDMA') ? '3G' : '4G';

    return ModemStatus(
      hasBattery: hasBat,
      batteryPercent: batPct,
      isCharging: charging,
      rxBytes: rx,
      txBytes: tx,
      totalBytes: rx + tx,
      rxRateBps: rxRate,
      txRateBps: txRate,
      uptimeSeconds: uptime,
      networkType: netType,
      operatorName: (data['network_provider'] ?? 'Yemen 4G').toString(),
      signalBars: bars,
      signalPercent: sigPct,
      band: rawBand.isEmpty ? 'B28' : rawBand,
      rsrp: data['lte_rsrp'] != null ? '${data['lte_rsrp']} dBm' : '-',
      rsrq: data['lte_rsrq'] != null ? '${data['lte_rsrq']} dB' : '-',
      sinr: data['lte_snr'] != null ? '${data['lte_snr']} dB' : '-',
      rssi: data['lte_rssi'] != null ? '${data['lte_rssi']} dBm' : '-',
      pci: (data['lte_pci'] ?? '-').toString(),
      cellId: (data['cell_id'] ?? '-').toString(),
      wanConnected:
          (data['ppp_status'] ?? '').toString().toLowerCase().contains('connect'),
      modemPhoneNumber: ModemStatus.normalizeModemNumber(
        (data['msisdn'] ?? data['LocalNumber'] ?? '').toString(),
      ),
      deviceModel: (data['model_name'] ?? modelHint).toString(),
      wanIp: (data['wan_ipaddr'] ?? '-').toString(),
      lanIp: (data['lan_ipaddr'] ?? gatewayIp).toString(),
      macAddress: (data['mac_address'] ?? '-').toString(),
      imei: (data['imei'] ?? '-').toString(),
      iccid: (data['sim_iccid'] ?? '-').toString(),
      imsi: (data['sim_imsi'] ?? '-').toString(),
      softwareVersion: (data['wa_inner_version'] ?? '-').toString(),
      hardwareVersion: (data['hardware_version'] ?? '-').toString(),
      ssid: (data['SSID1'] ?? 'Yemen4G').toString(),
      wifiPassword: (data['WPAPSK1'] ?? '').toString(),
      isHiddenSsid: (data['HideSSID'] ?? '0').toString() == '1',
      securityMode: (data['AuthMode'] ?? 'WPA2PSK').toString(),
      maxClients: _toInt(data['MAX_Access_num'], 10),
      connectedDevicesCount: connCount,
      adminUsername: _username,
      adminPassword: _password,
      devices: devices,
      capabilities: ModemCapabilities(
        hasBattery: hasBat,
        hasSignalMetrics: true,
        hasBandLock: true,
        hasSpeedLimit: false,
        hasWifiEdit: true,
        hasMaxClients: true,
        hasHideSsid: true,
        hasLcdQrToggle: false,
        hasDeviceBlock: true,
        hasDeviceRename: false,
        hasReboot: true,
        hasPowerOff: true,
        hasAdminPassword: true,
        hasSms: false,
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
    return _setCmd({
      'goformId': 'SET_WIFI_INFO',
      'SSID1': ssid,
      'WPAPSK1': password,
      'HideSSID': hideSsid ? '1' : '0',
      'MAX_Access_num': '$maxClients',
      'AuthMode': 'WPA2PSK',
      'EncrypType': 'AES',
    });
  }

  @override
  Future<bool> setBandConfig({
    required bool manualMode,
    required String networkMode,
    required List<String> bands,
  }) async {
    if (!manualMode || bands.isEmpty) {
      return _setCmd({
        'goformId': 'SET_NETWORK_MODE',
        'network_mode': networkMode == '4g_only' ? 'Only_LTE' : 'NETWORK_auto',
      });
    }
    int mask = 0;
    for (final b in bands) {
      final num = int.tryParse(b.toUpperCase().replaceAll('B', '').trim());
      if (num != null && num >= 1 && num <= 44) {
        mask |= (1 << (num - 1));
      }
    }
    return _setCmd({
      'goformId': 'BAND_SELECT',
      'is_gw_band': '0',
      'gw_band_mask': '0',
      'is_lte_band': '1',
      'lte_band_mask': '0x${mask.toRadixString(16)}',
    });
  }

  @override
  Future<bool> setSpeedLimit({
    required bool enabled,
    required int downloadMbps,
    required int uploadMbps,
  }) async {
    return _setCmd({
      'goformId': 'SPEED_LIMIT_SETTING',
      'speed_limit_switch': enabled ? '1' : '0',
      'dl_speed_limit': '${downloadMbps * 1024}',
      'ul_speed_limit': '${uploadMbps * 1024}',
    });
  }

  @override
  Future<bool> setDeviceBlock({
    required ConnectedDevice device,
    required bool block,
  }) async {
    return _setCmd({
      'goformId': 'ACL_MAC_SET',
      'ACL_mode': '2',
      'mac_addr': device.macAddress,
      'action': block ? 'add' : 'del',
    });
  }

  @override
  Future<bool> renameDevice({
    required ConnectedDevice device,
    required String newName,
  }) async {
    return _setCmd({
      'goformId': 'EDIT_DEVICE_NAME',
      'mac': device.macAddress,
      'hostname': newName,
    });
  }

  @override
  Future<bool> setLcdQrCode(bool visibleOnModemScreen) async => false;

  @override
  Future<bool> changeAdminPassword(String newPassword) async {
    final oldB64 = base64Encode(utf8.encode(_password));
    final newB64 = base64Encode(utf8.encode(newPassword));
    final ok = await _setCmd({
      'goformId': 'CHANGE_PASSWORD',
      'oldPassword': oldB64,
      'newPassword': newB64,
    });
    if (ok) _password = newPassword;
    return ok;
  }

  @override
  Future<bool> rebootModem() async {
    return _setCmd({'goformId': 'REBOOT_DEVICE'});
  }

  @override
  Future<bool> powerOffModem() async {
    return _setCmd({'goformId': 'SHUTDOWN_DEVICE'});
  }

  @override
  Future<List<SmsMessage>> fetchSmsInbox() async => [];
}
