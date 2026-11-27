import 'package:flutter/material.dart';
import '../models/modem_models.dart';
import '../services/app_controller.dart';
import '../widgets/gauges_and_cards.dart';
import '../widgets/wifi_quick_modal.dart';

class HomeTab extends StatelessWidget {
  final AppController controller;
  final VoidCallback onJumpToDevices;
  final VoidCallback onOpenSms;

  const HomeTab({
    super.key,
    required this.controller,
    required this.onJumpToDevices,
    required this.onOpenSms,
  });

  @override
  Widget build(BuildContext context) {
    final p = controller.palette;
    final s = controller.status;
    final enabledShortcuts =
        controller.shortcuts.where((item) => item.enabled).toList();

    return RefreshIndicator(
      color: p.accentPrimary,
      backgroundColor: p.bgCard,
      onRefresh: () => controller.refreshStatus(full: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 105),
        children: [
          // Row 1: البطارية (Right) + استهلاك البيانات (Left)
          Row(
            children: [
              Expanded(child: _buildBatteryCard(context, s, p)),
              const SizedBox(width: 12),
              Expanded(child: _buildDataUsageCard(context, s, p)),
            ],
          ),
          const SizedBox(height: 12),

          // Row 2: قوة الإشارة (Right) + الأجهزة المتصلة (Left)
          Row(
            children: [
              Expanded(child: _buildSignalCard(context, s, p)),
              const SizedBox(width: 12),
              Expanded(child: _buildConnectedDevicesCard(context, s, p)),
            ],
          ),
          const SizedBox(height: 14),

          // Shortcuts Container Card (الاختصارات)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: p.bgCard,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: p.borderSubtle.withOpacity(0.75)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: p.bgElevated,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.grid_view_rounded,
                            size: 18,
                            color: p.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'الاختصارات',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: p.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => _showEditShortcutsSheet(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: p.bgElevated,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: p.borderSubtle),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'تعديل الاختصارات',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: p.textSecondary,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Icon(
                              Icons.edit_outlined,
                              size: 14,
                              color: p.textSecondary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: enabledShortcuts.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.94,
                  ),
                  itemBuilder: (ctx, index) {
                    final item = enabledShortcuts[index];
                    return _buildShortcutTile(context, item, p);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBatteryCard(BuildContext context, ModemStatus s, dynamic p) {
    final String badgeText = !s.hasBattery
        ? 'كهرباء مباشرة'
        : (s.isCharging ? 'جاري الشحن ⚡' : 'لا يشحن');
    final Color badgeColor = !s.hasBattery
        ? p.info
        : (s.isCharging
            ? p.success
            : (s.batteryPercent <= 20 ? p.danger : p.textSecondary));

    return Container(
      height: 196,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.bgCard,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: p.borderSubtle.withOpacity(0.75)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'البطارية',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: p.textPrimary,
                ),
              ),
              Icon(
                s.isCharging
                    ? Icons.battery_charging_full_rounded
                    : Icons.battery_4_bar_rounded,
                size: 18,
                color: p.warning,
              ),
            ],
          ),
          BatteryRingGauge(
            percent: s.batteryPercent,
            hasBattery: s.hasBattery,
            isCharging: s.isCharging,
            palette: p,
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
            decoration: BoxDecoration(
              color: badgeColor.withOpacity(0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              badgeText,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: badgeColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataUsageCard(BuildContext context, ModemStatus s, dynamic p) {
    return Container(
      height: 196,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.bgCard,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: p.borderSubtle.withOpacity(0.75)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'استهلاك البيانات',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: p.textPrimary,
                ),
              ),
              InkWell(
                onTap: () => controller.refreshStatus(full: true),
                child: Icon(Icons.refresh_rounded, size: 18, color: p.warning),
              ),
            ],
          ),
          DataUsageRingGauge(
            rxBytes: s.rxBytes,
            txBytes: s.txBytes,
            centerText: ModemStatus.formatBytesCompact(s.totalBytes),
            palette: p,
          ),
          Column(
            children: [
              Directionality(
                textDirection: TextDirection.ltr,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      ModemStatus.formatBytesCompact(s.txBytes),
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: p.textPrimary,
                      ),
                    ),
                    Icon(Icons.arrow_upward_rounded, size: 12, color: p.warning),
                    const SizedBox(width: 8),
                    Text(
                      ModemStatus.formatBytesCompact(s.rxBytes),
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: p.textPrimary,
                      ),
                    ),
                    Icon(Icons.arrow_downward_rounded, size: 12, color: p.info),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                s.formattedUptimeClock,
                textDirection: TextDirection.ltr,
                style: TextStyle(
                  fontSize: 10.5,
                  color: p.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSignalCard(BuildContext context, ModemStatus s, dynamic p) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: () => showBandLockModal(context, controller),
      child: Container(
        height: 172,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: p.bgCard,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: p.borderSubtle.withOpacity(0.75)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'قوة الإشارة',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: p.textPrimary,
                  ),
                ),
                Icon(Icons.sensors_rounded, size: 18, color: p.success),
              ],
            ),
            SignalGaugeAndBars(
              signalPercent: s.signalPercent,
              signalBars: s.signalBars,
              palette: p,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: p.success.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    s.signalQualityArabic,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: p.success,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: p.accentPrimary.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    s.band,
                    textDirection: TextDirection.ltr,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: p.accentPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectedDevicesCard(
      BuildContext context, ModemStatus s, dynamic p) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onJumpToDevices,
      child: Container(
        height: 172,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: p.bgCard,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: p.borderSubtle.withOpacity(0.75)),
        ),
        child: Stack(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'الأجهزة المتصلة',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: p.textPrimary,
                  ),
                ),
                Icon(Icons.devices_rounded, size: 18, color: p.info),
              ],
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Text(
                  '${s.connectedDevicesCount}',
                  style: TextStyle(
                    fontSize: 42,
                    fontWeight: FontWeight.w800,
                    color: p.textPrimary,
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomLeft,
              child: Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: p.info.withOpacity(0.14),
                  border: Border.all(color: p.info.withOpacity(0.45)),
                ),
                child: Text(
                  '${s.maxClients}',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: p.info,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShortcutTile(
    BuildContext context,
    ShortcutItemConfig item,
    dynamic p,
  ) {
    late final IconData icon;
    late final Color color;
    late final VoidCallback onTap;

    switch (item.id) {
      case 'wifi':
        icon = Icons.wifi_rounded;
        color = p.info;
        onTap = () => showWifiQuickModal(context, controller);
        break;
      case 'reboot':
        icon = Icons.restart_alt_rounded;
        color = p.warning;
        onTap = () => _confirmRebootOrPower(context, isReboot: true);
        break;
      case 'speed':
        icon = Icons.speed_rounded;
        color = p.success;
        onTap = () => showSpeedLimitModal(context, controller);
        break;
      case 'admin_pass':
        icon = Icons.lock_person_rounded;
        color = p.accentPrimary;
        onTap = () => showAdminPasswordModal(context, controller);
        break;
      case 'devices':
        icon = Icons.shield_outlined;
        color = p.danger;
        onTap = onJumpToDevices;
        break;
      case 'power_off':
        icon = Icons.power_settings_new_rounded;
        color = const Color(0xFF38BDF8);
        onTap = () => _confirmRebootOrPower(context, isReboot: false);
        break;
      case 'band_lock':
        icon = Icons.cell_tower_rounded;
        color = p.accentSecondary;
        onTap = () => showBandLockModal(context, controller);
        break;
      case 'wifi_qr':
        icon = Icons.qr_code_2_rounded;
        color = const Color(0xFF14B8A6);
        onTap = () => showWifiQrSheet(context, controller);
        break;
      default:
        icon = Icons.sms_outlined;
        color = const Color(0xFFF59E0B);
        onTap = onOpenSms;
        break;
    }

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        decoration: BoxDecoration(
          color: p.bgElevated.withOpacity(0.55),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: p.borderSubtle.withOpacity(0.6)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withOpacity(0.15),
              ),
              child: Icon(icon, color: color, size: 21),
            ),
            const SizedBox(height: 8),
            Text(
              item.title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                height: 1.2,
                fontWeight: FontWeight.w600,
                color: p.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmRebootOrPower(
    BuildContext context, {
    required bool isReboot,
  }) async {
    final p = controller.palette;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          isReboot ? 'إعادة تشغيل المودم' : 'إيقاف تشغيل المودم',
          style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w700),
        ),
        content: Text(
          isReboot
              ? 'هل تريد إعادة تشغيل المودم الآن؟ سينقطع اتصال الواي فاي لمدة 30 ثانية تقريباً.'
              : 'هل أنت متأكد من إيقاف تشغيل المودم بالكامل عن بُعد؟',
          style: TextStyle(color: p.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isReboot ? p.warning : p.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isReboot ? 'إعادة التشغيل' : 'إيقاف التشغيل'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final ok = isReboot
          ? await controller.rebootModem()
          : await controller.powerOffModem();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ok
                  ? (isReboot
                      ? 'تم إرسال أمر إعادة تشغيل المودم بنجاح'
                      : 'تم إرسال أمر إيقاف تشغيل المودم بنجاح')
                  : 'تعذر تنفيذ الأمر على هذا المودم',
            ),
          ),
        );
      }
    }
  }

  void _showEditShortcutsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: controller.palette.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return ListenableBuilder(
          listenable: controller,
          builder: (ctx, _) {
            final p = controller.palette;
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'تخصيص الاختصارات السريعة',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: p.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: controller.shortcuts
                          .map(
                            (sc) => SwitchListTile(
                              title: Text(
                                sc.title,
                                style: TextStyle(
                                  color: p.textPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              value: sc.enabled,
                              activeColor: p.accentPrimary,
                              onChanged: (_) => controller.toggleShortcut(sc.id),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
