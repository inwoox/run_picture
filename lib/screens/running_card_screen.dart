import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:screenshot/screenshot.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import '../models/running_record.dart';
import '../models/overlay_style.dart';
import '../services/ocr_service.dart';
import '../utils/save_util.dart';
import '../widgets/ocr_confirm_sheet.dart';

const _localFonts = {'SUIT'};

TextStyle _ts(String font, {double? fontSize, FontWeight? fontWeight,
    Color? color, double? height, double? letterSpacing}) {
  final base = TextStyle(fontSize: fontSize, fontWeight: fontWeight,
      color: color, height: height, letterSpacing: letterSpacing);
  if (_localFonts.contains(font)) return base.copyWith(fontFamily: font);
  try { return GoogleFonts.getFont(font, textStyle: base); }
  catch (_) { return base.copyWith(fontFamily: font); }
}

enum _TemplateType { minimal, center, grid, side, badge, split, dark }

const _accentColors = [
  Color(0xFF1C1C1E),
  Color(0xFFE53935),
  Color(0xFF1565C0),
  Color(0xFF2E7D32),
  Color(0xFFE65100),
  Color(0xFF6A1B9A),
];

const _fonts = [
  'SUIT', 'Roboto', 'Oswald', 'Montserrat',
  // 손글씨 / 붓글씨 (OFL 상업 허용)
  'Nanum Pen Script',    // 한국어 손글씨
  'Nanum Brush Script',  // 한국어 붓글씨
  'Black Han Sans',      // 굵은 한국어 포스터체
  'Gaegu',               // 한국어 귀여운 손글씨
  'Caveat',              // 영문 손글씨
  'Pacifico',            // 영문 둥근 붓글씨
];

class RunningCardScreen extends StatefulWidget {
  final LabelLanguage language;
  const RunningCardScreen({super.key, this.language = LabelLanguage.korean});

  @override
  State<RunningCardScreen> createState() => _RunningCardScreenState();
}

class _RunningCardScreenState extends State<RunningCardScreen> {
  final ScreenshotController _screenshotController = ScreenshotController();
  late LabelLanguage _language;
  XFile? _captureImage;
  RunningRecord? _record;
  bool _isProcessing = false;
  _TemplateType _selectedTemplate = _TemplateType.minimal;
  Color _accentColor = _accentColors[0];
  String _fontFamily = 'SUIT';

  @override
  void initState() {
    super.initState();
    _language = widget.language;
  }

  String _t(String ko, String en) => _language == LabelLanguage.korean ? ko : en;

  Future<void> _pickCapture() async {
    final image = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (image == null) return;
    setState(() { _captureImage = image; _isProcessing = true; _record = null; });
    try {
      final record = await OcrService.extractFromImage(image.path);
      if (!mounted) return;
      // OCR 결과 확인·수정 시트
      final confirmed = await showOcrConfirmSheet(context, record, _language);
      if (!mounted) return;
      if (confirmed == null) {
        // 취소 시 이미지 선택 초기화
        setState(() { _captureImage = null; });
        return;
      }
      setState(() => _record = confirmed);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('OCR 실패: $e'),
            backgroundColor: const Color(0xFF1C1C1E)),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _saveCard() async {
    showSavingDialog(context);
    try {
      final bytes = await _screenshotController.capture(pixelRatio: 3.0);
      if (bytes == null) { hideSavingDialog(context); return; }
      final tmp = await getTemporaryDirectory();
      final file = File('${tmp.path}/rp_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes);
      await Gal.putImage(file.path, album: 'RunPicture');
      await file.delete();
      if (mounted) hideSavingDialog(context);
      if (mounted) _showAlert(_t('저장 완료', 'Saved'), _t('사진첩에 저장되었습니다!', 'Saved to photo library!'));
    } catch (e) {
      if (mounted) hideSavingDialog(context);
      if (mounted) _showAlert(_t('저장 실패', 'Save failed'), '$e', isError: true);
    }
  }

  void _showAlert(String title, String msg, {bool isError = false}) {
    showDialog(context: context, builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(title, style: TextStyle(
          color: isError ? Colors.red : Colors.white, fontWeight: FontWeight.bold)),
      content: Text(msg),
      actions: [TextButton(onPressed: () => Navigator.pop(context),
          child: Text(_t('확인', 'OK'),
              style: const TextStyle(color: Colors.white)))],
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Color(0xFF1C1C1E), size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('RUN PICTURE',
              style: TextStyle(fontFamily: 'SUIT', color: Color(0xFF1C1C1E),
                  fontWeight: FontWeight.w700, fontSize: 18, letterSpacing: 1.0)),
          Text(_t('러닝 카드 생성', 'Running Card'),
              style: const TextStyle(fontFamily: 'SUIT', color: Color(0xFF8E8E93),
                  fontWeight: FontWeight.w500, fontSize: 11, letterSpacing: 0)),
        ]),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              _langToggle('한', LabelLanguage.korean),
              const SizedBox(width: 6),
              _langToggle('EN', LabelLanguage.english),
            ]),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _buildPickerCard(),
          const SizedBox(height: 16),

          if (_captureImage == null) _buildGuide(),

          if (_isProcessing)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CircularProgressIndicator(color: Color(0xFF1C1C1E))),
            ),

          if (_record != null) ...[
            _buildTemplateSelector(),
            const SizedBox(height: 16),

            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Screenshot(
                controller: _screenshotController,
                child: MediaQuery(
                  data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(1.0)),
                  child: _buildCard(),
                ),
              ),
            ),
            const SizedBox(height: 16),

            _buildCustomization(),
            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saveCard,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1C1C1E),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: Text(_t('카드 저장', 'Save Card'),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ]),
      ),
    );
  }

  Widget _buildPickerCard() {
    return GestureDetector(
      onTap: _pickCapture,
      child: Container(
        height: 110,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: _captureImage == null
            ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(width: 48, height: 48,
                    decoration: BoxDecoration(color: const Color(0xFFF0F0F0),
                        borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.document_scanner_rounded,
                        color: Color(0xFF1C1C1E), size: 26)),
                const SizedBox(height: 10),
                Text(_t('러닝 기록 사진', 'Running Record Photo'),
                    style: const TextStyle(color: Color(0xFF1C1C1E),
                        fontWeight: FontWeight.w600, fontSize: 14)),
              ])
            : Stack(children: [
                ClipRRect(borderRadius: BorderRadius.circular(16),
                    child: Image.file(File(_captureImage!.path),
                        fit: BoxFit.cover, width: double.infinity, height: 110)),
                Positioned(bottom: 8, right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.black54,
                        borderRadius: BorderRadius.circular(12)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.edit, color: Colors.white, size: 12),
                      const SizedBox(width: 4),
                      Text(_t('변경', 'Change'),
                          style: const TextStyle(color: Colors.white, fontSize: 11)),
                    ]),
                  ),
                ),
              ]),
      ),
    );
  }

  Widget _buildTemplateSelector() {
    final templates = [
      (_TemplateType.minimal, _t('미니멀', 'Minimal'), Icons.crop_square_rounded),
      (_TemplateType.center,  _t('센터', 'Center'),    Icons.center_focus_strong_rounded),
      (_TemplateType.grid,    _t('그리드', 'Grid'),    Icons.grid_view_rounded),
      (_TemplateType.side,    _t('사이드', 'Side'),    Icons.view_sidebar_rounded),
      (_TemplateType.badge,   _t('배지', 'Badge'),     Icons.military_tech_rounded),
      (_TemplateType.split,   _t('스플릿', 'Split'),   Icons.splitscreen_rounded),
      (_TemplateType.dark,    _t('다크', 'Dark'),      Icons.dark_mode_rounded),
    ];
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: templates.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final (type, label, icon) = templates[i];
          final selected = _selectedTemplate == type;
          return GestureDetector(
            onTap: () => setState(() => _selectedTemplate = type),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: selected ? const Color(0xFF1C1C1E) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 6)],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 15, color: selected ? Colors.white : const Color(0xFF8E8E93)),
                const SizedBox(width: 6),
                Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : const Color(0xFF8E8E93))),
              ]),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCard() {
    final r = _record!;
    switch (_selectedTemplate) {
      case _TemplateType.minimal:
        return _MinimalCard(record: r, accent: _accentColor, font: _fontFamily, language: _language);
      case _TemplateType.center:
        return _CenterCard(record: r, accent: _accentColor, font: _fontFamily, language: _language);
      case _TemplateType.grid:
        return _GridCard(record: r, accent: _accentColor, font: _fontFamily, language: _language);
      case _TemplateType.side:
        return _SideCard(record: r, accent: _accentColor, font: _fontFamily, language: _language);
      case _TemplateType.badge:
        return _BadgeCard(record: r, accent: _accentColor, font: _fontFamily, language: _language);
      case _TemplateType.split:
        return _SplitCard(record: r, accent: _accentColor, font: _fontFamily, language: _language);
      case _TemplateType.dark:
        return _DarkCard(record: r, accent: _accentColor, font: _fontFamily, language: _language);
    }
  }

  Widget _buildCustomization() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_t('색상', 'Color'),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                color: Color(0xFF1C1C1E))),
        const SizedBox(height: 12),
        Row(children: _accentColors.map((c) {
          final selected = _accentColor == c;
          return GestureDetector(
            onTap: () => setState(() => _accentColor = c),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.only(right: 10),
              width: selected ? 34 : 28,
              height: selected ? 34 : 28,
              decoration: BoxDecoration(
                color: c, shape: BoxShape.circle,
                border: selected ? Border.all(color: Colors.white, width: 2.5) : null,
                boxShadow: [BoxShadow(
                    color: c.withValues(alpha: selected ? 0.5 : 0.2),
                    blurRadius: selected ? 8 : 3)],
              ),
            ),
          );
        }).toList()),
        const SizedBox(height: 16),
        const Divider(height: 1, color: Color(0xFFEEEEEE)),
        const SizedBox(height: 16),
        Text(_t('폰트', 'Font'),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                color: Color(0xFF1C1C1E))),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: _fonts.map((f) {
          final selected = _fontFamily == f;
          return GestureDetector(
            onTap: () => setState(() => _fontFamily = f),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: selected ? const Color(0xFF1C1C1E) : const Color(0xFFF5F7FA),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: selected
                    ? const Color(0xFF1C1C1E) : const Color(0xFFE5E5EA)),
              ),
              child: Text(f, style: _ts(f, fontSize: 12, fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : const Color(0xFF8E8E93))),
            ),
          );
        }).toList()),
      ]),
    );
  }

  Widget _buildGuide() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04),
            blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_t('이렇게 사용하세요', 'How to use'),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                color: Color(0xFF1C1C1E))),
        const SizedBox(height: 12),
        _guideStep('1', _t('러닝 기록 사진 선택', 'Select running record photo'),
            _t(
              '러닝 앱의 기록 화면 스크린샷을 선택하세요\n값이 있는 부분만 캡처하여 첨부해야 인식률이 높습니다\n(인식이 안되는 경우, 수동으로 페이스 등 입력 가능)',
              'Choose a screenshot from your running app\nCrop to the stats area only for better recognition\nYou can enter values manually if recognition fails',
            )),
        Padding(
          padding: const EdgeInsets.only(left: 34, bottom: 14),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset('assets/sample_running.png', width: double.infinity, fit: BoxFit.fitWidth),
          ),
        ),
        _guideStep('2', _t('템플릿 선택', 'Choose a template'),
            _t('미니멀, 센터, 헤드라인 등 원하는 스타일을 선택하세요', 'Pick a style: Minimal, Center, Headline, etc.')),
        _guideStep('3', _t('색상 · 폰트 변경', 'Customize color & font'),
            _t('액센트 색상과 폰트를 바꿔 나만의 카드를 만드세요', 'Adjust accent color and font to match your style')),
        _guideStep('4', _t('카드 저장', 'Save card'),
            _t('완성되면 카드 저장을 눌러 갤러리에 저장하세요', 'Tap Save Card to save to your gallery'),
            isLast: true),
      ]),
    );
  }

  Widget _guideStep(String num, String title, String desc, {bool isLast = false}) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Column(children: [
        Container(
          width: 22, height: 22,
          decoration: const BoxDecoration(color: Color(0xFF1C1C1E), shape: BoxShape.circle),
          child: Center(child: Text(num, style: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white))),
        ),
        if (!isLast)
          Container(width: 1, height: 28, color: const Color(0xFFE5E5EA),
              margin: const EdgeInsets.symmetric(vertical: 2)),
      ]),
      const SizedBox(width: 12),
      Expanded(
        child: Padding(
          padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 13,
                fontWeight: FontWeight.w600, color: Color(0xFF1C1C1E))),
            const SizedBox(height: 2),
            Text(desc, style: const TextStyle(fontSize: 11, color: Color(0xFF8E8E93), height: 1.4)),
          ]),
        ),
      ),
    ]);
  }

  Widget _langToggle(String label, LabelLanguage lang) {
    final selected = _language == lang;
    return GestureDetector(
      onTap: () => setState(() => _language = lang),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF1C1C1E) : const Color(0xFFF5F7FA),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: selected
              ? const Color(0xFF1C1C1E) : const Color(0xFFE5E5EA)),
        ),
        child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
            color: selected ? Colors.white : const Color(0xFF8E8E93))),
      ),
    );
  }
}

// ── 공통 ──────────────────────────────────────────────────────────────────────
const _cardRatio = 4.0 / 5.0;
const _dark = Color(0xFF1C1C1E);
const _grey = Color(0xFF8E8E93);

// ── 1. 미니멀 ────────────────────────────────────────────────────────────────
// 흰 배경 / 좌정렬 / 거리 크게 상단 / 액센트 가로선 / 통계 하단
class _MinimalCard extends StatelessWidget {
  final RunningRecord record;
  final Color accent;
  final String font;
  final LabelLanguage language;
  const _MinimalCard({required this.record, required this.accent,
      required this.font, required this.language});
  String _t(String ko, String en) => language == LabelLanguage.korean ? ko : en;

  @override
  Widget build(BuildContext context) {
    final dist = record.distance.replaceAll(RegExp(r'\s*km'), '').trim();
    return AspectRatio(
      aspectRatio: _cardRatio,
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(36, 32, 36, 32),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(record.date,
                style: _ts(font, fontSize: 12, color: _grey))),
            Text('RUN PICTURE', style: _ts(font, fontSize: 9,
                fontWeight: FontWeight.w800, color: accent, letterSpacing: 2)),
          ]),
          const Spacer(flex: 2),
          if (dist.isNotEmpty) ...[
            Text(_t('거리', 'DISTANCE'), style: _ts(font, fontSize: 10,
                color: _grey, letterSpacing: 2.5, fontWeight: FontWeight.w500)),
            const SizedBox(height: 2),
            FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
              child: Text(dist, style: _ts(font, fontSize: 86,
                  fontWeight: FontWeight.w900, color: _dark, height: 1.0)),
            ),
            Text('km', style: _ts(font, fontSize: 20,
                fontWeight: FontWeight.w700, color: accent)),
          ],
          const SizedBox(height: 28),
          Container(height: 2, color: accent),
          const SizedBox(height: 24),
          Row(children: _statRow(font, record, _t)),
          const Spacer(flex: 3),
        ]),
      ),
    );
  }
}

// ── 2. 센터 ──────────────────────────────────────────────────────────────────
// 흰 배경 / 모든 요소 중앙 정렬 / 거리 중심 / 통계 카드 하단
class _CenterCard extends StatelessWidget {
  final RunningRecord record;
  final Color accent;
  final String font;
  final LabelLanguage language;
  const _CenterCard({required this.record, required this.accent,
      required this.font, required this.language});
  String _t(String ko, String en) => language == LabelLanguage.korean ? ko : en;

  @override
  Widget build(BuildContext context) {
    final dist = record.distance.replaceAll(RegExp(r'\s*km'), '').trim();
    return AspectRatio(
      aspectRatio: _cardRatio,
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(28, 32, 28, 32),
        child: Column(children: [
          // 상단 브랜드
          Text('RUN PICTURE', style: _ts(font, fontSize: 10,
              fontWeight: FontWeight.w800, color: accent, letterSpacing: 3)),
          if (record.date.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(record.date, style: _ts(font, fontSize: 12, color: _grey)),
          ],
          const Spacer(flex: 3),

          // 거리 — 중앙 크게
          if (dist.isNotEmpty) ...[
            Text(_t('오늘 달린 거리', 'TODAY\'S DISTANCE'), style: _ts(font,
                fontSize: 10, color: _grey, letterSpacing: 2)),
            const SizedBox(height: 8),
            FittedBox(fit: BoxFit.scaleDown,
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(dist, style: _ts(font, fontSize: 96,
                    fontWeight: FontWeight.w900, color: _dark, height: 1.0)),
                const SizedBox(width: 6),
                Padding(padding: const EdgeInsets.only(bottom: 12),
                  child: Text('km', style: _ts(font, fontSize: 22,
                      fontWeight: FontWeight.w700, color: accent))),
              ]),
            ),
          ],

          const Spacer(flex: 2),

          // 통계 — 둥근 박스
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F7FA),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: _centeredStats(font, record, accent, _t)),
          ),
          const Spacer(flex: 1),
        ]),
      ),
    );
  }
}

// ── 4. 그리드 ────────────────────────────────────────────────────────────────
// 흰 배경 / 상단 거리 + 날짜 / 하단 통계를 격자 박스로 표시
class _GridCard extends StatelessWidget {
  final RunningRecord record;
  final Color accent;
  final String font;
  final LabelLanguage language;
  const _GridCard({required this.record, required this.accent,
      required this.font, required this.language});
  String _t(String ko, String en) => language == LabelLanguage.korean ? ko : en;

  @override
  Widget build(BuildContext context) {
    final dist = record.distance.replaceAll(RegExp(r'\s*km'), '').trim();
    final stats = <(String, String)>[
      if (record.time.isNotEmpty)      (_t('총 시간', 'TIME'),     record.time),
      if (record.pace.isNotEmpty)      (_t('평균 페이스', 'PACE'),  record.pace),
      if (record.heartRate.isNotEmpty) (_t('평균 심박수', 'HR'),    record.heartRate),
    ];

    return AspectRatio(
      aspectRatio: _cardRatio,
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // 브랜드
          Row(children: [
            Text('RUN PICTURE', style: _ts(font, fontSize: 9,
                fontWeight: FontWeight.w800, color: accent, letterSpacing: 2)),
            const Spacer(),
            if (record.date.isNotEmpty)
              Text(record.date, style: _ts(font, fontSize: 11, color: _grey)),
          ]),
          const Spacer(flex: 1),

          // 거리
          if (dist.isNotEmpty) ...[
            FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(dist, style: _ts(font, fontSize: 80,
                    fontWeight: FontWeight.w900, color: _dark, height: 1.0)),
                const SizedBox(width: 8),
                Padding(padding: const EdgeInsets.only(bottom: 8),
                  child: Text('km', style: _ts(font, fontSize: 18,
                      fontWeight: FontWeight.w700, color: accent))),
              ]),
            ),
          ],

          const SizedBox(height: 20),

          // 통계 격자
          ...stats.map((s) => Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F7FA),
              borderRadius: BorderRadius.circular(12),
              border: Border(left: BorderSide(color: accent, width: 3)),
            ),
            child: Row(children: [
              Text(s.$1, style: _ts(font, fontSize: 12, color: _grey,
                  fontWeight: FontWeight.w600)),
              const Spacer(),
              Text(s.$2, style: _ts(font, fontSize: 22,
                  fontWeight: FontWeight.w800, color: _dark)),
            ]),
          )),

          const Spacer(flex: 1),
        ]),
      ),
    );
  }
}

// ── 5. 사이드 ────────────────────────────────────────────────────────────────
// 왼쪽 액센트 컬럼(통계 세로 배치) + 오른쪽 거리 크게
class _SideCard extends StatelessWidget {
  final RunningRecord record;
  final Color accent;
  final String font;
  final LabelLanguage language;
  const _SideCard({required this.record, required this.accent,
      required this.font, required this.language});
  String _t(String ko, String en) => language == LabelLanguage.korean ? ko : en;

  @override
  Widget build(BuildContext context) {
    final dist = record.distance.replaceAll(RegExp(r'\s*km'), '').trim();
    final stats = <(String, String)>[
      if (record.time.isNotEmpty)      (_t('총 시간', 'TIME'),     record.time),
      if (record.pace.isNotEmpty)      (_t('평균 페이스', 'PACE'),  record.pace),
      if (record.heartRate.isNotEmpty) (_t('평균 심박수', 'HR'),    record.heartRate),
    ];

    return AspectRatio(
      aspectRatio: _cardRatio,
      child: Container(
        color: Colors.white,
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // 왼쪽 패널 — 액센트 배경
          Container(
            width: 110,
            color: accent,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('RUN\nPICTURE', style: _ts(font, fontSize: 10,
                  fontWeight: FontWeight.w900, color: Colors.white.withValues(alpha: 0.7),
                  letterSpacing: 1.5, height: 1.4)),
              const Spacer(),
              ...stats.expand((s) => [
                Text(s.$1, style: _ts(font, fontSize: 10,
                    color: Colors.white.withValues(alpha: 0.65),
                    letterSpacing: 1.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text(s.$2, style: _ts(font, fontSize: 18,
                    fontWeight: FontWeight.w800, color: Colors.white)),
                const SizedBox(height: 18),
              ]),
              if (record.date.isNotEmpty)
                Text(record.date, style: _ts(font, fontSize: 10,
                    color: Colors.white.withValues(alpha: 0.55))),
            ]),
          ),

          // 오른쪽 패널 — 거리 크게
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Spacer(flex: 2),
                if (dist.isNotEmpty) ...[
                  Text(_t('거리', 'DIST'), style: _ts(font, fontSize: 10,
                      color: _grey, letterSpacing: 2.5, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
                    child: Text(dist, style: _ts(font, fontSize: 72,
                        fontWeight: FontWeight.w900, color: _dark, height: 1.0)),
                  ),
                  Text('km', style: _ts(font, fontSize: 18,
                      fontWeight: FontWeight.w700, color: accent)),
                ],
                const Spacer(flex: 3),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

// ── 공통 헬퍼 ────────────────────────────────────────────────────────────────
List<Widget> _statRow(String font, RunningRecord r, String Function(String, String) t) {
  final items = <Widget>[];
  void add(String label, String value) {
    if (items.isNotEmpty) {
      items.add(Container(width: 1, height: 32, color: const Color(0xFFEEEEEE),
          margin: const EdgeInsets.only(right: 14)));
    }
    items.add(Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: _ts(font, fontSize: 10, color: _grey,
              letterSpacing: 1.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(value, style: _ts(font, fontSize: 15,
              fontWeight: FontWeight.w800, color: _dark)),
        ])));
  }
  if (r.time.isNotEmpty)      add(t('총 시간', 'TIME'), r.time);
  if (r.pace.isNotEmpty)      add(t('평균 페이스', 'PACE'), r.pace);
  if (r.heartRate.isNotEmpty) add(t('평균 심박수', 'HR'), r.heartRate);
  return items;
}


List<Widget> _centeredStats(String font, RunningRecord r, Color accent,
    String Function(String, String) t) {
  final items = <Widget>[];
  void add(String label, String value) {
    items.add(Column(children: [
      Text(value, style: _ts(font, fontSize: 20, fontWeight: FontWeight.w800, color: _dark)),
      const SizedBox(height: 4),
      Text(label, style: _ts(font, fontSize: 10, color: _grey,
          letterSpacing: 1.5, fontWeight: FontWeight.w500)),
    ]));
  }
  if (r.time.isNotEmpty)      add(t('총 시간', 'TIME'), r.time);
  if (r.pace.isNotEmpty)      add(t('평균 페이스', 'PACE'), r.pace);
  if (r.heartRate.isNotEmpty) add(t('평균 심박수', 'HR'), r.heartRate);
  return items;
}

// ── 6. 배지 ──────────────────────────────────────────────────────────────────
// 중앙 원형 거리 배지 + 하단 균일 크기 통계 박스
class _BadgeCard extends StatelessWidget {
  final RunningRecord record;
  final Color accent;
  final String font;
  final LabelLanguage language;
  const _BadgeCard({required this.record, required this.accent,
      required this.font, required this.language});
  String _t(String ko, String en) => language == LabelLanguage.korean ? ko : en;

  @override
  Widget build(BuildContext context) {
    final dist = record.distance.replaceAll(RegExp(r'\s*km'), '').trim();
    final stats = <(String, String)>[
      if (record.time.isNotEmpty)      (_t('총 시간', 'TIME'),     record.time),
      if (record.pace.isNotEmpty)      (_t('평균 페이스', 'PACE'),  record.pace),
      if (record.heartRate.isNotEmpty) (_t('평균 심박수', 'HR'),    record.heartRate),
    ];

    return AspectRatio(
      aspectRatio: _cardRatio,
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
        child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('RUN PICTURE', style: _ts(font, fontSize: 9,
                fontWeight: FontWeight.w800, color: accent, letterSpacing: 2)),
            if (record.date.isNotEmpty)
              Text(record.date, style: _ts(font, fontSize: 11, color: _grey)),
          ]),
          const Spacer(flex: 2),

          // 원형 배지
          Container(
            width: 160, height: 160,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: accent, width: 3),
              color: const Color(0xFFF8F8F8),
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(_t('거리', 'DIST'), style: _ts(font, fontSize: 10,
                  color: _grey, letterSpacing: 2, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              if (dist.isNotEmpty)
                FittedBox(
                  child: Text(dist, style: _ts(font, fontSize: 52,
                      fontWeight: FontWeight.w900, color: _dark, height: 1.0)),
                ),
              Text('km', style: _ts(font, fontSize: 14,
                  fontWeight: FontWeight.w700, color: accent)),
            ]),
          ),
          const Spacer(flex: 2),

          // 하단 균일 크기 통계
          if (stats.isNotEmpty)
            Row(children: [
              for (int i = 0; i < stats.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F7FA),
                      borderRadius: BorderRadius.circular(12),
                      border: Border(top: BorderSide(color: accent, width: 2.5)),
                    ),
                    child: Column(children: [
                      Text(stats[i].$2, style: _ts(font, fontSize: 17,
                          fontWeight: FontWeight.w800, color: _dark)),
                      const SizedBox(height: 4),
                      Text(stats[i].$1, style: _ts(font, fontSize: 10,
                          color: _grey, letterSpacing: 1.5, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ),
              ],
            ]),
          const Spacer(flex: 1),
        ]),
      ),
    );
  }
}

// ── 7. 스플릿 ────────────────────────────────────────────────────────────────
// 상단 액센트 배경 거리 / 하단 흰 배경 시간·페이스·심박 균등 배치
class _SplitCard extends StatelessWidget {
  final RunningRecord record;
  final Color accent;
  final String font;
  final LabelLanguage language;
  const _SplitCard({required this.record, required this.accent,
      required this.font, required this.language});
  String _t(String ko, String en) => language == LabelLanguage.korean ? ko : en;

  @override
  Widget build(BuildContext context) {
    final dist = record.distance.replaceAll(RegExp(r'\s*km'), '').trim();
    final stats = <(String, String)>[
      if (record.time.isNotEmpty)      (_t('총 시간', 'TIME'),     record.time),
      if (record.pace.isNotEmpty)      (_t('평균 페이스', 'PACE'),  record.pace),
      if (record.heartRate.isNotEmpty) (_t('평균 심박수', 'HR'),    record.heartRate),
    ];

    return AspectRatio(
      aspectRatio: _cardRatio,
      child: Column(children: [
        // 상단: 거리 (액센트 배경)
        Expanded(
          flex: 5,
          child: Container(
            width: double.infinity,
            color: accent,
            padding: const EdgeInsets.fromLTRB(28, 28, 28, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('RUN PICTURE', style: _ts(font, fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: Colors.white.withValues(alpha: 0.6), letterSpacing: 2)),
              const Spacer(),
              Text(_t('거리', 'DISTANCE'), style: _ts(font, fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.7),
                  letterSpacing: 2.5, fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              if (dist.isNotEmpty)
                FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
                  child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(dist, style: _ts(font, fontSize: 80,
                        fontWeight: FontWeight.w900, color: Colors.white, height: 1.0)),
                    const SizedBox(width: 8),
                    Padding(padding: const EdgeInsets.only(bottom: 10),
                      child: Text('km', style: _ts(font, fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Colors.white.withValues(alpha: 0.8)))),
                  ]),
                ),
              const SizedBox(height: 8),
            ]),
          ),
        ),

        // 하단: 통계 균등 배치 (흰 배경)
        Expanded(
          flex: 4,
          child: Container(
            width: double.infinity,
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Column(children: [
              if (stats.isNotEmpty)
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (int i = 0; i < stats.length; i++) ...[
                        if (i > 0)
                          Container(width: 1, color: const Color(0xFFEEEEEE),
                              margin: const EdgeInsets.symmetric(horizontal: 12)),
                        Expanded(
                          child: Column(mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                            Text(stats[i].$2, style: _ts(font, fontSize: 20,
                                fontWeight: FontWeight.w800, color: _dark)),
                            const SizedBox(height: 6),
                            Text(stats[i].$1, style: _ts(font, fontSize: 10,
                                color: _grey, letterSpacing: 1.5,
                                fontWeight: FontWeight.w600)),
                          ]),
                        ),
                      ],
                    ],
                  ),
                ),
              if (record.date.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(record.date, style: _ts(font, fontSize: 11, color: _grey)),
              ],
            ]),
          ),
        ),
      ]),
    );
  }
}

// ── 8. 다크 ──────────────────────────────────────────────────────────────────
// 어두운 배경 / 거리·시간·페이스·심박 2×2 균등 그리드
class _DarkCard extends StatelessWidget {
  final RunningRecord record;
  final Color accent;
  final String font;
  final LabelLanguage language;
  const _DarkCard({required this.record, required this.accent,
      required this.font, required this.language});
  String _t(String ko, String en) => language == LabelLanguage.korean ? ko : en;

  @override
  Widget build(BuildContext context) {
    final dist = record.distance.replaceAll(RegExp(r'\s*km'), '').trim();
    const bg = Color(0xFF1C1C1E);
    const cardBg = Color(0xFF2C2C2E);
    const textDim = Color(0xFF8E8E93);

    final allStats = <(String, String)>[
      if (dist.isNotEmpty)             (_t('거리', 'DIST'),   '$dist km'),
      if (record.time.isNotEmpty)      (_t('시간', 'TIME'),   record.time),
      if (record.pace.isNotEmpty)      (_t('평균 페이스', 'PACE'),  record.pace),
      if (record.heartRate.isNotEmpty) (_t('평균 심박수', 'HR'),    record.heartRate),
    ];

    return AspectRatio(
      aspectRatio: _cardRatio,
      child: Container(
        color: bg,
        padding: const EdgeInsets.fromLTRB(22, 28, 22, 28),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('RUN PICTURE', style: _ts(font, fontSize: 9,
                fontWeight: FontWeight.w800, color: accent, letterSpacing: 2)),
            const Spacer(),
            if (record.date.isNotEmpty)
              Text(record.date, style: _ts(font, fontSize: 11, color: textDim)),
          ]),
          const SizedBox(height: 16),
          Container(height: 2, width: 40, color: accent),
          const SizedBox(height: 20),

          // 2열 그리드
          Expanded(
            child: GridView.count(
              crossAxisCount: 2,
              childAspectRatio: 1.9,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              physics: const NeverScrollableScrollPhysics(),
              shrinkWrap: true,
              children: allStats.map((s) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(s.$1, style: _ts(font, fontSize: 10, color: textDim,
                      letterSpacing: 1.5, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(s.$2, style: _ts(font, fontSize: 18,
                      fontWeight: FontWeight.w800, color: Colors.white)),
                ]),
              )).toList(),
            ),
          ),
        ]),
      ),
    );
  }
}
