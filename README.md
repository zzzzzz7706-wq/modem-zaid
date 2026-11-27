# مودم زيد (Modem Zaid) — إدارة ذكية وموحدة لمودمات يمن فورجي وسبيد فورجي والراوترات

تطبيق أندرويد أصيل مبني بـ **Flutter** يتعرف تلقائياً وبدقة على أي مودم أو راوتر متصل بالهاتف عبر الواي فاي (مع ربط كامل للعملية بشبكة الواي فاي عبر `ConnectivityManager` في أندرويد حتى عند تفعيل بيانات الهاتف الخلوية في نفس الوقت)، ويقوم بترجمة واجهاته ومميزاته وبروتوكولاته برمجياً إلى واجهة عربية موحدة وحقيقية 100%.

## أبرز المميزات المحدثة (v1.6.0)
- **المحرك الذكي الشامل لاكتشاف والتحكم بأي مودم يمن فورجي (`SmartModemProfiler`)**:
  - تحليل تلقائي لصفحات HTML وملفات JavaScript الخاصة بالمودم لاكتشاف نقاط اتصال الـ API، وطريقة تشفير كلمة المرور (`SHA-256` / `MD5` / `Base64` / `TCL XOR`)، وحقول نماذج الدخول تلقائياً.
  - **نافذة محلل المودم الذكي (`SmartModemInspectorSheet`)**: فحص عميق لبصمة أي مودم، واختيار البروتوكول يدوياً عند الحاجة، ونسخ بصمة المودم (بدون كلمات مرور).
- **دعم أصيل ومتكامل لمودمات `Star Speed 4G` و `ZLT / Tozed` و `Qualcomm QCMAP` و `Alcatel / Speed 4G`**:
  - محول مخصص `TozedZltAdapter` (`/cgi-bin/http.cgi` و `/cgi-bin/lua.cgi`) يدعم قراءة الإشارة، وتعديل الواي فاي، وتثبيت الترددات، وحظر الأجهزة، وقراءة الرسائل، وإعادة التشغيل.
  - تطوير `ZteGoformAdapter` لدعم جميع متغيرات تشفير `Star Speed 4G / ZXIC` والدخول متعدد المستخدمين (`LOGIN_MULTI_USER`).
  - تطوير `UniversalTranslatorAdapter` بدعم `Qualcomm QCMAP` و `OpenWrt ubus` والتحكم الكامل في `Alcatel / TCL / Speed 4G` (`/jrd/webapi`).
- **دعم أصيل وسريع لمودمات المؤسسة العامة للاتصالات (`Yemen 4G CPE`، `MIFI-L818A`) و `Olax` و `Huawei` و `ZTE` و `SAM` و `Vortex` و `Cool 4G` و `Jetpack`**:
  - ربط أصيل ومحدث تلقائياً بواجهة الواي فاي في أندرويد حتى عند تفعيل وضع الطيران مع الواي فاي أو التبديل بين مودمين يحملان نفس العنوان `192.168.0.1`.
  - بيانات حقيقية 100% بدون وضع ديمو مع إدارة وحظر فعلي للأجهزة عبر `MAC Address`.

## البنية البرمجية
- `android_overrides/MainActivity.kt` & `lib/services/wifi_network_binder.dart`: قناة أندرويد الأصلية لقراءة بوابة الواي فاي الحقيقية وربط اتصال التطبيق بالواي فاي.
- `lib/models/modem_models.dart`: نماذج البيانات الموحدة وأنماط المصادقة (`ModemAuthMode`) وعائلات البروتوكولات (`ModemFamily`).
- `lib/services/smart_modem_profiler.dart`: محرك التحليل الذكي لصفحات HTML وملفات JS لاكتشاف نقاط الاتصال والتشفير تلقائياً.
- `lib/services/modem_detector.dart`: الفحص السريع والدقيق والتعرف الذكي على الشركة والطراز والبروتوكول.
- `lib/services/adapters/`: محولات البروتوكولات الحقيقية (`marvell_uapxc_adapter.dart`, `notion_mifi_adapter.dart`, `zte_goform_adapter.dart`, `tozed_zlt_adapter.dart`, `huawei_hilink_adapter.dart`, `universal_translator_adapter.dart`).
- `lib/services/app_controller.dart`: إدارة الجلسة، مراقبة تغيّر الواي فاي تلقائياً، ومنع تداخل بيانات المودمات.
- `lib/widgets/smart_modem_inspector_sheet.dart`, `devices_manager_sheet.dart` & `supported_modems_sheet.dart`: محلل المودم الذكي، لوحة إدارة الأجهزة، وقائمة المودمات المدعومة.
