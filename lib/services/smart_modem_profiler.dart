import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../models/modem_models.dart';
import 'modem_detector.dart';

/// Profile produced by introspecting a modem's HTML pages, `<form>` elements,
/// and frontend JavaScript files (login.js, config.js, service.js, app.js).
class SmartModemProfile {
  final String gatewayIp;
  final String scheme;
  final int port;
  final String serverHeader;
  final String pageTitle;
  final String detectedProtocol;
  final ModemFamily? familyHint;
  final String loginAction;
  final String usernameField;
  final String passwordField;
  final Map<String, String> hiddenFields;
  final String passwordEncoding; // sha256_upper, sha256_lower, md5_lower, base64, plain, ''
  final bool usesMultiUserLogin;
  final List<String> scriptPaths;
  final List<String> discoveredEndpoints;
  final List<String> statusEndpoints;
  final List<String> wifiEndpoints;
  final List<String> rebootEndpoints;
  final Map<String, String> probedApiResults;

  const SmartModemProfile({
    required this.gatewayIp,
    this.scheme = 'http',
    this.port = 80,
    this.serverHeader = '',
    this.pageTitle = '',
    this.detectedProtocol = '',
    this.familyHint,
    this.loginAction = '',
    this.usernameField = '',
    this.passwordField = '',
    this.hiddenFields = const {},
    this.passwordEncoding = '',
    this.usesMultiUserLogin = false,
    this.scriptPaths = const [],
    this.discoveredEndpoints = const [],
    this.statusEndpoints = const [],
    this.wifiEndpoints = const [],
    this.rebootEndpoints = const [],
    this.probedApiResults = const {},
  });

  bool get hasFormLogin => loginAction.isNotEmpty || passwordField.isNotEmpty;

  String get encodingArabic {
    switch (passwordEncoding) {
      case 'sha256_upper':
        return 'SHA-256 (أحرف كبيرة)';
      case 'sha256_lower':
        return 'SHA-256 (أحرف صغيرة)';
      case 'md5_lower':
        return 'MD5';
      case 'base64':
        return 'Base64';
      case 'tcl_xor':
        return 'TCL / Alcatel XOR';
      case 'plain':
        return 'نص مباشر';
      default:
        return 'تلقائي متعدد المحاولات';
    }
  }

  /// Generates a clean diagnostic fingerprint report (zero credentials)
  /// that the user can copy or inspect for any unknown Yemen 4G modem.
  String toFingerprintReport() {
    final buf = StringBuffer()
      ..writeln('=== بصمة المودم الذكية (Modem Zaid Inspector) ===')
      ..writeln('Gateway: $scheme://$gatewayIp:$port')
      ..writeln('Title: ${pageTitle.isEmpty ? "(فارغ)" : pageTitle}')
      ..writeln('Server: ${serverHeader.isEmpty ? "(غير محدد)" : serverHeader}')
      ..writeln('Detected Protocol: ${detectedProtocol.isEmpty ? "عام" : detectedProtocol}')
      ..writeln('Password Encoding: ${passwordEncoding.isEmpty ? "auto" : passwordEncoding}')
      ..writeln('Multi-User Login: $usesMultiUserLogin');
    if (loginAction.isNotEmpty) buf.writeln('Login Action: $loginAction');
    if (usernameField.isNotEmpty || passwordField.isNotEmpty) {
      buf.writeln('Form Fields: user="$usernameField", pass="$passwordField"');
    }
    if (scriptPaths.isNotEmpty) {
      buf.writeln('Scripts Inspected: ${scriptPaths.join(", ")}');
    }
    if (probedApiResults.isNotEmpty) {
      buf.writeln('--- Probed APIs ---');
      probedApiResults.forEach((k, v) => buf.writeln('  $k => $v'));
    }
    if (discoveredEndpoints.isNotEmpty) {
      buf.writeln('--- Discovered Endpoints (${discoveredEndpoints.length}) ---');
      for (final ep in discoveredEndpoints.take(20)) {
        buf.writeln('  $ep');
      }
    }
    return buf.toString().trim();
  }
}

class SmartModemProfiler {
  static final RegExp _skipVendorScript = RegExp(
    r'(?:jquery|bootstrap|angular|react|vue|lodash|underscore|moment|echarts|chart\.?js|polyfill|fontawesome|popper|swiper|crypto-js|aes\.min|rsa\.min|md5\.min|sha256\.min)',
    caseSensitive: false,
  );

  static final RegExp _priorityScript = RegExp(
    r'(?:login|auth|config|service|api|main|app|common|index|home|status|router|modem|util|ajax|http|cgi)',
    caseSensitive: false,
  );

  static Future<String> _fetchSmallText(
    String ip,
    String path,
    String localIp, {
    int port = 80,
    Duration timeout = const Duration(milliseconds: 1600),
  }) async {
    Socket? sock;
    try {
      sock = await ModemDetector.connectLanSocket(
        ip,
        port,
        localIp: localIp,
        timeout: timeout,
      );
      final hostHdr = port == 80 ? ip : '$ip:$port';
      final req = 'GET $path HTTP/1.1\r\n'
          'Host: $hostHdr\r\n'
          'User-Agent: Mozilla/5.0 (Linux; Android) ModemZaid\r\n'
          'Accept: */*\r\n'
          'Connection: close\r\n\r\n';
      sock.add(utf8.encode(req));
      await sock.flush();
      final raw = await ModemDetector.readHttpResponseBytes(
        sock,
        timeout: timeout,
      );
      if (raw.isEmpty) return '';
      final text = utf8.decode(raw, allowMalformed: true);
      final split = text.indexOf('\r\n\r\n');
      if (split == -1) return '';
      final head = text.substring(0, split);
      if (!RegExp(r'HTTP/\d\.\d\s+200').hasMatch(head)) return '';
      final body = text.substring(split + 4);
      return body.length > 96000 ? body.substring(0, 96000) : body;
    } catch (_) {
      return '';
    } finally {
      try {
        sock?.destroy();
      } catch (_) {}
    }
  }

  /// Extracts candidate `<script src="...">` paths from HTML, prioritizing app/login JS.
  static List<String> extractAppScriptPaths(String html) {
    final all = <String>[];
    final seen = <String>{};
    for (final m in RegExp(
      r'''<script[^>]+src\s*=\s*["']([^"']+\.js(?:\?[^"']*)?)["']''',
      caseSensitive: false,
    ).allMatches(html)) {
      var src = (m.group(1) ?? '').trim();
      if (src.isEmpty ||
          src.startsWith('http://') ||
          src.startsWith('https://') ||
          src.startsWith('//')) {
        continue;
      }
      if (!src.startsWith('/')) src = '/$src';
      final cleanNoQuery = src.split('?').first;
      if (_skipVendorScript.hasMatch(cleanNoQuery)) continue;
      if (seen.add(cleanNoQuery)) {
        all.add(cleanNoQuery);
      }
    }
    all.sort((a, b) {
      final ap = _priorityScript.hasMatch(a) ? 0 : 1;
      final bp = _priorityScript.hasMatch(b) ? 0 : 1;
      return ap.compareTo(bp);
    });
    return all.take(4).toList();
  }

  /// Fast introspection of already-fetched HTML plus up to 4 small app JS scripts.
  static Future<SmartModemProfile> profileFromHtml({
    required String ip,
    required String localIp,
    required String html,
    required Map<String, String> headers,
    String scheme = 'http',
    int port = 80,
    Map<String, String> probedApiResults = const {},
  }) async {
    final scripts = extractAppScriptPaths(html);
    final jsBodies = <String>[];
    final fetchedScripts = <String>[];

    if (scripts.isNotEmpty) {
      final fetched = await Future.wait(
        scripts.map((path) async {
          final body = await _fetchSmallText(ip, path, localIp, port: port);
          return (path, body);
        }),
      );
      for (final (path, body) in fetched) {
        if (body.isNotEmpty) {
          fetchedScripts.add(path);
          jsBodies.add(body);
        }
      }
    }

    final combined = '$html\n${jsBodies.join('\n')}';
    return _analyzeCombined(
      ip: ip,
      scheme: scheme,
      port: port,
      html: html,
      combined: combined,
      headers: headers,
      scriptPaths: fetchedScripts,
      probedApiResults: probedApiResults,
    );
  }

  static SmartModemProfile _analyzeCombined({
    required String ip,
    required String scheme,
    required int port,
    required String html,
    required String combined,
    required Map<String, String> headers,
    required List<String> scriptPaths,
    required Map<String, String> probedApiResults,
  }) {
    final title = RegExp(r'<title[^>]*>([^<]*)</title>', caseSensitive: false)
            .firstMatch(html)
            ?.group(1)
            ?.trim() ??
        '';
    final serverHdr = headers['server'] ?? '';

    // 1. Discover API/CGI endpoints from HTML & JS
    final epSet = <String>{};
    final epRegex = RegExp(
      r'''["'`](\/(?:cgi-bin|goform|reqproc|api|jrd|ubus|action|srv|Forms|boaform|web_whw|xml_action\.cgi|login\.cgi|submitLogin)[^"'`\s?#]{0,60})["'`]''',
    );
    for (final m in epRegex.allMatches(combined)) {
      final ep = (m.group(1) ?? '').trim();
      if (ep.length >= 4 && !ep.endsWith('.css') && !ep.endsWith('.png') && !ep.endsWith('.jpg')) {
        epSet.add(ep);
      }
    }
    final endpoints = epSet.toList()..sort();

    // 2. Parse HTML <form> for dynamic login
    String loginAction = '';
    String usernameField = '';
    String passwordField = '';
    final hiddenFields = <String, String>{};

    final formMatch = RegExp(
      r'<form\b([^>]*)>([\s\S]*?)</form>',
      caseSensitive: false,
    ).firstMatch(html);
    if (formMatch != null) {
      final formAttrs = formMatch.group(1) ?? '';
      final formBody = formMatch.group(2) ?? '';
      final act = RegExp(r'''action\s*=\s*["']?([^"'\s>]+)''', caseSensitive: false)
          .firstMatch(formAttrs)
          ?.group(1)
          ?.trim();
      if (act != null && act.isNotEmpty && act != '#') {
        loginAction = act.startsWith('/') ? act : '/$act';
      }
      for (final inp in RegExp(r'<input\b[^>]*>', caseSensitive: false).allMatches(formBody)) {
        final tag = inp.group(0)!;
        final type = RegExp(r'''type\s*=\s*["']?([a-zA-Z]+)''', caseSensitive: false)
                .firstMatch(tag)
                ?.group(1)
                ?.toLowerCase() ??
            'text';
        final name = RegExp(r'''name\s*=\s*["']?([^"'\s>]+)''', caseSensitive: false)
                .firstMatch(tag)
                ?.group(1)
                ?.trim() ??
            '';
        final val = RegExp(r'''value\s*=\s*["']([^"']*)["']''', caseSensitive: false)
                .firstMatch(tag)
                ?.group(1) ??
            '';
        if (name.isEmpty) continue;
        if (type == 'password') {
          passwordField = name;
        } else if (type == 'hidden') {
          hiddenFields[name] = val;
        } else if ((type == 'text' || type == 'email') && usernameField.isEmpty) {
          usernameField = name;
        }
      }
    }

    // 3. Detect password encoding algorithm from JS code
    final lower = combined.toLowerCase();
    String encoding = '';
    if (combined.contains('_TclRequestVerificationKey') || lower.contains('jrd/webapi')) {
      encoding = 'tcl_xor';
    } else if (RegExp(r'hex_sha256|sha256\s*\(|cryptojs\.sha256', caseSensitive: false)
        .hasMatch(combined)) {
      if (combined.contains('toLowerCase') && !combined.contains('toUpperCase')) {
        encoding = 'sha256_lower';
      } else {
        encoding = 'sha256_upper';
      }
    } else if (RegExp(r'hex_md5|md5\s*\(|cryptojs\.md5', caseSensitive: false)
        .hasMatch(combined)) {
      encoding = 'md5_lower';
    } else if (RegExp(r'base64\.encode|btoa\s*\(|encode64|base64encode', caseSensitive: false)
        .hasMatch(combined)) {
      encoding = 'base64';
    }

    final usesMultiUserLogin =
        combined.contains('LOGIN_MULTI_USER') ||
        RegExp(r'SHOW_LOGIN_USERNAME\s*:\s*true', caseSensitive: false).hasMatch(combined);

    // 4. Categorize discovered endpoints
    final statusEps = <String>[];
    final wifiEps = <String>[];
    final rebootEps = <String>[];
    for (final ep in endpoints) {
      final l = ep.toLowerCase();
      if (loginAction.isEmpty && (l.contains('login') || l.contains('auth'))) {
        loginAction = ep;
      }
      if (l.contains('status') || l.contains('info') || l.contains('sys') || l.contains('wan') || l.contains('device')) {
        statusEps.add(ep);
      }
      if (l.contains('wifi') || l.contains('wlan') || l.contains('wireless')) {
        wifiEps.add(ep);
      }
      if (l.contains('reboot') || l.contains('restart')) {
        rebootEps.add(ep);
      }
    }

    // 5. Infer protocol family hint
    ModemFamily? hint;
    String protoLabel = '';
    if (endpoints.any((e) => e.contains('goform_get_cmd_process') || e.contains('reqproc/proc_get'))) {
      hint = ModemFamily.zteGoform;
      protoLabel = 'ZTE / Star Speed / Qualcomm CGI';
    } else if (endpoints.any((e) => e.contains('/cgi-bin/http.cgi') || e.contains('/cgi-bin/lua.cgi')) ||
        lower.contains('cgi-bin/http.cgi') ||
        lower.contains('cgi-bin/lua.cgi')) {
      hint = ModemFamily.tozedZlt;
      protoLabel = 'Tozed / ZLT / Star Speed JSON CGI';
    } else if (endpoints.any((e) => e.contains('/jrd/webapi')) || lower.contains('jrd/webapi')) {
      hint = ModemFamily.universalTranslated;
      protoLabel = 'Alcatel / TCL / Speed 4G JSON-RPC';
    } else if (endpoints.any((e) => e.contains('qcmap_')) || lower.contains('qcmap_web_cgi')) {
      hint = ModemFamily.universalTranslated;
      protoLabel = 'Qualcomm QCMAP 4G CGI';
    } else if (endpoints.any((e) => e.startsWith('/ubus')) || lower.contains('luci')) {
      hint = ModemFamily.universalTranslated;
      protoLabel = 'OpenWrt / LuCI ubus';
    } else if (endpoints.any((e) => e.contains('xml_action.cgi'))) {
      hint = combined.contains('wifiSetting.js')
          ? ModemFamily.marvellUapxc
          : ModemFamily.notionMifi;
      protoLabel = combined.contains('wifiSetting.js')
          ? 'Yemen 4G CPE (UAPXC)'
          : 'Notion / Yemen 4G MiFi';
    } else if (endpoints.any((e) => e.contains('/api/webserver/'))) {
      hint = ModemFamily.huaweiHilink;
      protoLabel = 'Huawei HiLink API';
    } else if (endpoints.isNotEmpty) {
      hint = ModemFamily.universalTranslated;
      protoLabel = 'المترجم الذكي التكيّفي (${endpoints.length} نقطة اتصال)';
    }

    return SmartModemProfile(
      gatewayIp: ip,
      scheme: scheme,
      port: port,
      serverHeader: serverHdr,
      pageTitle: title,
      detectedProtocol: protoLabel,
      familyHint: hint,
      loginAction: loginAction,
      usernameField: usernameField,
      passwordField: passwordField,
      hiddenFields: hiddenFields,
      passwordEncoding: encoding,
      usesMultiUserLogin: usesMultiUserLogin,
      scriptPaths: scriptPaths,
      discoveredEndpoints: endpoints,
      statusEndpoints: statusEps,
      wifiEndpoints: wifiEps,
      rebootEndpoints: rebootEps,
      probedApiResults: probedApiResults,
    );
  }

  /// Full live deep inspection used by the "محلل المودم الذكي" UI sheet.
  static Future<SmartModemProfile> inspectGateway(
    String ip,
    String localIp,
  ) async {
    final probes = <String, String>{};
    final probePaths = <String>[
      '/',
      '/login.cgi',
      '/goform/goform_get_cmd_process?isTest=false&cmd=LD',
      '/reqproc/proc_get?isTest=false&cmd=LD',
      '/cgi-bin/http.cgi',
      '/cgi-bin/lua.cgi',
      '/cgi-bin/qcmap_auth',
      '/jrd/webapi',
      '/api/webserver/SesTokInfo',
      '/ubus',
      '/srv/status',
    ];

    String rootHtml = '';
    final rootHeaders = <String, String>{};

    await Future.wait(
      probePaths.map((path) async {
        Socket? sock;
        try {
          sock = await ModemDetector.connectLanSocket(
            ip,
            80,
            localIp: localIp,
            timeout: const Duration(milliseconds: 1800),
          );
          final req = 'GET $path HTTP/1.1\r\n'
              'Host: $ip\r\n'
              'User-Agent: Mozilla/5.0 (Linux; Android) ModemZaid\r\n'
              'Referer: http://$ip/index.html\r\n'
              'Connection: close\r\n\r\n';
          sock.add(utf8.encode(req));
          await sock.flush();
          final raw = await ModemDetector.readHttpResponseBytes(
            sock,
            timeout: const Duration(milliseconds: 1800),
            isHeaderOnlyChallenge: path == '/login.cgi',
          );
          if (raw.isEmpty) return;
          final text = utf8.decode(raw, allowMalformed: true);
          final split = text.indexOf('\r\n\r\n');
          final head = split != -1 ? text.substring(0, split) : text;
          final body = split != -1 ? text.substring(split + 4) : '';
          final lines = head.split('\r\n');
          final statusLine = lines.isNotEmpty ? lines.first : '';
          final codeMatch = RegExp(r'HTTP/\d\.\d\s+(\d{3})').firstMatch(statusLine);
          final code = codeMatch?.group(1) ?? '0';

          if (path == '/') {
            rootHtml = body;
            for (final line in lines.skip(1)) {
              final idx = line.indexOf(':');
              if (idx > 0) {
                rootHeaders[line.substring(0, idx).trim().toLowerCase()] =
                    line.substring(idx + 1).trim();
              }
            }
          } else if (code != '404' && code != '0') {
            final preview = body
                .replaceAll(RegExp(r'\s+'), ' ')
                .trim();
            final shortPreview =
                preview.length > 60 ? '${preview.substring(0, 60)}...' : preview;
            probes[path] = 'HTTP $code${shortPreview.isNotEmpty ? ' • $shortPreview' : ''}';
          }
        } catch (_) {
        } finally {
          try {
            sock?.destroy();
          } catch (_) {}
        }
      }),
    );

    return profileFromHtml(
      ip: ip,
      localIp: localIp,
      html: rootHtml,
      headers: rootHeaders,
      probedApiResults: probes,
    );
  }
}
