import '../../models/modem_models.dart';

abstract class ModemAdapter {
  String get gatewayIp;
  String get localClientIp;
  ModemFamily get family;
  String get protocolName;

  Future<bool> login(String username, String password);
  Future<void> logout();

  Future<ModemStatus> fetchStatus({bool forceFullRefresh = false});

  Future<bool> updateWifi({
    required String ssid,
    required String password,
    required bool hideSsid,
    required int maxClients,
  });

  Future<bool> setBandConfig({
    required bool manualMode,
    required String networkMode, // 'auto', '4g_only', '3g_only'
    required List<String> bands, // ['B28', 'B3']
  });

  Future<bool> setSpeedLimit({
    required bool enabled,
    required int downloadMbps,
    required int uploadMbps,
  });

  Future<bool> setDeviceBlock({
    required ConnectedDevice device,
    required bool block,
  });

  Future<bool> renameDevice({
    required ConnectedDevice device,
    required String newName,
  });

  Future<bool> setLcdQrCode(bool visibleOnModemScreen);

  Future<bool> changeAdminPassword(String newPassword);

  Future<bool> rebootModem();

  Future<bool> powerOffModem();

  Future<List<SmsMessage>> fetchSmsInbox();
}
