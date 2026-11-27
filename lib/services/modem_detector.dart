import 'dart:convert';
import 'dart:io';
import '../models/modem_models.dart';
import 'adapters/demo_modem_adapter.dart';
import 'adapters/huawei_hilink_adapter.dart';
import 'adapters/modem_adapter.dart';
import 'adapters/notion_mifi_adapter.dart';
import 'adapters/universal_translator_adapter.dart';
import 'adapters/zte_goform_adapter.dart';

class DetectionResult {
  final ModemIdentity identity;
  final ModemAdapter adapter;

  const DetectionResult({
    required this.identity,
    required this.adapter,
  });
}

class ModemDetector {
  static const List<String> commonGateways = [
    '192.168.43.1',
    '192.168.0.1',
    '192.168.8.1',
    '192.168.1.1',
    '192.168.225.1',
    '192.168.100.1',
    '192.168.2.1',
    '192.168.10.1',
    '192.168.169.1',
    '10.0.0.1',
  ];

  /// Returns `InternetAddress(localIp)` when `localIp` and `targetIp` share a /24
  /// prefix so Android routes LAN packets over `wlan0` even when Mobile Data is ON.
  static InternetAddress? resolveBindAddress(String localIp, String targetIp) {
    final lParts = localIp.split('.');
    final tParts = targetIp.split('.');
    if (lParts.length == 4 &&
        tParts.length == 4 &&
        lParts[0] == tParts[0] &&
        lParts[1] == tParts[1] &&
        lParts[2] == tParts[2]) {
      return InternetAddress.tryParse(localIp);
    }
    return null;
  }

  /// Connects a raw TCP socket preferring the Wi-Fi interface when in same subnet.
  static Future<Socket> connectLanSocket(
    String host,
    int port, {
    required String localIp,
    Duration timeout = const Duration(milliseconds: 1200),
  }) async {
    final bindAddr = resolveBindAddress(localIp, host);
    if (bindAddr != null) {
      try {
        return await Socket.connect(
          host,
          port,
          sourceAddress: bindAddr,
          timeout: timeout,
        );
      } catch (_) {
        // Fallback to default routing if OS rejects explicit source bind
      }
    }
    return Socket.connect(host, port, timeout: timeout);
  }

  /// Performs a clean raw HTTP GET over LAN socket (`Connection: close`).
  static Future<(Map<String, String> headers, String body)> _rawHttpGet(
    String ip,
    String path,
    String localIp, {
    Duration timeout = const Duration(milliseconds: 1600),
    Map<String, String>? extraHeaders,
  }) async {
    Socket? sock;
    try {
      sock = await connectLanSocket(ip, 80, localIp: localIp, timeout: timeout);
      final req = StringBuffer()
        ..write('GET $path HTTP/1.1\r\n')
        ..write('Host: $ip\r\n')
        ..write('Connection: close\r\n');
      extraHeaders?.forEach((k, v) => req.write('$k: $v\r\n'));
      req.write('\r\n');
      sock.add(utf8.encode(req.toString()));
      await sock.flush();

      final bytes = BytesBuilder(copy: false);
      await sock
          .listen((chunk) => bytes.add(chunk))
          .asFuture<void>()
          .timeout(timeout, onTimeout: () {});
      final wire = utf8.decode(bytes.takeBytes(), allowMalformed: true);
      final split = wire.indexOf('\r\n\r\n');
      final headStr = split != -1 ? wire.substring(0, split) : wire;
      final bodyStr = split != -1 ? wire.substring(split + 4) : '';
      final hdrs = <String, String>{};
      for (final line in headStr.split('\r\n').skip(1)) {
        final idx = line.indexOf(':');
        if (idx > 0) {
          hdrs[line.substring(0, idx).trim().toLowerCase()] =
              line.substring(idx + 1).trim();
        }
      }
      return (hdrs, bodyStr);
    } finally {
      try {
        sock?.destroy();
      } catch (_) {}
    }
  }

  /// Detects local Wi-Fi IPv4 address and prioritized candidate gateway IPs.
  static Future<(String localIp, List<String> candidates)>
      discoverNetworkCandidates({String? customIp}) async {
    String localIp = '';
    final candidates = <String>[];

    if (customIp != null && customIp.trim().isNotEmpty) {
      candidates.add(customIp.trim());
    }

    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );

      // Prefer Wi-Fi (`wlan0`, `ap0`) over cellular (`rmnet`, `ccmni`)
      interfaces.sort((a, b) {
        int score(String n) {
          final lower = n.toLowerCase();
          if (lower.startsWith('wlan') || lower.startsWith('wifi')) return 0;
          if (lower.startsWith('ap') || lower.startsWith('eth')) return 1;
          if (lower.startsWith('rmnet') ||
              lower.startsWith('ccmni') ||
              lower.startsWith('pdp')) {
            return 3;
          }
          return 2;
        }

        return score(a.name).compareTo(score(b.name));
      });

      for (final iface in interfaces) {
        final lowerName = iface.name.toLowerCase();
        // Skip cellular data interfaces so carrier private 10.x IPs don't mask Wi-Fi
        if (lowerName.startsWith('rmnet') ||
            lowerName.startsWith('ccmni') ||
            lowerName.startsWith('pdp')) {
          continue;
        }
        for (final addr in iface.addresses) {
          final ip = addr.address;
          if (ip.startsWith('192.168.') ||
              ip.startsWith('10.') ||
              ip.startsWith('172.')) {
            if (localIp.isEmpty) localIp = ip;
            final parts = ip.split('.');
            if (parts.length == 4) {
              final gw1 = '${parts[0]}.${parts[1]}.${parts[2]}.1';
              final gw254 = '${parts[0]}.${parts[1]}.${parts[2]}.254';
              if (!candidates.contains(gw1)) candidates.add(gw1);
              if (!candidates.contains(gw254)) candidates.add(gw254);
            }
          }
        }
      }
    } catch (_) {}

    for (final gw in commonGateways) {
      if (!candidates.contains(gw)) {
        candidates.add(gw);
      }
    }

    return (localIp, candidates);
  }

  /// Auto-discovers and fingerprints the active modem on LAN.
  static Future<DetectionResult> autoDetect({String? preferredIp}) async {
    final (localIp, candidates) =
        await discoverNetworkCandidates(customIp: preferredIp);

    final reachableIps = <String>[];
    await Future.wait(
      candidates.map((ip) async {
        try {
          final socket = await connectLanSocket(
            ip,
            80,
            localIp: localIp,
            timeout: const Duration(milliseconds: 950),
          );
          socket.destroy();
          reachableIps.add(ip);
        } catch (_) {}
      }),
    );

    final orderedReachable =
        candidates.where((ip) => reachableIps.contains(ip)).toList();

    for (final ip in orderedReachable) {
      final res = await fingerprintGateway(ip, localIp);
      if (res != null) return res;
    }

    if (preferredIp != null && preferredIp.trim().isNotEmpty) {
      final direct = await fingerprintGateway(preferredIp.trim(), localIp);
      if (direct != null) return direct;
    }

    final fallbackGateway = candidates.first;
    return DetectionResult(
      identity: ModemIdentity(
        gatewayIp: fallbackGateway,
        localClientIp: localIp,
        modelName: 'غير متصل بالمودم',
        protocolLabel: 'بانتظار اتصال الواي فاي',
        family: ModemFamily.notionMifi,
        reachable: false,
      ),
      adapter: NotionMifiAdapter(
        gatewayIp: fallbackGateway,
        localClientIp: localIp,
      ),
    );
  }

  /// Probes HTTP endpoints on `ip` over Wi-Fi socket to identify modem protocol & model.
  static Future<DetectionResult?> fingerprintGateway(
    String ip,
    String localIp,
  ) async {
    String rootHtml = '';
    String modelTitle = '';
    try {
      final (_, body) = await _rawHttpGet(ip, '/', localIp);
      rootHtml = body;
      final titleMatch =
          RegExp(r'<title>([^<]+)</title>', caseSensitive: false)
              .firstMatch(rootHtml);
      if (titleMatch != null) {
        modelTitle = titleMatch
            .group(1)!
            .replaceAll('Wireless Router', '')
            .trim();
      }
    } catch (_) {}

    // 1. Check Notion / Marvell / ASR MiFi (L818A, Vortex, SAM M50, M028T, L02H)
    try {
      final (hdrs, _) = await _rawHttpGet(ip, '/login.cgi', localIp);
      final www = hdrs['www-authenticate'] ?? '';
      if (www.toLowerCase().contains('digest') ||
          rootHtml.contains('xml_action.cgi') ||
          rootHtml.contains('g_platformName')) {
        final cleanModel = modelTitle.isEmpty ? 'Modem 4G MiFi' : modelTitle;
        return DetectionResult(
          identity: ModemIdentity(
            gatewayIp: ip,
            localClientIp: localIp,
            modelName: cleanModel,
            protocolLabel: 'Notion / Yemen 4G MiFi',
            family: ModemFamily.notionMifi,
            reachable: true,
          ),
          adapter: NotionMifiAdapter(
            gatewayIp: ip,
            localClientIp: localIp,
            detectedModelHint: cleanModel,
          ),
        );
      }
    } catch (_) {}

    // 2. Check Huawei / Brovi HiLink (/api/webserver/SesTokInfo)
    try {
      final (_, hiBody) =
          await _rawHttpGet(ip, '/api/webserver/SesTokInfo', localIp);
      if (hiBody.contains('SesInfo') || hiBody.contains('TokInfo')) {
        final cleanModel = modelTitle.isEmpty ? 'Huawei HiLink 4G' : modelTitle;
        return DetectionResult(
          identity: ModemIdentity(
            gatewayIp: ip,
            localClientIp: localIp,
            modelName: cleanModel,
            protocolLabel: 'Huawei HiLink API',
            family: ModemFamily.huaweiHilink,
            reachable: true,
          ),
          adapter: HuaweiHilinkAdapter(
            gatewayIp: ip,
            localClientIp: localIp,
            modelHint: cleanModel,
          ),
        );
      }
    } catch (_) {}

    // 3. Check ZTE / ZLT / Olax Sanechips CGI (/goform/goform_get_cmd_process)
    try {
      final (_, zteBodyRaw) = await _rawHttpGet(
        ip,
        '/goform/goform_get_cmd_process?isTest=false&cmd=model_name,modem_main_state',
        localIp,
        extraHeaders: {'Referer': 'http://$ip/index.html'},
      );
      final jsonStart = zteBodyRaw.indexOf('{');
      if (jsonStart != -1) {
        final zteBody = zteBodyRaw.substring(jsonStart).trim();
        if (zteBody.contains('model_name') ||
            zteBody.contains('modem_main_state')) {
          String zteModel = modelTitle.isEmpty ? 'ZTE / Olax 4G' : modelTitle;
          try {
            final map = jsonDecode(zteBody) as Map<String, dynamic>;
            final m = (map['model_name'] ?? '').toString().trim();
            if (m.isNotEmpty) zteModel = m;
          } catch (_) {}
          return DetectionResult(
            identity: ModemIdentity(
              gatewayIp: ip,
              localClientIp: localIp,
              modelName: zteModel,
              protocolLabel: 'ZTE / Olax Goform',
              family: ModemFamily.zteGoform,
              reachable: true,
            ),
            adapter: ZteGoformAdapter(
              gatewayIp: ip,
              localClientIp: localIp,
              modelHint: zteModel,
            ),
          );
        }
      }
    } catch (_) {}

    // 4. Universal Smart Translator for ANY other responding router/modem
    if (rootHtml.isNotEmpty) {
      final cleanModel = modelTitle.isEmpty ? 'راوتر / مودم ($ip)' : modelTitle;
      return DetectionResult(
        identity: ModemIdentity(
          gatewayIp: ip,
          localClientIp: localIp,
          modelName: cleanModel,
          protocolLabel: 'المترجم الذكي الشامل',
          family: ModemFamily.universalTranslated,
          reachable: true,
        ),
        adapter: UniversalTranslatorAdapter(
          gatewayIp: ip,
          localClientIp: localIp,
          detectedTitle: cleanModel,
        ),
      );
    }
    return null;
  }

  static DetectionResult createDemoMode() {
    final adapter = DemoModemAdapter();
    return DetectionResult(
      identity: const ModemIdentity(
        gatewayIp: '192.168.43.1',
        localClientIp: '192.168.43.200',
        modelName: 'MIFI-L818A (وضع تجريبي)',
        protocolLabel: 'محاكاة يمن فورجي',
        family: ModemFamily.demo,
        reachable: true,
      ),
      adapter: adapter,
    );
  }
}
