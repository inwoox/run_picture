import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../models/running_record.dart';
import '../models/overlay_style.dart';
import '../services/ocr_service.dart';
import 'editor_screen.dart';
import '../widgets/ratio_picker_sheet.dart';

class RecordPhotoScreen extends StatefulWidget {
  final LabelLanguage language;

  const RecordPhotoScreen({super.key, this.language = LabelLanguage.korean});

  @override
  State<RecordPhotoScreen> createState() => _RecordPhotoScreenState();
}

class _RecordPhotoScreenState extends State<RecordPhotoScreen> {
  XFile? _selectedImage;
  XFile? _captureImage;
  double _selectedRatio = 9.0 / 16.0;
  Alignment _selectedAlignment = Alignment.center;
  bool _isProcessing = false;
  late LabelLanguage _language;

  @override
  void initState() {
    super.initState();
    _language = widget.language;
  }

  String _t(String ko, String en) => _language == LabelLanguage.korean ? ko : en;

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
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => EditorScreen(image: _selectedImage!, record: record,
            language: _language, ratio: _selectedRatio, alignment: _selectedAlignment),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFF8E8E93)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _t(
                      '배경 사진과 러닝 기록 캡처 사진을 선택하고 기록 사진 생성을 누르면 기록 관련 텍스트가 배경 사진에 추가됩니다.',
                      'Select a background photo and running record capture, then tap Create to overlay your running stats on the photo.',
                    ),
                    style: const TextStyle(fontSize: 12, color: Color(0xFF1C1C1E), fontWeight: FontWeight.w600, height: 1.5),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 16),
            _sectionLabel(_t('배경 사진', 'Background Photo')),
            GestureDetector(
              onTap: _pickPhoto,
              child: Container(
                height: 200,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, 4))],
                ),
                child: _selectedImage == null
                    ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Container(
                          width: 52, height: 52,
                          decoration: BoxDecoration(color: const Color(0xFFF0F0F0), borderRadius: BorderRadius.circular(14)),
                          child: const Icon(Icons.add_photo_alternate_rounded, color: Color(0xFF1C1C1E), size: 28),
                        ),
                        const SizedBox(height: 12),
                        Text(_t('배경 사진 선택', 'Select Background Photo'),
                            style: const TextStyle(color: Color(0xFF1C1C1E), fontWeight: FontWeight.w600, fontSize: 15)),
                      ])
                    : Stack(children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.file(File(_selectedImage!.path), fit: BoxFit.cover, width: double.infinity, height: 200),
                        ),
                        Positioned(bottom: 10, right: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(Icons.edit, color: Colors.white, size: 14),
                              const SizedBox(width: 4),
                              Text(_t('변경', 'Change'), style: const TextStyle(color: Colors.white, fontSize: 12)),
                            ]),
                          ),
                        ),
                      ]),
              ),
            ),
            const SizedBox(height: 20),

            _sectionLabel(_t('러닝 기록 캡처', 'Running Capture')),
            GestureDetector(
              onTap: _pickCaptureImage,
              child: Container(
                height: 200,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, 4))],
                ),
                child: _captureImage == null
                    ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Container(
                          width: 52, height: 52,
                          decoration: BoxDecoration(color: const Color(0xFFF0F0F0), borderRadius: BorderRadius.circular(14)),
                          child: const Icon(Icons.document_scanner_rounded, color: Color(0xFF1C1C1E), size: 28),
                        ),
                        const SizedBox(height: 12),
                        Text(_t('러닝 기록 캡처 선택', 'Select Running Record Capture'),
                            style: const TextStyle(color: Color(0xFF1C1C1E), fontWeight: FontWeight.w600, fontSize: 15)),
                      ])
                    : Stack(children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.file(File(_captureImage!.path), fit: BoxFit.cover, width: double.infinity, height: 200),
                        ),
                        Positioned(bottom: 10, right: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(Icons.edit, color: Colors.white, size: 14),
                              const SizedBox(width: 4),
                              Text(_t('변경', 'Change'), style: const TextStyle(color: Colors.white, fontSize: 12)),
                            ]),
                          ),
                        ),
                      ]),
              ),
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

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(text, style: const TextStyle(color: Color(0xFF1C1C1E), fontSize: 15, fontWeight: FontWeight.w700)),
  );

  Widget _langToggle(String label, LabelLanguage lang) {
    final selected = _language == lang;
    return GestureDetector(
      onTap: () => setState(() => _language = lang),
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
