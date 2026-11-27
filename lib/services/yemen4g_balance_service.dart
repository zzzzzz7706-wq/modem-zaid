import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import '../models/modem_models.dart';

/// Native client for Yemen 4G Balance Inquiry (svc.ptc.gov.ye/4g).
/// Fetches session nonce & CAPTCHA image bytes directly and parses the HTML
/// response into native Arabic cards without displaying a raw web browser.
class Yemen4gBalanceService {
  static const String _portalUrl = 'https://svc.ptc.gov.ye/4g/';
  static const String _captchaBaseUrl =
      'https://svc.ptc.gov.ye/wp-content/plugins/query4g-bill-api/securimage/securimage_show.php?namespace=q4g_one_captcha';

  final Map<String, String> _cookies = {};
  String _nonceField = '';

  HttpClient _createHttpClient() {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);
    // PTC portal uses government SSL chain that some older Android trust stores flag
    client.badCertificateCallback =
        (X509Certificate cert, String host, int port) =>
            host.endsWith('ptc.gov.ye') || host.endsWith('yemen.net.ye');
    return client;
  }

  void _captureCookies(HttpClientResponse response) {
    for (final c in response.cookies) {
      _cookies[c.name] = c.value;
    }
  }

  String get _cookieHeader =>
      _cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');

  /// Loads portal session & returns live CAPTCHA PNG image bytes.
  Future<Uint8List?> loadCaptchaSession() async {
    final client = _createHttpClient();
    try {
      // 1. Load main form page to obtain session cookies and hidden nonce
      final req = await client.getUrl(Uri.parse(_portalUrl));
      req.headers.set(
        HttpHeaders.userAgentHeader,
        'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/124.0 Mobile Safari/537.36',
      );
      final res = await req.close().timeout(const Duration(seconds: 12));
      _captureCookies(res);
      final html = await utf8.decoder.bind(res).join();

      final nonceMatch = RegExp(
        r'name="qb4g_nonce_field"\s+value="([^"]+)"',
        caseSensitive: false,
      ).firstMatch(html);
      if (nonceMatch != null) {
        _nonceField = nonceMatch.group(1) ?? '';
      }

      // 2. Fetch CAPTCHA image using the same session cookie
      final capUri = Uri.parse(
        '$_captchaBaseUrl&t=${DateTime.now().millisecondsSinceEpoch}',
      );
      final capReq = await client.getUrl(capUri);
      if (_cookies.isNotEmpty) {
        capReq.headers.set(HttpHeaders.cookieHeader, _cookieHeader);
      }
      capReq.headers.set(HttpHeaders.refererHeader, _portalUrl);
      final capRes = await capReq.close().timeout(const Duration(seconds: 10));
      _captureCookies(capRes);

      final builder = BytesBuilder();
      await for (final chunk in capRes) {
        builder.add(chunk);
      }
      final bytes = builder.takeBytes();
      return bytes.isNotEmpty ? bytes : null;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Submits phone number & CAPTCHA code and translates result into BalanceInfo.
  Future<BalanceInfo> queryBalance({
    required String phoneNumber,
    required String captchaCode,
  }) async {
    final cleanPhone = phoneNumber.replaceAll(RegExp(r'\s+'), '');
    final cleanCaptcha = captchaCode.trim();

    final client = _createHttpClient();
    try {
      final req = await client.postUrl(Uri.parse(_portalUrl));
      req.headers.set(
        HttpHeaders.contentTypeHeader,
        'application/x-www-form-urlencoded; charset=UTF-8',
      );
      req.headers.set(HttpHeaders.refererHeader, _portalUrl);
      if (_cookies.isNotEmpty) {
        req.headers.set(HttpHeaders.cookieHeader, _cookieHeader);
      }

      final bodyMap = {
        'qb4g_nonce_field': _nonceField,
        '_wp_http_referer': '/4g/',
        'qb4g_submit': 'YES',
        'phone4gidnew': cleanPhone,
        'captcha_code_q4Gbill': cleanCaptcha,
        'qsubmitnew': 'استعلام',
      };
      final encodedBody = bodyMap.entries
          .map((e) =>
              '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
          .join('&');

      req.add(utf8.encode(encodedBody));
      final res = await req.close().timeout(const Duration(seconds: 15));
      _captureCookies(res);
      final html = await utf8.decoder.bind(res).join();

      return _parsePortalHtml(cleanPhone, html);
    } finally {
      client.close(force: true);
    }
  }

  BalanceInfo _parsePortalHtml(String phone, String html) {
    // Extract #qbillmsgnew block if present
    String section = html;
    final msgIdx = html.indexOf('id="qbillmsgnew"');
    if (msgIdx != -1) {
      final endIdx = html.indexOf('</form>', msgIdx);
      section = html.substring(
        msgIdx,
        endIdx != -1 ? endIdx : (msgIdx + 4000).clamp(0, html.length),
      );
    }

    // Extract table rows <tr><td>Key</td><td>Value</td></tr>
    final details = <String, String>{};
    final rowRegex = RegExp(
      r'<tr[^>]*>\s*<t[dh][^>]*>(.*?)</t[dh]>\s*<t[dh][^>]*>(.*?)</t[dh]>\s*</tr>',
      dotAll: true,
      caseSensitive: false,
    );
    for (final m in rowRegex.allMatches(section)) {
      final k = _stripHtml(m.group(1) ?? '');
      final v = _stripHtml(m.group(2) ?? '');
      if (k.isNotEmpty && v.isNotEmpty) {
        details[k] = v;
      }
    }

    String balance = '';
    String pkg = '';
    String expiry = '';

    details.forEach((k, v) {
      if (k.contains('رصيد') || k.contains('متبقي') || k.contains('حجم')) {
        if (balance.isEmpty) balance = v;
      } else if (k.contains('باقة') || k.contains('سرعة') || k.contains('نوع')) {
        if (pkg.isEmpty) pkg = v;
      } else if (k.contains('تاريخ') || k.contains('انتهاء') || k.contains('صلاحية')) {
        if (expiry.isEmpty) expiry = v;
      }
    });

    final cleanText = _stripHtml(section);
    if (balance.isEmpty) {
      final gbMatch = RegExp(r'(\d+(?:\.\d+)?\s*(?:جيجا|ميجا|GB|MB)[^\n<]{0,20})',
              caseSensitive: false)
          .firstMatch(cleanText);
      if (gbMatch != null) {
        balance = gbMatch.group(1)!.trim();
      }
    }

    String statusMsg = '';
    if (cleanText.contains('رمز التحقق') || cleanText.contains('غير صحيح')) {
      statusMsg = 'رمز التحقق أو رقم الهاتف غير صحيح، يرجى المحاولة مجدداً.';
    } else if (details.isEmpty && balance.isEmpty) {
      statusMsg = cleanText.length > 220
          ? cleanText.substring(0, 220).trim()
          : cleanText.trim();
      if (statusMsg.isEmpty) {
        statusMsg = 'لم يتم العثور على بيانات لهذا الرقم أو انتهت الجلسة.';
      }
    } else {
      statusMsg = 'تم جلب بيانات الرصيد بنجاح';
    }

    return BalanceInfo(
      phoneNumber: phone,
      remainingBalance: balance.isEmpty ? 'راجع التفاصيل أدناه' : balance,
      packageName: pkg,
      expiryDate: expiry,
      statusMessage: statusMsg,
      details: details,
    );
  }

  static String _stripHtml(String input) {
    return input
        .replaceAll(RegExp(r'<script[^>]*>.*?</script>', dotAll: true), ' ')
        .replaceAll(RegExp(r'<style[^>]*>.*?</style>', dotAll: true), ' ')
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
