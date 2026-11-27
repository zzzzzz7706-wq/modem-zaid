import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import '../../models/modem_models.dart';
import '../modem_detector.dart';
import 'modem_adapter.dart';

/// Adapter for ZTE / ZLT / Olax / Sanechips CGI modems
/// (ZTE MF927, MF293N, ZLT M30/M90 Pro, Olax MT80/MT80 Pro/MF982).
class ZteGoformAdapter implements ModemAdapter {
  @override
  final String gatewayIp;

  @override
  final String localClientIp;

  final String modelHint;
  final bool useReqProc;
  late final http.Client _client =
      ModemDetector.createLanHttpClient(localClientIp);
  String _cookie = '';
  String _username = 'admin';
  String _password = 'admin';

  ZteGoformAdapter({
    required this.gatewayIp,
    required this.localClientIp,
    this.modelHint = 'ZTE / Olax 4G',
    this.useReqProc = false,
  });

  @override
  ModemFamily get family => ModemFamily.zteGoform;

  @override
  String get protocolName =>
      useReqProc ? 'Qualcomm / Speed 4G CGI' : 'ZTE / Olax Goform CGI';

  String get _getPath =>
      useReqProc ? '/reqproc/proc_get' : '/goform/goform_get_cmd_process';

  String get _setPath =>
      useReqProc ? '/reqproc/proc_post' : '/goform/goform_set_cmd_process';

  Map<String, String> get _headers => {
        'Referer': 'http://$gatewayIp/index.html',
        'X-Requested-With': 'XMLHttpRequest',
        if (_cookie.isNotEmpty) 'Cookie': _cookie,
      };

  Future<Map<String, dynamic>> _getCmd(List<String> cmds) async {
    final cmdParam = cmds.join(',');
    final uri = Uri.parse(
      'http://$gatewayIp$_getPath?isTest=false&multi_data=1&cmd=${Uri.encodeComponent(cmdParam)}',
    );
    final res = await _client
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 5));
    final sc = res.headers['set-cookie'];
    if (sc != null && sc.isNotEmpty) _cookie = sc.split(';').first;
    final body = utf8.decode(res.bodyBytes, allowMalformed: true).trim();
    final start = body.indexOf('{');
    if (start != -1) {
      return jsonDecode(body.substring(start)) as Map<String, dynamic>;
    }
    return {};
  }

  Future<bool> _setCmd(Map<String, String> fields) async {
    try {
      Map<String, dynamic> adData = {};
      try {
        adData = await _getCmd(['RD', 'wa_inner_version', 'cr_version']);
      } catch (_) {}
      final rd = (adData['RD'] ?? '').toString();
      final bodyFields = Map<String, String>.from(fields);
      bodyFields['isTest'] = 'false';
      if (rd.isNotEmpty) {
        final v1 =
            '${adData['wa_inner_version'] ?? ''}${adData['cr_version'] ?? ''}';
        final h1 = md5.convert(utf8.encode(v1)).toString();
        final ad = md5.convert(utf8.encode('$h1$rd')).toString();
        bodyFields['AD'] = ad;
      }

      final uri = Uri.parse('http://$gatewayIp$_setPath');
      final res = await _client
          .post(uri, headers: _headers, body: bodyFields)
          .timeout(const Duration(seconds: 6));
      final sc = res.headers['set-cookie'];
      if (sc != null && sc.isNotEmpty) _cookie = sc.split(';').first;
      final text = utf8.decode(res.bodyBytes, allowMalformed: true);
      return text.contains('success') || text.contains('"0"');
    } catch (_) {
      return false;
    }
  }

  @override
  Future<LoginOutcome> loginWithOutcome(String username, String password) async {
    _username = username.trim().isEmpty ? 'admin' : username.trim();
    _password = password;

    // Pre-login info: LD (salt for new firmwares), login state, lock state.
    Map<String, dynamic> pre = {};
    bool reachedServer = false;
    try {
      pre = await _getCmd(
          ['LD', 'loginfo', 'psw_fail_num_str', 'login_lock_time', 'modem_main_state']);
      reachedServer = true;
    } catch (_) {}

    if ((pre['loginfo'] ?? '').toString().toLowerCase() == 'ok') {
      return const LoginOutcome(success: true);
    }
    final lockTime = int.tryParse((pre['login_lock_time'] ?? '').toString()) ?? 0;
    final failLeft = (pre['psw_fail_num_str'] ?? '').toString();
    if (failLeft == '0' && lockTime > 0) {
      return LoginOutcome(
        success: false,
        wrongCredentials: false,
        message: 'المودم مقفل مؤقتاً بسبب محاولات خاطئة. انتظر ${lockTime > 60 ? '${(lockTime / 60).ceil()} دقيقة' : '$lockTime ثانية'} ثم حاول.',
      );
    }

    final ld = (pre['LD'] ?? '').toString().trim();
    final candidates = <String>[];
    if (ld.isNotEmpty) {
      // New ZTE / Olax / Speed 4G firmwares: SHA256(SHA256(pwd).upper + LD).upper
      final inner = sha256.convert(utf8.encode(_password)).toString().toUpperCase();
      candidates.add(sha256.convert(utf8.encode('$inner$ld')).toString().toUpperCase());
    } else {
      // Classic firmwares: Base64(pwd), then SHA256 variant used by some clones.
      candidates.add(base64Encode(utf8.encode(_password)));
      candidates.add(sha256.convert(utf8.encode(_password)).toString().toUpperCase());
    }

    String lastResult = '';
    for (final encoded in candidates) {
      try {
        final uri = Uri.parse('http://$gatewayIp$_setPath');
        final res = await _client.post(
          uri,
          headers: _headers,
          body: {
            'isTest': 'false',
            'goformId': 'LOGIN',
            'password': encoded,
            'username': _username,
          },
        ).timeout(const Duration(seconds: 6));
        reachedServer = true;
        final sc = res.headers['set-cookie'];
        if (sc != null && sc.isNotEmpty) _cookie = sc.split(';').first;
        final text = utf8.decode(res.bodyBytes, allowMalformed: true);
        final m = RegExp(r'"result"\s*:\s*"?(\w+)"?').firstMatch(text);
        lastResult = m?.group(1) ?? '';
        if (lastResult == '0' || text.contains('success')) {
          return const LoginOutcome(success: true);
        }
        // "3" = wrong password on classic firmwares. With LD there's only one
        // correct encoding so don't retry (each retry costs a lock attempt).
        if (ld.isNotEmpty) break;
      } catch (_) {}
    }

    if (!reachedServer) {
      return LoginOutcome(
        success: false,
        wrongCredentials: false,
        message: 'تعذر الوصول إلى المودم ($gatewayIp) عبر الواي فاي.',
      );
    }

    // Read remaining attempts to give a precise message.
    String left = '';
    try {
      final post = await _getCmd(['psw_fail_num_str', 'loginfo']);
      if ((post['loginfo'] ?? '').toString().toLowerCase() == 'ok') {
        return const LoginOutcome(success: true);
      }
      left = (post['psw_fail_num_str'] ?? '').toString();
    } catch (_) {}

    if (lastResult == '1' && left.isEmpty) {
      return const LoginOutcome(
        success: false,
        wrongCredentials: false,
        message: 'رفض المودم الدخول. قد يكون مستخدماً من جهاز آخر — حاول بعد قليل.',
      );
    }
    return LoginOutcome(
      success: false,
      wrongCredentials: true,
      message: left.isNotEmpty && left != '0'
          ? 'كلمة المرور غير صحيحة (المحاولات المتبقية: $left).'
          : 'كلمة المرور غير صحيحة.',
    );
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
      'sim_msisdn',
      'wa_inner_version',
      'hardware_version',
      'model_name',
      'SSID1',
      'WPAPSK1',
      'HideSSID',
      'AuthMode',
      'MAX_Access_num',
      'sta_count',
      'ACL_mode',
      'ACL_mac_list',
    ]);

    if (data.isEmpty) {
      throw SocketException('تعذر جلب حالة المودم من $gatewayIp');
    }

    Map<String, dynamic> devData = {};
    try {
      devData = await _getCmd(['station_list', 'offline_station_list']);
    } catch (_) {}

    final batVal = _toInt(
      data['battery_vol_percent'] ?? data['battery_pers'] ?? data['battery_value'],
      -1,
    );
    final hasBat = batVal >= 0;
    final batPct = hasBat ? batVal.clamp(0, 100) : 0;
    final charging = (data['battery_charging'] ?? '').toString() == '1';

    final rx = _toInt(data['realtime_rx_bytes']);
    final tx = _toInt(data['realtime_tx_bytes']);
    final rxRate = _toInt(data['realtime_rx_thrpt']);
    final txRate = _toInt(data['realtime_tx_thrpt']);
    final uptime = _toInt(data['realtime_time']);

    final rawBars = _toInt(data['signalbar'], -1);
    final rsrpVal = _toInt(data['lte_rsrp'], 0);
    final hasSignal = rawBars >= 0 || (rsrpVal < -40 && rsrpVal >= -145);
    int bars = rawBars >= 0 ? rawBars.clamp(0, 5) : 0;
    int sigPct = bars * 20;
    if (rsrpVal < -40 && rsrpVal >= -145) {
      sigPct = (((rsrpVal + 122) / 47.0) * 100).round().clamp(5, 100);
      if (bars == 0) bars = ((sigPct / 20.0).ceil()).clamp(1, 5);
    }

    String rawBand =
        (data['wan_active_band'] ?? data['lte_ca_pcell_band'] ?? '').toString().trim();
    if (rawBand.isNotEmpty && !rawBand.toUpperCase().startsWith('B')) {
      final numPart = rawBand.replaceAll(RegExp(r'[^0-9]'), '');
      if (numPart.isNotEmpty) rawBand = 'B$numPart';
    }

    final aclRaw = (data['ACL_mac_list'] ?? '').toString();
    final blockedMacs = aclRaw
        .split(RegExp(r'[;,\s]+'))
        .map((s) => s.trim().toUpperCase())
        .where((s) => RegExp(r'^([0-9A-F]{2}:){5}[0-9A-F]{2}$').hasMatch(s))
        .toList();

    final devices = <ConnectedDevice>[];
    final seenMacs = <String>{};
    int idx = 0;

    void parseStationList(dynamic listObj, bool isOnline) {
      if (listObj is List) {
        for (final item in listObj) {
          if (item is Map) {
            final ip = (item['ip_addr'] ?? '').toString().trim();
            final mac = (item['mac_addr'] ?? '').toString().trim().toUpperCase();
            if (mac.isEmpty || seenMacs.contains(mac)) continue;
            seenMacs.add(mac);
            final host = (item['hostname'] ?? '').toString().trim();
            final isBlk = blockedMacs.contains(mac);
            devices.add(
              ConnectedDevice(
                index: idx++,
                name: host.isEmpty ? 'جهاز $idx' : host,
                ipAddress: ip.isEmpty ? (isOnline ? '-' : 'غير متصل') : ip,
                macAddress: mac,
                isBlocked: isBlk,
                isConnected: isOnline && !isBlk,
                isCurrentDevice: ip.isNotEmpty && ip == localClientIp,
              ),
            );
          }
        }
      }
    }

    parseStationList(devData['station_list'], true);
    parseStationList(devData['offline_station_list'], false);

    for (final bm in blockedMacs) {
      if (!seenMacs.contains(bm)) {
        devices.add(
          ConnectedDevice(
            index: idx++,
            name: 'جهاز محظور',
            ipAddress: 'محظور عبر MAC',
            macAddress: bm,
            isBlocked: true,
            isConnected: false,
          ),
        );
      }
    }

    final connCount = devices.where((d) => d.isConnected && !d.isBlocked).isNotEmpty
        ? devices.where((d) => d.isConnected && !d.isBlocked).length
        : _toInt(data['sta_count'], 0);

    final netRaw = (data['network_type'] ?? '').toString().toUpperCase();
    final netType = netRaw.isEmpty
        ? ''
        : (netRaw.contains('3G') || netRaw.contains('WCDMA') ? '3G' : '4G');

    final imei = (data['imei'] ?? '').toString();
    final iccid = (data['sim_iccid'] ?? '').toString();
    final imsi = (data['sim_imsi'] ?? '').toString();
    final modemNum = ModemStatus.extractFirstValidNumber(
      [
        (data['msisdn'] ?? '').toString(),
        (data['LocalNumber'] ?? '').toString(),
        (data['sim_msisdn'] ?? '').toString(),
      ],
      imei: imei,
      iccid: iccid,
      imsi: imsi,
    );

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
      operatorName: (data['network_provider'] ?? '').toString(),
      signalBars: bars,
      signalPercent: sigPct,
      band: rawBand,
      rsrp: (data['lte_rsrp'] ?? '').toString().isNotEmpty
          ? '${data['lte_rsrp']} dBm'
          : '-',
      rsrq: (data['lte_rsrq'] ?? '').toString().isNotEmpty
          ? '${data['lte_rsrq']} dB'
          : '-',
      sinr: (data['lte_snr'] ?? '').toString().isNotEmpty
          ? '${data['lte_snr']} dB'
          : '-',
      rssi: (data['lte_rssi'] ?? '').toString().isNotEmpty
          ? '${data['lte_rssi']} dBm'
          : '-',
      pci: (data['lte_pci'] ?? '-').toString(),
      cellId: (data['cell_id'] ?? '-').toString(),
      wanConnected:
          (data['ppp_status'] ?? '').toString().toLowerCase().contains('connect'),
      modemPhoneNumber: modemNum,
      deviceModel: (data['model_name'] ?? modelHint).toString(),
      wanIp: (data['wan_ipaddr'] ?? '-').toString(),
      lanIp: (data['lan_ipaddr'] ?? gatewayIp).toString(),
      macAddress: (data['mac_address'] ?? '-').toString(),
      imei: imei.isEmpty ? '-' : imei,
      iccid: iccid.isEmpty ? '-' : iccid,
      imsi: imsi.isEmpty ? '-' : imsi,
      softwareVersion: (data['wa_inner_version'] ?? '-').toString(),
      hardwareVersion: (data['hardware_version'] ?? '-').toString(),
      ssid: (data['SSID1'] ?? '').toString(),
      wifiPassword: (data['WPAPSK1'] ?? '').toString(),
      isHiddenSsid: (data['HideSSID'] ?? '0').toString() == '1',
      securityMode: (data['AuthMode'] ?? 'WPA2PSK').toString(),
      maxClients: _toInt(data['MAX_Access_num'], 10),
      connectedDevicesCount: connCount,
      adminUsername: _username,
      adminPassword: _password,
      devices: devices,
      blockedMacs: blockedMacs,
      capabilities: ModemCapabilities(
        hasBattery: hasBat,
        hasSignalMetrics: hasSignal,
        hasBandLock: true,
        hasSpeedLimit: false,
        hasWifiEdit: true,
        hasMaxClients: true,
        hasHideSsid: true,
        hasLcdQrToggle: false,
        hasDeviceBlock: true,
        hasDeviceRename: true,
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
  }) async =>
      false;

  @override
  Future<bool> blockMacAddress(String macAddress) async {
    final norm = macAddress.trim().toUpperCase();
    final sent = await _setCmd({
      'goformId': 'ACL_MAC_SET',
      'ACL_mode': '2',
      'mac_addr': norm,
      'action': 'add',
    });
    if (!sent) return false;
    await Future.delayed(const Duration(seconds: 2));
    try {
      final check = await _getCmd(['ACL_mac_list']);
      return (check['ACL_mac_list'] ?? '')
          .toString()
          .toUpperCase()
          .contains(norm);
    } catch (_) {
      return sent;
    }
  }

  @override
  Future<bool> unblockMacAddress(String macAddress) async {
    final norm = macAddress.trim().toUpperCase();
    final sent = await _setCmd({
      'goformId': 'ACL_MAC_SET',
      'ACL_mode': '2',
      'mac_addr': norm,
      'action': 'del',
    });
    if (!sent) return false;
    await Future.delayed(const Duration(seconds: 2));
    try {
      final check = await _getCmd(['ACL_mac_list']);
      return !(check['ACL_mac_list'] ?? '')
          .toString()
          .toUpperCase()
          .contains(norm);
    } catch (_) {
      return sent;
    }
  }

  @override
  Future<bool> setDeviceBlock({
    required ConnectedDevice device,
    required bool block,
  }) {
    if (device.isCurrentDevice && block) return Future.value(false);
    return block
        ? blockMacAddress(device.macAddress)
        : unblockMacAddress(device.macAddress);
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
  Future<bool> rebootModem() async => _setCmd({'goformId': 'REBOOT_DEVICE'});

  @override
  Future<bool> powerOffModem() async => _setCmd({'goformId': 'SHUTDOWN_DEVICE'});

  @override
  Future<List<SmsMessage>> fetchSmsInbox() async => [];
}
