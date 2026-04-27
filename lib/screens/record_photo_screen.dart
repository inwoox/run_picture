import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../models/overlay_style.dart';
import '../app_settings.dart';
import '../services/ocr_service.dart';
import 'editor_screen.dart';
import '../widgets/ratio_picker_sheet.dart';
import '../widgets/ocr_confirm_sheet.dart';

class RecordPhotoScreen extends StatefulWidget {
  const RecordPhotoScreen({super.key});

  @override
  State<RecordPhotoScreen> createState() => _RecordPhotoScreenState();
}

class _RecordPhotoScreenState extends State<RecordPhotoScreen> {
  XFile? _selectedImage;
  XFile? _captureImage;
  double _selectedRatio = 9.0 / 16.0;
  Alignment _selectedAlignment = Alignment.center;
  bool _isProcessing = false;

  String _t(String ko, String en) => languageNotifier.value == LabelLanguage.korean ? ko : en;

  Future<void> _pickPhoto() async {
    final image = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (image == null || !mounted) return;
    final result = await showRatioPickerSheet(context, image.path);
    if (result == null || !mounted) return;
    final (ratio, alignment) = result;
    setState(() { _selectedImage = image; _selectedRatio = ratio; _selectedAlignment = alignment; });
  }

  Future<void> _pickCaptureImage() async {
    final image = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (image != null) setState(() => _captureImage = image);
  }

  Future<void> _processOcr() async {
    if (_captureImage == null) { _showError(_t('러닝 캡처 이미지를 선택해주세요', 'Please select a running capture')); return; }
    if (_selectedImage == null) { _showError(_t('배경 사진을 먼저 선택해주세요', 'Please select a background photo')); return; }
    setState(() => _isProcessing = true);
    try {
      final record = await OcrService.extractFromImage(_captureImage!.path);
      if (!mounted) return;
      // OCR 결과 확인·수정 시트
      final confirmed = await showOcrConfirmSheet(context, record, languageNotifier.value);
      if (!mounted) return;
      if (confirmed == null) return; // 취소
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => EditorScreen(image: _selectedImage!, record: confirmed,
            language: languageNotifier.value, ratio: _selectedRatio, alignment: _selectedAlignment),
      ));
    } catch (e) {
      if (mounted) _showError('${_t('OCR 처리 실패', 'OCR failed')}: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: const Color(0xFF1C1C1E), behavior: SnackBarBehavior.floating),
    );
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
          const Text('PaceGraphy',
              style: TextStyle(fontFamily: 'SUIT', color: Color(0xFF1C1C1E),
                  fontWeight: FontWeight.w700, fontSize: 18, letterSpacing: 1.0)),
          Text(_t('기록 사진 생성', 'Create Record Photo'),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(child: _pickerCard(image: _selectedImage, label: _t('배경 사진', 'Background Photo'),
                  icon: Icons.add_photo_alternate_rounded, onTap: _pickPhoto)),
              const SizedBox(width: 12),
              Expanded(child: _pickerCard(image: _captureImage, label: _t('러닝 기록 사진', 'Running Record'),
                  icon: Icons.document_scanner_rounded, onTap: _pickCaptureImage)),
            ]),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_t('이렇게 사용하세요', 'How to use'),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                        color: Color(0xFF1C1C1E))),
                const SizedBox(height: 12),
                _guideStep('1', _t('배경 사진 선택', 'Select background photo'),
                    _t('기록을 담고 싶은 배경 사진을 선택하세요', 'Choose a photo to use as the background')),
                _guideStep('2', _t('러닝 기록 사진 선택', 'Select running record photo'),
                    _t(
                      '러닝 앱의 기록 화면 스크린샷을 선택하세요\n값이 있는 부분만 캡처하여 첨부해야 인식률이 높습니다\n(인식이 안되는 경우, 수동으로 페이스 등 입력 가능)',
                      'Choose a screenshot from your running app\nCrop to the stats area only for better recognition\nYou can enter values manually if recognition fails',
                    )),
                Padding(
                  padding: const EdgeInsets.only(left: 34, bottom: 14),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SvgPicture.asset('assets/sample_running.svg', width: double.infinity, height: 180, fit: BoxFit.contain),
                  ),
                ),
                _guideStep('3', _t('기록 사진 생성 탭', 'Tap Create Record Photo'),
                    _t('버튼을 누르면 OCR로 기록을 자동 인식합니다', 'Tap the button to auto-extract stats via OCR')),
                _guideStep('4', _t('텍스트 편집 후 저장', 'Edit text and save'),
                    _t('인식된 기록을 확인·수정하고 사진에 추가해 저장하세요', 'Review, edit, and save your stats onto the photo'),
                    isLast: true),
              ]),
            ),
            const SizedBox(height: 24),

            _isProcessing
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF1C1C1E)))
                : SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _processOcr,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1C1C1E),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      child: Text(_t('기록 사진 생성', 'Create Photo'),
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _pickerCard({required XFile? image, required String label,
      required IconData icon, required VoidCallback onTap, double height = 110}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, 3))],
        ),
        child: image == null
            ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(width: 36, height: 36,
                    decoration: BoxDecoration(color: const Color(0xFFF0F0F0), borderRadius: BorderRadius.circular(12)),
                    child: Icon(icon, color: const Color(0xFF1C1C1E), size: 20)),
                if (height >= 100) ...[
                  const SizedBox(height: 8),
                  Text(label, style: const TextStyle(color: Color(0xFF1C1C1E),
                      fontWeight: FontWeight.w600, fontSize: 12), textAlign: TextAlign.center),
                ],
              ])
            : Stack(children: [
                ClipRRect(borderRadius: BorderRadius.circular(14),
                    child: Image.file(File(image.path), fit: BoxFit.cover, width: double.infinity, height: height)),
                Positioned(bottom: 6, right: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.edit, color: Colors.white, size: 11),
                      SizedBox(width: 3),
                      Text('변경', style: TextStyle(color: Colors.white, fontSize: 10)),
                    ]),
                  ),
                ),
              ]),
      ),
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
    final selected = languageNotifier.value == lang;
    return GestureDetector(
      onTap: () => setState(() => languageNotifier.value = lang),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF1C1C1E) : const Color(0xFFF5F7FA),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: selected ? const Color(0xFF1C1C1E) : const Color(0xFFE5E5EA)),
        ),
        child: Text(label, style: TextStyle(
          fontSize: 11, fontWeight: FontWeight.w600,
          color: selected ? Colors.white : const Color(0xFF8E8E93),
        )),
      ),
    );
  }
}
