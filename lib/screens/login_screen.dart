import 'package:flutter/material.dart';
import '../services/app_controller.dart';
import '../widgets/balance_inquiry_sheet.dart';
import '../widgets/gauges_and_cards.dart';

class LoginScreen extends StatefulWidget {
  final AppController controller;

  const LoginScreen({super.key, required this.controller});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final TextEditingController _userCtrl;
  late final TextEditingController _passCtrl;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _userCtrl = TextEditingController(text: widget.controller.savedUsername);
    _passCtrl = TextEditingController(text: widget.controller.savedPassword);
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    FocusScope.of(context).unfocus();
    final user = _userCtrl.text.trim().isEmpty ? 'admin' : _userCtrl.text.trim();
    final pass = _passCtrl.text.isEmpty ? 'admin' : _passCtrl.text;
    await widget.controller.login(user, pass);
  }

  void _showGatewayConfigDialog() {
    final p = widget.controller.palette;
    final ipCtrl = TextEditingController(
      text: widget.controller.customGatewayIp.isEmpty
          ? widget.controller.identity.gatewayIp
          : widget.controller.customGatewayIp,
    );

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
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
                'معلومات الاتصال والتعرف الذكي',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: p.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              _infoTile('المودم المكتشف', widget.controller.identity.modelName, p),
              _infoTile(
                  'البروتوكول المترجم', widget.controller.identity.protocolLabel, p),
              _infoTile(
                  'عنوان هاتفك', widget.controller.identity.localClientIp, p),
              const SizedBox(height: 12),
              TextField(
                controller: ipCtrl,
                textDirection: TextDirection.ltr,
                style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  labelText: 'عنوان المودم (اتركه فارغاً للكشف التلقائي)',
                  hintText: '192.168.43.1',
                  filled: true,
                  fillColor: p.bgElevated,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await widget.controller.setCustomGatewayIp('');
                      },
                      child: const Text('كشف تلقائي'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: p.accentPrimary,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await widget.controller.setCustomGatewayIp(ipCtrl.text);
                      },
                      child: const Text('فحص وحفظ'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoTile(String k, String v, dynamic p) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(k, style: TextStyle(fontSize: 12.5, color: p.textSecondary)),
          Flexible(
            child: Text(
              v,
              textAlign: TextAlign.left,
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

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final p = c.palette;
    final id = c.identity;

    return Scaffold(
      backgroundColor: p.bgPrimary,
      body: SingleChildScrollView(
        child: SizedBox(
          height: MediaQuery.of(context).size.height,
          child: Stack(
            children: [
              // 1. Curved Top Gradient Wave (matching 00:00 of the video)
              ClipPath(
                clipper: LoginWaveClipper(),
                child: Container(
                  height: 235,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: p.waveGradient,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),
              ),

              // 2. Top Action Bar (Balance Inquiry Pill + Bell / Info / Theme Icons)
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Right icons (RTL start): Bell, Info, Palette
                      Row(
                        children: [
                          _glassCircleButton(
                            icon: Icons.notifications_none_rounded,
                            onTap: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    id.reachable
                                        ? 'المودم (${id.modelName}) جاهز على ${id.gatewayIp}'
                                        : 'يرجى الاتصال بشبكة الواي فاي الخاصة بالمودم أولاً',
                                  ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 8),
                          _glassCircleButton(
                            icon: Icons.info_outline_rounded,
                            onTap: _showGatewayConfigDialog,
                          ),
                          const SizedBox(width: 8),
                          _glassCircleButton(
                            icon: Icons.palette_outlined,
                            onTap: c.cyclePalette,
                          ),
                        ],
                      ),

                      // Left pill (RTL end): استعلام الرصيد
                      InkWell(
                        borderRadius: BorderRadius.circular(24),
                        onTap: () => showBalanceInquirySheet(context, c),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.22),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.35),
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'استعلام الرصيد',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              SizedBox(width: 6),
                              Icon(
                                Icons.account_balance_wallet_outlined,
                                color: Colors.white,
                                size: 17,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 3. Main Welcome & Login Form
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Spacer(flex: 3),
                      Text(
                        'مرحباً بك في مودم زيد',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: p.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Connection Status Pill Badge (متصل / جاري الفحص)
                      InkWell(
                        borderRadius: BorderRadius.circular(24),
                        onTap: c.isDetecting ? null : c.detectModem,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: (id.reachable ? p.success : p.warning)
                                .withOpacity(0.10),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: (id.reachable ? p.success : p.warning)
                                  .withOpacity(0.55),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (c.isDetecting)
                                SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: p.accentPrimary,
                                  ),
                                )
                              else
                                Container(
                                  width: 9,
                                  height: 9,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: id.reachable ? p.success : p.warning,
                                  ),
                                ),
                              const SizedBox(width: 8),
                              Text(
                                c.isDetecting
                                    ? 'جاري التعرف على المودم...'
                                    : (id.reachable
                                        ? 'متصل • ${id.modelName}'
                                        : 'غير متصل (اضغط لإعادة الفحص)'),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: id.reachable ? p.success : p.warning,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 30),

                      // Username Field
                      TextField(
                        controller: _userCtrl,
                        style: TextStyle(
                          color: p.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: InputDecoration(
                          hintText: 'اسم المستخدم (الافتراضية: admin)',
                          hintStyle: TextStyle(
                            color: p.textSecondary.withOpacity(0.75),
                            fontSize: 13.5,
                          ),
                          filled: true,
                          fillColor: p.bgCard,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 16,
                          ),
                          prefixIcon: Icon(
                            Icons.person_outline_rounded,
                            color: p.textSecondary,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: p.borderSubtle),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: p.borderSubtle),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide:
                                BorderSide(color: p.accentPrimary, width: 1.4),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Password Field
                      TextField(
                        controller: _passCtrl,
                        obscureText: _obscurePassword,
                        onSubmitted: (_) => _handleLogin(),
                        style: TextStyle(
                          color: p.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: InputDecoration(
                          hintText: 'كلمة المرور (الافتراضية: admin)',
                          hintStyle: TextStyle(
                            color: p.textSecondary.withOpacity(0.75),
                            fontSize: 13.5,
                          ),
                          filled: true,
                          fillColor: p.bgCard,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 16,
                          ),
                          prefixIcon: Icon(
                            Icons.lock_outline_rounded,
                            color: p.textSecondary,
                          ),
                          suffixIcon: IconButton(
                            onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword),
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color: p.textSecondary,
                            ),
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: p.borderSubtle),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: p.borderSubtle),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide:
                                BorderSide(color: p.accentPrimary, width: 1.4),
                          ),
                        ),
                      ),

                      if (c.lastError != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: p.danger.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: p.danger.withOpacity(0.4)),
                          ),
                          child: Text(
                            c.lastError!,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: p.danger, fontSize: 12.5),
                          ),
                        ),
                      ],
                      const SizedBox(height: 26),

                      // Login Button + Biometric Fingerprint Circle (matching 00:00)
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 54,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: p.bgElevated,
                                  foregroundColor: p.textPrimary,
                                  elevation: 0,
                                  side: BorderSide(color: p.borderSubtle),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                onPressed: c.isLoggingIn ? null : _handleLogin,
                                child: c.isLoggingIn
                                    ? SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.2,
                                          color: p.accentPrimary,
                                        ),
                                      )
                                    : const Text(
                                        'تسجيل الدخول إلى المودم',
                                        style: TextStyle(
                                          fontSize: 15.5,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          InkWell(
                            borderRadius: BorderRadius.circular(28),
                            onTap: c.isLoggingIn
                                ? null
                                : () => c.authenticateWithBiometrics(),
                            child: Container(
                              width: 54,
                              height: 54,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: p.bgElevated,
                                border: Border.all(color: p.borderSubtle),
                              ),
                              child: Icon(
                                Icons.fingerprint_rounded,
                                size: 28,
                                color: p.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),

                      if (!id.reachable) ...[
                        const SizedBox(height: 12),
                        TextButton.icon(
                          onPressed: c.isLoggingIn ? null : c.enterDemoMode,
                          icon: Icon(Icons.play_circle_outline_rounded,
                              color: p.accentSecondary, size: 18),
                          label: Text(
                            'معاينة الواجهة (وضع المحاكاة بدون مودم)',
                            style: TextStyle(
                              color: p.accentSecondary,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],

                      const Spacer(flex: 2),
                      Text(
                        'v1.0.0',
                        style: TextStyle(
                          color: p.textSecondary.withOpacity(0.75),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 18),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _glassCircleButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(0.22),
          border: Border.all(color: Colors.white.withOpacity(0.32)),
        ),
        child: Icon(icon, color: Colors.white, size: 19),
      ),
    );
  }
}
