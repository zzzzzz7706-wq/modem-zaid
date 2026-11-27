import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/modem_models.dart';
import '../services/app_controller.dart';

/// Opens full-featured Connected, Offline History, and Blocked MAC Devices Manager
Future<void> showDevicesManagerSheet(
  BuildContext context,
  AppController controller,
) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: controller.palette.bgCard,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.82,
      minChildSize: 0.5,
      maxChildSize: 0.94,
      builder: (ctx, scrollCtrl) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: DevicesManagerPanel(
          controller: controller,
          scrollController: scrollCtrl,
          isBottomSheet: true,
        ),
      ),
    ),
  );
}

class DevicesManagerPanel extends StatefulWidget {
  final AppController controller;
  final ScrollController? scrollController;
  final bool isBottomSheet;

  const DevicesManagerPanel({
    super.key,
    required this.controller,
    this.scrollController,
    this.isBottomSheet = false,
  });

  @override
  State<DevicesManagerPanel> createState() => _DevicesManagerPanelState();
}

class _DevicesManagerPanelState extends State<DevicesManagerPanel> {
  int _filterTab = 0; // 0: متصل الآن, 1: سبق اتصالها, 2: المحظورة
  String? _busyMac;

  Future<void> _handleBlockToggle(ConnectedDevice dev, bool block) async {
    setState(() => _busyMac = dev.macAddress);
    final (ok, msg) = await widget.controller.toggleBlockDevice(dev, block);
    if (!mounted) return;
    setState(() => _busyMac = null);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor:
            ok ? widget.controller.palette.bgElevated : widget.controller.palette.danger,
        content: Text(msg),
      ),
    );
  }

  Future<void> _showManualMacBlockDialog() async {
    final p = widget.controller.palette;
    final macCtrl = TextEditingController();
    bool submitting = false;
    String? localErr;

    await showDialog(
      context: context,
      barrierDismissible: !submitting,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return Dialog(
              backgroundColor: p.bgCard,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
                side: BorderSide(color: p.borderSubtle),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.shield_rounded, color: p.danger),
                        const SizedBox(width: 8),
                        Text(
                          'حظر جهاز عبر MAC Address',
                          style: TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w800,
                            color: p.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'أدخل عنوان MAC للجهاز المراد منعه من الاتصال بالواي فاي، وسيتم التحقق من تطبيقه داخل المودم.',
                      style: TextStyle(fontSize: 12, color: p.textSecondary),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: macCtrl,
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: p.textPrimary,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                      ),
                      decoration: InputDecoration(
                        hintText: 'AA:BB:CC:DD:EE:FF',
                        filled: true,
                        fillColor: p.bgElevated,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                    if (localErr != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        localErr!,
                        style: TextStyle(color: p.danger, fontSize: 12),
                      ),
                    ],
                    if (submitting) ...[
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: p.accentPrimary,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              'جاري تطبيق الحظر على المودم والتحقق الفعلي (4 ثوانٍ)...',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: p.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed:
                                submitting ? null : () => Navigator.pop(ctx),
                            child: const Text('إلغاء'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: p.danger,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: submitting
                                ? null
                                : () async {
                                    final norm = AppController.normalizeMacInput(
                                        macCtrl.text);
                                    if (norm == null) {
                                      setDialogState(() {
                                        localErr =
                                            'صيغة MAC غير صحيحة (مثال: A4:77:33:8E:12:9C)';
                                      });
                                      return;
                                    }
                                    setDialogState(() {
                                      submitting = true;
                                      localErr = null;
                                    });
                                    final (ok, msg) = await widget.controller
                                        .blockByMacAddress(norm);
                                    if (ctx.mounted) Navigator.pop(ctx);
                                    if (mounted) {
                                      if (ok) setState(() => _filterTab = 2);
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          backgroundColor:
                                              ok ? p.bgElevated : p.danger,
                                          content: Text(msg),
                                        ),
                                      );
                                    }
                                  },
                            child: const Text('تنفيذ الحظر'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showRenameDialog(ConnectedDevice dev) {
    final p = widget.controller.palette;
    final ctrl = TextEditingController(text: dev.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.bgCard,
        title: Text('تعديل اسم الجهاز', style: TextStyle(color: p.textPrimary)),
        content: TextField(
          controller: ctrl,
          style: TextStyle(color: p.textPrimary),
          decoration: const InputDecoration(hintText: 'اكتب اسماً واضحاً للجهاز'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: p.accentPrimary,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final newName = ctrl.text.trim();
              Navigator.pop(ctx);
              if (newName.isEmpty) return;
              final ok = await widget.controller
                  .renameConnectedDevice(dev, newName);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      ok
                          ? 'تم حفظ اسم الجهاز ($newName) في المودم'
                          : 'هذا المودم لا يدعم حفظ الأسماء المخصصة',
                    ),
                  ),
                );
              }
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final c = widget.controller;
        final p = c.palette;
        final s = c.status;

        final onlineDevices =
            s.devices.where((d) => d.isConnected && !d.isBlocked).toList();
        final offlineHistory =
            s.devices.where((d) => !d.isConnected && !d.isBlocked).toList();
        final blockedDevices = s.devices.where((d) => d.isBlocked).toList();

        List<ConnectedDevice> activeList;
        String emptyMessage;
        if (_filterTab == 0) {
          activeList = onlineDevices;
          emptyMessage = 'لا توجد أجهزة متصلة حالياً.';
        } else if (_filterTab == 1) {
          activeList = offlineHistory;
          emptyMessage =
              'لا توجد أجهزة سابقة غير متصلة مسجلة في ذاكرة المودم حالياً.';
        } else {
          activeList = blockedDevices;
          emptyMessage = 'قائمة الحظر فارغة — لا توجد أجهزة محظورة حالياً.';
        }

        final headerColumn = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.isBottomSheet) ...[
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: p.borderSubtle,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.devices_rounded, color: p.info, size: 22),
                    const SizedBox(width: 8),
                    Text(
                      'إدارة الأجهزة المتصلة والحظر',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: p.textPrimary,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    IconButton(
                      tooltip: 'تحديث القائمة الآن',
                      onPressed: c.isBusyAction
                          ? null
                          : () => c.refreshStatus(full: true),
                      icon: Icon(Icons.refresh_rounded,
                          color: p.accentPrimary, size: 20),
                    ),
                    if (s.capabilities.hasDeviceBlock)
                      InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: _showManualMacBlockDialog,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: p.danger.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                            border:
                                Border.all(color: p.danger.withOpacity(0.45)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add_moderator_rounded,
                                  size: 15, color: p.danger),
                              const SizedBox(width: 4),
                              Text(
                                'حظر MAC',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: p.danger,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            // 3 Filter Chips: متصل الآن | سبق اتصالها | المحظورة
            Row(
              children: [
                _tabPill(
                  index: 0,
                  label: 'متصل الآن (${onlineDevices.length})',
                  activeColor: p.success,
                  p: p,
                ),
                const SizedBox(width: 6),
                _tabPill(
                  index: 1,
                  label: 'سابقة (${offlineHistory.length})',
                  activeColor: p.info,
                  p: p,
                ),
                const SizedBox(width: 6),
                _tabPill(
                  index: 2,
                  label: 'المحظورة (${blockedDevices.length})',
                  activeColor: p.danger,
                  p: p,
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
        );

        if (widget.isBottomSheet) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              headerColumn,
              Expanded(
                child: activeList.isEmpty
                    ? Center(
                        child: Text(
                          emptyMessage,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: p.textSecondary, fontSize: 13),
                        ),
                      )
                    : ListView.builder(
                        controller: widget.scrollController,
                        itemCount: activeList.length,
                        itemBuilder: (ctx, i) =>
                            _buildDeviceCard(activeList[i], s, p),
                      ),
              ),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            headerColumn,
            if (activeList.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Text(
                  emptyMessage,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: p.textSecondary, fontSize: 12.5),
                ),
              )
            else
              ...activeList.map((dev) => _buildDeviceCard(dev, s, p)),
          ],
        );
      },
    );
  }

  Widget _tabPill({
    required int index,
    required String label,
    required Color activeColor,
    required dynamic p,
  }) {
    final selected = _filterTab == index;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _filterTab = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? activeColor.withOpacity(0.18) : p.bgElevated,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? activeColor : p.borderSubtle,
            ),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: selected ? activeColor : p.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDeviceCard(ConnectedDevice dev, ModemStatus s, dynamic p) {
    final isThisBusy = _busyMac == dev.macAddress;
    final Color stateColor = dev.isBlocked
        ? p.danger
        : (dev.isConnected ? p.success : p.textSecondary);
    final String stateLabel = dev.isBlocked
        ? 'محظور في المودم'
        : (dev.isConnected ? 'متصل الآن (${dev.connectionType})' : 'سبق اتصاله (غير متصل)');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: p.bgElevated.withOpacity(0.65),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: dev.isBlocked
              ? p.danger.withOpacity(0.55)
              : (dev.isCurrentDevice
                  ? p.accentPrimary.withOpacity(0.55)
                  : p.borderSubtle),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: stateColor.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  dev.isBlocked
                      ? Icons.block_rounded
                      : (dev.isConnected
                          ? Icons.smartphone_rounded
                          : Icons.history_rounded),
                  color: stateColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
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
                              fontWeight: FontWeight.w800,
                              color: p.textPrimary,
                            ),
                          ),
                        ),
                        if (dev.isCurrentDevice) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: p.accentPrimary.withOpacity(0.22),
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: Text(
                              'جهازك الحالي',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: p.accentPrimary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: stateColor,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          dev.connectedDuration.isNotEmpty
                              ? '$stateLabel • ${dev.connectedDuration}'
                              : stateLabel,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: stateColor,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (s.capabilities.hasDeviceRename && !dev.isBlocked)
                IconButton(
                  tooltip: 'تسمية الجهاز',
                  onPressed: () => _showRenameDialog(dev),
                  icon: Icon(Icons.edit_outlined,
                      size: 18, color: p.textSecondary),
                ),
            ],
          ),
          const SizedBox(height: 10),
          // IP + MAC Address Row + Direct Block / Unblock Action Button
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: p.bgCard.withOpacity(0.65),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'IP: ${dev.ipAddress}',
                        textDirection: TextDirection.ltr,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: p.textPrimary,
                        ),
                      ),
                      InkWell(
                        onTap: () {
                          Clipboard.setData(
                              ClipboardData(text: dev.macAddress));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content:
                                  Text('تم نسخ MAC (${dev.macAddress})'),
                            ),
                          );
                        },
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                'MAC: ${dev.macAddress}',
                                textDirection: TextDirection.ltr,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: p.textSecondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(Icons.copy_rounded,
                                size: 12, color: p.textSecondary),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (s.capabilities.hasDeviceBlock && !dev.isCurrentDevice)
                  SizedBox(
                    height: 34,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: dev.isBlocked ? p.success : p.danger,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: (isThisBusy || widget.controller.isBusyAction)
                          ? null
                          : () => _handleBlockToggle(dev, !dev.isBlocked),
                      icon: isThisBusy
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Icon(
                              dev.isBlocked
                                  ? Icons.lock_open_rounded
                                  : Icons.block_rounded,
                              size: 15,
                            ),
                      label: Text(
                        isThisBusy
                            ? 'جاري التنفيذ...'
                            : (dev.isBlocked ? 'فك الحظر' : 'حظر الجهاز'),
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
