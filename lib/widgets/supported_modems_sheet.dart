import 'package:flutter/material.dart';
import '../services/app_controller.dart';

class _ModemBrandGroup {
  final String brandAr;
  final List<(String model, String gateway, String authType)> models;

  const _ModemBrandGroup({
    required this.brandAr,
    required this.models,
  });
}

const List<_ModemBrandGroup> _supportedYemenModems = [
  _ModemBrandGroup(
    brandAr: 'المؤسسة العامة للاتصالات (يمن فورجي)',
    models: [
      ('Yemen 4G CPE (UAPXC)', '192.168.0.1', 'مستخدم + كلمة مرور'),
      ('MIFI-L818A / M028T / L02H', '192.168.43.1', 'مستخدم + كلمة مرور'),
    ],
  ),
  _ModemBrandGroup(
    brandAr: 'ستار سبيد (Star Speed)',
    models: [
      ('Star Speed MiFi (MF 600)', '192.168.0.1', 'كلمة مرور / مستخدم'),
      ('Star Speed Router (OSYSTEL)', '192.168.0.1', 'كلمة مرور فقط'),
    ],
  ),
  _ModemBrandGroup(
    brandAr: 'أولاكس (Olax)',
    models: [
      ('MT80PRO', '192.168.0.1 / 192.168.8.1', 'كلمة مرور فقط'),
      ('MT80', '192.168.0.1 / 192.168.8.1', 'كلمة مرور فقط'),
      ('MF982', '192.168.0.1', 'كلمة مرور فقط'),
    ],
  ),
  _ModemBrandGroup(
    brandAr: 'زد إل تي (ZLT)',
    models: [
      ('ZLT M60M', '192.168.0.1', 'كلمة مرور / مستخدم'),
      ('ZLT S25', '192.168.0.1 / 192.168.70.1', 'كلمة مرور / مستخدم'),
      ('ZLT M90 PRO', '192.168.0.1', 'كلمة مرور فقط'),
    ],
  ),
  _ModemBrandGroup(
    brandAr: 'زد تي إي (ZTE)',
    models: [
      ('ZTE MF293', '192.168.0.1', 'كلمة مرور فقط'),
      ('ZTE U10S / U20', '192.168.0.1', 'كلمة مرور فقط'),
    ],
  ),
  _ModemBrandGroup(
    brandAr: 'هواوي (Huawei)',
    models: [
      ('Huawei B535', '192.168.8.1', 'كلمة مرور فقط'),
      ('Huawei CPE (B310 / B312 / B315 / E5577)', '192.168.8.1', 'كلمة مرور فقط'),
    ],
  ),
  _ModemBrandGroup(
    brandAr: 'سام (SAM)',
    models: [
      ('SAM M50', '192.168.0.1 / 192.168.8.1', 'مستخدم + كلمة مرور'),
      ('SAM M50 PRO', '192.168.0.1 / 192.168.8.1', 'مستخدم + كلمة مرور'),
    ],
  ),
  _ModemBrandGroup(
    brandAr: 'فورتكس (Vortex)',
    models: [
      ('Vortex (M49)', '192.168.43.1 / 192.168.0.1', 'مستخدم + كلمة مرور'),
    ],
  ),
  _ModemBrandGroup(
    brandAr: 'كول 4 جي (Cool 4G)',
    models: [
      ('Cool 4G (F239)', '192.168.43.1 / 192.168.0.1', 'مستخدم + كلمة مرور'),
    ],
  ),
  _ModemBrandGroup(
    brandAr: 'جيتباك (Jetpack)',
    models: [
      ('Jetpack MiFi (8800L / 7730L / 6620L)', '192.168.1.1', 'كلمة مرور فقط'),
    ],
  ),
  _ModemBrandGroup(
    brandAr: 'وي جو (WeGo) وفالكون (Falcon)',
    models: [
      ('WeGo 4G MiFi', '192.168.0.1 / 192.168.43.1', 'تلقائي'),
      ('Falcon 4G MiFi', '192.168.0.1 / 192.168.43.1', 'تلقائي'),
    ],
  ),
];

void showSupportedModemsDialog(BuildContext context, AppController controller) {
  final p = controller.palette;
  showDialog(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: p.bgCard,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 28),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(26),
        side: BorderSide(color: p.borderSubtle),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'المودمات المدعومة',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: p.textPrimary,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(ctx),
                  icon: Icon(Icons.close_rounded, color: p.textSecondary),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: p.borderSubtle),
          Flexible(
            child: ListView.separated(
              padding: const EdgeInsets.all(14),
              shrinkWrap: true,
              itemCount: _supportedYemenModems.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) {
                final group = _supportedYemenModems[i];
                return Container(
                  decoration: BoxDecoration(
                    color: p.bgElevated.withOpacity(0.55),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: p.borderSubtle),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 11, 14, 9),
                        child: Text(
                          group.brandAr,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: p.accentSecondary,
                          ),
                        ),
                      ),
                      Divider(height: 1, color: p.borderSubtle),
                      ...group.models.map(
                        (m) => ExpansionTile(
                          tilePadding:
                              const EdgeInsets.symmetric(horizontal: 14),
                          childrenPadding:
                              const EdgeInsets.fromLTRB(14, 0, 14, 10),
                          leading: Icon(Icons.router_rounded,
                              color: p.accentPrimary, size: 22),
                          title: Text(
                            m.$1,
                            textDirection: TextDirection.ltr,
                            textAlign: TextAlign.left,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: p.textPrimary,
                            ),
                          ),
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('عنوان البوابة الافتراضي:',
                                    style: TextStyle(
                                        fontSize: 12, color: p.textSecondary)),
                                Text(
                                  m.$2,
                                  textDirection: TextDirection.ltr,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: p.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('نوع الدخول:',
                                    style: TextStyle(
                                        fontSize: 12, color: p.textSecondary)),
                                Text(
                                  m.$3,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: p.accentPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
