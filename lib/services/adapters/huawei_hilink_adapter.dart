import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import '../../models/modem_models.dart';
import 'modem_adapter.dart';

/// Adapter for Huawei / Brovi / Soyealink HiLink XML API routers
/// (E5577, E5573, B310, B312, B315, B525, H122, etc. on 192.168.8.1).
class HuaweiHilinkAdapter implements ModemAdapter {
  @override
  final String gatewayIp;

  @override
  final String localClientIp;

  final String modelHint;
  final http.Client _client = http.Client();

  String _cookie = '';
  String _token = '';
  String _username = 'admin';
  String _password = 'admin';

  HuaweiHilinkAdapter({
    required this.gatewayIp,
    required this.localClientIp,
    this.modelHint = 'Huawei HiLink 4G',
  });

  @override
  ModemFamily get family => ModemFamily.huaweiHilink;

  @override
  String get protocolName => 'Huawei HiLink XML API';

  static String _findTag(XmlDocument? doc, String tag) {
    if (doc == null) return '';
    final els = doc.rootElement.findAllElements(tag);
    if (els.isEmpty) return '';
    return els.first.innerText.trim();
  }

  static int _toInt(String s, [int fallback = 0]) {
    if (s.isEmpty) return fallback;
    final clean = s.replaceAll(RegExp(r'[^0-9\-]'), '');
    return int.tryParse(clean) ?? fallback;
  }

  Future<bool> _refreshSesTok() async {
    try {
      final res = await _client
          .get(
            Uri.parse('http://$gatewayIp/api/webserver/SesTokInfo'),
            headers: {if (_cookie.isNotEmpty) 'Cookie': _cookie},
          )
          .timeout(const Duration(seconds: 4));
      final sc = res.headers['set-cookie'];
      if (sc != null && sc.isNotEmpty) _cookie = sc.split(';').first;
      final doc =
          XmlDocument.parse(utf8.decode(res.bodyBytes, allowMalformed: true));
      final ses = _findTag(doc, 'SesInfo');
      final tok = _findTag(doc, 'TokInfo');
      if (ses.isNotEmpty) _cookie = ses;
      if (tok.isNotEmpty) _token = tok;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<XmlDocument?> _apiGet(String path) async {
    try {
      if (_cookie.isEmpty) await _refreshSesTok();
      final res = await _client.get(
        Uri.parse('http://$gatewayIp$path'),
        headers: {
          if (_cookie.isNotEmpty) 'Cookie': _cookie,
          if (_token.isNotEmpty) '__RequestVerificationToken': _token,
        },
      ).timeout(const Duration(seconds: 5));
      final sc = res.headers['set-cookie'];
      if (sc != null && sc.isNotEmpty) _cookie = sc.split(';').first;
      final tok = res.headers['__requestverificationtoken'];
      if (tok != null && tok.isNotEmpty) _token = tok;
      return XmlDocument.parse(utf8.decode(res.bodyBytes, allowMalformed: true));
    } catch (_) {
      return null;
    }
  }

  Future<bool> _apiPost(String path, String xmlBody) async {
    try {
      await _refreshSesTok();
      final res = await _client
          .post(
            Uri.parse('http://$gatewayIp$path'),
            headers: {
              'Content-Type': 'application/xml; charset=UTF-8',
              if (_cookie.isNotEmpty) 'Cookie': _cookie,
              if (_token.isNotEmpty) '__RequestVerificationToken': _token,
            },
            body: '<?xml version="1.0" encoding="UTF-8"?>$xmlBody',
          )
          .timeout(const Duration(seconds: 6));
      final sc = res.headers['set-cookie'];
      if (sc != null && sc.isNotEmpty) _cookie = sc.split(';').first;
      final tok = res.headers['__requestverificationtoken'];
      if (tok != null && tok.isNotEmpty) _token = tok;
      final body = utf8.decode(res.bodyBytes, allowMalformed: true);
      return body.contains('<response>OK</response>');
    } catch (_) {
      return false;
    }
  }

  @override
  Future<LoginOutcome> loginWithOutcome(String username, String password) async {
    _username = username.trim().isEmpty ? 'admin' : username.trim();
    _password = password;
    final reachable = await _refreshSesTok();
    if (!reachable) {
      return LoginOutcome(
        success: false,
        wrongCredentials: false,
        message: 'تعذر الوصول إلى مودم هواوي ($gatewayIp).',
      );
    }

    final passShaHex = sha256.convert(utf8.encode(_password)).toString();
    final passB64 = base64Encode(utf8.encode(passShaHex));
    final combined = '$_username$passB64$_token';
    final finalShaHex = sha256.convert(utf8.encode(combined)).toString();
    final finalEncoded = base64Encode(utf8.encode(finalShaHex));

    final ok4 = await _apiPost(
      '/api/user/login',
      '<request><Username>$_username</Username><Password>$finalEncoded</Password><password_type>4</password_type></request>',
    );
    if (ok4) return const LoginOutcome(success: true);

    final plainB64 = base64Encode(utf8.encode(_password));
    final ok0 = await _apiPost(
      '/api/user/login',
      '<request><Username>$_username</Username><Password>$plainB64</Password></request>',
    );
    if (ok0) return const LoginOutcome(success: true);

    return const LoginOutcome(
      success: false,
      wrongCredentials: true,
      message: 'اسم المستخدم أو كلمة المرور غير صحيحة.',
    );
  }

  @override
  Future<void> logout() async {
    await _apiPost('/api/user/logout', '<request><Logout>1</Logout></request>');
  }

  List<String> _parseBlockedMacs(XmlDocument? macDoc) {
    if (macDoc == null) return [];
    final mode = _findTag(macDoc, 'WifiMacFilterStatus');
    if (mode != '2') return []; // 2 = Deny / Blacklist in HiLink
    final list = <String>[];
    for (int i = 0; i < 16; i++) {
      final m = _findTag(macDoc, 'WifiMacFilterMac$i').toUpperCase();
      if (m.isNotEmpty && !list.contains(m)) list.add(m);
    }
    return list;
  }

  @override
  Future<ModemStatus> fetchStatus({bool forceFullRefresh = false}) async {
    final monDoc = await _apiGet('/api/monitoring/status');
    if (monDoc == null) {
      throw SocketException('انقطع الاتصال بمودم هواوي ($gatewayIp)');
    }
    final sigDoc = await _apiGet('/api/device/signal');
    final trafDoc = await _apiGet('/api/monitoring/traffic-statistics');
    final infoDoc = await _apiGet('/api/device/information');
    final wlanDoc = await _apiGet('/api/wlan/basic-settings');
    final hostDoc = await _apiGet('/api/wlan/host-list');
    final plmnDoc = await _apiGet('/api/net/current-plmn');
    final macDoc = await _apiGet('/api/wlan/mac-filter');

    final hasBat = _findTag(monDoc, 'BatteryPercent').isNotEmpty;
    final batPct = hasBat
        ? _toInt(_findTag(monDoc, 'BatteryPercent'), 0).clamp(0, 100)
        : 0;
    final charging = _findTag(monDoc, 'BatteryStatus') == '1';

    final rx = _toInt(_findTag(trafDoc, 'CurrentDownload'));
    final tx = _toInt(_findTag(trafDoc, 'CurrentUpload'));
    final rxRate = _toInt(_findTag(trafDoc, 'CurrentDownloadRate'));
    final txRate = _toInt(_findTag(trafDoc, 'CurrentUploadRate'));
    final uptime = _toInt(_findTag(trafDoc, 'CurrentConnectTime'));

    final rawBars = _toInt(_findTag(monDoc, 'SignalIcon'), -1);
    final rsrp = _findTag(sigDoc, 'rsrp');
    final rsrq = _findTag(sigDoc, 'rsrq');
    final sinr = _findTag(sigDoc, 'sinr');
    final rssi = _findTag(sigDoc, 'rssi');
    final pci = _findTag(sigDoc, 'pci');
    final cellId = _findTag(sigDoc, 'cell_id');
    final bandNum = _findTag(sigDoc, 'band');
    final band =
        bandNum.isEmpty ? '' : 'B${bandNum.toUpperCase().replaceAll('B', '')}';

    final rsrpInt = _toInt(rsrp, 0);
    final hasSignal = rawBars >= 0 || (rsrpInt < -40 && rsrpInt >= -145);
    int bars = rawBars >= 0 ? rawBars.clamp(0, 5) : 0;
    int sigPct = bars * 20;
    if (rsrpInt < -40 && rsrpInt >= -145) {
      sigPct = (((rsrpInt + 122) / 47.0) * 100).round().clamp(5, 100);
      if (bars == 0) bars = ((sigPct / 20.0).ceil()).clamp(1, 5);
    }

    final blockedMacs = _parseBlockedMacs(macDoc);
    final devices = <ConnectedDevice>[];
    final seenMacs = <String>{};
    if (hostDoc != null) {
      int idx = 0;
      for (final h in hostDoc.rootElement.findAllElements('Host')) {
        final ipEls = h.findElements('IpAddress');
        final macEls = h.findElements('MacAddress');
        final nameEls = h.findElements('HostName');
        final stateEls = h.findElements('AssociatedSsid');
        final ip = ipEls.isEmpty ? '-' : ipEls.first.innerText.trim();
        final mac =
            macEls.isEmpty ? '' : macEls.first.innerText.trim().toUpperCase();
        final host =
            nameEls.isEmpty ? '' : nameEls.first.innerText.trim();
        if (mac.isNotEmpty && !seenMacs.contains(mac)) {
          seenMacs.add(mac);
          final isBlk = blockedMacs.contains(mac);
          final online = stateEls.isEmpty || stateEls.first.innerText.isNotEmpty;
          devices.add(
            ConnectedDevice(
              index: idx,
              name: host.isEmpty ? 'جهاز ${idx + 1}' : host,
              ipAddress: ip,
              macAddress: mac,
              isBlocked: isBlk,
              isConnected: online && !isBlk,
              isCurrentDevice: ip == localClientIp,
            ),
          );
          idx++;
        }
      }
    }

    for (final bm in blockedMacs) {
      if (!seenMacs.contains(bm)) {
        devices.add(
          ConnectedDevice(
            index: devices.length,
            name: 'جهاز محظور',
            ipAddress: 'محظور عبر MAC',
            macAddress: bm,
            isBlocked: true,
            isConnected: false,
          ),
        );
      }
    }

    final activeDevs = devices.where((d) => d.isConnected && !d.isBlocked).length;
    final connCount = activeDevs > 0
        ? activeDevs
        : _toInt(_findTag(monDoc, 'CurrentWifiUser'), 0);

    final imei = _findTag(infoDoc, 'Imei');
    final iccid = _findTag(infoDoc, 'Iccid');
    final imsi = _findTag(infoDoc, 'Imsi');
    final modemNum = ModemStatus.extractFirstValidNumber(
      [
        _findTag(infoDoc, 'Msisdn'),
        _findTag(monDoc, 'msisdn'),
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
      networkType: '4G',
      operatorName: _findTag(plmnDoc, 'FullName'),
      signalBars: bars,
      signalPercent: sigPct,
      band: band,
      rsrp: rsrp.isEmpty ? '-' : rsrp,
      rsrq: rsrq.isEmpty ? '-' : rsrq,
      sinr: sinr.isEmpty ? '-' : sinr,
      rssi: rssi.isEmpty ? '-' : rssi,
      pci: pci.isEmpty ? '-' : pci,
      cellId: cellId.isEmpty ? '-' : cellId,
      wanConnected: _findTag(monDoc, 'ConnectionStatus') == '901',
      modemPhoneNumber: modemNum,
      deviceModel: _findTag(infoDoc, 'DeviceName').isEmpty
          ? modelHint
          : _findTag(infoDoc, 'DeviceName'),
      wanIp: _findTag(infoDoc, 'WanIPAddress').isEmpty
          ? '-'
          : _findTag(infoDoc, 'WanIPAddress'),
      lanIp: gatewayIp,
      macAddress: _findTag(infoDoc, 'MacAddress1').isEmpty
          ? '-'
          : _findTag(infoDoc, 'MacAddress1'),
      imei: imei.isEmpty ? '-' : imei,
      iccid: iccid.isEmpty ? '-' : iccid,
      imsi: imsi.isEmpty ? '-' : imsi,
      softwareVersion: _findTag(infoDoc, 'SoftwareVersion').isEmpty
          ? '-'
          : _findTag(infoDoc, 'SoftwareVersion'),
      hardwareVersion: _findTag(infoDoc, 'HardwareVersion').isEmpty
          ? '-'
          : _findTag(infoDoc, 'HardwareVersion'),
      ssid: _findTag(wlanDoc, 'WifiSsid'),
      wifiPassword: _findTag(wlanDoc, 'WifiWpaPreSharedKey'),
      isHiddenSsid: _findTag(wlanDoc, 'WifiHide') == '1',
      maxClients: _toInt(_findTag(monDoc, 'MaxWifiUser'), 10),
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
        hasMaxClients: false,
        hasHideSsid: true,
        hasLcdQrToggle: false,
        hasDeviceBlock: true,
        hasDeviceRename: false,
        hasReboot: true,
        hasPowerOff: true,
        hasAdminPassword: false,
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
    final keyTag = password.isNotEmpty
        ? '<WifiWpaPreSharedKey>${const HtmlEscape().convert(password)}</WifiWpaPreSharedKey>'
        : '';
    return _apiPost(
      '/api/wlan/basic-settings',
      '<request>'
      '<WifiSsid>${const HtmlEscape().convert(ssid)}</WifiSsid>'
      '<WifiHide>${hideSsid ? 1 : 0}</WifiHide>'
      '$keyTag'
      '</request>',
    );
  }

  @override
  Future<bool> setBandConfig({
    required bool manualMode,
    required String networkMode,
    required List<String> bands,
  }) async {
    String netModeCode = '00';
    if (networkMode == '4g_only') netModeCode = '03';
    if (networkMode == '3g_only') netModeCode = '02';

    String lteBandHex = '7FFFFFFFFFFFFFFF';
    if (manualMode && bands.isNotEmpty) {
      BigInt mask = BigInt.zero;
      for (final b in bands) {
        final n = int.tryParse(b.toUpperCase().replaceAll('B', '').trim());
        if (n != null && n >= 1 && n <= 64) {
          mask |= (BigInt.one << (n - 1));
        }
      }
      if (mask > BigInt.zero) {
        lteBandHex = mask.toRadixString(16).toUpperCase();
      }
    }
    return _apiPost(
      '/api/net/net-mode',
      '<request>'
      '<NetworkMode>$netModeCode</NetworkMode>'
      '<NetworkBand>3FFFFFFF</NetworkBand>'
      '<LTEBand>$lteBandHex</LTEBand>'
      '</request>',
    );
  }

  Future<bool> _updateHiLinkMacFilter(String mac, bool block) async {
    final norm = mac.trim().toUpperCase();
    final currentDoc = await _apiGet('/api/wlan/mac-filter');
    final list = _parseBlockedMacs(currentDoc);
    if (block) {
      if (!list.contains(norm)) {
        if (list.length >= 10) return false;
        list.add(norm);
      }
    } else {
      list.removeWhere((m) => m == norm);
    }
    final sb = StringBuffer('<request><WifiMacFilterStatus>2</WifiMacFilterStatus>');
    for (int i = 0; i < 10; i++) {
      final val = i < list.length ? list[i] : '';
      sb.write('<WifiMacFilterMac$i>$val</WifiMacFilterMac$i>');
    }
    sb.write('</request>');
    final ok = await _apiPost('/api/wlan/mac-filter', sb.toString());
    if (!ok) return false;
    await Future.delayed(const Duration(seconds: 2));
    final verifyDoc = await _apiGet('/api/wlan/mac-filter');
    final verifiedList = _parseBlockedMacs(verifyDoc);
    return block ? verifiedList.contains(norm) : !verifiedList.contains(norm);
  }

  @override
  Future<bool> blockMacAddress(String macAddress) =>
      _updateHiLinkMacFilter(macAddress, true);

  @override
  Future<bool> unblockMacAddress(String macAddress) =>
      _updateHiLinkMacFilter(macAddress, false);

  @override
  Future<bool> setDeviceBlock({
    required ConnectedDevice device,
    required bool block,
  }) {
    if (device.isCurrentDevice && block) return Future.value(false);
    return _updateHiLinkMacFilter(device.macAddress, block);
  }

  @override
  Future<bool> setSpeedLimit({
    required bool enabled,
    required int downloadMbps,
    required int uploadMbps,
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
  Future<bool> rebootModem() async =>
      _apiPost('/api/device/control', '<request><Control>1</Control></request>');

  @override
  Future<bool> powerOffModem() async =>
      _apiPost('/api/device/control', '<request><Control>4</Control></request>');

  @override
  Future<List<SmsMessage>> fetchSmsInbox() async => [];
}
