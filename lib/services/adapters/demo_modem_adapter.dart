import '../../models/modem_models.dart';
import 'modem_adapter.dart';

/// Interactive Demo Adapter for offline preview when away from a physical modem.
class DemoModemAdapter implements ModemAdapter {
  @override
  final String gatewayIp;

  @override
  final String localClientIp;

  int _battery = 74;
  bool _charging = false;
  int _rxBytes = 690171904;
  int _txBytes = 254174822;
  int _uptime = 12977;
  String _ssid = 'K';
  String _wifiPass = '1234567890';
  bool _hideSsid = false;
  int _maxClients = 10;
  bool _lcdQr = false;
  bool _manualBand = true;
  String _networkMode = '4g_only';
  List<String> _bands = ['B28'];
  bool _speedLimit = false;
  int _dlMbps = 20;
  int _ulMbps = 5;
  String _adminPass = 'admin';

  late List<ConnectedDevice> _devices;
  final List<String> _blockedMacs = [];

  DemoModemAdapter({
    this.gatewayIp = '192.168.43.1',
    this.localClientIp = '192.168.43.200',
  }) {
    _devices = [
      ConnectedDevice(
        index: 0,
        name: 'S21-Ultra',
        ipAddress: localClientIp,
        macAddress: '06:A7:07:DA:10:03',
        connectionType: 'Wi-Fi',
        connectedDuration: '03:36:15',
        isCurrentDevice: true,
        isConnected: true,
      ),
      const ConnectedDevice(
        index: 1,
        name: 'Galaxy-Tab-S9',
        ipAddress: '192.168.43.142',
        macAddress: '58:CB:52:41:09:AF',
        connectionType: 'Wi-Fi',
        connectedDuration: '01:14:22',
        isCurrentDevice: false,
        isConnected: true,
      ),
      const ConnectedDevice(
        index: 2,
        name: 'Laptop-Work',
        ipAddress: 'غير متصل',
        macAddress: 'B4:2E:99:1A:44:C0',
        connectionType: 'Wi-Fi',
        isCurrentDevice: false,
        isConnected: false,
      ),
    ];
  }

  @override
  ModemFamily get family => ModemFamily.demo;

  @override
  String get protocolName => 'وضع المحاكاة التفاعلي';

  @override
  Future<LoginOutcome> loginWithOutcome(String username, String password) async {
    await Future.delayed(const Duration(milliseconds: 280));
    return const LoginOutcome(success: true);
  }

  @override
  Future<void> logout() async {}

  @override
  Future<ModemStatus> fetchStatus({bool forceFullRefresh = false}) async {
    _uptime += 3;
    _rxBytes += 84 * 1024;
    _txBytes += 22 * 1024;

    final merged = _devices.map((d) {
      final blk = _blockedMacs.contains(d.macAddress.toUpperCase());
      return ConnectedDevice(
        index: d.index,
        name: d.name,
        ipAddress: d.ipAddress,
        macAddress: d.macAddress.toUpperCase(),
        connectionType: d.connectionType,
        connectedDuration: d.connectedDuration,
        isBlocked: blk,
        isCurrentDevice: d.isCurrentDevice,
        isConnected: d.isConnected && !blk,
      );
    }).toList();

    for (final bm in _blockedMacs) {
      if (!merged.any((d) => d.macAddress == bm)) {
        merged.add(
          ConnectedDevice(
            index: merged.length,
            name: 'جهاز محظور يدوياً',
            ipAddress: 'محظور عبر MAC',
            macAddress: bm,
            isBlocked: true,
            isConnected: false,
          ),
        );
      }
    }

    final activeDevices =
        merged.where((d) => d.isConnected && !d.isBlocked).length;

    return ModemStatus(
      hasBattery: true,
      batteryPercent: _battery,
      isCharging: _charging,
      rxBytes: _rxBytes,
      txBytes: _txBytes,
      totalBytes: _rxBytes + _txBytes,
      rxRateBps: 420 * 1024,
      txRateBps: 95 * 1024,
      uptimeSeconds: _uptime,
      networkType: _networkMode == '3g_only' ? '3G' : '4G',
      operatorName: 'يمن فورجي (Yemen 4G)',
      signalBars: 5,
      signalPercent: 88,
      band: _bands.isNotEmpty ? _bands.first : 'B28',
      rsrp: '-81 dBm',
      rsrq: '-8.0 dB',
      sinr: '19 dB',
      rssi: '-57 dBm',
      pci: '214',
      cellId: '4180923',
      wanConnected: true,
      modemPhoneNumber: '106406416',
      deviceModel: 'MIFI-L818A (محاكاة)',
      wanIp: '100.101.226.253',
      lanIp: gatewayIp,
      macAddress: 'C8:3A:35:7B:40:11',
      currentDeviceMac: '06:A7:07:DA:10:03',
      imei: '864920051938472',
      iccid: '8996703001928374651',
      imsi: '421100102210464',
      softwareVersion: 'V2.1.4_Yemen4G',
      hardwareVersion: 'REV_B28_V3',
      ssid: _ssid,
      wifiPassword: _wifiPass,
      isHiddenSsid: _hideSsid,
      securityMode: 'WPA2-PSK',
      cipherMode: 'AES-CCMP',
      maxClients: _maxClients,
      connectedDevicesCount: activeDevices,
      lcdQrEnabled: _lcdQr,
      isManualBand: _manualBand,
      networkMode: _networkMode,
      selectedBands: List.from(_bands),
      supportedBands: const [
        'B3',
        'B28',
        'B1',
        'B8',
        'B38',
        'B40',
        'B41'
      ],
      speedLimitEnabled: _speedLimit,
      downloadLimitMbps: _dlMbps,
      uploadLimitMbps: _ulMbps,
      adminUsername: 'admin',
      adminPassword: _adminPass,
      devices: merged,
      blockedMacs: List.from(_blockedMacs),
      capabilities: const ModemCapabilities(),
    );
  }

  @override
  Future<bool> updateWifi({
    required String ssid,
    required String password,
    required bool hideSsid,
    required int maxClients,
  }) async {
    _ssid = ssid;
    if (password.isNotEmpty) _wifiPass = password;
    _hideSsid = hideSsid;
    _maxClients = maxClients;
    return true;
  }

  @override
  Future<bool> setBandConfig({
    required bool manualMode,
    required String networkMode,
    required List<String> bands,
  }) async {
    _manualBand = manualMode;
    _networkMode = networkMode;
    _bands = bands.isEmpty ? ['B28'] : List.from(bands);
    return true;
  }

  @override
  Future<bool> setSpeedLimit({
    required bool enabled,
    required int downloadMbps,
    required int uploadMbps,
  }) async {
    _speedLimit = enabled;
    _dlMbps = downloadMbps;
    _ulMbps = uploadMbps;
    return true;
  }

  @override
  Future<bool> blockMacAddress(String macAddress) async {
    final norm = macAddress.trim().toUpperCase();
    if (norm == '06:A7:07:DA:10:03') return false;
    if (!_blockedMacs.contains(norm)) _blockedMacs.add(norm);
    return true;
  }

  @override
  Future<bool> unblockMacAddress(String macAddress) async {
    final norm = macAddress.trim().toUpperCase();
    _blockedMacs.remove(norm);
    return true;
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
    final i = _devices.indexWhere((d) => d.macAddress == device.macAddress);
    if (i != -1) {
      final old = _devices[i];
      _devices[i] = ConnectedDevice(
        index: old.index,
        name: newName,
        ipAddress: old.ipAddress,
        macAddress: old.macAddress,
        connectionType: old.connectionType,
        connectedDuration: old.connectedDuration,
        isBlocked: old.isBlocked,
        isCurrentDevice: old.isCurrentDevice,
        isConnected: old.isConnected,
      );
    }
    return true;
  }

  @override
  Future<bool> setLcdQrCode(bool visibleOnModemScreen) async {
    _lcdQr = visibleOnModemScreen;
    return true;
  }

  @override
  Future<bool> changeAdminPassword(String newPassword) async {
    _adminPass = newPassword;
    return true;
  }

  @override
  Future<bool> rebootModem() async => true;

  @override
  Future<bool> powerOffModem() async => true;

  @override
  Future<List<SmsMessage>> fetchSmsInbox() async {
    return const [
      SmsMessage(
        id: '1',
        sender: 'Yemen 4G',
        content:
            'عزيزي المشترك، تم تجديد باقة يمن فورجي بنجاح. رصيدك الحالي 35 جيجابايت.',
        timestamp: '2026-11-27 09:15',
        isUnread: true,
      ),
    ];
  }
}
