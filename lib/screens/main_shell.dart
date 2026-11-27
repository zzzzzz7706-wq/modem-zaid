import 'package:flutter/material.dart';
import '../models/modem_models.dart';
import '../services/app_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/balance_inquiry_sheet.dart';
import '../widgets/devices_manager_sheet.dart';
import '../widgets/gauges_and_cards.dart';
import '../widgets/wifi_quick_modal.dart';
import 'diagnostics_tab.dart';
import 'home_tab.dart';
import 'modem_settings_tab.dart';

class MainShell extends StatefulWidget {
  final AppController controller;

  const MainShell({super.key, required this.controller});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _tabIndex = 0;

  String get _currentTitle {
    switch (_tabIndex) {
      case 0:
        return 'الرئيسية';
      case 1:
        return 'إعدادات المودم';
      default:
        return 'التشخيص';
    }
  }

  void _openSmsInboxSheet() {
    final p = widget.controller.palette;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: p.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (ctx) {
        return FutureBuilder<List<SmsMessage>>(
          future: widget.controller.loadSmsInbox(),
          builder: (ctx, snap) {
            final msgs = snap.data ?? [];
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.55,
              maxChildSize: 0.85,
              builder: (ctx, scrollCtrl) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'رسائل شريحة المودم (SMS)',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: p.textPrimary,
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(ctx),
                            icon: Icon(Icons.close_rounded,
                                color: p.textSecondary),
                          ),
                        ],
                      ),
                      const Divider(),
                      Expanded(
                        child: snap.connectionState == ConnectionState.waiting
                            ? const Center(child: CircularProgressIndicator())
                            : (msgs.isEmpty
                                ? Center(
                                    child: Text(
                                      'لا توجد رسائل SMS في ذاكرة المودم حالياً',
                                      style: TextStyle(color: p.textSecondary),
                                    ),
                                  )
                                : ListView.separated(
                                    controller: scrollCtrl,
                                    itemCount: msgs.length,
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(height: 10),
                                    itemBuilder: (ctx, i) {
                                      final m = msgs[i];
                                      return Container(
                                        padding: const EdgeInsets.all(14),
                                        decoration: BoxDecoration(
                                          color: p.bgElevated,
                                          borderRadius:
                                              BorderRadius.circular(16),
                                          border: Border.all(
                                            color: m.isUnread
                                                ? p.accentPrimary
                                                : p.borderSubtle,
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Text(
                                                  m.sender,
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                    color: p.accentSecondary,
                                                  ),
                                                ),
                                                Text(
                                                  m.timestamp,
                                                  textDirection:
                                                      TextDirection.ltr,
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: p.textSecondary,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              m.content,
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: p.textPrimary,
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  )),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  void _openAlertsSheet() {
    final p = widget.controller.palette;
    final alerts = widget.controller.alerts;
    showModalBottomSheet(
      context: context,
      backgroundColor: p.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'التنبيهات وسجل العمليات',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: p.textPrimary,
                    ),
                  ),
                  if (alerts.isNotEmpty)
                    TextButton(
                      onPressed: () {
                        widget.controller.clearAlerts();
                        Navigator.pop(ctx);
                      },
                      child: const Text('مسح الكل'),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              if (alerts.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 22),
                  child: Text(
                    'لا توجد تنبيهات جديدة. المودم يعمل بصورة مستقرة.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: p.textSecondary),
                  ),
                )
              else
                ...alerts.take(6).map(
                      (a) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: p.bgElevated,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.notifications_active_outlined,
                                color: p.warning, size: 18),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                a,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: p.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final p = c.palette;
    final s = c.status;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: p.bgPrimary,
      extendBody: true,
      drawer: _buildDrawer(context, c, p),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Right (RTL start): Hamburger + Screen Title (matching 00:03)
                Row(
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(22),
                      onTap: () => _scaffoldKey.currentState?.openDrawer(),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: p.bgCard,
                          border: Border.all(color: p.borderSubtle),
                        ),
                        child: Icon(Icons.menu_rounded,
                            color: p.textPrimary, size: 21),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _currentTitle,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: p.textPrimary,
                      ),
                    ),
                  ],
                ),

                // Left (RTL end): Palette + Bell with unread red dot
                Row(
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(22),
                      onTap: c.cyclePalette,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: p.bgCard,
                          border: Border.all(color: p.borderSubtle),
                        ),
                        child: Icon(Icons.palette_outlined,
                            color: p.textPrimary, size: 20),
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      borderRadius: BorderRadius.circular(22),
                      onTap: _openAlertsSheet,
                      child: Stack(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: p.bgCard,
                              border: Border.all(color: p.borderSubtle),
                            ),
                            child: Icon(Icons.notifications_rounded,
                                color: p.textPrimary, size: 20),
                          ),
                          if (c.alerts.isNotEmpty)
                            Positioned(
                              top: 6,
                              left: 6,
                              child: Container(
                                width: 9,
                                height: 9,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: p.danger,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          if (c.isConnectionLost)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: p.warning.withOpacity(0.16),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: p.warning.withOpacity(0.55)),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: p.warning,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      c.freshnessStatusArabic,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: p.warning,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => c.refreshStatus(full: true),
                    child: const Text('اتصال الآن'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: IndexedStack(
              index: _tabIndex,
              children: [
                HomeTab(
                  controller: c,
                  onJumpToDevices: () => showDevicesManagerSheet(context, c),
                  onOpenSms: _openSmsInboxSheet,
                ),
                ModemSettingsTab(controller: c),
                DiagnosticsTab(controller: c),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: FloatingGlassBottomNav(
        currentIndex: _tabIndex,
        networkBadge: s.networkType.isEmpty ? '4G' : s.networkType,
        onTabSelected: (idx) => setState(() => _tabIndex = idx),
        on4GPressed: () => showBandLockModal(context, c),
        palette: p,
      ),
    );
  }

  Widget _buildDrawer(BuildContext context, AppController c, AppPalette p) {
    return Drawer(
      backgroundColor: p.bgCard,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: p.waveGradient,
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'مودم زيد',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${c.status.deviceModel} • ${c.identity.gatewayIp}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (c.status.modemPhoneNumber.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'رقم المودم: ${c.status.modemPhoneNumber}',
                      style: const TextStyle(
                        fontSize: 13.5,
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            ListTile(
              leading: Icon(Icons.account_balance_wallet_rounded,
                  color: p.accentSecondary),
              title: Text(
                'استعلام رصيد يمن فورجي',
                style:
                    TextStyle(color: p.textPrimary, fontWeight: FontWeight.w600),
              ),
              onTap: () {
                Navigator.pop(context);
                showBalanceInquirySheet(context, c);
              },
            ),
            ListTile(
              leading: Icon(Icons.sms_rounded, color: p.warning),
              title: Text(
                'رسائل الشريحة (SMS)',
                style:
                    TextStyle(color: p.textPrimary, fontWeight: FontWeight.w600),
              ),
              onTap: () {
                Navigator.pop(context);
                _openSmsInboxSheet();
              },
            ),
            ListTile(
              leading: Icon(Icons.qr_code_2_rounded, color: p.info),
              title: Text(
                'باركود مشاركة الواي فاي',
                style:
                    TextStyle(color: p.textPrimary, fontWeight: FontWeight.w600),
              ),
              onTap: () {
                Navigator.pop(context);
                showWifiQrSheet(context, c);
              },
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Text(
                'مظهر التطبيق والألوان',
                style: TextStyle(fontSize: 12, color: p.textSecondary),
              ),
            ),
            ...AppPalette.all.map(
              (pal) => RadioListTile<String>(
                value: pal.id,
                groupValue: p.id,
                activeColor: pal.accentPrimary,
                title: Text(
                  pal.nameAr,
                  style: TextStyle(fontSize: 13, color: p.textPrimary),
                ),
                onChanged: (_) => c.setPalette(pal),
              ),
            ),
            const Spacer(),
            const Divider(),
            ListTile(
              leading: Icon(Icons.logout_rounded, color: p.danger),
              title: Text(
                'تسجيل الخروج من المودم',
                style: TextStyle(color: p.danger, fontWeight: FontWeight.w700),
              ),
              onTap: () async {
                Navigator.pop(context);
                await c.logout();
              },
            ),
          ],
        ),
      ),
    );
  }
}
