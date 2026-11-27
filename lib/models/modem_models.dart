enum ModemFamily {
  notionMifi,
  zteGoform,
  huaweiHilink,
  universalTranslated,
  demo,
}

class ModemIdentity {
  final String gatewayIp;
  final String localClientIp;
  final String modelName;
  final String protocolLabel;
  final ModemFamily family;
  final bool reachable;

  const ModemIdentity({
    required this.gatewayIp,
    required this.localClientIp,
    required this.modelName,
    required this.protocolLabel,
    required this.family,
    required this.reachable,
  });

  ModemIdentity copyWith({
    String? gatewayIp,
    String? localClientIp,
    String? modelName,
    String? protocolLabel,
    ModemFamily? family,
    bool? reachable,
  }) {
    return ModemIdentity(
      gatewayIp: gatewayIp ?? this.gatewayIp,
      localClientIp: localClientIp ?? this.localClientIp,
      modelName: modelName ?? this.modelName,
      protocolLabel: protocolLabel ?? this.protocolLabel,
      family: family ?? this.family,
      reachable: reachable ?? this.reachable,
    );
  }
}

class ModemCapabilities {
  final bool hasBattery;
  final bool hasSignalMetrics;
  final bool hasBandLock;
  final bool hasSpeedLimit;
  final bool hasWifiEdit;
  final bool hasMaxClients;
  final bool hasHideSsid;
  final bool hasLcdQrToggle;
  final bool hasDeviceBlock;
  final bool hasDeviceRename;
  final bool hasReboot;
  final bool hasPowerOff;
  final bool hasAdminPassword;
  final bool hasSms;

  const ModemCapabilities({
    this.hasBattery = true,
    this.hasSignalMetrics = true,
    this.hasBandLock = true,
    this.hasSpeedLimit = true,
    this.hasWifiEdit = true,
    this.hasMaxClients = true,
    this.hasHideSsid = true,
    this.hasLcdQrToggle = true,
    this.hasDeviceBlock = true,
    this.hasDeviceRename = true,
    this.hasReboot = true,
    this.hasPowerOff = true,
    this.hasAdminPassword = true,
    this.hasSms = true,
  });
}

class ConnectedDevice {
  final int index;
  final String name;
  final String ipAddress;
  final String macAddress;
  final String connectionType;
  final String connectedDuration;
  final bool isBlocked;
  final bool isCurrentDevice;
  final bool isConnected;
  final int rxBytes;
  final int txBytes;
  final String rawNameType;

  const ConnectedDevice({
    required this.index,
    required this.name,
    required this.ipAddress,
    required this.macAddress,
    this.connectionType = 'Wi-Fi',
    this.connectedDuration = '',
    this.isBlocked = false,
    this.isCurrentDevice = false,
    this.isConnected = true,
    this.rxBytes = 0,
    this.txBytes = 0,
    this.rawNameType = '1',
  });
}

class SmsMessage {
  final String id;
  final String sender;
  final String content;
  final String timestamp;
  final bool isUnread;

  const SmsMessage({
    required this.id,
    required this.sender,
    required this.content,
    required this.timestamp,
    this.isUnread = false,
  });
}

class BalanceInfo {
  final String phoneNumber;
  final String remainingBalance;
  final String packageName;
  final String expiryDate;
  final String statusMessage;
  final Map<String, String> details;

  const BalanceInfo({
    required this.phoneNumber,
    required this.remainingBalance,
    this.packageName = '',
    this.expiryDate = '',
    this.statusMessage = '',
    this.details = const {},
  });
}

class ModemStatus {
  // Battery
  final bool hasBattery;
  final int batteryPercent;
  final bool isCharging;

  // Data Usage & Session
  final int rxBytes;
  final int txBytes;
  final int totalBytes;
  final int rxRateBps;
  final int txRateBps;
  final int uptimeSeconds;

  // Signal & Network
  final String networkType; // 4G, 3G, 4G+, 5G
  final String operatorName;
  final int signalBars; // 0..5
  final int signalPercent; // 0..100
  final String band; // e.g. B28, B3
  final String rsrp;
  final String rsrq;
  final String sinr;
  final String rssi;
  final String pci;
  final String cellId;
  final bool wanConnected;

  // Device Details
  final String deviceModel;
  final String wanIp;
  final String lanIp;
  final String macAddress;
  final String imei;
  final String iccid;
  final String imsi;
  final String softwareVersion;
  final String hardwareVersion;

  // Wi-Fi Details
  final String ssid;
  final String wifiPassword;
  final bool isHiddenSsid;
  final String securityMode;
  final String cipherMode;
  final int maxClients;
  final int connectedDevicesCount;
  final bool lcdQrEnabled;

  // Band Lock
  final bool isManualBand;
  final String networkMode; // auto, 4g_only, 3g_only
  final List<String> selectedBands;
  final List<String> supportedBands;

  // Speed Limit
  final bool speedLimitEnabled;
  final int downloadLimitMbps;
  final int uploadLimitMbps;

  // Admin
  final String adminUsername;
  final String adminPassword;

  // Connected Devices & Translated Extras
  final List<ConnectedDevice> devices;
  final Map<String, String> translatedExtras;
  final ModemCapabilities capabilities;

  const ModemStatus({
    this.hasBattery = true,
    this.batteryPercent = 0,
    this.isCharging = false,
    this.rxBytes = 0,
    this.txBytes = 0,
    this.totalBytes = 0,
    this.rxRateBps = 0,
    this.txRateBps = 0,
    this.uptimeSeconds = 0,
    this.networkType = '4G',
    this.operatorName = 'Yemen 4G',
    this.signalBars = 4,
    this.signalPercent = 80,
    this.band = 'B28',
    this.rsrp = '-',
    this.rsrq = '-',
    this.sinr = '-',
    this.rssi = '-',
    this.pci = '-',
    this.cellId = '-',
    this.wanConnected = true,
    this.deviceModel = 'Modem 4G',
    this.wanIp = '-',
    this.lanIp = '192.168.43.1',
    this.macAddress = '-',
    this.imei = '-',
    this.iccid = '-',
    this.imsi = '-',
    this.softwareVersion = '-',
    this.hardwareVersion = '-',
    this.ssid = 'Yemen4G',
    this.wifiPassword = '',
    this.isHiddenSsid = false,
    this.securityMode = 'WPA2-PSK',
    this.cipherMode = 'AES-CCMP',
    this.maxClients = 10,
    this.connectedDevicesCount = 1,
    this.lcdQrEnabled = false,
    this.isManualBand = false,
    this.networkMode = 'auto',
    this.selectedBands = const [],
    this.supportedBands = const ['B3', 'B28', 'B1', 'B7', 'B8', 'B20', 'B38', 'B40', 'B41'],
    this.speedLimitEnabled = false,
    this.downloadLimitMbps = 10,
    this.uploadLimitMbps = 5,
    this.adminUsername = 'admin',
    this.adminPassword = '',
    this.devices = const [],
    this.translatedExtras = const {},
    this.capabilities = const ModemCapabilities(),
  });

  String get signalQualityArabic {
    if (signalPercent >= 75) return 'ممتازة';
    if (signalPercent >= 50) return 'جيدة جداً';
    if (signalPercent >= 30) return 'متوسطة';
    return 'ضعيفة';
  }

  String get formattedUptimeClock {
    final hrs = uptimeSeconds ~/ 3600;
    final mins = (uptimeSeconds % 3600) ~/ 60;
    final secs = uptimeSeconds % 60;
    return '${hrs.toString().padLeft(2, '0')}:${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  String get formattedSessionHours {
    final hours = uptimeSeconds / 3600.0;
    if (hours < 0.1 && uptimeSeconds > 0) {
      return '${(uptimeSeconds ~/ 60)} د';
    }
    return '${hours.toStringAsFixed(1)} س';
  }

  static String formatBytesCompact(int bytes) {
    if (bytes <= 0) return '0 MB';
    final mb = bytes / (1024.0 * 1024.0);
    if (mb >= 1024) {
      final gb = mb / 1024.0;
      return '${gb.toStringAsFixed(2)} GB';
    }
    if (mb >= 100) {
      return '${mb.round()} MB';
    }
    return '${mb.toStringAsFixed(1)} MB';
  }

  static String formatBytesArabicDetailed(int bytes) {
    if (bytes <= 0) return '0.0 م.بايت';
    final mb = bytes / (1024.0 * 1024.0);
    if (mb >= 1024) {
      final gb = mb / 1024.0;
      return '${gb.toStringAsFixed(2)} ج.بايت';
    }
    return '${mb.toStringAsFixed(1)} م.بايت';
  }

  static String formatSpeed(int bps) {
    if (bps <= 0) return '0 KB/s';
    if (bps < 1024) return '$bps B/s';
    if (bps < 1024 * 1024) {
      return '${(bps / 1024.0).toStringAsFixed(1)} KB/s';
    }
    return '${(bps / (1024.0 * 1024.0)).toStringAsFixed(2)} MB/s';
  }
}

class ShortcutItemConfig {
  final String id;
  final String title;
  final bool enabled;

  const ShortcutItemConfig({
    required this.id,
    required this.title,
    this.enabled = true,
  });

  ShortcutItemConfig copyWith({bool? enabled}) {
    return ShortcutItemConfig(
      id: id,
      title: title,
      enabled: enabled ?? this.enabled,
    );
  }
}
