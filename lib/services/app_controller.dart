import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/modem_models.dart';
import '../theme/app_theme.dart';
import 'adapters/modem_adapter.dart';
import 'modem_detector.dart';

class AppController extends ChangeNotifier {
  AppPalette _palette = AppPalette.midnightModmia;
  AppPalette get palette => _palette;

  ModemIdentity _identity = const ModemIdentity(
    gatewayIp: '192.168.43.1',
    localClientIp: '192.168.43.200',
    modelName: 'جاري الفحص...',
    protocolLabel: 'فحص الشبكة',
    family: ModemFamily.notionMifi,
    reachable: false,
  );
  ModemIdentity get identity => _identity;

  ModemAdapter? _adapter;
  ModemStatus _status = const ModemStatus();
  ModemStatus get status => _status;

  bool _isDetecting = false;
  bool get isDetecting => _isDetecting;

  bool _isLoggingIn = false;
  bool get isLoggingIn => _isLoggingIn;

  bool _isAuthenticated = false;
  bool get isAuthenticated => _isAuthenticated;

  bool _isBusyAction = false;
  bool get isBusyAction => _isBusyAction;

  String? _lastError;
  String? get lastError => _lastError;

  String _savedUsername = 'admin';
  String get savedUsername => _savedUsername;

  String _savedPassword = 'admin';
  String get savedPassword => _savedPassword;

  String _customGatewayIp = '';
  String get customGatewayIp => _customGatewayIp;

  List<String> _savedPhones = [];
  List<String> get savedPhones => _savedPhones;

  final List<String> _alerts = [];
  List<String> get alerts => List.unmodifiable(_alerts);

  List<ShortcutItemConfig> _shortcuts = const [
    ShortcutItemConfig(id: 'wifi', title: 'إعدادات الواي فاي', enabled: true),
    ShortcutItemConfig(id: 'reboot', title: 'إعادة تشغيل المودم', enabled: true),
    ShortcutItemConfig(id: 'speed', title: 'تحديد السرعة', enabled: true),
    ShortcutItemConfig(id: 'admin_pass', title: 'كلمة مرور المدير', enabled: true),
    ShortcutItemConfig(id: 'devices', title: 'حماية المتصلين', enabled: true),
    ShortcutItemConfig(id: 'power_off', title: 'إيقاف التشغيل', enabled: true),
    ShortcutItemConfig(id: 'band_lock', title: 'تثبيت الترددات', enabled: true),
    ShortcutItemConfig(id: 'wifi_qr', title: 'باركود الواي فاي', enabled: true),
    ShortcutItemConfig(id: 'sms', title: 'رسائل المودم', enabled: true),
  ];
  List<ShortcutItemConfig> get shortcuts => _shortcuts;

  Timer? _pollTimer;
  Timer? _clockTimer;
  bool _lowBatteryNotified = false;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final palId = prefs.getString('palette_id') ?? 'midnight';
    _palette = AppPalette.byId(palId);
    _savedUsername = prefs.getString('saved_username') ?? 'admin';
    _savedPassword = prefs.getString('saved_password') ?? 'admin';
    _customGatewayIp = prefs.getString('custom_gateway_ip') ?? '';
    _savedPhones = prefs.getStringList('saved_yemen4g_phones') ?? [];

    final disabledIds = prefs.getStringList('disabled_shortcuts') ?? [];
    if (disabledIds.isNotEmpty) {
      _shortcuts = _shortcuts
          .map((s) => s.copyWith(enabled: !disabledIds.contains(s.id)))
          .toList();
    }

    notifyListeners();
    await detectModem();
  }

  Future<void> setPalette(AppPalette newPalette) async {
    _palette = newPalette;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('palette_id', newPalette.id);
  }

  void cyclePalette() {
    final idx = AppPalette.all.indexWhere((p) => p.id == _palette.id);
    final next = AppPalette.all[(idx + 1) % AppPalette.all.length];
    setPalette(next);
  }

  Future<void> toggleShortcut(String id) async {
    _shortcuts = _shortcuts
        .map((s) => s.id == id ? s.copyWith(enabled: !s.enabled) : s)
        .toList();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    final disabled =
        _shortcuts.where((s) => !s.enabled).map((s) => s.id).toList();
    await prefs.setStringList('disabled_shortcuts', disabled);
  }

  Future<void> savePhoneForBalance(String phone) async {
    final clean = phone.trim();
    if (clean.isEmpty) return;
    if (!_savedPhones.contains(clean)) {
      _savedPhones = [clean, ..._savedPhones].take(5).toList();
      notifyListeners();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('saved_yemen4g_phones', _savedPhones);
    }
  }

  Future<void> setCustomGatewayIp(String ip) async {
    _customGatewayIp = ip.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('custom_gateway_ip', _customGatewayIp);
    await detectModem();
  }

  Future<void> detectModem() async {
    _isDetecting = true;
    _lastError = null;
    notifyListeners();
    try {
      final result = await ModemDetector.autoDetect(
        preferredIp: _customGatewayIp.isEmpty ? null : _customGatewayIp,
      );
      _identity = result.identity;
      _adapter = result.adapter;
    } catch (e) {
      _lastError = 'تعذر فحص الشبكة اللاسلكية';
    } finally {
      _isDetecting = false;
      notifyListeners();
    }
  }

  Future<bool> login(String username, String password) async {
    _isLoggingIn = true;
    _lastError = null;
    notifyListeners();

    try {
      if (_adapter == null || !_identity.reachable) {
        await detectModem();
      }
      if (_adapter == null || !_identity.reachable) {
        _lastError =
            'تأكد من اتصال الهاتف بشبكة الواي فاي الخاصة بالمودم (${_identity.gatewayIp}) أو جرب الوضع التجريبي.';
        _isLoggingIn = false;
        notifyListeners();
        return false;
      }

      final ok = await _adapter!.login(username, password);
      if (!ok) {
        _lastError = 'اسم المستخدم أو كلمة المرور غير صحيحة، أو رفض المودم الاتصال.';
        _isLoggingIn = false;
        notifyListeners();
        return false;
      }

      _savedUsername = username.trim().isEmpty ? 'admin' : username.trim();
      _savedPassword = password;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('saved_username', _savedUsername);
      await prefs.setString('saved_password', _savedPassword);

      _status = await _adapter!.fetchStatus(forceFullRefresh: true);
      _evaluateAlerts(_status);
      _isAuthenticated = true;
      _startLivePolling();
      return true;
    } catch (e) {
      _lastError = 'حدث خطأ أثناء الاتصال بالمودم: ${_identity.gatewayIp}';
      return false;
    } finally {
      _isLoggingIn = false;
      notifyListeners();
    }
  }

  Future<bool> authenticateWithBiometrics() async {
    final auth = LocalAuthentication();
    try {
      final canCheck =
          await auth.canCheckBiometrics || await auth.isDeviceSupported();
      if (canCheck) {
        final didAuth = await auth.authenticate(
          localizedReason: 'تسجيل الدخول السريع إلى المودم عبر البصمة',
          options: const AuthenticationOptions(
            biometricOnly: false,
            stickyAuth: true,
          ),
        );
        if (!didAuth) return false;
      }
    } catch (_) {
      // Fallback to saved credentials if device has no lock screen configured
    }
    return login(_savedUsername, _savedPassword);
  }

  Future<void> enterDemoMode() async {
    _isLoggingIn = true;
    _lastError = null;
    notifyListeners();
    final demo = ModemDetector.createDemoMode();
    _identity = demo.identity;
    _adapter = demo.adapter;
    await _adapter!.login('admin', 'admin');
    _status = await _adapter!.fetchStatus(forceFullRefresh: true);
    _evaluateAlerts(_status);
    _isAuthenticated = true;
    _isLoggingIn = false;
    _startLivePolling();
    notifyListeners();
  }

  Future<void> logout() async {
    _stopLivePolling();
    try {
      await _adapter?.logout();
    } catch (_) {}
    _isAuthenticated = false;
    _lowBatteryNotified = false;
    notifyListeners();
    await detectModem();
  }

  void _startLivePolling() {
    _stopLivePolling();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      refreshStatus(silent: true);
    });
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_isAuthenticated && _status.uptimeSeconds > 0) {
        _status = ModemStatus(
          hasBattery: _status.hasBattery,
          batteryPercent: _status.batteryPercent,
          isCharging: _status.isCharging,
          rxBytes: _status.rxBytes,
          txBytes: _status.txBytes,
          totalBytes: _status.totalBytes,
          rxRateBps: _status.rxRateBps,
          txRateBps: _status.txRateBps,
          uptimeSeconds: _status.uptimeSeconds + 1,
          networkType: _status.networkType,
          operatorName: _status.operatorName,
          signalBars: _status.signalBars,
          signalPercent: _status.signalPercent,
          band: _status.band,
          rsrp: _status.rsrp,
          rsrq: _status.rsrq,
          sinr: _status.sinr,
          rssi: _status.rssi,
          pci: _status.pci,
          cellId: _status.cellId,
          wanConnected: _status.wanConnected,
          deviceModel: _status.deviceModel,
          wanIp: _status.wanIp,
          lanIp: _status.lanIp,
          macAddress: _status.macAddress,
          imei: _status.imei,
          iccid: _status.iccid,
          imsi: _status.imsi,
          softwareVersion: _status.softwareVersion,
          hardwareVersion: _status.hardwareVersion,
          ssid: _status.ssid,
          wifiPassword: _status.wifiPassword,
          isHiddenSsid: _status.isHiddenSsid,
          securityMode: _status.securityMode,
          cipherMode: _status.cipherMode,
          maxClients: _status.maxClients,
          connectedDevicesCount: _status.connectedDevicesCount,
          lcdQrEnabled: _status.lcdQrEnabled,
          isManualBand: _status.isManualBand,
          networkMode: _status.networkMode,
          selectedBands: _status.selectedBands,
          supportedBands: _status.supportedBands,
          speedLimitEnabled: _status.speedLimitEnabled,
          downloadLimitMbps: _status.downloadLimitMbps,
          uploadLimitMbps: _status.uploadLimitMbps,
          adminUsername: _status.adminUsername,
          adminPassword: _status.adminPassword,
          devices: _status.devices,
          translatedExtras: _status.translatedExtras,
          capabilities: _status.capabilities,
        );
        notifyListeners();
      }
    });
  }

  void _stopLivePolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _clockTimer?.cancel();
    _clockTimer = null;
  }

  Future<void> refreshStatus({bool silent = false, bool full = false}) async {
    if (_adapter == null) return;
    if (!silent) {
      _isBusyAction = true;
      notifyListeners();
    }
    try {
      final next = await _adapter!.fetchStatus(forceFullRefresh: full);
      _status = next;
      _evaluateAlerts(next);
    } catch (_) {} finally {
      if (!silent) {
        _isBusyAction = false;
      }
      notifyListeners();
    }
  }

  void _evaluateAlerts(ModemStatus s) {
    if (s.hasBattery && s.batteryPercent <= 15 && !s.isCharging && !_lowBatteryNotified) {
      _lowBatteryNotified = true;
      _addAlert('بطارية المودم منخفضة (${s.batteryPercent}%) — يُنصح بتوصيل الشاحن.');
    }
  }

  void _addAlert(String msg) {
    if (!_alerts.contains(msg)) {
      _alerts.insert(0, msg);
      if (_alerts.length > 15) _alerts.removeLast();
    }
  }

  void clearAlerts() {
    _alerts.clear();
    notifyListeners();
  }

  // --- Modem Control Actions ---

  Future<bool> saveWifiSettings({
    required String ssid,
    required String password,
    required bool hideSsid,
    required int maxClients,
  }) async {
    if (_adapter == null) return false;
    _isBusyAction = true;
    notifyListeners();
    try {
      final ok = await _adapter!.updateWifi(
        ssid: ssid,
        password: password,
        hideSsid: hideSsid,
        maxClients: maxClients,
      );
      if (ok) {
        _addAlert('تم تحديث إعدادات الواي فاي ($ssid) بنجاح.');
        await Future.delayed(const Duration(milliseconds: 600));
        await refreshStatus(silent: true, full: true);
      }
      return ok;
    } finally {
      _isBusyAction = false;
      notifyListeners();
    }
  }

  Future<bool> saveBandSettings({
    required bool manualMode,
    required String networkMode,
    required List<String> bands,
  }) async {
    if (_adapter == null) return false;
    _isBusyAction = true;
    notifyListeners();
    try {
      final ok = await _adapter!.setBandConfig(
        manualMode: manualMode,
        networkMode: networkMode,
        bands: bands,
      );
      if (ok) {
        final desc = manualMode ? bands.join(', ') : 'تلقائي';
        _addAlert('تم تحديث ترددات الأبراج ($desc).');
        await Future.delayed(const Duration(seconds: 1));
        await refreshStatus(silent: true, full: true);
      }
      return ok;
    } finally {
      _isBusyAction = false;
      notifyListeners();
    }
  }

  Future<bool> saveSpeedLimit({
    required bool enabled,
    required int downloadMbps,
    required int uploadMbps,
  }) async {
    if (_adapter == null) return false;
    _isBusyAction = true;
    notifyListeners();
    try {
      final ok = await _adapter!.setSpeedLimit(
        enabled: enabled,
        downloadMbps: downloadMbps,
        uploadMbps: uploadMbps,
      );
      if (ok) {
        _addAlert(enabled
            ? 'تم تفعيل تحديد السرعة (${downloadMbps}M تنزيل / ${uploadMbps}M رفع).'
            : 'تم إيقاف تحديد السرعة.');
        await refreshStatus(silent: true, full: true);
      }
      return ok;
    } finally {
      _isBusyAction = false;
      notifyListeners();
    }
  }

  Future<bool> toggleBlockDevice(ConnectedDevice device, bool block) async {
    if (_adapter == null) return false;
    _isBusyAction = true;
    notifyListeners();
    try {
      final ok = await _adapter!.setDeviceBlock(device: device, block: block);
      if (ok) {
        _addAlert(block
            ? 'تم حظر الجهاز (${device.name}) من الشبكة.'
            : 'تم إلغاء حظر الجهاز (${device.name}).');
        await refreshStatus(silent: true, full: true);
      }
      return ok;
    } finally {
      _isBusyAction = false;
      notifyListeners();
    }
  }

  Future<bool> renameConnectedDevice(
      ConnectedDevice device, String newName) async {
    if (_adapter == null) return false;
    _isBusyAction = true;
    notifyListeners();
    try {
      final ok =
          await _adapter!.renameDevice(device: device, newName: newName);
      if (ok) {
        await refreshStatus(silent: true, full: true);
      }
      return ok;
    } finally {
      _isBusyAction = false;
      notifyListeners();
    }
  }

  Future<bool> toggleLcdQrCode(bool visible) async {
    if (_adapter == null) return false;
    _isBusyAction = true;
    notifyListeners();
    try {
      final ok = await _adapter!.setLcdQrCode(visible);
      if (ok) {
        await refreshStatus(silent: true, full: true);
      }
      return ok;
    } finally {
      _isBusyAction = false;
      notifyListeners();
    }
  }

  Future<bool> updateAdminPassword(String newPassword) async {
    if (_adapter == null) return false;
    _isBusyAction = true;
    notifyListeners();
    try {
      final ok = await _adapter!.changeAdminPassword(newPassword);
      if (ok) {
        _savedPassword = newPassword;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('saved_password', newPassword);
        _addAlert('تم تغيير كلمة مرور مدير المودم بنجاح.');
        await refreshStatus(silent: true, full: true);
      }
      return ok;
    } finally {
      _isBusyAction = false;
      notifyListeners();
    }
  }

  Future<bool> rebootModem() async {
    if (_adapter == null) return false;
    final ok = await _adapter!.rebootModem();
    if (ok) {
      _addAlert('جاري إعادة تشغيل المودم...');
    }
    return ok;
  }

  Future<bool> powerOffModem() async {
    if (_adapter == null) return false;
    final ok = await _adapter!.powerOffModem();
    if (ok) {
      _addAlert('تم إرسال أمر إيقاف تشغيل المودم.');
    }
    return ok;
  }

  Future<List<SmsMessage>> loadSmsInbox() async {
    if (_adapter == null) return [];
    return _adapter!.fetchSmsInbox();
  }

  /// Measures TCP handshake latency in ms (works on unrooted Android 10-15).
  Future<int?> measureTcpPing(String host, int port) async {
    final sw = Stopwatch()..start();
    try {
      final socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(milliseconds: 2500),
      );
      sw.stop();
      socket.destroy();
      return sw.elapsedMilliseconds;
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _stopLivePolling();
    super.dispose();
  }
}
