import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import '../models/modem_models.dart';
import 'adapters/huawei_hilink_adapter.dart';
import 'adapters/marvell_uapxc_adapter.dart';
import 'adapters/modem_adapter.dart';
import 'adapters/notion_mifi_adapter.dart';
import 'adapters/universal_translator_adapter.dart';
import 'adapters/zte_goform_adapter.dart';
import 'wifi_network_binder.dart';

class DetectionResult {
  final ModemIdentity identity;
  final ModemAdapter adapter;

  const DetectionResult({
    required this.identity,
    required this.adapter,
  });
}

/// Raw HTTP probe result (status `0` = no HTTP reply at all).
class _HttpProbe {
  final int status;
  final Map<String, String> headers;
  final String body;

  const _HttpProbe(this.status, this.headers, this.body);

  static const none = _HttpProbe(0, {}, '');

  bool get responded => status > 0;
}

/// Accumulated result of crawling the modem's landing/login pages (following redirects).
class _PageScan {
  final int firstStatus;
  final Map<String, String> headers;
  final String html;

  const _PageScan(this.firstStatus, this.headers, this.html);

  bool get responded => firstStatus > 0;
}

/// UPnP root-device description (manufacturer / modelName) announced by the router.
class _UpnpInfo {
  final String manufacturer;
  final String modelName;
  final String modelNumber;
  final String friendlyName;

  const _UpnpInfo({
    this.manufacturer = '',
    this.modelName = '',
    this.modelNumber = '',
    this.friendlyName = '',
  });
}

class ModemDetector {
  static const List<String> commonGateways = [
    '192.168.43.1',
    '192.168.0.1',
    '192.168.8.1',
    '192.168.1.1',
    '192.168.100.1',
    '192.168.70.1',
    '192.168.254.254',
    '192.168.225.1',
    '192.168.2.1',
    '192.168.3.1',
    '192.168.10.1',
    '192.168.15.1',
    '192.168.31.1',
    '192.168.169.1',
    '192.168.0.254',
    '192.168.1.254',
    '192.168.8.254',
    '10.0.0.1',
    '10.0.0.138',
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

  /// HTTP client for adapters whose sockets are bound to the Wi-Fi address,
  /// so requests never leak onto Mobile Data (`rmnet*`).
  static http.Client createLanHttpClient(String localIp) {
    final hc = HttpClient()
      ..connectionTimeout = const Duration(seconds: 6)
      ..idleTimeout = const Duration(seconds: 4)
      ..badCertificateCallback = (_, __, ___) => true;
    hc.connectionFactory = (Uri uri, String? proxyHost, int? proxyPort) {
      final bind = resolveBindAddress(localIp, uri.host);
      if (bind != null && uri.scheme == 'http') {
        return Socket.startConnect(uri.host, uri.port, sourceAddress: bind);
      }
      if (uri.scheme == 'https') {
        return SecureSocket.startConnect(
          uri.host,
          uri.port,
          onBadCertificate: (_) => true,
        );
      }
      return Socket.startConnect(uri.host, uri.port);
    };
    return IOClient(hc);
  }

  static int _indexOfBytes(Uint8List data, List<int> pattern, [int start = 0]) {
    for (var i = start; i <= data.length - pattern.length; i++) {
      var ok = true;
      for (var j = 0; j < pattern.length; j++) {
        if (data[i + j] != pattern[j]) {
          ok = false;
          break;
        }
      }
      if (ok) return i;
    }
    return -1;
  }

  static Uint8List _dechunk(Uint8List body) {
    final out = BytesBuilder(copy: false);
    var i = 0;
    while (i < body.length) {
      final le = _indexOfBytes(body, const [13, 10], i);
      if (le == -1) break;
      final sizeStr =
          latin1.decode(body.sublist(i, le)).split(';').first.trim();
      final size = int.tryParse(sizeStr, radix: 16);
      if (size == null) return body; // Not really chunked
      if (size == 0) break;
      final start = le + 2;
      final end = start + size;
      if (end > body.length) {
        out.add(body.sublist(start));
        break;
      }
      out.add(body.sublist(start, end));
      i = end + 2;
    }
    return out.takeBytes();
  }

  /// Reads an HTTP/1.x response from `sock` and finishes immediately once the
  /// full body arrives (via `Content-Length`, chunked `0\r\n\r\n`, `</RGW>`,
  /// `</html>`, or header-only `WWW-Authenticate` / CGI login response), avoiding
  /// 5-second hangs on embedded `Mongoose/3.0` servers that ignore `Connection: close`.
  static Future<Uint8List> readHttpResponseBytes(
    Socket sock, {
    required Duration timeout,
    bool isHeaderOnlyChallenge = false,
    bool isCgiLoginAction = false,
  }) async {
    final builder = BytesBuilder(copy: false);
    final done = Completer<void>();
    Timer? totalTimer;
    Timer? idleAfterHeaderTimer;
    StreamSubscription<Uint8List>? sub;

    void finish() {
      if (!done.isCompleted) done.complete();
    }

    int? parsedContentLength;
    bool isChunked = false;
    bool headersParsed = false;
    int bodyStart = -1;

    sub = sock.listen(
      (chunk) {
        builder.add(chunk);
        final cur = builder.toBytes();
        if (!headersParsed) {
          final split = _indexOfBytes(cur, const [13, 10, 13, 10]);
          if (split != -1) {
            headersParsed = true;
            bodyStart = split + 4;
            final headText =
                latin1.decode(cur.sublist(0, split), allowInvalid: true);
            final lowerHead = headText.toLowerCase();
            final clMatch =
                RegExp(r'content-length:\s*(\d+)').firstMatch(lowerHead);
            if (clMatch != null) {
              parsedContentLength = int.tryParse(clMatch.group(1)!);
            }
            if (lowerHead.contains('transfer-encoding:') &&
                lowerHead.contains('chunked')) {
              isChunked = true;
            }
            if (isHeaderOnlyChallenge &&
                parsedContentLength == null &&
                !isChunked &&
                lowerHead.contains('www-authenticate:')) {
              finish();
              return;
            }
          }
        }

        if (headersParsed) {
          if (parsedContentLength != null &&
              cur.length >= bodyStart + parsedContentLength!) {
            finish();
            return;
          }
          if (isChunked &&
              _indexOfBytes(cur, const [48, 13, 10, 13, 10], bodyStart) != -1) {
            finish();
            return;
          }
          final tailStart = cur.length > 512 ? cur.length - 512 : 0;
          final tail = latin1.decode(cur.sublist(tailStart), allowInvalid: true);
          if (tail.contains('</RGW>') ||
              tail.contains('</html>') ||
              tail.contains('</HTML>')) {
            finish();
            return;
          }
          if (isCgiLoginAction) {
            final full = latin1.decode(cur, allowInvalid: true);
            final statusHits = RegExp(r'HTTP/1\.\d\s+\d{3}').allMatches(full).length;
            if (statusHits >= 2 && full.endsWith('\r\n\r\n')) {
              finish();
              return;
            }
            idleAfterHeaderTimer?.cancel();
            idleAfterHeaderTimer =
                Timer(const Duration(milliseconds: 140), finish);
          } else if (parsedContentLength == null && !isChunked) {
            final fullHead =
                latin1.decode(cur.sublist(0, bodyStart), allowInvalid: true).toLowerCase();
            if (fullHead.contains('www-authenticate:') && cur.length == bodyStart) {
              finish();
              return;
            }
          }
        }
      },
      onDone: finish,
      onError: (_) => finish(),
      cancelOnError: true,
    );

    totalTimer = Timer(timeout, finish);
    await done.future;
    totalTimer.cancel();
    idleAfterHeaderTimer?.cancel();
    try {
      await sub.cancel();
    } catch (_) {}
    return builder.takeBytes();
  }

  /// Performs a clean raw HTTP GET over LAN socket (`Connection: close`).
  static Future<_HttpProbe> _rawHttp(
    String ip,
    String path,
    String localIp, {
    int port = 80,
    Duration timeout = const Duration(milliseconds: 2800),
    Map<String, String>? extraHeaders,
  }) async {
    Socket? sock;
    try {
      sock = await connectLanSocket(ip, port, localIp: localIp, timeout: timeout);
      final hostHeader = port == 80 ? ip : '$ip:$port';
      final req = StringBuffer()
        ..write('GET $path HTTP/1.1\r\n')
        ..write('Host: $hostHeader\r\n')
        ..write('User-Agent: Mozilla/5.0 (Linux; Android) ModemZaid\r\n')
        ..write('Accept: */*\r\n')
        ..write('Connection: close\r\n');
      extraHeaders?.forEach((k, v) => req.write('$k: $v\r\n'));
      req.write('\r\n');
      sock.add(utf8.encode(req.toString()));
      await sock.flush();

      final wire = await readHttpResponseBytes(
        sock,
        timeout: timeout,
        isHeaderOnlyChallenge: path == '/login.cgi',
        isCgiLoginAction: path.startsWith('/login.cgi?'),
      );
      if (wire.isEmpty) return _HttpProbe.none;

      final split = _indexOfBytes(wire, const [13, 10, 13, 10]);
      final headStr = latin1.decode(split != -1 ? wire.sublist(0, split) : wire,
          allowInvalid: true);
      var bodyBytes =
          split != -1 ? Uint8List.fromList(wire.sublist(split + 4)) : Uint8List(0);

      final lines = headStr.split('\r\n');
      final statusMatch =
          RegExp(r'HTTP/\d\.\d\s+(\d{3})').firstMatch(lines.isNotEmpty ? lines.first : '');
      final status = statusMatch != null ? int.parse(statusMatch.group(1)!) : 0;
      final hdrs = <String, String>{};
      for (final line in lines.skip(1)) {
        final idx = line.indexOf(':');
        if (idx > 0) {
          hdrs[line.substring(0, idx).trim().toLowerCase()] =
              line.substring(idx + 1).trim();
        }
      }
      if ((hdrs['transfer-encoding'] ?? '').toLowerCase().contains('chunked')) {
        bodyBytes = _dechunk(bodyBytes);
      }
      final body = utf8.decode(bodyBytes, allowMalformed: true);
      return _HttpProbe(status, hdrs, body);
    } catch (_) {
      return _HttpProbe.none;
    } finally {
      try {
        sock?.destroy();
      } catch (_) {}
    }
  }

  static bool _isPrivateIpv4(String ip) {
    final p = ip.split('.');
    if (p.length != 4) return false;
    final a = int.tryParse(p[0]) ?? -1;
    final b = int.tryParse(p[1]) ?? -1;
    return a == 10 || (a == 192 && b == 168) || (a == 172 && b >= 16 && b <= 31);
  }

  /// Detects local Wi-Fi IPv4 address and prioritized candidate gateway IPs.
  /// The REAL Wi-Fi DHCP gateway reported by Android always comes first.
  static Future<(String localIp, List<String> candidates)>
      discoverNetworkCandidates({
    String? customIp,
    WifiLinkInfo? wifi,
  }) async {
    String localIp = '';
    final candidates = <String>[];

    void addCandidate(String ip) {
      final clean = ip.trim();
      if (clean.isEmpty || clean == '0.0.0.0') return;
      if (!candidates.contains(clean)) candidates.add(clean);
    }

    if (customIp != null && customIp.trim().isNotEmpty) {
      addCandidate(customIp);
    }

    if (wifi != null) {
      if (wifi.localIp.isNotEmpty) localIp = wifi.localIp;
      if (wifi.gateway.isNotEmpty) addCandidate(wifi.gateway);
      for (final dns in wifi.dnsServers) {
        if (_isPrivateIpv4(dns)) addCandidate(dns);
      }
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
            lowerName.startsWith('pdp') ||
            lowerName.startsWith('dummy') ||
            lowerName.startsWith('tun')) {
          continue;
        }
        for (final addr in iface.addresses) {
          final ip = addr.address;
          if (_isPrivateIpv4(ip)) {
            if (localIp.isEmpty) localIp = ip;
            final parts = ip.split('.');
            if (parts.length == 4) {
              addCandidate('${parts[0]}.${parts[1]}.${parts[2]}.1');
              addCandidate('${parts[0]}.${parts[1]}.${parts[2]}.254');
            }
          }
        }
      }
    } catch (_) {}

    for (final gw in commonGateways) {
      addCandidate(gw);
    }

    return (localIp, candidates);
  }

  static Future<bool> _isPortOpen(
      String ip, int port, String localIp, Duration timeout) async {
    try {
      final s = await connectLanSocket(ip, port, localIp: localIp, timeout: timeout);
      s.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  static DetectionResult _unreachable(
    String gateway,
    String localIp,
    String title,
    String message,
  ) {
    return DetectionResult(
      identity: ModemIdentity(
        gatewayIp: gateway,
        localClientIp: localIp,
        modelName: title,
        protocolLabel: 'بانتظار اتصال الواي فاي',
        family: ModemFamily.universalTranslated,
        reachable: false,
        statusMessage: message,
      ),
      adapter: UniversalTranslatorAdapter(
        gatewayIp: gateway,
        localClientIp: localIp,
      ),
    );
  }

  /// Auto-discovers and fingerprints the active modem on LAN.
  static Future<DetectionResult> autoDetect({String? preferredIp}) async {
    // 1. Ask Android for the REAL Wi-Fi gateway and bind the app to Wi-Fi.
    final wifi = await WifiNetworkBinder.query(bind: true);
    final hasCustom = preferredIp != null && preferredIp.trim().isNotEmpty;

    if (!wifi.connected && !hasCustom) {
      return _unreachable(
        '',
        '',
        'غير متصل بالواي فاي',
        'الهاتف غير متصل بأي شبكة واي فاي. اتصل بشبكة المودم ثم أعد الفحص.',
      );
    }

    final (localIp, candidates) = await discoverNetworkCandidates(
      customIp: preferredIp,
      wifi: wifi,
    );

    // 2. Find which candidates actually accept HTTP connections.
    final open80 = <String>{};
    await Future.wait(
      candidates.map((ip) async {
        // The real gateway gets a longer timeout (slow ADSL/fiber routers).
        final isPrimary = ip == wifi.gateway || ip == preferredIp?.trim();
        final ok = await _isPortOpen(
          ip,
          80,
          localIp,
          Duration(milliseconds: isPrimary ? 2500 : 1000),
        );
        if (ok) open80.add(ip);
      }),
    );

    final ordered = candidates.where(open80.contains).toList();
    for (final ip in ordered) {
      final res = await fingerprintGateway(ip, localIp);
      if (res != null) return res;
    }

    // 3. Check HTTPS (443) or Alt-HTTP (8080) on primary gateway (PTC Fiber/ADSL ONTs).
    final primary = hasCustom
        ? (preferredIp ?? '').trim()
        : (wifi.gateway.isNotEmpty ? wifi.gateway : candidates.first);
    if (primary.isNotEmpty) {
      if (await _isPortOpen(
          primary, 8080, localIp, const Duration(milliseconds: 1800))) {
        final p8080 = await _rawHttp(primary, '/', localIp,
            port: 8080, timeout: const Duration(milliseconds: 3500));
        final v = _vendorFromText(
            '${p8080.headers.values.join(' ')}\n${p8080.body}');
        final name = _composeModelName(
          vendor: v,
          candidates: _htmlModelCandidates(p8080.body),
          ip: primary,
          fallback: '',
        );
        return DetectionResult(
          identity: ModemIdentity(
            gatewayIp: primary,
            localClientIp: localIp,
            modelName: name,
            vendor: v,
            protocolLabel: 'المترجم الذكي الشامل (8080)',
            family: ModemFamily.universalTranslated,
            reachable: true,
          ),
          adapter: UniversalTranslatorAdapter(
            gatewayIp: primary,
            localClientIp: localIp,
            detectedTitle: name,
            port: 8080,
          ),
        );
      }
      if (await _isPortOpen(
          primary, 443, localIp, const Duration(milliseconds: 1800))) {
        String httpsBody = '';
        try {
          final client = createLanHttpClient(localIp);
          final r = await client
              .get(Uri.parse('https://$primary/'))
              .timeout(const Duration(seconds: 4));
          httpsBody = utf8.decode(r.bodyBytes, allowMalformed: true);
          client.close();
        } catch (_) {}
        final v = _vendorFromText(httpsBody);
        final name = _composeModelName(
          vendor: v,
          candidates: _htmlModelCandidates(httpsBody),
          ip: primary,
          fallback: '',
        );
        return DetectionResult(
          identity: ModemIdentity(
            gatewayIp: primary,
            localClientIp: localIp,
            modelName: name,
            vendor: v,
            protocolLabel: 'المترجم الذكي الشامل (HTTPS)',
            family: ModemFamily.universalTranslated,
            reachable: true,
          ),
          adapter: UniversalTranslatorAdapter(
            gatewayIp: primary,
            localClientIp: localIp,
            detectedTitle: name,
            baseScheme: 'https',
            port: 443,
          ),
        );
      }
    }
    return _unreachable(
      primary,
      localIp,
      'لم يتم العثور على المودم',
      primary.isEmpty
          ? 'تعذر تحديد عنوان المودم. أدخل عنوان IP يدوياً من زر الإعدادات.'
          : 'المودم ($primary) لا يستجيب. تأكد أنك متصل بشبكة المودم نفسه، أو أدخل عنوانه يدوياً.',
    );
  }

  // ---------------------------------------------------------------------------
  // Fingerprinting
  // ---------------------------------------------------------------------------

  /// Probes HTTP endpoints on `ip` over Wi-Fi socket to identify modem protocol & model.
  static Future<DetectionResult?> fingerprintGateway(
    String ip,
    String localIp,
  ) async {
    // UPnP runs in parallel – it often reveals manufacturer + exact model.
    final upnpFuture = _discoverUpnp(ip, localIp)
        .timeout(const Duration(seconds: 4), onTimeout: () => null)
        .catchError((_) => null);

    final page = await _scanWebPages(ip, localIp);
    final html = page.html;
    final headerText =
        page.headers.entries.map((e) => '${e.key}: ${e.value}').join('\n');
    final formAuth = _detectFormAuthMode(page);

    // 1. Marvell UAPXC (PTC Yemen 4G CPE `192.168.0.1`) vs Notion Duster MiFi (`L818A`)
    final notionProbe = await _rawHttp(ip, '/login.cgi', localIp);
    final www = (notionProbe.headers['www-authenticate'] ?? '').toLowerCase();
    if (www.contains('digest') ||
        html.contains('xml_action.cgi') ||
        html.contains('g_platformName')) {
      // True discriminator: UAPXC loads `wifiSetting.js` and returns `<error_cause>5</error_cause>`
      // on Duster GET, whereas Notion L818A loads `wireless_settings.js` (both share `lTitleUAPXC`!).
      bool isUapxc = html.contains('wifiSetting.js');
      if (!isUapxc) {
        final dusterCheck = await _rawHttp(
          ip,
          '/xml_action.cgi?method=get&module=duster&file=status1',
          localIp,
          timeout: const Duration(milliseconds: 1600),
        );
        if (dusterCheck.body.contains('<error_cause>')) {
          isUapxc = true;
        }
      }

      final upnp = await upnpFuture;
      final candidates = [
        ..._upnpCandidates(upnp),
        ..._htmlModelCandidates(html),
      ];
      var vendor = _resolveVendor(
        upnp: upnp,
        primaryText:
            '$headerText\n${notionProbe.headers['www-authenticate'] ?? ''}',
        html: html,
      );
      if (vendor.isEmpty) vendor = _inferVendorFromCandidates(candidates);

      if (isUapxc) {
        if (vendor.isEmpty) vendor = 'Yemen 4G';
        final name = _composeModelName(
          vendor: vendor,
          candidates: candidates,
          ip: ip,
          fallback: 'CPE',
        );
        return DetectionResult(
          identity: ModemIdentity(
            gatewayIp: ip,
            localClientIp: localIp,
            modelName: name,
            vendor: vendor,
            protocolLabel: 'Yemen 4G CPE (UAPXC)',
            family: ModemFamily.marvellUapxc,
            reachable: true,
            authMode: formAuth ?? ModemAuthMode.usernameAndPassword,
          ),
          adapter: MarvellUapxcAdapter(
            gatewayIp: ip,
            localClientIp: localIp,
            detectedModelHint: name,
          ),
        );
      }

      final name = _composeModelName(
        vendor: vendor,
        candidates: candidates,
        ip: ip,
        fallback: 'MiFi 4G',
      );
      return DetectionResult(
        identity: ModemIdentity(
          gatewayIp: ip,
          localClientIp: localIp,
          modelName: name,
          vendor: vendor,
          protocolLabel: 'Notion / Yemen 4G MiFi',
          family: ModemFamily.notionMifi,
          reachable: true,
          authMode: formAuth ?? ModemAuthMode.usernameAndPassword,
        ),
        adapter: NotionMifiAdapter(
          gatewayIp: ip,
          localClientIp: localIp,
          detectedModelHint: name,
        ),
      );
    }

    // 2. Huawei / Brovi / Soyealink HiLink (/api/webserver/SesTokInfo or /api/webserver/token)
    var hi = await _rawHttp(ip, '/api/webserver/SesTokInfo', localIp);
    if (!hi.body.contains('SesInfo') && !hi.body.contains('TokInfo')) {
      final tokProbe = await _rawHttp(ip, '/api/webserver/token', localIp);
      if (tokProbe.body.contains('<token>')) hi = tokProbe;
    }
    final hiBody = hi.body;
    final isHilink = hiBody.contains('SesInfo') ||
        hiBody.contains('TokInfo') ||
        hiBody.contains('<token>') ||
        (hiBody.contains('<error>') && hiBody.contains('<code>')) ||
        html.toLowerCase().contains('hilink');
    if (isHilink) {
      final basic =
          await _rawHttp(ip, '/api/device/basic_information', localIp);
      final devName = _xmlTag(basic.body, 'devicename');
      final classify = _xmlTag(basic.body, 'classify');
      final hilinkLogin =
          await _rawHttp(ip, '/api/user/hilink_login', localIp);
      final noLogin = _xmlTag(hilinkLogin.body, 'hilink_login') == '0';
      final upnp = await upnpFuture;
      final lowerAll = '$html\n$headerText\n${basic.body}'.toLowerCase();
      final vendor = lowerAll.contains('brovi')
          ? 'Brovi'
          : (lowerAll.contains('soyealink') ? 'Soyealink' : 'Huawei');
      final name = _composeModelName(
        vendor: vendor,
        candidates: [
          devName,
          ..._upnpCandidates(upnp),
          ..._htmlModelCandidates(html),
        ],
        ip: ip,
        fallback: classify.isNotEmpty ? classify : 'HiLink 4G',
      );
      return DetectionResult(
        identity: ModemIdentity(
          gatewayIp: ip,
          localClientIp: localIp,
          modelName: name,
          vendor: vendor,
          protocolLabel: 'Huawei HiLink API',
          family: ModemFamily.huaweiHilink,
          reachable: true,
          authMode: noLogin
              ? ModemAuthMode.none
              : (formAuth ?? ModemAuthMode.passwordOnly),
        ),
        adapter: HuaweiHilinkAdapter(
          gatewayIp: ip,
          localClientIp: localIp,
          modelHint: name,
        ),
      );
    }

    // 3. ZTE / ZXIC / Star Speed 4G / ZLT / Olax / Qualcomm CGI (/goform/... or /reqproc/...)
    const zteMultiQuery =
        '?isTest=false&multi_data=1&cmd=Language,model_name,hardware_version,wa_inner_version,cr_version,modem_main_state,SSID1';
    var zteLd = await _rawHttp(
      ip,
      '/goform/goform_get_cmd_process?isTest=false&cmd=LD',
      localIp,
      extraHeaders: {'Referer': 'http://$ip/index.html'},
    );
    var zte = await _rawHttp(
      ip,
      '/goform/goform_get_cmd_process$zteMultiQuery',
      localIp,
      extraHeaders: {'Referer': 'http://$ip/index.html'},
    );
    var useReqProc = false;
    bool isValidZteJson( _HttpProbe p) {
      if (p.status != 200) return false;
      final t = p.body.trim();
      final s = t.indexOf('{');
      return s != -1 && t.endsWith('}') && !t.toLowerCase().contains('<html');
    }

    if (!isValidZteJson(zteLd) && !isValidZteJson(zte)) {
      final reqLd = await _rawHttp(
        ip,
        '/reqproc/proc_get?isTest=false&cmd=LD',
        localIp,
        extraHeaders: {'Referer': 'http://$ip/index.html'},
      );
      final reqMulti = await _rawHttp(
        ip,
        '/reqproc/proc_get$zteMultiQuery',
        localIp,
        extraHeaders: {'Referer': 'http://$ip/index.html'},
      );
      if (isValidZteJson(reqLd) || isValidZteJson(reqMulti)) {
        zteLd = reqLd;
        zte = reqMulti;
        useReqProc = true;
      }
    }

    if (isValidZteJson(zteLd) || isValidZteJson(zte)) {
      final zteBody = isValidZteJson(zte)
          ? zte.body.substring(zte.body.indexOf('{')).trim()
          : zteLd.body.substring(zteLd.body.indexOf('{')).trim();
      String zteModel = '';
      String zteHw = '';
      String zteSsid = '';
      try {
        final map = jsonDecode(zteBody) as Map<String, dynamic>;
        zteModel = (map['model_name'] ?? '').toString().trim();
        zteHw = (map['hardware_version'] ?? '').toString().trim();
        zteSsid = (map['SSID1'] ?? '').toString().trim();
      } catch (_) {}

      // ZTE KnockoutJS SPA loads login inputs from /tmpl/login.html & config from /js/config/config.js
      ModemAuthMode? spaAuth = formAuth;
      String extraSpaText = '';
      if (spaAuth == null || zteModel.isEmpty) {
        final tmpl = await _rawHttp(ip, '/tmpl/login.html', localIp,
            timeout: const Duration(milliseconds: 1600));
        if (tmpl.status == 200 && tmpl.body.isNotEmpty) {
          extraSpaText = tmpl.body;
          spaAuth ??=
              _detectFormAuthMode(_PageScan(200, tmpl.headers, tmpl.body));
        }
        final cfg = await _rawHttp(ip, '/js/config/config.js', localIp,
            timeout: const Duration(milliseconds: 1600));
        if (cfg.status == 200 && cfg.body.isNotEmpty) {
          extraSpaText = '$extraSpaText\n${cfg.body}';
          if (spaAuth == null &&
              RegExp(r'SHOW_LOGIN_USERNAME\s*:\s*true', caseSensitive: false)
                  .hasMatch(cfg.body)) {
            spaAuth = ModemAuthMode.usernameAndPassword;
          }
        }
      }

      final upnp = await upnpFuture;
      final lowerAll =
          '$html\n$headerText\n$zteBody\n$zteSsid\n$extraSpaText'.toLowerCase();
      final scanned = _resolveVendor(
        upnp: upnp,
        primaryText: '$headerText\n$zteSsid',
        html: '$html\n$extraSpaText',
      );
      final candidates = [
        zteModel,
        if (zteModel.isEmpty && zteHw.isNotEmpty) zteHw,
        ..._upnpCandidates(upnp),
        ..._htmlModelCandidates('$html\n$extraSpaText'),
      ];
      final inferred = _inferVendorFromCandidates(candidates);
      final vendor = lowerAll.contains('star speed') ||
              lowerAll.contains('starspeed') ||
              lowerAll.contains('star_speed')
          ? 'Star Speed 4G'
          : _hasWord(lowerAll, 'speed 4g') || _hasWord(lowerAll, 'speed4g')
              ? 'Speed 4G'
              : _hasWord(lowerAll, 'olax')
                  ? 'Olax'
                  : _hasWord(lowerAll, 'zlt')
                      ? 'ZLT'
                      : (scanned.isNotEmpty
                          ? scanned
                          : (inferred.isNotEmpty
                              ? inferred
                              : (useReqProc ? 'Speed 4G' : 'ZTE')));
      final name = _composeModelName(
        vendor: vendor,
        candidates: candidates,
        ip: ip,
        fallback: '4G Router',
      );
      final resolvedAuth = spaAuth ?? ModemAuthMode.passwordOnly;
      return DetectionResult(
        identity: ModemIdentity(
          gatewayIp: ip,
          localClientIp: localIp,
          modelName: name,
          vendor: vendor,
          protocolLabel:
              useReqProc ? 'Speed 4G / Qualcomm CGI' : 'ZTE / Star Speed CGI',
          family: ModemFamily.zteGoform,
          reachable: true,
          authMode: resolvedAuth,
        ),
        adapter: ZteGoformAdapter(
          gatewayIp: ip,
          localClientIp: localIp,
          modelHint: name,
          useReqProc: useReqProc,
          passwordOnly: resolvedAuth == ModemAuthMode.passwordOnly,
        ),
      );
    }

    // 4. Universal Smart Translator for ANY other router/modem (Jetpack MiFi,
    // PTC ADSL/Fiber, Huawei EMUI B312, Alcatel /jrd/webapi, Tozed ZLT, etc.)
    final emuiDev = await _rawHttp(ip, '/api/system/deviceinfo', localIp,
        timeout: const Duration(milliseconds: 1600));
    final jetpackSrv = await _rawHttp(ip, '/srv/status', localIp,
        timeout: const Duration(milliseconds: 1600));
    String emuiModel = '';
    if (emuiDev.body.trim().startsWith('{')) {
      try {
        final m = jsonDecode(emuiDev.body.trim()) as Map<String, dynamic>;
        emuiModel =
            (m['DeviceName'] ?? m['ProductClass'] ?? '').toString().trim();
      } catch (_) {}
    }
    final isJetpack = jetpackSrv.body.contains('statusData') ||
        html.contains('gSecureToken') ||
        html.toLowerCase().contains('jetpack');

    // Redirect from HTTP:80 -> HTTPS:443?
    final locHdr = (page.headers['location'] ?? '').trim().toLowerCase();
    final redirectsToHttps = locHdr.startsWith('https://$ip');

    if (page.responded ||
        notionProbe.responded ||
        hi.responded ||
        zte.responded ||
        emuiDev.responded ||
        jetpackSrv.responded) {
      final upnp = await upnpFuture;
      final realm = RegExp(r'realm="([^"]+)"', caseSensitive: false)
              .firstMatch(page.headers['www-authenticate'] ?? '')
              ?.group(1) ??
          '';
      final candidates = [
        if (emuiModel.isNotEmpty) emuiModel,
        ..._upnpCandidates(upnp),
        ..._htmlModelCandidates(html),
        realm,
      ];
      var vendor = isJetpack
          ? 'Jetpack'
          : _resolveVendor(
              upnp: upnp,
              primaryText: '$headerText\n${emuiDev.body}',
              html: html,
            );
      if (vendor.isEmpty) vendor = _inferVendorFromCandidates(candidates);
      final name = _composeModelName(
        vendor: vendor,
        candidates: candidates,
        ip: ip,
        fallback: isJetpack ? 'MiFi' : '',
      );
      final isPasswordOnly = isJetpack ||
          html.contains('jrd/webapi') ||
          vendor == 'Alcatel' ||
          vendor == 'Star Speed 4G' ||
          vendor == 'Speed 4G' ||
          emuiModel.isNotEmpty;
      return DetectionResult(
        identity: ModemIdentity(
          gatewayIp: ip,
          localClientIp: localIp,
          modelName: name,
          vendor: vendor,
          protocolLabel:
              isJetpack ? 'Jetpack MiFi API' : 'المترجم الذكي الشامل',
          family: ModemFamily.universalTranslated,
          reachable: true,
          authMode: formAuth ??
              (isPasswordOnly
                  ? ModemAuthMode.passwordOnly
                  : ModemAuthMode.usernameAndPassword),
        ),
        adapter: UniversalTranslatorAdapter(
          gatewayIp: ip,
          localClientIp: localIp,
          detectedTitle: name,
          baseScheme: redirectsToHttps ? 'https' : 'http',
          port: redirectsToHttps ? 443 : 80,
        ),
      );
    }
    return null;
  }

  /// Fetches `/` and follows HTTP + meta/JS redirects (max 4 hops) on the same host.
  static Future<_PageScan> _scanWebPages(String ip, String localIp) async {
    final buf = StringBuffer();
    final headersAll = <String, String>{};
    int firstStatus = 0;
    String path = '/';
    final visited = <String>{};

    for (var hop = 0; hop < 4; hop++) {
      if (visited.contains(path)) break;
      visited.add(path);
      var p = await _rawHttp(ip, path, localIp,
          timeout: const Duration(milliseconds: 4500));
      if (!p.responded && hop == 0) {
        // Slow routers (old ADSL / fiber ONT) — retry once with a longer wait.
        p = await _rawHttp(ip, path, localIp,
            timeout: const Duration(milliseconds: 7000));
      }
      if (!p.responded) break;
      if (firstStatus == 0) firstStatus = p.status;
      p.headers.forEach((k, v) => headersAll.putIfAbsent(k, () => v));
      buf.writeln(p.body);

      String? next;
      if (p.status >= 300 && p.status < 400) next = p.headers['location'];
      if (next == null && p.body.length < 4000) next = _findClientRedirect(p.body);
      if (next == null) break;
      final resolved = _resolveSameHostPath(ip, path, next);
      if (resolved == null) break;
      path = resolved;
    }

    // Very small SPA shells: also look at the usual login page names.
    if (firstStatus > 0 && buf.length < 600) {
      for (final extra in const [
        '/index.html',
        '/index.htm',
        '/login.html',
        '/login.htm',
        '/html/index.html',
      ]) {
        if (visited.contains(extra)) continue;
        final p = await _rawHttp(ip, extra, localIp);
        if (p.status == 200 && p.body.isNotEmpty) {
          buf.writeln(p.body);
          break;
        }
      }
    }
    return _PageScan(firstStatus, headersAll, buf.toString());
  }

  static String? _findClientRedirect(String body) {
    final patterns = [
      RegExp(r'''http-equiv\s*=\s*["']?refresh["']?[^>]*url\s*=\s*([^"'>\s;]+)''',
          caseSensitive: false),
      RegExp(r'''location\.replace\(\s*["']([^"']+)["']''', caseSensitive: false),
      RegExp(r'''(?:window\.|top\.|self\.|document\.)?location(?:\.href)?\s*=\s*["']([^"']+)["']''',
          caseSensitive: false),
    ];
    for (final re in patterns) {
      final m = re.firstMatch(body);
      final v = m?.group(1)?.trim() ?? '';
      if (v.isNotEmpty && !v.startsWith('javascript')) return v;
    }
    return null;
  }

  static String? _resolveSameHostPath(String ip, String currentPath, String next) {
    final n = next.trim();
    if (n.isEmpty || n.startsWith('#')) return null;
    if (n.startsWith('http://') || n.startsWith('https://')) {
      final u = Uri.tryParse(n);
      if (u == null || u.scheme != 'http' || u.host != ip) return null;
      if (u.hasPort && u.port != 80) return null;
      final p = u.path.isEmpty ? '/' : u.path;
      return u.hasQuery ? '$p?${u.query}' : p;
    }
    if (n.startsWith('/')) return n;
    final dir = currentPath.contains('/')
        ? currentPath.substring(0, currentPath.lastIndexOf('/') + 1)
        : '/';
    return '$dir$n';
  }

  /// Decides whether the login page asks for username+password or password only.
  static ModemAuthMode? _detectFormAuthMode(_PageScan page) {
    final www = (page.headers['www-authenticate'] ?? '').toLowerCase();
    if (page.firstStatus == 401 || www.contains('basic') || www.contains('digest')) {
      return ModemAuthMode.usernameAndPassword;
    }
    int pw = 0;
    int user = 0;
    for (final m in RegExp(r'<input\b[^>]*>', caseSensitive: false).allMatches(page.html)) {
      final tag = m.group(0)!.toLowerCase();
      final typeMatch = RegExp(r'''type\s*=\s*["']?([a-z]+)''').firstMatch(tag);
      final type = typeMatch?.group(1) ?? 'text';
      if (type == 'password') {
        pw++;
        continue;
      }
      if (type != 'text' && type != 'email') continue;
      final idName = RegExp(r'''(?:name|id)\s*=\s*["']?([^"'\s>]+)''')
          .allMatches(tag)
          .map((e) => e.group(1) ?? '')
          .join(' ');
      if (RegExp(r'user|account|uname|usr|login_?name|admin_?name').hasMatch(idName)) {
        user++;
      }
    }
    if (pw > 0 && user == 0) return ModemAuthMode.passwordOnly;
    if (pw > 0 && user > 0) return ModemAuthMode.usernameAndPassword;
    return null;
  }

  // ---------------------------------------------------------------------------
  // Smart vendor / model name resolution
  // ---------------------------------------------------------------------------

  static const Map<String, List<String>> _vendorKeywords = {
    'Huawei': ['huawei', 'hilink', 'echolife'],
    'ZTE': ['zte', 'zxhn', 'zxv10'],
    'Olax': ['olax'],
    'ZLT': ['zlt'],
    'Star Speed 4G': ['star speed', 'starspeed', 'osystel', 'ستار سبيد'],
    'Speed 4G': ['speed 4g', 'speed4g', 'سبيد فورجي'],
    'SAM': ['sam m50', 'sam 4g', 'sam4g'],
    'Vortex': ['vortex'],
    'Cool 4G': ['cool 4g', 'cool4g', 'f239'],
    'Jetpack': ['jetpack', 'inseego', 'novatel'],
    'WeGo': ['wego'],
    'Falcon': ['falcon'],
    'Opera': ['opera 4g', 'opera mifi'],
    'GreenPacket': ['greenpacket', 'green packet'],
    'Tozed': ['tozed'],
    'Telrad': ['telrad'],
    'TCL': ['tcl'],
    'Soyealink': ['soyealink'],
    'TP-Link': ['tp-link', 'tplink', 'tp link'],
    'Mercusys': ['mercusys'],
    'Tenda': ['tenda'],
    'D-Link': ['d-link', 'dlink'],
    'Netgear': ['netgear'],
    'Xiaomi': ['xiaomi', 'miwifi'],
    'Alcatel': ['alcatel', 'linkzone'],
    'Nokia': ['nokia'],
    'FiberHome': ['fiberhome'],
    'Brovi': ['brovi'],
    'MikroTik': ['mikrotik', 'routeros'],
    'Ubiquiti': ['ubiquiti', 'airos'],
    'Linksys': ['linksys'],
    'ASUS': ['asus'],
    'Cudy': ['cudy'],
    'Totolink': ['totolink'],
    'Netis': ['netis'],
    'Comfast': ['comfast'],
    'ZyXEL': ['zyxel'],
    'GL.iNet': ['gl-inet', 'gl.inet'],
    'Ruijie': ['ruijie', 'reyee'],
    'Vodafone': ['vodafone'],
    'Sagemcom': ['sagemcom'],
    'Technicolor': ['technicolor'],
    'Notion': ['notion'],
    'OpenWrt': ['openwrt', 'luci'],
  };

  /// Infers manufacturer from model code prefixes when HTML/UPnP omits vendor text.
  static String _inferVendorFromCandidates(List<String> candidates) {
    final joined = candidates.join(' ').toUpperCase();
    if (RegExp(r'\b(E557\d|E578\d|E588\d|E8372|B31[0125]|B525|B535|B612|B818|H112|H122|H155|HG53\d|HG6[35]\d|HG8\d{3}|EG8\d{3}|DG8045)\b')
        .hasMatch(joined)) {
      return 'Huawei';
    }
    if (RegExp(r'\b(MF\s*600|OSYSTEL|B50\s*PRO)\b').hasMatch(joined)) {
      return 'Star Speed 4G';
    }
    if (RegExp(r'\b(MT80\s*PRO|MT80|MF982|MC80|U90|WD680|AX6\s*PRO)\b')
        .hasMatch(joined)) {
      return 'Olax';
    }
    if (RegExp(r'\b(M60M|S25|M90\s*PRO|M90|S10G|S12|P25|P28|T30|X21|X28|M30S?)\b')
        .hasMatch(joined)) {
      return 'ZLT';
    }
    if (RegExp(r'\b(MF293\w*|U10S|U20|MF9\d{2}|MF28\d|MC8\d{2}|MU5\d{3}|ZXHN|H108N|H168N|H267N|F6[0678]\d)\b')
        .hasMatch(joined)) {
      return 'ZTE';
    }
    if (RegExp(r'\b(SAM\s*M50|M50\s*PRO)\b').hasMatch(joined)) {
      return 'SAM';
    }
    if (RegExp(r'\b(M49)\b').hasMatch(joined)) {
      return 'Vortex';
    }
    if (RegExp(r'\b(F239)\b').hasMatch(joined)) {
      return 'Cool 4G';
    }
    if (RegExp(r'\b(8800L|7730L|6620L|M2000|M2100)\b').hasMatch(joined)) {
      return 'Jetpack';
    }
    if (RegExp(r'\b(MW4[015]|MW70|EE40|EE70|HH4[01]|HH7[01])\b')
        .hasMatch(joined)) {
      return 'Alcatel';
    }
    if (RegExp(r'\b(TL-WR|TL-MR|TL-WA|TD-W|ARCHER)\b').hasMatch(joined)) {
      return 'TP-Link';
    }
    if (RegExp(r'\b(DIR-|DSL-|DWR-|DAP-)').hasMatch(joined)) {
      return 'D-Link';
    }
    if (RegExp(r'\b(4G0[369]|4G18[05]|AC10|N301)\b').hasMatch(joined)) {
      return 'Tenda';
    }
    if (RegExp(r'\b(MIFI-L818|L818A?|M028T|L02[CH])\b').hasMatch(joined)) {
      return 'Notion';
    }
    if (RegExp(r'\b(MQ-725|WN-600|K5188)\b').hasMatch(joined)) {
      return 'GreenPacket';
    }
    return '';
  }

  static bool _hasWord(String lowerText, String word) {
    return RegExp('(?<![a-z])${RegExp.escape(word)}(?![a-z])').hasMatch(lowerText);
  }

  static String _vendorFromText(String text) {
    final lower = text.toLowerCase();
    String best = '';
    int bestHits = 0;
    _vendorKeywords.forEach((vendor, keys) {
      var hits = 0;
      for (final k in keys) {
        hits += RegExp('(?<![a-z])${RegExp.escape(k)}(?![a-z])').allMatches(lower).length;
      }
      if (hits > bestHits) {
        bestHits = hits;
        best = vendor;
      }
    });
    return best;
  }

  static String _resolveVendor({
    _UpnpInfo? upnp,
    required String primaryText,
    required String html,
  }) {
    if (upnp != null && upnp.manufacturer.isNotEmpty) {
      final fromUpnp = _vendorFromText(upnp.manufacturer);
      if (fromUpnp.isNotEmpty) return fromUpnp;
      final m = _cleanName(upnp.manufacturer);
      if (!_isGenericName(m) && m.length <= 24) return m;
    }
    final fromHeaders = _vendorFromText(primaryText);
    if (fromHeaders.isNotEmpty) return fromHeaders;
    final title = _htmlTitle(html);
    final fromTitle = _vendorFromText(title);
    if (fromTitle.isNotEmpty) return fromTitle;
    return _vendorFromText(html);
  }

  static String _htmlTitle(String html) {
    final m = RegExp(r'<title[^>]*>([^<]*)</title>', caseSensitive: false).firstMatch(html);
    return (m?.group(1) ?? '').trim();
  }

  static List<String> _upnpCandidates(_UpnpInfo? u) {
    if (u == null) return const [];
    final out = <String>[];
    if (u.modelName.isNotEmpty) {
      final num = u.modelNumber;
      final hasLetters = RegExp(r'[A-Za-z]').hasMatch(num);
      if (num.isNotEmpty &&
          hasLetters &&
          !u.modelName.toLowerCase().contains(num.toLowerCase())) {
        out.add('${u.modelName} $num');
      }
      out.add(u.modelName);
    }
    if (u.modelNumber.isNotEmpty && RegExp(r'[A-Za-z]').hasMatch(u.modelNumber)) {
      out.add(u.modelNumber);
    }
    if (u.friendlyName.isNotEmpty) out.add(u.friendlyName);
    return out;
  }

  static List<String> _htmlModelCandidates(String html) {
    final out = <String>[];
    final title = _htmlTitle(html);
    if (title.isNotEmpty) out.add(title);
    final patterns = [
      RegExp(
          r'''(?:model_?name|modelName|ModelName|product_?name|productName|ProductName|device_?name|deviceName|DeviceName|devicename|board_?name|device_?model|deviceModel|ProductClass|g_platformName)["']?\s*[:=]\s*["']([^"'<>\r\n]{2,40})["']'''),
      RegExp(
          r'<(?:ModelName|modelName|DeviceName|devicename|product_name|model_name|ProductClass)>([^<]{2,40})</'),
      RegExp(
          r'''<meta[^>]+name\s*=\s*["']description["'][^>]+content\s*=\s*["']([^"']{2,40})''',
          caseSensitive: false),
    ];
    for (final re in patterns) {
      for (final m in re.allMatches(html).take(4)) {
        final v = (m.group(1) ?? '').trim();
        if (v.isNotEmpty) out.add(v);
      }
    }
    return out;
  }

  static const Set<String> _genericWords = {
    'login', 'log', 'in', 'index', 'home', 'web', 'webui', 'ui', 'server',
    'router', 'wireless', 'mobile', 'wifi', 'wi', 'fi', 'mifi', 'hotspot',
    '4g', '5g', '3g', 'lte', 'modem', 'welcome', 'loading', 'redirect',
    'redirecting', 'page', 'main', 'admin', 'administrator', 'management',
    'manager', 'configuration', 'config', 'setup', 'status', 'gateway', 'portal',
    'cpe', 'broadband', 'device', 'default', 'http', 'https', 'null',
    'undefined', 'document', 'untitled', 'please', 'wait', 'the', 'to', 'of',
    'and', 'for', 'a', 'internet', 'igd', 'linux', 'upnp', 'miniupnpd',
    'network', 'access', 'point', 'ap', 'system', 'interface', 'utility',
    'my', 'new', 'user', 'sign', 'control', 'panel', 'center', 'centre',
    'dashboard', 'settings', 'error', 'not', 'found', '404', 'unauthorized',
    'forbidden', 'object', 'moved', 'ok', 'cgi', 'html', 'mobile-wifi',
  };

  static bool _isGenericName(String s) {
    final t = s.trim();
    if (t.length < 2) return true;
    if (t.contains('{{') || t.contains('<%') || t.contains(r'$(') || t.contains('var ')) {
      return true;
    }
    final words = t
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9\u0600-\u06FF]+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return true;
    return words.every((w) => _genericWords.contains(w));
  }

  static String _cleanName(String raw) {
    var s = raw
        .replaceAll(RegExp(r'&[a-z]+;'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    // Keep the most specific segment of titles like "HUAWEI B310 - Login".
    final segments = s
        .split(RegExp(r'\s+[-|–—:]\s+|\s*\|\s*'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (segments.length > 1) {
      final specific = segments.firstWhere(
        (e) => !_isGenericName(e),
        orElse: () => segments.first,
      );
      s = specific;
    }
    s = s
        .replaceAll(RegExp(r'\b(Wireless Router|Web Management|Web UI|WebUI|Login Page|Log In|Login)\b',
            caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (s.length > 40) s = s.substring(0, 40).trim();
    return s;
  }

  static String _composeModelName({
    required String vendor,
    required List<String> candidates,
    required String ip,
    required String fallback,
  }) {
    for (final c in candidates) {
      final clean = _cleanName(c);
      if (_isGenericName(clean)) continue;
      // Avoid using the vendor alone as the "model".
      if (vendor.isNotEmpty && clean.toLowerCase() == vendor.toLowerCase()) continue;
      if (vendor.isNotEmpty) {
        final vLower = vendor.toLowerCase().replaceAll('-', '');
        final cLower = clean.toLowerCase().replaceAll('-', '');
        if (!cLower.contains(vLower)) return '$vendor $clean';
      }
      return clean;
    }
    if (vendor.isNotEmpty) {
      return fallback.isNotEmpty ? '$vendor $fallback' : 'مودم $vendor';
    }
    if (fallback.isNotEmpty) return fallback;
    return 'مودم ($ip)';
  }

  static String _xmlTag(String xml, String tag) {
    final m = RegExp('<$tag>([^<]*)</$tag>', caseSensitive: false).firstMatch(xml);
    return (m?.group(1) ?? '').trim();
  }

  /// Better model name from data read AFTER login (e.g. Notion `device_name`,
  /// Huawei `DeviceName`). Returns `null` when nothing better is available.
  static String? improveModelName(ModemIdentity id, String deviceModel) {
    final clean = _cleanName(deviceModel);
    if (_isGenericName(clean)) return null;
    final vendor = id.vendor;
    String candidate = clean;
    if (vendor.isNotEmpty &&
        !clean.toLowerCase().replaceAll('-', '').contains(vendor.toLowerCase().replaceAll('-', ''))) {
      candidate = '$vendor $clean';
    }
    if (candidate == id.modelName) return null;
    return candidate;
  }

  /// SSDP M-SEARCH (unicast to gateway + multicast) → fetch root description XML.
  static Future<_UpnpInfo?> _discoverUpnp(String ip, String localIp) async {
    RawDatagramSocket? sock;
    try {
      final bindAddr = resolveBindAddress(localIp, ip) ?? InternetAddress.anyIPv4;
      sock = await RawDatagramSocket.bind(bindAddr, 0);
      final msg = utf8.encode(
        'M-SEARCH * HTTP/1.1\r\n'
        'HOST: 239.255.255.250:1900\r\n'
        'MAN: "ssdp:discover"\r\n'
        'MX: 1\r\n'
        'ST: upnp:rootdevice\r\n\r\n',
      );
      final locations = <String>{};
      final s = sock;
      final gotPacket = Completer<void>();
      final sub = s.listen((ev) {
        if (ev != RawSocketEvent.read) return;
        final dg = s.receive();
        if (dg == null || dg.address.address != ip) return;
        final text = utf8.decode(dg.data, allowMalformed: true);
        final m = RegExp(r'^location:\s*(\S+)', caseSensitive: false, multiLine: true)
            .firstMatch(text);
        if (m != null) {
          locations.add(m.group(1)!.trim());
          if (!gotPacket.isCompleted) gotPacket.complete();
        }
      });
      s.send(msg, InternetAddress(ip), 1900);
      try {
        s.send(msg, InternetAddress('239.255.255.250'), 1900);
      } catch (_) {}
      await gotPacket.future
          .timeout(const Duration(milliseconds: 450), onTimeout: () {});
      await sub.cancel();
      s.close();
      sock = null;

      for (final loc in locations) {
        final uri = Uri.tryParse(loc);
        if (uri == null || uri.host != ip || uri.scheme != 'http') continue;
        final path = (uri.path.isEmpty ? '/' : uri.path) + (uri.hasQuery ? '?${uri.query}' : '');
        final p = await _rawHttp(ip, path, localIp,
            port: uri.hasPort ? uri.port : 80,
            timeout: const Duration(milliseconds: 2500));
        if (!p.responded) continue;
        final info = _UpnpInfo(
          manufacturer: _xmlTag(p.body, 'manufacturer'),
          modelName: _xmlTag(p.body, 'modelName'),
          modelNumber: _xmlTag(p.body, 'modelNumber'),
          friendlyName: _xmlTag(p.body, 'friendlyName'),
        );
        if (info.manufacturer.isNotEmpty || info.modelName.isNotEmpty) return info;
      }
    } catch (_) {
    } finally {
      sock?.close();
    }
    return null;
  }
}
