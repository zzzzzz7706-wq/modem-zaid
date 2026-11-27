import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/modem_models.dart';
import '../services/app_controller.dart';
import '../widgets/wifi_quick_modal.dart';

class ModemSettingsTab extends StatefulWidget {
  final AppController controller;
  final int initialSubTab;

  const ModemSettingsTab({
    super.key,
    required this.controller,
    this.initialSubTab = 0,
  });

  @override
  State<ModemSettingsTab> createState() => _ModemSettingsTabState();
}

class _ModemSettingsTabState extends State<ModemSettingsTab> {
  late int _subTabIndex;
  bool _deviceInfoExpanded = false;
  bool _showWifiPassword = false;
  bool _showAdminPassword = false;

  @override
  void initState() {
    super.initState();
    _subTabIndex = widget.initialSubTab;
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.controller.palette;
    final s = widget.controller.status;

    return Column(
      children: [
        // Top 4 Sub-Tabs matching 00:13 - 00:18 of the video
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
          decoration: BoxDecoration(
            color: p.bgCard,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: p.borderSubtle.withOpacity(0.75)),
          ),
          child: Row(
            children: [
              _subTabButton(0, Icons.info_outline_rounded, 'نظرة سريعة', p),
              _subTabButton(1, Icons.wifi_rounded, 'إعدادات الشبكة', p),
              _subTabButton(2, Icons.speed_rounded, 'التحكم', p),
              _subTabButton(3, Icons.settings_outlined, 'إعدادات عامة', p),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            color: p.accentPrimary,
            backgroundColor: p.bgCard,
            onRefresh: () => widget.controller.refreshStatus(full: true),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 108),
              children: [
                if (_subTabIndex == 0) ..._buildQuickOverview(context, s, p),
                if (_subTabIndex == 1) ..._buildNetworkSettings(context, s, p),
                if (_subTabIndex == 2) ..._buildControlSettings(context, s, p),
                if (_subTabIndex == 3) ..._buildGeneralSettings(context, s, p),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _subTabButton(int index, IconData icon, String title, dynamic p) {
    final active = _subTabIndex == index;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() => _subTabIndex = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
          decoration: BoxDecoration(
            border: active
                ? Border(
                    bottom: BorderSide(color: p.accentSecondary, width: 2.5),
                  )
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 20,
                color: active ? p.accentSecondary : p.textSecondary,
              ),
              const SizedBox(height: 4),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: active ? p.accentSecondary : p.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- Sub-Tab 0: نظرة سريعة (00:13 - 00:15) ---
  List<Widget> _buildQuickOverview(
      BuildContext context, ModemStatus s, dynamic p) {
    return [
      // 1. Expandable معلومات الجهاز
      Container(
        decoration: BoxDecoration(
          color: p.bgCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: p.borderSubtle.withOpacity(0.75)),
        ),
        child: Column(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () =>
                  setState(() => _deviceInfoExpanded = !_deviceInfoExpanded),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        _iconBox(Icons.smartphone_rounded, p.accentSecondary, p),
                        const SizedBox(width: 12),
                        Text(
                          'معلومات الجهاز',
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                            color: p.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    Icon(
                      _deviceInfoExpanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: p.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
            if (_deviceInfoExpanded) ...[
              Divider(height: 1, color: p.borderSubtle),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _detailRow('طراز المودم', s.deviceModel, p),
                    _detailRow('المشغل', s.operatorName, p),
                    _detailRow('عنوان المودم (LAN)', s.lanIp, p),
                    _detailRow('عنوان الشبكة (WAN IP)', s.wanIp, p),
                    _detailRow('عنوان MAC', s.macAddress, p),
                    _detailRow('رقم IMEI', s.imei, p),
                    _detailRow('رقم الشريحة ICCID', s.iccid, p),
                    _detailRow('إصدار النظام', s.softwareVersion, p),
                    _detailRow('إصدار العتاد', s.hardwareVersion, p),
                    ...s.translatedExtras.entries
                        .map((e) => _detailRow(e.key, e.value, p)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 14),

      // 2. إحصائيات البيانات (00:13 - 00:14)
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: p.bgCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: p.borderSubtle.withOpacity(0.75)),
        ),
        child: Column(
          children: [
            Row(
              children: [
                _iconBox(Icons.pie_chart_outline_rounded, p.accentSecondary, p),
                const SizedBox(width: 10),
                Text(
                  'إحصائيات البيانات',
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: p.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'إحصائيات الجلسة الحالية',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: p.accentSecondary,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _statMiniCard(
                    icon: Icons.arrow_downward_rounded,
                    color: p.success,
                    value: ModemStatus.formatBytesArabicDetailed(s.rxBytes),
                    label: 'تم تنزيله',
                    sub: ModemStatus.formatSpeed(s.rxRateBps),
                    p: p,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _statMiniCard(
                    icon: Icons.arrow_upward_rounded,
                    color: p.danger,
                    value: ModemStatus.formatBytesArabicDetailed(s.txBytes),
                    label: 'تم رفعه',
                    sub: ModemStatus.formatSpeed(s.txRateBps),
                    p: p,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _statMiniCard(
                    icon: Icons.sync_rounded,
                    color: p.info,
                    value: ModemStatus.formatBytesArabicDetailed(s.totalBytes),
                    label: 'إجمالي البيانات',
                    sub: '',
                    p: p,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _statMiniCard(
                    icon: Icons.access_time_rounded,
                    color: p.warning,
                    value: s.formattedSessionHours,
                    label: 'وقت الجلسة',
                    sub: s.formattedUptimeClock,
                    p: p,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),

      // 3. الأجهزة المتصلة (00:14)
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: p.bgCard,
          borderRadius: BorderRadius.circular(20),
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
                    _iconBox(Icons.devices_rounded, p.info, p),
                    const SizedBox(width: 10),
                    Text(
                      'الأجهزة المتصلة (${s.devices.length})',
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: p.textPrimary,
                      ),
                    ),
                  ],
                ),
                _editActionPill(
                  label: 'تحديث',
                  icon: Icons.refresh_rounded,
                  p: p,
                  onTap: () => widget.controller.refreshStatus(full: true),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (s.devices.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'لا توجد تفاصيل أجهزة إضافية حالياً',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: p.textSecondary),
                ),
              )
            else
              ...s.devices.map((dev) => _buildDeviceTile(context, dev, p)),
          ],
        ),
      ),
    ];
  }

  Widget _buildDeviceTile(
      BuildContext context, ConnectedDevice dev, dynamic p) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.bgElevated.withOpacity(0.65),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: dev.isBlocked ? p.danger.withOpacity(0.5) : p.borderSubtle,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: (dev.isBlocked ? p.danger : p.accentSecondary)
                  .withOpacity(0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              dev.isBlocked ? Icons.block_rounded : Icons.hub_outlined,
              color: dev.isBlocked ? p.danger : p.accentSecondary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        dev.name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: p.textPrimary,
                        ),
                      ),
                    ),
                    if (dev.isCurrentDevice) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: p.accentSecondary.withOpacity(0.22),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'أنت',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: p.accentSecondary,
                          ),
                        ),
                      ),
                    ],
                    if (dev.isBlocked) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: p.danger.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'محظور',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: p.danger,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  dev.connectedDuration.isNotEmpty
                      ? '${dev.ipAddress}  •  ${dev.connectedDuration}'
                      : '${dev.ipAddress}  •  ${dev.macAddress}',
                  textDirection: TextDirection.ltr,
                  style: TextStyle(fontSize: 11.5, color: p.textSecondary),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert_rounded, color: p.textSecondary),
            color: p.bgElevated,
            onSelected: (action) async {
              if (action == 'rename') {
                _showRenameDeviceDialog(context, dev);
              } else if (action == 'block') {
                if (dev.isCurrentDevice && !dev.isBlocked) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('لا يمكن حظر هاتفك الحالي المتصل بالمودم!'),
                    ),
                  );
                  return;
                }
                final ok = await widget.controller
                    .toggleBlockDevice(dev, !dev.isBlocked);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        ok
                            ? (dev.isBlocked
                                ? 'تم فك الحظر عن ${dev.name}'
                                : 'تم حظر ${dev.name} فوراً')
                            : 'تعذر تعديل حالة الحظر على هذا المودم',
                      ),
                    ),
                  );
                }
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'rename',
                child: Text('تسمية الجهاز'),
              ),
              PopupMenuItem(
                value: 'block',
                child: Text(
                  dev.isBlocked ? 'إلغاء حظر الجهاز' : 'حظر هذا الجهاز',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showRenameDeviceDialog(BuildContext context, ConnectedDevice dev) {
    final ctrl = TextEditingController(text: dev.name);
    final p = widget.controller.palette;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.bgCard,
        title: Text('تسمية الجهاز', style: TextStyle(color: p.textPrimary)),
        content: TextField(
          controller: ctrl,
          style: TextStyle(color: p.textPrimary),
          decoration: const InputDecoration(hintText: 'اسم الجهاز الجديد'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await widget.controller.renameConnectedDevice(dev, ctrl.text);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  // --- Sub-Tab 1: إعدادات الشبكة (00:16) ---
  List<Widget> _buildNetworkSettings(
      BuildContext context, ModemStatus s, dynamic p) {
    return [
      // Card 1: معلومات الواي فاي
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: p.bgCard,
          borderRadius: BorderRadius.circular(20),
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
                    _iconBox(Icons.wifi_rounded, p.accentSecondary, p),
                    const SizedBox(width: 10),
                    Text(
                      'معلومات الواي فاي',
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: p.textPrimary,
                      ),
                    ),
                  ],
                ),
                _editActionPill(
                  label: 'إعداد',
                  icon: Icons.edit_rounded,
                  p: p,
                  onTap: () => showWifiQuickModal(context, widget.controller),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _wifiInfoField(
              title: 'اسم الشبكة (SSID)',
              value: s.ssid,
              trailing: IconButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: s.ssid));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم نسخ اسم الشبكة')),
                  );
                },
                icon: Icon(Icons.copy_rounded, size: 18, color: p.textSecondary),
              ),
              p: p,
            ),
            const SizedBox(height: 10),
            _wifiInfoField(
              title: 'الحماية والظهور',
              value:
                  '${s.securityMode == 'None' ? 'مفتوحة' : 'محمية (${s.securityMode})'} • ${s.isHiddenSsid ? 'مخفية' : 'ظاهرة'}',
              p: p,
            ),
            const SizedBox(height: 10),
            _wifiInfoField(
              title: 'كلمة المرور',
              value: s.wifiPassword.isEmpty
                  ? '••••••••'
                  : (_showWifiPassword ? s.wifiPassword : '••••••••••'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: () =>
                        setState(() => _showWifiPassword = !_showWifiPassword),
                    icon: Icon(
                      _showWifiPassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 19,
                      color: p.accentSecondary,
                    ),
                  ),
                  if (s.wifiPassword.isNotEmpty)
                    IconButton(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: s.wifiPassword));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('تم نسخ كلمة المرور')),
                        );
                      },
                      icon: Icon(Icons.copy_rounded,
                          size: 18, color: p.accentSecondary),
                    ),
                ],
              ),
              p: p,
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),

      // Card 2: إعدادات الأبراج والنطاقات (00:16)
      InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => showBandLockModal(context, widget.controller),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: p.bgCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: p.borderSubtle.withOpacity(0.75)),
          ),
          child: Row(
            children: [
              _iconBox(Icons.cell_tower_rounded, p.accentPrimary, p),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'إعدادات الأبراج والنطاقات',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: p.textPrimary,
                      ),
                    ),
                    Text(
                      s.isManualBand
                          ? 'وضع الاختيار اليدوي لنطاق مفعل (${s.selectedBands.join(", ")})'
                          : 'وضع الاختيار التلقائي للأبراج مفعل',
                      style: TextStyle(fontSize: 11.5, color: p.textSecondary),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: p.accentPrimary.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  s.band,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: p.accentPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.keyboard_arrow_down_rounded, color: p.textSecondary),
            ],
          ),
        ),
      ),
    ];
  }

  // --- Sub-Tab 2: التحكم (00:17) ---
  List<Widget> _buildControlSettings(
      BuildContext context, ModemStatus s, dynamic p) {
    return [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: p.bgCard,
          borderRadius: BorderRadius.circular(20),
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
                    _iconBox(Icons.speed_rounded, p.success, p),
                    const SizedBox(width: 10),
                    Text(
                      'سرعة الانترنت',
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: p.textPrimary,
                      ),
                    ),
                  ],
                ),
                _editActionPill(
                  label: 'إعداد',
                  icon: Icons.edit_rounded,
                  p: p,
                  onTap: () => showSpeedLimitModal(context, widget.controller),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: p.bgElevated.withOpacity(0.65),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: p.borderSubtle),
              ),
              child: Row(
                children: [
                  Icon(
                    s.speedLimitEnabled
                        ? Icons.check_circle_rounded
                        : Icons.cancel_rounded,
                    color: s.speedLimitEnabled ? p.success : p.textSecondary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'الحالة',
                          style:
                              TextStyle(fontSize: 11.5, color: p.textSecondary),
                        ),
                        Text(
                          s.speedLimitEnabled
                              ? 'نشط: تنزيل ${s.downloadLimitMbps}M / رفع ${s.uploadLimitMbps}M'
                              : 'تحديد السرعة غير نشط',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: p.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ];
  }

  // --- Sub-Tab 3: إعدادات عامة (00:18) ---
  List<Widget> _buildGeneralSettings(
      BuildContext context, ModemStatus s, dynamic p) {
    return [
      // Card 1: إعدادات كلمة مرور المدير
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: p.bgCard,
          borderRadius: BorderRadius.circular(20),
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
                    _iconBox(Icons.admin_panel_settings_outlined,
                        p.accentSecondary, p),
                    const SizedBox(width: 10),
                    Text(
                      'إعدادات كلمة مرور المدير',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: p.textPrimary,
                      ),
                    ),
                  ],
                ),
                _editActionPill(
                  label: 'إعداد',
                  icon: Icons.edit_rounded,
                  p: p,
                  onTap: () =>
                      showAdminPasswordModal(context, widget.controller),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: p.bgElevated.withOpacity(0.65),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: p.borderSubtle),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'كلمة مرور مدير المودم (${s.adminUsername})',
                        style:
                            TextStyle(fontSize: 11.5, color: p.textSecondary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _showAdminPassword
                            ? (s.adminPassword.isEmpty ? 'admin' : s.adminPassword)
                            : '••••••••',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: p.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    onPressed: () => setState(
                        () => _showAdminPassword = !_showAdminPassword),
                    icon: Icon(
                      _showAdminPassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: p.accentSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),

      // Card 2: عرض الباركود في شاشة المودم + عرض باركود الواي فاي
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: p.bgCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: p.borderSubtle.withOpacity(0.75)),
        ),
        child: Column(
          children: [
            Row(
              children: [
                _iconBox(Icons.qr_code_2_rounded, p.info, p),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'عرض الباركود في شاشة المودم',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: p.textPrimary,
                        ),
                      ),
                      Text(
                        s.lcdQrEnabled ? 'مفعل على الشاشة' : 'غير مفعل',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: s.lcdQrEnabled ? p.success : p.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: s.lcdQrEnabled,
                  activeColor: p.info,
                  onChanged: (val) => widget.controller.toggleLcdQrCode(val),
                ),
              ],
            ),
            const Divider(height: 22),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  side: BorderSide(color: p.borderSubtle),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () => showWifiQrSheet(context, widget.controller),
                icon: Icon(Icons.qr_code_scanner_rounded, color: p.info),
                label: Text(
                  'عرض باركود الواي فاي على الهاتف',
                  style: TextStyle(
                    color: p.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),

      // Card 3: إعادة تشغيل المودم
      _powerCard(
        context: context,
        title: 'إعادة تشغيل المودم',
        subtitle: 'أعد تشغيل المودم لتطبيق التغييرات أو حل مشاكل الاتصال.',
        buttonLabel: 'إعادة تشغيل',
        icon: Icons.restart_alt_rounded,
        color: p.danger,
        isReboot: true,
        p: p,
      ),
      const SizedBox(height: 14),

      // Card 4: إيقاف تشغيل المودم
      _powerCard(
        context: context,
        title: 'إيقاف تشغيل المودم',
        subtitle: 'إغلاق المودم تماماً عن بُعد للحفاظ على شحن البطارية.',
        buttonLabel: 'إيقاف التشغيل',
        icon: Icons.power_settings_new_rounded,
        color: p.warning,
        isReboot: false,
        p: p,
      ),
    ];
  }

  Widget _powerCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required String buttonLabel,
    required IconData icon,
    required Color color,
    required bool isReboot,
    required dynamic p,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.bgCard,
        borderRadius: BorderRadius.circular(20),
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
                  _iconBox(icon, color, p),
                  const SizedBox(width: 10),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: p.textPrimary,
                    ),
                  ),
                ],
              ),
              _editActionPill(
                label: buttonLabel,
                icon: icon,
                p: p,
                onTap: () async {
                  final ok = isReboot
                      ? await widget.controller.rebootModem()
                      : await widget.controller.powerOffModem();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          ok
                              ? 'تم إرسال الأمر ($title) بنجاح'
                              : 'تعذر إرسال الأمر للمودم',
                        ),
                      ),
                    );
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(fontSize: 12, color: p.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _iconBox(IconData icon, Color color, dynamic p) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Icon(icon, color: color, size: 20),
    );
  }

  Widget _editActionPill({
    required String label,
    required IconData icon,
    required dynamic p,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: p.accentSecondary.withOpacity(0.16),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: p.accentSecondary.withOpacity(0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: p.accentSecondary,
              ),
            ),
            const SizedBox(width: 5),
            Icon(icon, size: 14, color: p.accentSecondary),
          ],
        ),
      ),
    );
  }

  Widget _statMiniCard({
    required IconData icon,
    required Color color,
    required String value,
    required String label,
    required String sub,
    required dynamic p,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: p.bgElevated.withOpacity(0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.borderSubtle.withOpacity(0.6)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 6),
          Text(
            value,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: p.textPrimary,
            ),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 11.5, color: p.textSecondary),
          ),
          if (sub.isNotEmpty)
            Text(
              sub,
              textDirection: TextDirection.ltr,
              style: TextStyle(
                fontSize: 10.5,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }

  Widget _wifiInfoField({
    required String title,
    required String value,
    Widget? trailing,
    required dynamic p,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: p.bgElevated.withOpacity(0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.borderSubtle),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 11.5, color: p.textSecondary),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: p.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _detailRow(String k, String v, dynamic p) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(k, style: TextStyle(fontSize: 12.5, color: p.textSecondary)),
          const SizedBox(width: 10),
          Flexible(
            child: SelectableText(
              v,
              textDirection: TextDirection.ltr,
              style: TextStyle(
                fontSize: 12.5,
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
