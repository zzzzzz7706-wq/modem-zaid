import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/app_controller.dart';

/// Exact "تعديل إعدادات الواي فاي" modal from frames 00:08 - 00:11 of the video
Future<void> showWifiQuickModal(
  BuildContext context,
  AppController controller,
) async {
  final s = controller.status;
  final ssidCtrl = TextEditingController(text: s.ssid);
  final passCtrl = TextEditingController(text: s.wifiPassword);
  bool obscurePass = true;
  bool hideSsid = s.isHiddenSsid;
  int maxClients = s.maxClients.clamp(1, 32);
  bool saving = false;

  await showDialog(
    context: context,
    barrierDismissible: !saving,
    builder: (ctx) {
      final p = controller.palette;
      return StatefulBuilder(
        builder: (ctx, setState) {
          return Dialog(
            backgroundColor: p.bgCard,
            insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: BorderSide(color: p.borderSubtle),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'تعديل إعدادات الواي فاي',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: p.textPrimary,
                        ),
                      ),
                      IconButton(
                        onPressed: saving ? null : () => Navigator.pop(ctx),
                        icon: Icon(Icons.close_rounded, color: p.textSecondary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // SSID Field
                  Text(
                    'اسم الشبكة (SSID)',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: p.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: ssidCtrl,
                    style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: p.bgElevated,
                      prefixIcon: Icon(Icons.wifi_rounded, color: p.textSecondary),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: p.borderSubtle),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: p.borderSubtle),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  // Password Field
                  Text(
                    'كلمة المرور',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: p.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: passCtrl,
                    obscureText: obscurePass,
                    style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: p.bgElevated,
                      hintText: '8 أحرف أو أرقام على الأقل',
                      hintStyle: TextStyle(color: p.textSecondary.withOpacity(0.6)),
                      prefixIcon: Icon(Icons.lock_outline_rounded, color: p.textSecondary),
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => obscurePass = !obscurePass),
                        icon: Icon(
                          obscurePass
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          color: p.textSecondary,
                        ),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: p.borderSubtle),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: p.borderSubtle),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  // Hide SSID Toggle Card
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: p.bgElevated.withOpacity(0.65),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: p.borderSubtle),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.visibility_off_outlined, color: p.textSecondary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'إخفاء اسم الشبكة',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: p.textPrimary,
                                ),
                              ),
                              Text(
                                'إخفاء شبكة الواي فاي عن الظهور العام.',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: p.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: hideSsid,
                          activeColor: p.accentSecondary,
                          onChanged: (v) => setState(() => hideSsid = v),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Max Connected Devices Card
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: p.bgElevated.withOpacity(0.65),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: p.borderSubtle),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.devices_rounded, color: p.textSecondary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'الحد الأقصى للأجهزة المتصلة',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: p.textPrimary,
                                ),
                              ),
                              Text(
                                'اختر حد الأجهزة',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: p.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: p.bgCard,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: p.borderSubtle),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<int>(
                              value: maxClients,
                              dropdownColor: p.bgElevated,
                              items: List.generate(32, (i) => i + 1)
                                  .map(
                                    (n) => DropdownMenuItem(
                                      value: n,
                                      child: Text(
                                        '$n',
                                        style: TextStyle(
                                          color: p.textPrimary,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (val) {
                                if (val != null) setState(() => maxClients = val);
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Action Buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            side: BorderSide(color: p.borderSubtle),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: saving ? null : () => Navigator.pop(ctx),
                          child: Text(
                            'إلغاء',
                            style: TextStyle(
                              color: p.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: p.bgElevated,
                            foregroundColor: p.textPrimary,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            side: BorderSide(color: p.accentPrimary.withOpacity(0.6)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: saving
                              ? null
                              : () async {
                                  final newSsid = ssidCtrl.text.trim();
                                  final newPass = passCtrl.text;
                                  if (newSsid.isEmpty) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('يرجى إدخال اسم الشبكة (SSID)'),
                                      ),
                                    );
                                    return;
                                  }
                                  if (newPass.isNotEmpty && newPass.length < 8) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'كلمة مرور الواي فاي يجب ألا تقل عن 8 أحرف أو أرقام',
                                        ),
                                      ),
                                    );
                                    return;
                                  }
                                  setState(() => saving = true);
                                  final ok = await controller.saveWifiSettings(
                                    ssid: newSsid,
                                    password: newPass,
                                    hideSsid: hideSsid,
                                    maxClients: maxClients,
                                  );
                                  if (ctx.mounted) Navigator.pop(ctx);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          ok
                                              ? 'تم حفظ إعدادات الواي فاي بنجاح (قد ينقطع الاتصال لثوانٍ لتطبيق التغيير)'
                                              : 'تعذر حفظ التغييرات في المودم',
                                        ),
                                      ),
                                    );
                                  }
                                },
                          child: saving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text(
                                  'حفظ التغييرات',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
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

/// Scannable Wi-Fi QR Code Modal
Future<void> showWifiQrSheet(
  BuildContext context,
  AppController controller,
) async {
  final s = controller.status;
  final p = controller.palette;
  final qrPayload =
      'WIFI:T:WPA;S:${s.ssid};P:${s.wifiPassword};H:${s.isHiddenSsid ? 'true' : 'false'};;';

  await showModalBottomSheet(
    context: context,
    backgroundColor: p.bgCard,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    builder: (ctx) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: p.borderSubtle,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'باركود الاتصال بشبكة الواي فاي',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: p.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'وجه كاميرا الهاتف الآخر لمسح الرمز والاتصال مباشرة بشبكة (${s.ssid})',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: p.textSecondary),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: QrImageView(
                data: qrPayload,
                version: QrVersions.auto,
                size: 200,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'SSID: ${s.ssid}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: p.accentPrimary,
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// LTE Band Lock & Network Mode Modal (4G orb & إعدادات الأبراج والنطاقات)
Future<void> showBandLockModal(
  BuildContext context,
  AppController controller,
) async {
  final s = controller.status;
  bool manual = s.isManualBand;
  String netMode = s.networkMode;
  final selected = Set<String>.from(
    s.selectedBands.isEmpty ? [s.band] : s.selectedBands,
  );
  bool saving = false;

  const bandDescriptions = <String, String>{
    'B28': '700 MHz (تغطية بعيدة المدى - يمن فورجي)',
    'B3': '1800 MHz (سرعة عالية للمدن - يمن فورجي)',
    'B20': '800 MHz (اختراق ممتاز للمباني)',
    'B1': '2100 MHz (نطاق عالي السعة)',
    'B7': '2600 MHz (سرعات فائقة)',
    'B8': '900 MHz (تغطية واسعة)',
    'B38': '2600 TDD',
    'B40': '2300 TDD',
    'B41': '2500 TDD (سرعة عالية جداً)',
  };

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: controller.palette.bgCard,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    builder: (ctx) {
      final p = controller.palette;
      return StatefulBuilder(
        builder: (ctx, setState) {
          return Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              18,
              20,
              MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.cell_tower_rounded, color: p.accentPrimary),
                          const SizedBox(width: 8),
                          Text(
                            'إعدادات الأبراج وتثبيت الترددات',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: p.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: p.accentPrimary.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'الحالي: ${s.band}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: p.accentPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // Network Mode Selector
                  Text(
                    'وضع الشبكة المفضل',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: p.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _modeChip(
                        label: '4G فقط (ثابت)',
                        active: netMode == '4g_only',
                        palette: p,
                        onTap: () => setState(() => netMode = '4g_only'),
                      ),
                      const SizedBox(width: 8),
                      _modeChip(
                        label: 'تلقائي 4G/3G',
                        active: netMode == 'auto',
                        palette: p,
                        onTap: () => setState(() => netMode = 'auto'),
                      ),
                      const SizedBox(width: 8),
                      _modeChip(
                        label: '3G فقط',
                        active: netMode == '3g_only',
                        palette: p,
                        onTap: () => setState(() => netMode = '3g_only'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // Auto vs Manual Band Switch
                  SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    tileColor: p.bgElevated.withOpacity(0.6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(color: p.borderSubtle),
                    ),
                    title: Text(
                      'تثبيت يدوي للنطاق الترددي (Band Lock)',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: p.textPrimary,
                      ),
                    ),
                    subtitle: Text(
                      manual
                          ? 'سيتم إجبار المودم على الاتصال بالترددات المحددة فقط'
                          : 'المودم يختار التردد تلقائياً حسب البرج',
                      style: TextStyle(fontSize: 11.5, color: p.textSecondary),
                    ),
                    value: manual,
                    activeColor: p.accentPrimary,
                    onChanged: (v) => setState(() => manual = v),
                  ),
                  if (manual) ...[
                    const SizedBox(height: 12),
                    Text(
                      'اختر تردد أو أكثر لتثبيت المودم عليه:',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: p.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: s.supportedBands.map((b) {
                        final isSel = selected.contains(b);
                        return FilterChip(
                          selected: isSel,
                          backgroundColor: p.bgElevated,
                          selectedColor: p.accentPrimary.withOpacity(0.26),
                          checkmarkColor: p.accentPrimary,
                          side: BorderSide(
                            color: isSel ? p.accentPrimary : p.borderSubtle,
                          ),
                          label: Text(
                            bandDescriptions.containsKey(b)
                                ? '$b • ${bandDescriptions[b]!.split('(').first.trim()}'
                                : 'LTE $b',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: isSel ? p.textPrimary : p.textSecondary,
                            ),
                          ),
                          onSelected: (val) {
                            setState(() {
                              if (val) {
                                selected.add(b);
                              } else if (selected.length > 1) {
                                selected.remove(b);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ],
                  const SizedBox(height: 20),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: p.accentPrimary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: saving
                        ? null
                        : () async {
                            setState(() => saving = true);
                            final ok = await controller.saveBandSettings(
                              manualMode: manual,
                              networkMode: netMode,
                              bands: selected.toList(),
                            );
                            if (ctx.mounted) Navigator.pop(ctx);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    ok
                                        ? 'تم تطبيق إعدادات الأبراج والنطاقات بنجاح!'
                                        : 'هذا المودم لا يدعم قفل الترددات عن بُعد أو فشل التطبيق',
                                  ),
                                ),
                              );
                            }
                          },
                    child: saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2),
                          )
                        : const Text(
                            'تطبيق وتثبيت الإعدادات',
                            style: TextStyle(
                                fontSize: 14.5, fontWeight: FontWeight.w700),
                          ),
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

Widget _modeChip({
  required String label,
  required bool active,
  required dynamic palette,
  required VoidCallback onTap,
}) {
  return Expanded(
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active
              ? palette.accentPrimary.withOpacity(0.22)
              : palette.bgElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active ? palette.accentPrimary : palette.borderSubtle,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: active ? palette.textPrimary : palette.textSecondary,
          ),
        ),
      ),
    ),
  );
}

/// Speed Limit Controller Modal (تحديد السرعة)
Future<void> showSpeedLimitModal(
  BuildContext context,
  AppController controller,
) async {
  final s = controller.status;
  bool enabled = s.speedLimitEnabled;
  double dl = s.downloadLimitMbps.clamp(1, 150).toDouble();
  double ul = s.uploadLimitMbps.clamp(1, 50).toDouble();
  bool saving = false;

  await showDialog(
    context: context,
    builder: (ctx) {
      final p = controller.palette;
      return StatefulBuilder(
        builder: (ctx, setState) {
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
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'تحديد سرعة الإنترنت',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: p.textPrimary,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: Icon(Icons.close_rounded, color: p.textSecondary),
                      ),
                    ],
                  ),
                  SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                    tileColor: p.bgElevated,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    title: Text(
                      'تفعيل تحديد السرعة',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: p.textPrimary,
                      ),
                    ),
                    subtitle: Text(
                      'لتوفير باقة يمن فورجي ومنع استنزاف الرصيد',
                      style: TextStyle(fontSize: 11.5, color: p.textSecondary),
                    ),
                    value: enabled,
                    activeColor: p.success,
                    onChanged: (v) => setState(() => enabled = v),
                  ),
                  if (enabled) ...[
                    const SizedBox(height: 16),
                    Text(
                      'حد سرعة التنزيل: ${dl.round()} ميجابت/ث',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: p.info,
                      ),
                    ),
                    Slider(
                      value: dl,
                      min: 1,
                      max: 150,
                      divisions: 149,
                      activeColor: p.info,
                      onChanged: (v) => setState(() => dl = v),
                    ),
                    Text(
                      'حد سرعة الرفع: ${ul.round()} ميجابت/ث',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: p.warning,
                      ),
                    ),
                    Slider(
                      value: ul,
                      min: 1,
                      max: 50,
                      divisions: 49,
                      activeColor: p.warning,
                      onChanged: (v) => setState(() => ul = v),
                    ),
                  ],
                  const SizedBox(height: 16),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: p.accentPrimary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: saving
                        ? null
                        : () async {
                            setState(() => saving = true);
                            final ok = await controller.saveSpeedLimit(
                              enabled: enabled,
                              downloadMbps: dl.round(),
                              uploadMbps: ul.round(),
                            );
                            if (ctx.mounted) Navigator.pop(ctx);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    ok
                                        ? 'تم تحديث إعدادات السرعة بنجاح'
                                        : 'هذا المودم لا يدعم تحديد السرعة أو فشل الحفظ',
                                  ),
                                ),
                              );
                            }
                          },
                    child: saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2),
                          )
                        : const Text(
                            'حفظ الإعدادات',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
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

/// Change Admin Password Modal (إعدادات كلمة مرور المدير)
Future<void> showAdminPasswordModal(
  BuildContext context,
  AppController controller,
) async {
  final passCtrl = TextEditingController();
  final confirmCtrl = TextEditingController();
  bool obscure = true;
  bool saving = false;

  await showDialog(
    context: context,
    builder: (ctx) {
      final p = controller.palette;
      return StatefulBuilder(
        builder: (ctx, setState) {
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
                  Text(
                    'تغيير كلمة مرور مدير المودم',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: p.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: passCtrl,
                    obscureText: obscure,
                    style: TextStyle(color: p.textPrimary),
                    decoration: InputDecoration(
                      labelText: 'كلمة المرور الجديدة',
                      filled: true,
                      fillColor: p.bgElevated,
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => obscure = !obscure),
                        icon: Icon(
                          obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirmCtrl,
                    obscureText: obscure,
                    style: TextStyle(color: p.textPrimary),
                    decoration: InputDecoration(
                      labelText: 'تأكيد كلمة المرور الجديدة',
                      filled: true,
                      fillColor: p.bgElevated,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('إلغاء'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: p.accentPrimary,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: saving
                              ? null
                              : () async {
                                  final np = passCtrl.text.trim();
                                  if (np.length < 4) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                            'كلمة المرور يجب ألا تقل عن 4 أحرف'),
                                      ),
                                    );
                                    return;
                                  }
                                  if (np != confirmCtrl.text.trim()) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('كلمتا المرور غير متطابقتين'),
                                      ),
                                    );
                                    return;
                                  }
                                  setState(() => saving = true);
                                  final ok =
                                      await controller.updateAdminPassword(np);
                                  if (ctx.mounted) Navigator.pop(ctx);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          ok
                                              ? 'تم تحديث كلمة مرور المدير بنجاح'
                                              : 'تعذر تحديث كلمة مرور المدير',
                                        ),
                                      ),
                                    );
                                  }
                                },
                          child: const Text('حفظ'),
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
