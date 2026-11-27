import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
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

      // Prefer wlan / wifi / ap interfaces first
      interfaces.sort((a, b) {
        final aWifi = a.name.toLowerCase().contains('wlan') ||
            a.name.toLowerCase().contains('ap') ||
            a.name.toLowerCase().contains('en');
        final bWifi = b.name.toLowerCase().contains('wlan') ||
            b.name.toLowerCase().contains('ap') ||
            b.name.toLowerCase().contains('en');
        if (aWifi && !bWifi) return -1;
        if (!aWifi && bWifi) return 1;
        return 0;
      });

      for (final iface in interfaces) {
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

    return (localIp.isEmpty ? '192.168.43.200' : localIp, candidates);
  }

  /// Auto-discovers and fingerprints the active modem on LAN.
  static Future<DetectionResult> autoDetect({String? preferredIp}) async {
    final (localIp, candidates) =
        await discoverNetworkCandidates(customIp: preferredIp);

    // Quick parallel TCP port 80 reachability filter
    final reachableIps = <String>[];
    await Future.wait(
      candidates.map((ip) async {
        try {
          final socket = await Socket.connect(
            ip,
            80,
            timeout: const Duration(milliseconds: 900),
          );
          socket.destroy();
          reachableIps.add(ip);
        } catch (_) {}
      }),
    );

    // Preserve priority order from candidates
    final orderedReachable =
        candidates.where((ip) => reachableIps.contains(ip)).toList();

    for (final ip in orderedReachable) {
      final res = await fingerprintGateway(ip, localIp);
      if (res != null) return res;
    }

    // If preferredIp was given explicitly, try fingerprinting directly even if socket timed out
    if (preferredIp != null && preferredIp.trim().isNotEmpty) {
      final direct = await fingerprintGateway(preferredIp.trim(), localIp);
      if (direct != null) return direct;
    }

    // Unreachable fallback (not connected to modem Wi-Fi yet)
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

  /// Probes HTTP endpoints on `ip` to identify the exact modem protocol & model.
  static Future<DetectionResult?> fingerprintGateway(
    String ip,
    String localIp,
  ) async {
    final client = http.Client();
    try {
      String rootHtml = '';
      String modelTitle = '';
      try {
        final rootRes = await client
            .get(Uri.parse('http://$ip/'))
            .timeout(const Duration(milliseconds: 1800));
        rootHtml = utf8.decode(rootRes.bodyBytes, allowMalformed: true);
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
        final loginRes = await client
            .get(Uri.parse('http://$ip/login.cgi'))
            .timeout(const Duration(milliseconds: 1400));
        final www = loginRes.headers['www-authenticate'] ?? '';
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
        final hiRes = await client
            .get(Uri.parse('http://$ip/api/webserver/SesTokInfo'))
            .timeout(const Duration(milliseconds: 1400));
        final hiBody = utf8.decode(hiRes.bodyBytes, allowMalformed: true);
        if (hiBody.contains('SesInfo') || hiBody.contains('TokInfo')) {
          final cleanModel =
              modelTitle.isEmpty ? 'Huawei HiLink 4G' : modelTitle;
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
        final zteRes = await client
            .get(
              Uri.parse(
                'http://$ip/goform/goform_get_cmd_process?isTest=false&cmd=model_name,modem_main_state',
              ),
              headers: {'Referer': 'http://$ip/index.html'},
            )
            .timeout(const Duration(milliseconds: 1400));
        final zteBody =
            utf8.decode(zteRes.bodyBytes, allowMalformed: true).trim();
        if (zteBody.startsWith('{') &&
            (zteBody.contains('model_name') ||
                zteBody.contains('modem_main_state'))) {
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
    } finally {
      client.close();
    }
    return null;
  }

  static DetectionResult createDemoMode() {
    final adapter = DemoModemAdapter();
    return DetectionResult(
      identity: const ModemIdentity(
        gatewayIp: '192.168.43.1',
        localClientIp: '192.168.43.200',
        modelName: 'L818A (وضع تجريبي)',
        protocolLabel: 'محاكاة يمن فورجي',
        family: ModemFamily.demo,
        reachable: true,
      ),
      adapter: adapter,
    );
  }
}
