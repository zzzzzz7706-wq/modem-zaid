import 'dart:math' as math;
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

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  late final TextEditingController _userCtrl;
  late final TextEditingController _passCtrl;
  late final AnimationController _entranceCtrl;
  late final AnimationController _waveCtrl;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _userCtrl = TextEditingController(text: widget.controller.savedUsername);
    _passCtrl = TextEditingController(text: widget.controller.savedPassword);

    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    )..forward();

    _waveCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    _entranceCtrl.dispose();
    _waveCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    FocusScope.of(context).unfocus();
    final user = _userCtrl.text.trim().isEmpty ? 'admin' : _userCtrl.text.trim();
    final pass = _passCtrl.text.isEmpty ? 'admin' : _passCtrl.text;
    await widget.controller.login(user, pass);
  }

  Widget _staggeredItem(int step, Widget child) {
    final start = (step * 0.11).clamp(0.0, 0.65);
    final end = (start + 0.45).clamp(0.0, 1.0);
    final curved = CurvedAnimation(
      parent: _entranceCtrl,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.14),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
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
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: p.borderSubtle),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'تفاصيل المودم المكتشف',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: p.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              _infoTile('طراز المودم', widget.controller.identity.modelName, p),
              if (widget.controller.lastModemNumber.isNotEmpty)
                _infoTile('رقم المودم المحفوظ',
                    widget.controller.lastModemNumber, p),
              _infoTile(
                  'نظام الترجمة', widget.controller.identity.protocolLabel, p),
              _infoTile(
                  'عنوان هاتفك', widget.controller.identity.localClientIp, p),
              const SizedBox(height: 14),
              TextField(
                controller: ipCtrl,
                textDirection: TextDirection.ltr,
                style: TextStyle(
                    color: p.textPrimary, fontWeight: FontWeight.w700),
                decoration: InputDecoration(
                  labelText: 'عنوان IP للمودم (اتركه فارغاً للكشف التلقائي)',
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
                      child: const Text('فحص تلقائي'),
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
                      child: const Text('اتصال وحفظ'),
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
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(k, style: TextStyle(fontSize: 12.5, color: p.textSecondary)),
          Flexible(
            child: Text(
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

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final p = c.palette;
    final id = c.identity;
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: p.bgPrimary,
      body: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: screenHeight),
          child: Stack(
            children: [
              // 1. Animated Multi-Layer Aurora Wave Header
              AnimatedBuilder(
                animation: _waveCtrl,
                builder: (context, _) {
                  return Stack(
                    children: [
                      ClipPath(
                        clipper: LoginWaveClipper(phase: _waveCtrl.value + 0.35),
                        child: Container(
                          height: 255,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                p.accentPrimary.withOpacity(0.32),
                                p.accentSecondary.withOpacity(0.22),
                              ],
                              begin: Alignment.topRight,
                              end: Alignment.bottomLeft,
                            ),
                          ),
                        ),
                      ),
                      ClipPath(
                        clipper: LoginWaveClipper(phase: _waveCtrl.value),
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
                    ],
                  );
                },
              ),

              // 2. Top Action Bar (Balance Inquiry Pill + Bell / Info / Theme Icons)
              SafeArea(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          _glassCircleButton(
                            icon: Icons.notifications_none_rounded,
                            onTap: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    id.reachable
                                        ? 'المودم (${id.modelName}) متصل وجاهز على ${id.gatewayIp}'
                                        : 'يرجى الاتصال بشبكة الواي فاي الخاصة بالمودم أولاً',
                                  ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 8),
                          _glassCircleButton(
                            icon: Icons.tune_rounded,
                            onTap: _showGatewayConfigDialog,
                          ),
                          const SizedBox(width: 8),
                          _glassCircleButton(
                            icon: Icons.palette_outlined,
                            onTap: c.cyclePalette,
                          ),
                        ],
                      ),
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
                              color: Colors.white.withOpacity(0.38),
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

              // 3. Staggered Animated Login Content
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 130, 22, 20),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Animated Glowing 4G Router Emblem
                      _staggeredItem(
                        0,
                        AnimatedBuilder(
                          animation: _waveCtrl,
                          builder: (context, child) {
                            final pulse =
                                1.0 + 0.05 * math.sin(_waveCtrl.value * math.pi * 2);
                            return Transform.scale(
                              scale: c.isLoggingIn ? (pulse * 1.06) : pulse,
                              child: Container(
                                width: 78,
                                height: 78,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: p.bgCard,
                                  border: Border.all(
                                    color: p.accentPrimary.withOpacity(0.65),
                                    width: 2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: p.accentPrimary.withOpacity(0.32),
                                      blurRadius: 24,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  Icons.router_rounded,
                                  size: 36,
                                  color: p.accentPrimary,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Welcome Title
                      _staggeredItem(
                        1,
                        Text(
                          'مرحباً بك في مودم زيد',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 27,
                            fontWeight: FontWeight.w800,
                            color: p.textPrimary,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Live Modem Status + Modem Number Badge
                      _staggeredItem(
                        2,
                        InkWell(
                          borderRadius: BorderRadius.circular(24),
                          onTap: c.isDetecting ? null : c.detectModem,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: (id.reachable ? p.success : p.warning)
                                  .withOpacity(0.11),
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
                                      color:
                                          id.reachable ? p.success : p.warning,
                                      boxShadow: [
                                        BoxShadow(
                                          color: (id.reachable
                                                  ? p.success
                                                  : p.warning)
                                              .withOpacity(0.6),
                                          blurRadius: 6,
                                        ),
                                      ],
                                    ),
                                  ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    c.isDetecting
                                        ? 'جاري التعرف على المودم...'
                                        : (id.reachable
                                            ? (c.lastModemNumber.isNotEmpty
                                                ? 'متصل • ${id.modelName} • ${c.lastModemNumber}'
                                                : 'متصل • ${id.modelName} (${id.gatewayIp})')
                                            : 'غير متصل بالمودم (اضغط لإعادة الفحص)'),
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color:
                                          id.reachable ? p.success : p.warning,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 26),

                      // Glassmorphic Login Form Card
                      _staggeredItem(
                        3,
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: p.bgCard.withOpacity(0.92),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: p.borderSubtle.withOpacity(0.85),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.24),
                                blurRadius: 22,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextField(
                                controller: _userCtrl,
                                style: TextStyle(
                                  color: p.textPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                                decoration: InputDecoration(
                                  labelText: 'اسم المستخدم',
                                  labelStyle:
                                      TextStyle(color: p.textSecondary),
                                  hintText: 'الافتراضي: admin',
                                  filled: true,
                                  fillColor: p.bgElevated.withOpacity(0.75),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 15,
                                  ),
                                  prefixIcon: Icon(
                                    Icons.person_outline_rounded,
                                    color: p.accentPrimary,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide:
                                        BorderSide(color: p.borderSubtle),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide:
                                        BorderSide(color: p.borderSubtle),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: BorderSide(
                                        color: p.accentPrimary, width: 1.5),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              TextField(
                                controller: _passCtrl,
                                obscureText: _obscurePassword,
                                onSubmitted: (_) => _handleLogin(),
                                style: TextStyle(
                                  color: p.textPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                                decoration: InputDecoration(
                                  labelText: 'كلمة المرور',
                                  labelStyle:
                                      TextStyle(color: p.textSecondary),
                                  hintText: 'الافتراضية: admin',
                                  filled: true,
                                  fillColor: p.bgElevated.withOpacity(0.75),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 15,
                                  ),
                                  prefixIcon: Icon(
                                    Icons.lock_outline_rounded,
                                    color: p.accentPrimary,
                                  ),
                                  suffixIcon: IconButton(
                                    onPressed: () => setState(() =>
                                        _obscurePassword = !_obscurePassword),
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                      color: p.textSecondary,
                                    ),
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide:
                                        BorderSide(color: p.borderSubtle),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide:
                                        BorderSide(color: p.borderSubtle),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: BorderSide(
                                        color: p.accentPrimary, width: 1.5),
                                  ),
                                ),
                              ),
                              if (c.lastError != null) ...[
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 9,
                                  ),
                                  decoration: BoxDecoration(
                                    color: p.danger.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                        color: p.danger.withOpacity(0.4)),
                                  ),
                                  child: Text(
                                    c.lastError!,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        color: p.danger, fontSize: 12.5),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 20),

                              // Gradient Login Button + Biometric Fingerprint Orb
                              Row(
                                children: [
                                  Expanded(
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(16),
                                      onTap:
                                          c.isLoggingIn ? null : _handleLogin,
                                      child: AnimatedContainer(
                                        duration:
                                            const Duration(milliseconds: 250),
                                        height: 54,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              p.accentSecondary,
                                              p.accentPrimary,
                                            ],
                                            begin: Alignment.centerRight,
                                            end: Alignment.centerLeft,
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(16),
                                          boxShadow: [
                                            BoxShadow(
                                              color: p.accentPrimary
                                                  .withOpacity(0.38),
                                              blurRadius: 16,
                                              offset: const Offset(0, 6),
                                            ),
                                          ],
                                        ),
                                        child: c.isLoggingIn
                                            ? const Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  SizedBox(
                                                    width: 20,
                                                    height: 20,
                                                    child:
                                                        CircularProgressIndicator(
                                                      strokeWidth: 2.3,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                  SizedBox(width: 10),
                                                  Text(
                                                    'جاري الدخول للمودم...',
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 15,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                ],
                                              )
                                            : const Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  Text(
                                                    'تسجيل الدخول إلى المودم',
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 15.5,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                    ),
                                                  ),
                                                  SizedBox(width: 8),
                                                  Icon(
                                                    Icons
                                                        .arrow_back_ios_new_rounded,
                                                    color: Colors.white,
                                                    size: 16,
                                                  ),
                                                ],
                                              ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  InkWell(
                                    borderRadius: BorderRadius.circular(16),
                                    onTap: c.isLoggingIn
                                        ? null
                                        : () => c.authenticateWithBiometrics(),
                                    child: Container(
                                      width: 54,
                                      height: 54,
                                      decoration: BoxDecoration(
                                        color: p.bgElevated,
                                        borderRadius: BorderRadius.circular(16),
                                        border:
                                            Border.all(color: p.borderSubtle),
                                      ),
                                      child: Icon(
                                        Icons.fingerprint_rounded,
                                        size: 28,
                                        color: p.accentPrimary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
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
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      Text(
                        'مودم زيد • الإصدار 1.2.0',
                        style: TextStyle(
                          color: p.textSecondary.withOpacity(0.75),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
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
        width: 39,
        height: 39,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(0.22),
          border: Border.all(color: Colors.white.withOpacity(0.34)),
        ),
        child: Icon(icon, color: Colors.white, size: 19),
      ),
    );
  }
}
