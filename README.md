# مودم زيد (Modem Zaid) — إدارة ذكية وموحدة لمودمات يمن فورجي وسبيد فورجي والراوترات

تطبيق أندرويد أصيل مبني بـ **Flutter** يتعرف تلقائياً وبدقة على أي مودم أو راوتر متصل بالهاتف عبر الواي فاي (مع ربط كامل للعملية بشبكة الواي فاي عبر `ConnectivityManager` في أندرويد حتى عند تفعيل بيانات الهاتف الخلوية في نفس الوقت)، ويقوم بترجمة واجهاته ومميزاته وبروتوكولاته برمجياً إلى واجهة عربية موحدة وحقيقية 100%.

## أبرز المميزات المحدثة (v1.6.1)
- **اكتشاف ذكي وتلقائي بالكامل في الخلفية (`SmartModemProfiler`)**:
  - تحليل تلقائي لصفحات HTML وملفات JavaScript الخاصة بالمودم لاكتشاف نقاط اتصال الـ API، وطريقة تشفير كلمة المرور (`SHA-256` / `MD5` / `Base64` / `TCL XOR`)، ونوع الدخول (كلمة مرور فقط أو مستخدم + كلمة مرور) بدون أي تدخل يدوي.
- **إصلاح ودعم كامل لمودمات كلمة المرور الواحدة ومودمات `Demo-Webs` / `Star Speed 4G` / `ZLT` / `Olax`**:
  - معالجة ردود JSON لخوادم `Demo-Webs` (`/reqproc/proc_get` و `/reqproc/proc_post`) وتجربة الدخول الذكي بكلمة المرور فقط وباسم المستخدم `admin` تلقائياً.
  - محول مخصص `TozedZltAdapter` (`/cgi-bin/http.cgi` و `/cgi-bin/lua.cgi`) يدعم قراءة الإشارة، وتعديل الواي فاي، وتثبيت الترددات، وحظر الأجهزة، والرسائل، وإعادة التشغيل.
  - دعم `Qualcomm QCMAP` و `OpenWrt ubus` والتحكم الكامل في `Alcatel / TCL / Speed 4G` (`/jrd/webapi`).
- **دعم أصيل وسريع لمودمات المؤسسة العامة للاتصالات (`Yemen 4G CPE`، `MIFI-L818A`) و `Huawei` و `ZTE` و `SAM` و `Vortex` و `Cool 4G` و `Jetpack`**:
  - ربط أصيل ومحدث تلقائياً بواجهة الواي فاي في أندرويد حتى عند تفعيل وضع الطيران مع الواي فاي أو التبديل بين مودمين يحملان نفس العنوان `192.168.0.1`.

## البنية البرمجية
- `android_overrides/MainActivity.kt` & `lib/services/wifi_network_binder.dart`: قناة أندرويد الأصلية لقراءة بوابة الواي فاي الحقيقية وربط اتصال التطبيق بالواي فاي.
- `lib/models/modem_models.dart`: نماذج البيانات الموحدة وأنماط المصادقة (`ModemAuthMode`) وعائلات البروتوكولات (`ModemFamily`).
- `lib/services/smart_modem_profiler.dart`: محرك التحليل الذكي التلقائي لصفحات HTML وملفات JS.
- `lib/services/modem_detector.dart`: الفحص السريع والدقيق والتعرف الذكي على الشركة والطراز والبروتوكول.
- `lib/services/adapters/`: محولات البروتوكولات الحقيقية (`marvell_uapxc_adapter.dart`, `notion_mifi_adapter.dart`, `zte_goform_adapter.dart`, `tozed_zlt_adapter.dart`, `huawei_hilink_adapter.dart`, `universal_translator_adapter.dart`).
- `lib/services/app_controller.dart`: إدارة الجلسة، مراقبة تغيّر الواي فاي تلقائياً، ومنع تداخل بيانات المودمات.
- `lib/widgets/devices_manager_sheet.dart` & `lib/widgets/supported_modems_sheet.dart`: لوحة إدارة الأجهزة وقائمة المودمات المدعومة.
