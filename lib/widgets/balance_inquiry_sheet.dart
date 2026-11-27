import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/modem_models.dart';
import '../services/app_controller.dart';
import '../services/yemen4g_balance_service.dart';

Future<void> showBalanceInquirySheet(
  BuildContext context,
  AppController controller,
) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: controller.palette.bgCard,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (ctx) => _BalanceInquirySheetBody(controller: controller),
  );
}

class _BalanceInquirySheetBody extends StatefulWidget {
  final AppController controller;

  const _BalanceInquirySheetBody({required this.controller});

  @override
  State<_BalanceInquirySheetBody> createState() =>
      _BalanceInquirySheetBodyState();
}

class _BalanceInquirySheetBodyState extends State<_BalanceInquirySheetBody> {
  final _service = Yemen4gBalanceService();
  final _phoneCtrl = TextEditingController();
  final _captchaCtrl = TextEditingController();

  Uint8List? _captchaBytes;
  bool _loadingCaptcha = true;
  bool _submitting = false;
  BalanceInfo? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.controller.savedPhones.isNotEmpty) {
      _phoneCtrl.text = widget.controller.savedPhones.first;
    }
    _loadCaptcha();
  }

  Future<void> _loadCaptcha() async {
    setState(() {
      _loadingCaptcha = true;
      _error = null;
    });
    final bytes = await _service.loadCaptchaSession();
    if (!mounted) return;
    setState(() {
      _captchaBytes = bytes;
      _loadingCaptcha = false;
      if (bytes == null) {
        _error =
            'تعذر تحميل رمز التحقق. تأكد من توفر اتصال بالإنترنت للوصول لبوابة يمن فورجي.';
      }
    });
  }

  Future<void> _submit() async {
    final phone = _phoneCtrl.text.trim();
    final cap = _captchaCtrl.text.trim();
    if (phone.length < 8) {
      setState(() => _error = 'يرجى إدخال رقم يمن فورجي الصحيح (يبدأ غالباً بـ 10)');
      return;
    }
    if (cap.isEmpty) {
      setState(() => _error = 'يرجى إدخال رمز التحقق الظاهر في الصورة');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
      _result = null;
    });

    try {
      await widget.controller.savePhoneForBalance(phone);
      final info = await _service.queryBalance(
        phoneNumber: phone,
        captchaCode: cap,
      );
      if (!mounted) return;
      setState(() {
        _result = info;
        _submitting = false;
      });
      _captchaCtrl.clear();
      _loadCaptcha();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'حدث خطأ أثناء الاتصال ببوابة الاستعلام، حاول مجدداً.';
      });
      _loadCaptcha();
    }
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _captchaCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.controller.palette;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.account_balance_wallet_rounded,
                        color: p.accentSecondary),
                    const SizedBox(width: 8),
                    Text(
                      'استعلام رصيد يمن فورجي',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: p.textPrimary,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close_rounded, color: p.textSecondary),
                ),
              ],
            ),
            if (widget.controller.savedPhones.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: widget.controller.savedPhones
                    .map(
                      (ph) => ActionChip(
                        backgroundColor: p.bgElevated,
                        side: BorderSide(color: p.borderSubtle),
                        label: Text(
                          ph,
                          textDirection: TextDirection.ltr,
                          style: TextStyle(
                            fontSize: 12,
                            color: p.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onPressed: () => setState(() => _phoneCtrl.text = ph),
                      ),
                    )
                    .toList(),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.number,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: p.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
              decoration: InputDecoration(
                labelText: 'رقم هاتف يمن فورجي (مثال: 10xxxxxxx)',
                filled: true,
                fillColor: p.bgElevated,
                prefixIcon: Icon(Icons.phone_android_rounded, color: p.textSecondary),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: p.borderSubtle),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // CAPTCHA Row
            Row(
              children: [
                Expanded(
                  flex: 5,
                  child: Container(
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: p.borderSubtle),
                    ),
                    alignment: Alignment.center,
                    child: _loadingCaptcha
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : (_captchaBytes != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.memory(
                                  _captchaBytes!,
                                  fit: BoxFit.contain,
                                ),
                              )
                            : const Text(
                                'لا توجد صورة',
                                style: TextStyle(color: Colors.black54, fontSize: 12),
                              )),
                  ),
                ),
                IconButton(
                  tooltip: 'تحديث الرمز',
                  onPressed: _loadingCaptcha ? null : _loadCaptcha,
                  icon: Icon(Icons.refresh_rounded, color: p.accentPrimary),
                ),
                Expanded(
                  flex: 5,
                  child: TextField(
                    controller: _captchaCtrl,
                    keyboardType: TextInputType.number,
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: p.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                    decoration: InputDecoration(
                      hintText: 'رمز التحقق',
                      filled: true,
                      fillColor: p.bgElevated,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: p.danger.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: p.danger.withOpacity(0.4)),
                ),
                child: Text(
                  _error!,
                  style: TextStyle(color: p.danger, fontSize: 12.5),
                ),
              ),
            ],
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: p.accentPrimary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : const Icon(Icons.search_rounded),
              label: Text(
                _submitting ? 'جاري الاستعلام...' : 'استعلام عن الرصيد الآن',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
            if (_result != null) ...[
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: p.bgElevated,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: p.accentPrimary.withOpacity(0.5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'نتيجة الاستعلام (${_result!.phoneNumber})',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: p.accentSecondary,
                          ),
                        ),
                        Icon(Icons.verified_rounded, color: p.success, size: 20),
                      ],
                    ),
                    const Divider(height: 18),
                    if (_result!.remainingBalance.isNotEmpty)
                      _kvRow('الرصيد المتبقي', _result!.remainingBalance, p,
                          highlight: true),
                    if (_result!.packageName.isNotEmpty)
                      _kvRow('الباقة', _result!.packageName, p),
                    if (_result!.expiryDate.isNotEmpty)
                      _kvRow('تاريخ الانتهاء', _result!.expiryDate, p),
                    ..._result!.details.entries.map(
                      (e) => _kvRow(e.key, e.value, p),
                    ),
                    if (_result!.details.isEmpty)
                      Text(
                        _result!.statusMessage,
                        style: TextStyle(color: p.textPrimary, fontSize: 13),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _kvRow(String k, String v, dynamic p, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              k,
              style: TextStyle(color: p.textSecondary, fontSize: 12.5),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              v,
              textAlign: TextAlign.left,
              style: TextStyle(
                color: highlight ? p.success : p.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: highlight ? 15 : 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
