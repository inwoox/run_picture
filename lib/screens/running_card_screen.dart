import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:screenshot/screenshot.dart';
import 'package:path_provider/path_provider.dart';
import '../models/running_record.dart';
import '../models/overlay_style.dart';
import '../services/ocr_service.dart';

const _localFonts = {'SUIT'};

TextStyle _ts(String font, {double? fontSize, FontWeight? fontWeight,
    Color? color, double? height, double? letterSpacing}) {
  final base = TextStyle(fontSize: fontSize, fontWeight: fontWeight,
      color: color, height: height, letterSpacing: letterSpacing);
  if (_localFonts.contains(font)) return base.copyWith(fontFamily: font);
  try { return GoogleFonts.getFont(font, textStyle: base); }
  catch (_) { return base.copyWith(fontFamily: font); }
}

enum _TemplateType { minimal, center, headline, grid, side }

const _accentColors = [
  Color(0xFF1C1C1E),
  Color(0xFFE53935),
  Color(0xFF1565C0),
  Color(0xFF2E7D32),
  Color(0xFFE65100),
  Color(0xFF6A1B9A),
];

const _fonts = ['SUIT', 'Roboto', 'Oswald', 'Montserrat'];

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
      if (mounted) setState(() => _record = record);
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
    try {
      final Uint8List? bytes = await _screenshotController.capture(pixelRatio: 3.0);
      if (bytes == null) return;
      final Directory dir;
      if (Platform.isAndroid) {
        dir = Directory('/storage/emulated/0/Pictures/RunningPhoto');
      } else {
        final docs = await getApplicationDocumentsDirectory();
        dir = Directory('${docs.path}/RunningPhoto');
      }
      if (!await dir.exists()) await dir.create(recursive: true);
      final file = File('${dir.path}/card_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes);
      if (Platform.isAndroid) {
        try { await Process.run('am', ['broadcast', '-a',
          'android.intent.action.MEDIA_SCANNER_SCAN_FILE',
          '-d', 'file://${file.path}']); } catch (_) {}
      }
      if (mounted) _showAlert(_t('저장 완료', 'Saved'),
          _t('갤러리 앱에서 확인하세요\n(RunningPhoto 폴더)', 'Check Gallery\n(RunningPhoto folder)'));
    } catch (e) {
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
        title: const Text('RUN PICTURE',
            style: TextStyle(fontFamily: 'SUIT', color: Color(0xFF1C1C1E),
                fontWeight: FontWeight.w700, fontSize: 20, letterSpacing: 1.0)),
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
                child: _buildCard(),
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
                Text(_t('러닝 기록 캡처 선택', 'Select Running Capture'),
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
      (_TemplateType.minimal,  _t('미니멀', 'Minimal'),  Icons.crop_square_rounded),
      (_TemplateType.center,   _t('센터', 'Center'),     Icons.center_focus_strong_rounded),
      (_TemplateType.headline, _t('헤드라인', 'Headline'), Icons.text_fields_rounded),
      (_TemplateType.grid,     _t('그리드', 'Grid'),     Icons.grid_view_rounded),
      (_TemplateType.side,     _t('사이드', 'Side'),     Icons.view_sidebar_rounded),
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
      case _TemplateType.headline:
        return _HeadlineCard(record: r, accent: _accentColor, font: _fontFamily, language: _language);
      case _TemplateType.grid:
        return _GridCard(record: r, accent: _accentColor, font: _fontFamily, language: _language);
      case _TemplateType.side:
        return _SideCard(record: r, accent: _accentColor, font: _fontFamily, language: _language);
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
                style: _ts(font, fontSize: 11, color: _grey))),
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
            Text(record.date, style: _ts(font, fontSize: 11, color: _grey)),
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

// ── 3. 헤드라인 ───────────────────────────────────────────────────────────────
// 흰 배경 / 거리 숫자 최대로 크게 화면 가득 / 통계는 최하단 한 줄
class _HeadlineCard extends StatelessWidget {
  final RunningRecord record;
  final Color accent;
  final String font;
  final LabelLanguage language;
  const _HeadlineCard({required this.record, required this.accent,
      required this.font, required this.language});
  String _t(String ko, String en) => language == LabelLanguage.korean ? ko : en;

  @override
  Widget build(BuildContext context) {
    final dist = record.distance.replaceAll(RegExp(r'\s*km'), '').trim();
    return AspectRatio(
      aspectRatio: _cardRatio,
      child: Container(
        color: Colors.white,
        child: Stack(children: [
          // 액센트 상단 바
          Positioned(top: 0, left: 0, right: 0,
              child: Container(height: 5, color: accent)),

          Padding(
            padding: const EdgeInsets.fromLTRB(28, 20, 28, 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // 상단 라벨
              Row(children: [
                Text(_t('거리', 'DISTANCE'), style: _ts(font, fontSize: 11,
                    color: accent, letterSpacing: 3, fontWeight: FontWeight.w700)),
                const Spacer(),
                Text('RUN PICTURE', style: _ts(font, fontSize: 9,
                    color: _grey, letterSpacing: 1.5)),
              ]),

              const Spacer(flex: 1),

              // 거리 — 화면 가득
              if (dist.isNotEmpty)
                FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
                  child: Text(dist, style: _ts(font, fontSize: 130,
                      fontWeight: FontWeight.w900, color: _dark, height: 0.9)),
                ),

              // km 단위
              Row(children: [
                Container(width: 3, height: 18, color: accent,
                    margin: const EdgeInsets.only(right: 8)),
                Text('km', style: _ts(font, fontSize: 18,
                    fontWeight: FontWeight.w700, color: _dark)),
              ]),

              const Spacer(flex: 2),

              // 하단 통계 한 줄
              Container(height: 1, color: const Color(0xFFEEEEEE)),
              const SizedBox(height: 14),
              Row(children: [
                if (record.time.isNotEmpty) _miniStat(font, _t('시간', 'TIME'), record.time),
                if (record.time.isNotEmpty && record.pace.isNotEmpty)
                  _miniDivider(),
                if (record.pace.isNotEmpty) _miniStat(font, _t('페이스', 'PACE'), record.pace),
                if (record.pace.isNotEmpty && record.heartRate.isNotEmpty)
                  _miniDivider(),
                if (record.heartRate.isNotEmpty) _miniStat(font, _t('심박', 'HR'), record.heartRate),
                const Spacer(),
                if (record.date.isNotEmpty)
                  Text(record.date, style: _ts(font, fontSize: 10, color: _grey)),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _miniStat(String font, String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: _ts(font, fontSize: 8, color: _grey,
          letterSpacing: 1.5, fontWeight: FontWeight.w600)),
      const SizedBox(height: 2),
      Text(value, style: _ts(font, fontSize: 13, fontWeight: FontWeight.w800, color: _dark)),
    ],
  );

  Widget _miniDivider() => Container(
      width: 1, height: 24, color: const Color(0xFFEEEEEE),
      margin: const EdgeInsets.symmetric(horizontal: 14));
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
      if (record.time.isNotEmpty)      (_t('총 시간', 'TIME'),   record.time),
      if (record.pace.isNotEmpty)      (_t('평균 페이스', 'PACE'), record.pace),
      if (record.heartRate.isNotEmpty) (_t('평균 심박수', 'HR'),  record.heartRate),
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
              Text(record.date, style: _ts(font, fontSize: 10, color: _grey)),
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
              Text(s.$1, style: _ts(font, fontSize: 11, color: _grey,
                  fontWeight: FontWeight.w600)),
              const Spacer(),
              Text(s.$2, style: _ts(font, fontSize: 20,
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
      if (record.time.isNotEmpty)      (_t('시간', 'TIME'),   record.time),
      if (record.pace.isNotEmpty)      (_t('페이스', 'PACE'), record.pace),
      if (record.heartRate.isNotEmpty) (_t('심박', 'HR'),     record.heartRate),
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
                Text(s.$1, style: _ts(font, fontSize: 9,
                    color: Colors.white.withValues(alpha: 0.65),
                    letterSpacing: 1.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text(s.$2, style: _ts(font, fontSize: 16,
                    fontWeight: FontWeight.w800, color: Colors.white)),
                const SizedBox(height: 18),
              ]),
              if (record.date.isNotEmpty)
                Text(record.date, style: _ts(font, fontSize: 9,
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
          Text(label, style: _ts(font, fontSize: 9, color: _grey,
              letterSpacing: 1.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(value, style: _ts(font, fontSize: 14,
              fontWeight: FontWeight.w800, color: _dark)),
        ])));
  }
  if (r.time.isNotEmpty)      add(t('총 시간', 'TIME'), r.time);
  if (r.pace.isNotEmpty)      add(t('페이스', 'PACE'), r.pace);
  if (r.heartRate.isNotEmpty) add(t('심박수', 'HR'), r.heartRate);
  return items;
}

List<Widget> _centeredStats(String font, RunningRecord r, Color accent,
    String Function(String, String) t) {
  final items = <Widget>[];
  void add(String label, String value) {
    items.add(Column(children: [
      Text(value, style: _ts(font, fontSize: 18, fontWeight: FontWeight.w800, color: _dark)),
      const SizedBox(height: 4),
      Text(label, style: _ts(font, fontSize: 9, color: _grey,
          letterSpacing: 1.5, fontWeight: FontWeight.w500)),
    ]));
  }
  if (r.time.isNotEmpty)      add(t('총 시간', 'TIME'), r.time);
  if (r.pace.isNotEmpty)      add(t('페이스', 'PACE'), r.pace);
  if (r.heartRate.isNotEmpty) add(t('심박수', 'HR'), r.heartRate);
  return items;
}
