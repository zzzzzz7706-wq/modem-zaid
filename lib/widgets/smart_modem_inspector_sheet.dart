import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/modem_models.dart';
import '../services/app_controller.dart';
import '../services/smart_modem_profiler.dart';

void showSmartModemInspectorSheet(
  BuildContext context,
  AppController controller,
) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _SmartModemInspectorSheet(controller: controller),
  );
}

class _SmartModemInspectorSheet extends StatefulWidget {
  final AppController controller;

  const _SmartModemInspectorSheet({required this.controller});

  @override
  State<_SmartModemInspectorSheet> createState() =>
      _SmartModemInspectorSheetState();
}

class _SmartModemInspectorSheetState extends State<_SmartModemInspectorSheet> {
  bool _scanning = true;
  SmartModemProfile? _profile;
  String? _error;

  @override
  void initState() {
    super.initState();
    _runScan();
  }

  Future<void> _runScan() async {
    setState(() {
      _scanning = true;
      _error = null;
    });
    try {
      final prof = await widget.controller.inspectConnectedModem();
      if (mounted) {
        setState(() {
          _profile = prof;
          _scanning = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'تعذر فحص المودم. تأكد من اتصالك بشبكة الواي فاي الخاصة بالمودم.';
          _scanning = false;
        });
      }
    }
  }

  String _familyLabel(ModemFamily? fam) {
    if (fam == null) return 'تلقائي ذكي (موصى به)';
    switch (fam) {
      case ModemFamily.zteGoform:
        return 'Star Speed / ZTE / Olax CGI';
      case ModemFamily.tozedZlt:
        return 'Star Speed / ZLT / Tozed (JSON CGI)';
      case ModemFamily.marvellUapxc:
        return 'Yemen 4G CPE (UAPXC)';
      case ModemFamily.notionMifi:
        return 'Notion / L818A MiFi';
      case ModemFamily.huaweiHilink:
        return 'Huawei / Brovi HiLink';
      case ModemFamily.universalTranslated:
        return 'المترجم الذكي (QCMAP / Alcatel / عام)';
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.controller.palette;
    final prof = _profile;

    return DraggableScrollableSheet(
      initialChildSize: 0.82,
      minChildSize: 0.5,
      maxChildSize: 0.94,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: p.bgCard,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: p.borderSubtle),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: p.textSecondary.withOpacity(0.35),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: Row(
                children: [
                  Icon(Icons.auto_awesome_rounded, color: p.accentPrimary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'محلل المودم الذكي الشامل',
                          style: TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w800,
                            color: p.textPrimary,
                          ),
                        ),
                        Text(
                          'فحص عميق لـ HTML/JS وبروتوكولات أي مودم يمن فورجي',
                          style: TextStyle(fontSize: 11.5, color: p.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _scanning ? null : _runScan,
                    tooltip: 'إعادة الفحص',
                    icon: Icon(Icons.refresh_rounded, color: p.accentSecondary),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close_rounded, color: p.textSecondary),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: p.borderSubtle),
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.all(16),
                children: [
                  // Protocol Override Card
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: p.bgElevated.withOpacity(0.65),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: p.borderSubtle),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'وضع اختيار البروتوكول',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: p.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'إذا لم يتعرف التطبيق على مودم نادر تلقائياً، يمكنك تجربة اختيار بروتوكوله مباشرة:',
                          style: TextStyle(fontSize: 11.5, color: p.textSecondary),
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<ModemFamily?>(
                          value: widget.controller.forcedFamily,
                          dropdownColor: p.bgCard,
                          style: TextStyle(
                            color: p.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'Cairo',
                          ),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: p.bgCard,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: p.borderSubtle),
                            ),
                          ),
                          items: [
                            DropdownMenuItem<ModemFamily?>(
                              value: null,
                              child: Text(_familyLabel(null)),
                            ),
                            ...ModemFamily.values.map(
                              (f) => DropdownMenuItem<ModemFamily?>(
                                value: f,
                                child: Text(_familyLabel(f)),
                              ),
                            ),
                          ],
                          onChanged: (val) async {
                            await widget.controller.setForcedFamily(val);
                            if (mounted) setState(() {});
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  if (_scanning)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 36),
                      child: Column(
                        children: [
                          CircularProgressIndicator(color: p.accentPrimary),
                          const SizedBox(height: 14),
                          Text(
                            'جاري فحص نقاط الاتصال وتحليل ملفات المودم...',
                            style: TextStyle(color: p.textSecondary, fontSize: 13),
                          ),
                        ],
                      ),
                    )
                  else if (_error != null)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: p.danger.withOpacity(0.14),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: p.danger.withOpacity(0.4)),
                      ),
                      child: Text(
                        _error!,
                        style: TextStyle(color: p.danger, fontWeight: FontWeight.w700),
                      ),
                    )
                  else if (prof != null) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: p.bgElevated.withOpacity(0.55),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: p.borderSubtle),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'نتائج التحليل الذكي',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: p.accentSecondary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _row('عنوان البوابة', prof.gatewayIp, p),
                          _row(
                            'عنوان الصفحة',
                            prof.pageTitle.isEmpty ? 'غير متوفر' : prof.pageTitle,
                            p,
                          ),
                          _row(
                            'الخادم',
                            prof.serverHeader.isEmpty ? 'غير محدد' : prof.serverHeader,
                            p,
                          ),
                          _row(
                            'البروتوكول المكتشف',
                            prof.detectedProtocol.isEmpty
                                ? 'المترجم الذكي التكيّفي'
                                : prof.detectedProtocol,
                            p,
                          ),
                          _row('تشفير الدخول', prof.encodingArabic, p),
                          if (prof.loginAction.isNotEmpty)
                            _row('مسار الدخول', prof.loginAction, p),
                          _row(
                            'ملفات JS المفحوصة',
                            '${prof.scriptPaths.length}',
                            p,
                          ),
                          _row(
                            'نقاط API المكتشفة',
                            '${prof.discoveredEndpoints.length}',
                            p,
                          ),
                        ],
                      ),
                    ),
                    if (prof.probedApiResults.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: p.bgElevated.withOpacity(0.55),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: p.borderSubtle),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'الواجهات المستجيبة على المودم',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                                color: p.success,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ...prof.probedApiResults.entries.map(
                              (e) => Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      e.key,
                                      textDirection: TextDirection.ltr,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: p.accentPrimary,
                                      ),
                                    ),
                                    Text(
                                      e.value,
                                      textDirection: TextDirection.ltr,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: p.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: p.accentPrimary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: prof.toFingerprintReport()),
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'تم نسخ بصمة المودم بنجاح (بدون أي كلمات مرور)',
                              ),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.copy_rounded, size: 19),
                      label: const Text(
                        'نسخ بصمة المودم',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String k, String v, dynamic p) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(k, style: TextStyle(fontSize: 12, color: p.textSecondary)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              v,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.left,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: p.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
