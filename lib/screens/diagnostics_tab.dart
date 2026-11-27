import 'package:flutter/material.dart';
import '../services/app_controller.dart';
import '../widgets/smart_modem_inspector_sheet.dart';
import '../widgets/wifi_quick_modal.dart';

class DiagnosticsTab extends StatefulWidget {
  final AppController controller;

  const DiagnosticsTab({super.key, required this.controller});

  @override
  State<DiagnosticsTab> createState() => _DiagnosticsTabState();
}

class _DiagnosticsTabState extends State<DiagnosticsTab> {
  bool _runningPing = false;
  Map<String, int?> _pingResults = {};

  Future<void> _runPingSuite() async {
    setState(() {
      _runningPing = true;
      _pingResults = {};
    });

    final gw = widget.controller.identity.gatewayIp;
    final targets = <String, (String, int)>{
      'بوابة المودم ($gw)': (gw, 80),
      'بوابة يمن فورجي (PTC)': ('svc.ptc.gov.ye', 443),
      'خادم جوجل العالمي (8.8.8.8)': ('8.8.8.8', 53),
      'خادم كلاودفلير السريع (1.1.1.1)': ('1.1.1.1', 53),
    };

    final results = <String, int?>{};
    for (final entry in targets.entries) {
      final ms = await widget.controller.measureTcpPing(
        entry.value.$1,
        entry.value.$2,
      );
      results[entry.key] = ms;
      if (mounted) {
        setState(() => _pingResults = Map.from(results));
      }
    }

    if (mounted) {
      setState(() => _runningPing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.controller.palette;
    final s = widget.controller.status;

    return RefreshIndicator(
      color: p.accentPrimary,
      backgroundColor: p.bgCard,
      onRefresh: () => widget.controller.refreshStatus(full: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 108),
        children: [
          // 1. Live Tower Alignment & RF Signal Metrics Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: p.bgCard,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: p.borderSubtle.withOpacity(0.75)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.radar_rounded, color: p.success),
                        const SizedBox(width: 8),
                        Text(
                          'رادار توجيه البرج وجودة التغطية',
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                            color: p.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => showBandLockModal(context, widget.controller),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: p.accentPrimary.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${s.networkType} • ${s.band}',
                          textDirection: TextDirection.ltr,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: p.accentPrimary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'حرك المودم ببطء نحو النافذة للحصول على أعلى قيمة لـ SINR وأقرب قيمة من -75 لـ RSRP.',
                  style: TextStyle(fontSize: 11.5, color: p.textSecondary),
                ),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: s.signalPercent / 100.0,
                    minHeight: 11,
                    backgroundColor: p.bgElevated,
                    color: s.signalPercent >= 65
                        ? p.success
                        : (s.signalPercent >= 35 ? p.warning : p.danger),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'تقييم التغطية الحالي: ${s.signalQualityArabic} (${s.signalPercent}%)',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: p.success,
                  ),
                ),
                const SizedBox(height: 14),
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1.35,
                  children: [
                    _rfMetricTile('RSRP', s.rsrp, 'قوة البرج', p),
                    _rfMetricTile('SINR', s.sinr, 'نقاء الإشارة', p),
                    _rfMetricTile('RSRQ', s.rsrq, 'جودة القناة', p),
                    _rfMetricTile('RSSI', s.rssi, 'مستوى الاستقبال', p),
                    _rfMetricTile('PCI', s.pci, 'الخلية الفيزيائية', p),
                    _rfMetricTile('Cell ID', s.cellId, 'معرف البرج', p),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 2. Ping & Network Response Diagnostic Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: p.bgCard,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: p.borderSubtle.withOpacity(0.75)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.network_ping_rounded, color: p.info),
                        const SizedBox(width: 8),
                        Text(
                          'فحص زمن الاستجابة (Ping)',
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                            color: p.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: p.accentPrimary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _runningPing ? null : _runPingSuite,
                      icon: _runningPing
                          ? const SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2),
                            )
                          : const Icon(Icons.play_arrow_rounded, size: 18),
                      label: Text(_runningPing ? 'جاري الفحص' : 'بدء الفحص'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_pingResults.isEmpty && !_runningPing)
                  Text(
                    'اضغط على "بدء الفحص" لقياس سرعة استجابة المودم والإنترنت للألعاب والتصفح.',
                    style: TextStyle(fontSize: 12, color: p.textSecondary),
                  )
                else
                  ..._pingResults.entries.map((entry) {
                    final ms = entry.value;
                    final color = ms == null
                        ? p.danger
                        : (ms < 80
                            ? p.success
                            : (ms < 160 ? p.warning : p.danger));
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: p.bgElevated.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            entry.key,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: p.textPrimary,
                            ),
                          ),
                          Text(
                            ms != null ? '$ms ms' : 'فشل الاتصال',
                            textDirection: TextDirection.ltr,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: color,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 3. Universal Protocol & Capability Summary Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: p.bgCard,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: p.borderSubtle.withOpacity(0.75)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.auto_awesome_rounded, color: p.accentSecondary),
                    const SizedBox(width: 8),
                    Text(
                      'محرك الترجمة الذكي للمودم',
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: p.textPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'المودم المتصل: ${s.deviceModel} • البروتوكول: ${widget.controller.identity.protocolLabel}',
                  style: TextStyle(fontSize: 12.5, color: p.textSecondary),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _capChip('إدارة الواي فاي', s.capabilities.hasWifiEdit, p),
                    _capChip('تثبيت الترددات', s.capabilities.hasBandLock, p),
                    _capChip('تحديد السرعة', s.capabilities.hasSpeedLimit, p),
                    _capChip('حظر المتسللين', s.capabilities.hasDeviceBlock, p),
                    _capChip('البطارية الحية', s.capabilities.hasBattery, p),
                    _capChip('رسائل الشريحة SMS', s.capabilities.hasSms, p),
                  ],
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: p.accentSecondary,
                    side: BorderSide(color: p.accentSecondary.withOpacity(0.45)),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () =>
                      showSmartModemInspectorSheet(context, widget.controller),
                  icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                  label: const Text(
                    'محلل المودم الذكي (فحص البصمة والبروتوكول)',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _rfMetricTile(String code, String val, String ar, dynamic p) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: p.bgElevated.withOpacity(0.65),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.borderSubtle),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            code,
            textDirection: TextDirection.ltr,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: p.accentPrimary,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              val,
              textDirection: TextDirection.ltr,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: p.textPrimary,
              ),
            ),
          ),
          Text(
            ar,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 9.5, color: p.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _capChip(String label, bool active, dynamic p) {
    final c = active ? p.success : p.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            active ? Icons.check_circle_rounded : Icons.remove_circle_outline,
            size: 14,
            color: c,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: p.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
