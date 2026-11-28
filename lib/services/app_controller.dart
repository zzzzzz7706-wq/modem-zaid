import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/modem_models.dart';
import '../theme/app_theme.dart';
import 'adapters/modem_adapter.dart';
import 'modem_detector.dart';
import 'wifi_network_binder.dart';

class AppController extends ChangeNotifier {
  AppPalette _palette = AppPalette.midnightRoyal;
  AppPalette get palette => _palette;

  ModemIdentity _identity = const ModemIdentity(
    gatewayIp: '192.168.43.1',
    localClientIp: '',
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

  bool _isConnectionLost = false;
  bool get isConnectionLost => _isConnectionLost;

  DateTime? _lastUpdatedAt;
  DateTime? get lastUpdatedAt => _lastUpdatedAt;

  int _consecutivePollFailures = 0;

  String? _lastError;
  String? get lastError => _lastError;

  String _savedUsername = 'admin';
  String get savedUsername => _savedUsername;

  String _savedPassword = 'admin';
  String get savedPassword => _savedPassword;

  String _customGatewayIp = '';
  String get customGatewayIp => _customGatewayIp;

  /// Real service number of the CURRENTLY connected & logged-in modem only.
  /// Never falls back to a number remembered from a previous modem.
  String get currentModemNumber =>
      _isAuthenticated ? _status.modemPhoneNumber : '';

  List<String> _savedPhones = [];
  List<String> get savedPhones => _savedPhones;

  final List<String> _alerts = [];
  List<String> get alerts => List.unmodifiable(_alerts);

  List<ShortcutItemConfig> _shortcuts = const [
    ShortcutItemConfig(id: 'wifi', title: 'إعدادات الواي فاي', enabled: true),
    ShortcutItemConfig(id: 'reboot', title: 'إعادة تشغيل المودم', enabled: true),
    ShortcutItemConfig(id: 'speed', title: 'تحديد السرعة', enabled: true),
    ShortcutItemConfig(id: 'admin_pass', title: 'كلمة مرور المدير', enabled: true),
    ShortcutItemConfig(id: 'devices', title: 'إدارة وحظر الأجهزة', enabled: true),
    ShortcutItemConfig(id: 'power_off', title: 'إيقاف التشغيل', enabled: true),
    ShortcutItemConfig(id: 'band_lock', title: 'تثبيت الترددات', enabled: true),
    ShortcutItemConfig(id: 'wifi_qr', title: 'باركود الواي فاي', enabled: true),
    ShortcutItemConfig(id: 'sms', title: 'رسائل المودم', enabled: true),
  ];
  List<ShortcutItemConfig> get shortcuts => _shortcuts;

  Timer? _pollTimer;
  Timer? _clockTimer;
  Timer? _wifiWatchTimer;
  String _lastSeenWifiSig = '';
  bool _lowBatteryNotified = false;
  bool _pollInFlight = false;

  String get freshnessStatusArabic {
    if (_isConnectionLost) {
      return 'انقطع الاتصال بالمودم — البيانات المعروضة آخر قراءة مسجلة، جاري إعادة الاتصال...';
    }
    if (_lastUpdatedAt == null) return 'جاري التحديث...';
    final diff = DateTime.now().difference(_lastUpdatedAt!).inSeconds;
    if (diff <= 6) return 'مباشر • متصل بالمودم الآن';
    return 'آخر تحديث قبل $diff ثانية';
  }

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final palId = prefs.getString('palette_id') ?? 'midnight';
    _palette = AppPalette.byId(palId);
    _savedUsername = prefs.getString('saved_username') ?? 'admin';
    _savedPassword = prefs.getString('saved_password') ?? 'admin';
    _customGatewayIp = prefs.getString('custom_gateway_ip') ?? '';
    // Older versions persisted the previous modem's number and showed it for
    // any modem – remove it so only the live number is ever displayed.
    await prefs.remove('last_modem_number');
    _savedPhones = prefs.getStringList('saved_yemen4g_phones') ?? [];

    final disabledIds = prefs.getStringList('disabled_shortcuts') ?? [];
    if (disabledIds.isNotEmpty) {
      _shortcuts = _shortcuts
          .map((s) => s.copyWith(enabled: !disabledIds.contains(s.id)))
          .toList();
    }

    notifyListeners();
    await detectModem();
    _startWifiDiscoveryWatcher();
  }

  void _startWifiDiscoveryWatcher() {
    _wifiWatchTimer?.cancel();
    _wifiWatchTimer = Timer.periodic(const Duration(seconds: 4), (_) async {
      if (_isAuthenticated || _isDetecting || _isLoggingIn) return;
      try {
        final wifi = await WifiNetworkBinder.query(bind: true);
        final sig = '${wifi.connected}|${wifi.gateway}|${wifi.localIp}';
        if (sig != _lastSeenWifiSig || (wifi.connected && !_identity.reachable)) {
          _lastSeenWifiSig = sig;
          await detectModem();
        }
      } catch (_) {}
    });
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

  bool _isSameModem(ModemIdentity a, ModemIdentity b) =>
      a.gatewayIp == b.gatewayIp && a.family == b.family;

  /// Clears every value read from a previous modem so nothing stale
  /// (number, devices, signal...) can appear for a different modem.
  void _clearModemData() {
    _status = const ModemStatus();
    _lastUpdatedAt = null;
    _isConnectionLost = false;
    _consecutivePollFailures = 0;
    _lowBatteryNotified = false;
  }

  Future<void> detectModem({bool keepLastError = false}) async {
    _isDetecting = true;
    if (!keepLastError) _lastError = null;
    notifyListeners();
    try {
      final wifi = await WifiNetworkBinder.query(bind: true);
      _lastSeenWifiSig = '${wifi.connected}|${wifi.gateway}|${wifi.localIp}';
      final result = await ModemDetector.autoDetect(
        preferredIp: _customGatewayIp.isEmpty ? null : _customGatewayIp,
      );
      if (!_isSameModem(_identity, result.identity) ||
          !result.identity.reachable) {
        if (!_isAuthenticated) _clearModemData();
      }
      _identity = result.identity;
      _adapter = result.adapter;
    } catch (_) {
      if (!keepLastError) _lastError = 'تعذر فحص الشبكة اللاسلكية';
    } finally {
      _isDetecting = false;
      notifyListeners();
    }
  }

  /// Uses the model name read after login (e.g. `device_name`) when it is more
  /// precise than what the unauthenticated scan found.
  void _refineModelName(ModemStatus s) {
    if (s.deviceModel.isEmpty) return;
    final better = ModemDetector.improveModelName(_identity, s.deviceModel);
    if (better != null) {
      _identity = _identity.copyWith(modelName: better);
    }
  }

  Future<bool> login(String username, String password) async {
    _isLoggingIn = true;
    _lastError = null;
    notifyListeners();

    try {
      // Always re-bind to Wi-Fi and verify the active modem fingerprint before login
      // so switching between two modems (even both on 192.168.0.1 or in Airplane Mode)
      // never reuses a stale adapter.
      await detectModem(keepLastError: true);

      if (_adapter == null || !_identity.reachable) {
        _lastError = _identity.statusMessage.isNotEmpty
            ? _identity.statusMessage
            : 'تعذر العثور على مودم متصل عبر الواي فاي. تأكد من الاتصال بشبكة الواي فاي الخاصة بالمودم.';
        return false;
      }

      // Password-only modems: the login screen sends `admin` internally.
      final effectiveUser = username.trim().isEmpty ? 'admin' : username.trim();

      final outcome = await _adapter!.loginWithOutcome(effectiveUser, password);
      if (!outcome.success) {
        _lastError = outcome.message.isNotEmpty
            ? outcome.message
            : 'تعذر تسجيل الدخول إلى المودم.';
        return false;
      }

      _savedUsername = effectiveUser;
      _savedPassword = password;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('saved_username', _savedUsername);
      await prefs.setString('saved_password', _savedPassword);

      // Fresh session: never carry values from a previous modem/session.
      _clearModemData();
      _status = await _adapter!.fetchStatus(forceFullRefresh: false);
      _refineModelName(_status);
      _lastUpdatedAt = DateTime.now();
      _isConnectionLost = false;
      _consecutivePollFailures = 0;
      await _recordDetectedModemNumber(_status.modemPhoneNumber);
      _evaluateAlerts(_status);
      _isAuthenticated = true;
      _startLivePolling();

      // Load complete device list, MAC blacklist, and secondary settings immediately after entry
      Future.microtask(() => refreshStatus(silent: true, full: true));
      return true;
    } catch (_) {
      _lastError =
          'تعذر إكمال قراءة بيانات المودم (${_identity.gatewayIp}). يرجى المحاولة مرة أخرى.';
      return false;
    } finally {
      _isLoggingIn = false;
      notifyListeners();
    }
  }

  /// Adds the live number to the balance-inquiry quick list (user convenience).
  Future<void> _recordDetectedModemNumber(String num) async {
    final clean = num.trim();
    if (clean.isEmpty) return;
    if (_savedPhones.isNotEmpty && _savedPhones.first == clean) return;
    _savedPhones = [clean, ..._savedPhones.where((p) => p != clean)]
        .take(5)
        .toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('saved_yemen4g_phones', _savedPhones);
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
    } catch (_) {}
    return login(_savedUsername, _savedPassword);
  }

  Future<void> logout() async {
    _stopLivePolling();
    try {
      await _adapter?.logout();
    } catch (_) {}
    _isAuthenticated = false;
    _clearModemData();
    notifyListeners();
    await detectModem();
  }

  void _startLivePolling() {
    _stopLivePolling();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!_pollInFlight && !_isBusyAction) {
        refreshStatus(silent: true);
      }
    });
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      // Never advance clock on stale/disconnected data
      if (_isAuthenticated &&
          !_isConnectionLost &&
          _status.uptimeSeconds > 0) {
        _status = _status.copyWithUptime(_status.uptimeSeconds + 1);
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
    _pollInFlight = true;
    if (!silent) {
      _isBusyAction = true;
      notifyListeners();
    }
    try {
      if (_isConnectionLost) {
        // Attempt automatic gateway re-discovery & re-authentication
        final det = await ModemDetector.autoDetect(
          preferredIp: _customGatewayIp.isEmpty ? null : _customGatewayIp,
        );
        if (det.identity.reachable) {
          if (!_isSameModem(_identity, det.identity)) {
            // A different modem: drop everything shown from the old one.
            _clearModemData();
            _isConnectionLost = true;
          }
          _identity = det.identity;
          _adapter = det.adapter;
          final reauth =
              await _adapter!.loginWithOutcome(_savedUsername, _savedPassword);
          if (!reauth.success) {
            throw const SocketException('Re-auth pending');
          }
        }
      }

      final next = await _adapter!.fetchStatus(forceFullRefresh: full);
      _status = next;
      _refineModelName(next);
      _lastUpdatedAt = DateTime.now();
      if (_isConnectionLost) {
        _isConnectionLost = false;
        _addAlert('تمت استعادة الاتصال المباشر بالمودم (${_identity.gatewayIp}).');
      }
      _consecutivePollFailures = 0;

      if (next.modemPhoneNumber.isNotEmpty) {
        await _recordDetectedModemNumber(next.modemPhoneNumber);
      }
      _evaluateAlerts(next);
    } catch (_) {
      _consecutivePollFailures++;
      if (_consecutivePollFailures >= 2) {
        _isConnectionLost = true;
      }
    } finally {
      _pollInFlight = false;
      if (!silent) {
        _isBusyAction = false;
      }
      notifyListeners();
    }
  }

  void _evaluateAlerts(ModemStatus s) {
    if (s.hasBattery &&
        s.batteryPercent <= 15 &&
        !s.isCharging &&
        !_lowBatteryNotified) {
      _lowBatteryNotified = true;
      _addAlert(
          'بطارية المودم منخفضة (${s.batteryPercent}%) — يُنصح بتوصيل الشاحن.');
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

  // --- Verified Modem Control Actions ---

  static String? normalizeMacInput(String input) {
    final cleaned = input
        .trim()
        .toUpperCase()
        .replaceAll('-', ':')
        .replaceAll(' ', '');
    if (RegExp(r'^([0-9A-F]{2}:){5}[0-9A-F]{2}$').hasMatch(cleaned)) {
      return cleaned;
    }
    return null;
  }

  Future<(bool, String)> toggleBlockDevice(
      ConnectedDevice device, bool block) async {
    if (_adapter == null) return (false, 'لا يوجد اتصال بالمودم.');
    if (block && device.isCurrentDevice) {
      return (false, 'لا يمكن حظر هاتفك الحالي المتصل بالمودم.');
    }
    if (!_status.capabilities.hasDeviceBlock) {
      return (false, 'هذا الطراز من المودم لا يدعم حظر الأجهزة عبر البروتوكول الحالي.');
    }

    _isBusyAction = true;
    notifyListeners();
    try {
      final verified =
          await _adapter!.setDeviceBlock(device: device, block: block);
      if (verified) {
        await refreshStatus(silent: true, full: true);
        final msg = block
            ? 'تم تنفيذ وتأكيد حظر الجهاز (${device.name} • ${device.macAddress}) من المودم فعلياً.'
            : 'تم فك الحظر عن الجهاز (${device.name} • ${device.macAddress}) وتأكيده من المودم.';
        _addAlert(msg);
        return (true, msg);
      }
      return (
        false,
        block
            ? 'لم يؤكد المودم إضافة الجهاز لقائمة الحظر — حاول مرة أخرى.'
            : 'لم يؤكد المودم إزالة الجهاز من قائمة الحظر — حاول مرة أخرى.'
      );
    } catch (_) {
      return (false, 'حدث خطأ أثناء إرسال أمر الحظر إلى المودم.');
    } finally {
      _isBusyAction = false;
      notifyListeners();
    }
  }

  Future<(bool, String)> blockByMacAddress(String rawMac) async {
    if (_adapter == null) return (false, 'لا يوجد اتصال بالمودم.');
    final normMac = normalizeMacInput(rawMac);
    if (normMac == null) {
      return (
        false,
        'صيغة عنوان MAC غير صحيحة. يرجى كتابته بالصيغة: AA:BB:CC:DD:EE:FF'
      );
    }
    if (_status.currentDeviceMac.isNotEmpty &&
        normMac == _status.currentDeviceMac.toUpperCase()) {
      return (false, 'لا يمكنك حظر عنوان MAC الخاص بهاتفك الحالي!');
    }

    _isBusyAction = true;
    notifyListeners();
    try {
      final verified = await _adapter!.blockMacAddress(normMac);
      if (verified) {
        await refreshStatus(silent: true, full: true);
        final msg = 'تم حظر العنوان ($normMac) وتأكيد إضافته لقائمة الحظر في المودم.';
        _addAlert(msg);
        return (true, msg);
      }
      return (
        false,
        'تعذر تأكيد حظر العنوان ($normMac) من المودم (الحد الأقصى 10 عناوين أو رفض المودم العملية).'
      );
    } finally {
      _isBusyAction = false;
      notifyListeners();
    }
  }

  Future<(bool, String)> unblockByMacAddress(String rawMac) async {
    if (_adapter == null) return (false, 'لا يوجد اتصال بالمودم.');
    final normMac = normalizeMacInput(rawMac);
    if (normMac == null) return (false, 'عنوان MAC غير صالح.');

    _isBusyAction = true;
    notifyListeners();
    try {
      final verified = await _adapter!.unblockMacAddress(normMac);
      if (verified) {
        await refreshStatus(silent: true, full: true);
        final msg = 'تم إلغاء حظر العنوان ($normMac) وتأكيده من المودم بنجاح.';
        _addAlert(msg);
        return (true, msg);
      }
      return (false, 'تعذر تأكيد إزالة الحظر من المودم.');
    } finally {
      _isBusyAction = false;
      notifyListeners();
    }
  }

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
        _addAlert('تم تثبيت ترددات الأبراج ($desc) وتأكيدها من المودم.');
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
        _addAlert('تم تغيير كلمة مرور مدير المودم وتأكيدها بنجاح.');
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
      _isConnectionLost = true;
      _addAlert('جاري إعادة تشغيل المودم... سيتم إعادة الاتصال تلقائياً عند جهوزيته.');
      notifyListeners();
    }
    return ok;
  }

  Future<bool> powerOffModem() async {
    if (_adapter == null) return false;
    final ok = await _adapter!.powerOffModem();
    if (ok) {
      _isConnectionLost = true;
      _addAlert('تم إرسال أمر إيقاف تشغيل المودم بنجاح.');
      notifyListeners();
    }
    return ok;
  }

  Future<List<SmsMessage>> loadSmsInbox() async {
    if (_adapter == null) return [];
    return _adapter!.fetchSmsInbox();
  }

  Future<int?> measureTcpPing(String host, int port) async {
    final sw = Stopwatch()..start();
    try {
      final isGateway = host == _identity.gatewayIp;
      final socket = isGateway
          ? await ModemDetector.connectLanSocket(
              host,
              port,
              localIp: _identity.localClientIp,
              timeout: const Duration(milliseconds: 2500),
            )
          : await Socket.connect(
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
    _wifiWatchTimer?.cancel();
    _stopLivePolling();
    super.dispose();
  }
}
