import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:screenshot/screenshot.dart';
import 'package:image/image.dart' as img;
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import '../models/overlay_style.dart';

// ── 배경 제거 (isolate) ─────────────────────────────────────────────────────
Future<Uint8List> _bgRemoveTask(Map<String, dynamic> args) async {
  final bytes = args['bytes'] as Uint8List;
  final threshold = args['threshold'] as int;
  final removeDark = args['removeDark'] as bool; // true=어두운배경, false=밝은배경
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;
  final result = img.Image(width: decoded.width, height: decoded.height, numChannels: 4);
  for (int y = 0; y < decoded.height; y++) {
    for (int x = 0; x < decoded.width; x++) {
      final pixel = decoded.getPixel(x, y);
      final r = pixel.r.toInt(); final g = pixel.g.toInt(); final b = pixel.b.toInt();
      final brightness = (r + g + b) ~/ 3;
      final shouldRemove = removeDark ? brightness < threshold : brightness > (255 - threshold);
      if (shouldRemove) {
        result.setPixelRgba(x, y, 0, 0, 0, 0);
      } else {
        result.setPixelRgba(x, y, r, g, b, 255);
      }
    }
  }
  return Uint8List.fromList(img.encodePng(result));
}

// ── 지우개 CustomPainter ────────────────────────────────────────────────────
class _ErasePainter extends CustomPainter {
  final ui.Image image;
  final List<List<Offset>> strokes;
  final List<Offset> currentStroke;
  final double radius;

  const _ErasePainter({
    required this.image,
    required this.strokes,
    required this.currentStroke,
    required this.radius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(Rect.fromLTWH(0, 0, size.width, size.height), Paint());

    final src = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    canvas.drawImageRect(image, src, Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..filterQuality = FilterQuality.high);

    final erasePaint = Paint()
      ..blendMode = BlendMode.dstOut
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    void drawStroke(List<Offset> pts) {
      if (pts.isEmpty) return;
      if (pts.length == 1) {
        canvas.drawCircle(pts[0], radius,
            Paint()..blendMode = BlendMode.dstOut);
        return;
      }
      final path = Path()..moveTo(pts[0].dx, pts[0].dy);
      for (int i = 1; i < pts.length; i++) path.lineTo(pts[i].dx, pts[i].dy);
      canvas.drawPath(path, erasePaint);
    }

    for (final s in strokes) drawStroke(s);
    drawStroke(currentStroke);

    canvas.restore();
  }

  @override
  bool shouldRepaint(_ErasePainter old) => true;
}

// ── 메인 화면 ────────────────────────────────────────────────────────────────
class PhotoInPhotoScreen extends StatefulWidget {
  final LabelLanguage language;
  const PhotoInPhotoScreen({super.key, this.language = LabelLanguage.korean});

  @override
  State<PhotoInPhotoScreen> createState() => _PhotoInPhotoScreenState();
}

class _PhotoInPhotoScreenState extends State<PhotoInPhotoScreen> {
  final ScreenshotController _screenshotController = ScreenshotController();
  final GlobalKey _previewKey = GlobalKey();

  XFile? _bgImage;
  XFile? _insertImage;
  late LabelLanguage _language;

  // 위치/크기
  double _insertDx = 0, _insertDy = 0, _insertWidth = 0;
  double _widthAtScaleStart = 0;
  bool _initialized = false;

  // 배경 제거
  bool _removeBackground = false;
  bool _isProcessingBg = false;
  Uint8List? _processedBytes;
  double _bgThreshold = 60;
  bool _removeDark = true; // true=어두운배경(가민), false=밝은배경(스트라바)

  // 지우개
  bool _eraseMode = false;
  double _eraseRadius = 20;
  List<List<Offset>> _eraseStrokes = [];
  List<Offset> _currentStroke = [];
  ui.Image? _insertUiImage;

  @override
  void initState() {
    super.initState();
    _language = widget.language;
  }

  @override
  void dispose() {
    _insertUiImage?.dispose();
    super.dispose();
  }

  String _t(String ko, String en) => _language == LabelLanguage.korean ? ko : en;

  Future<ui.Image> _bytesToUiImage(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  Future<void> _loadUiImageFromFile(String path) async {
    final bytes = await File(path).readAsBytes();
    final uiImg = await _bytesToUiImage(bytes);
    if (mounted) setState(() => _insertUiImage = uiImg);
  }

  Future<void> _loadUiImageFromBytes(Uint8List bytes) async {
    final uiImg = await _bytesToUiImage(bytes);
    if (mounted) setState(() => _insertUiImage = uiImg);
  }

  Future<void> _pickBg() async {
    final img = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (img != null) setState(() { _bgImage = img; _initialized = false; });
  }

  Future<void> _pickInsert() async {
    final image = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _insertImage = image;
        _initialized = false;
        _removeBackground = false;
        _processedBytes = null;
        _eraseStrokes = [];
        _currentStroke = [];
        _insertUiImage = null;
      });
      await _loadUiImageFromFile(image.path);
    }
  }

  void _initPosition(Size previewSize) {
    if (_initialized) return;
    _insertWidth = previewSize.width * 0.4;
    _insertDx = (previewSize.width - _insertWidth) / 2;
    _insertDy = (previewSize.height - _insertWidth) / 2;
    _initialized = true;
  }

  Future<void> _applyBgRemoval() async {
    if (_insertImage == null) return;
    setState(() => _isProcessingBg = true);
    try {
      final bytes = await File(_insertImage!.path).readAsBytes();
      final result = await compute(_bgRemoveTask, {'bytes': bytes, 'threshold': _bgThreshold.toInt(), 'removeDark': _removeDark});
      setState(() { _processedBytes = result; _removeBackground = true; });
      await _loadUiImageFromBytes(result);
    } finally {
      if (mounted) setState(() => _isProcessingBg = false);
    }
  }

  Future<void> _disableBgRemoval() async {
    setState(() { _removeBackground = false; _processedBytes = null; });
    if (_insertImage != null) await _loadUiImageFromFile(_insertImage!.path);
  }

  void _undoErase() {
    if (_eraseStrokes.isNotEmpty) setState(() => _eraseStrokes.removeLast());
  }

  void _resetErase() => setState(() { _eraseStrokes = []; _currentStroke = []; });

  Future<Directory> _getSaveDirectory() async {
    if (Platform.isAndroid) {
      final dir = Directory('/storage/emulated/0/Pictures/RunningPhoto');
      if (!await dir.exists()) await dir.create(recursive: true);
      return dir;
    } else {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}/RunningPhoto');
      if (!await dir.exists()) await dir.create(recursive: true);
      return dir;
    }
  }

  Future<void> _saveImage() async {
    try {
      final Uint8List? bytes = await _screenshotController.capture(pixelRatio: 5.0);
      if (bytes == null) { _alert(_t('캡처 실패', 'Capture failed'), isError: true); return; }
      final dir = await _getSaveDirectory();
      final file = File('${dir.path}/pip_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes);
      _alert('${_t('저장 완료', 'Saved')}!\n${file.path}');
    } catch (e) {
      _alert('${_t('저장 실패', 'Save failed')}: $e', isError: true);
    }
  }

  void _alert(String msg, {bool isError = false}) {
    if (!mounted) return;
    showDialog(context: context, builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(isError ? _t('오류', 'Error') : _t('저장 완료', 'Saved'),
          style: TextStyle(color: isError ? Colors.red : Colors.white, fontWeight: FontWeight.bold)),
      content: Text(msg),
      actions: [TextButton(onPressed: () => Navigator.pop(context),
          child: Text(_t('확인', 'OK'), style: const TextStyle(color: Colors.white)))],
    ));
  }

  Widget _buildInsertWidget() {
    if (_insertUiImage == null) return const SizedBox();
    final imgH = _insertWidth * _insertUiImage!.height / _insertUiImage!.width;
    return SizedBox(
      width: _insertWidth,
      height: imgH,
      child: CustomPaint(
        size: Size(_insertWidth, imgH),
        painter: _ErasePainter(
          image: _insertUiImage!,
          strokes: _eraseStrokes,
          currentStroke: _currentStroke,
          radius: _eraseRadius,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bothSelected = _bgImage != null && _insertImage != null;

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
      body: Column(
        children: [
          // ── 사진 선택 ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(children: [
              Expanded(child: _pickerCard(image: _bgImage, label: _t('배경 사진', 'Background'),
                  icon: Icons.add_photo_alternate_rounded, onTap: _pickBg)),
              const SizedBox(width: 12),
              Expanded(child: _pickerCard(image: _insertImage, label: _t('삽입할 사진', 'Insert Photo'),
                  icon: Icons.photo_library_rounded, onTap: _pickInsert)),
            ]),
          ),

          // ── 편집 도구 (삽입 사진 선택 시) ──
          if (_insertImage != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6, offset: const Offset(0, 2))],
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // 배경 제거 토글
                  Row(children: [
                    const Icon(Icons.auto_fix_high_rounded, size: 15, color: Color(0xFF1C1C1E)),
                    const SizedBox(width: 6),
                    Text(_t('배경 제거', 'Remove BG'),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1C1C1E))),
                    const Spacer(),
                    if (_isProcessingBg)
                      const SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF1C1C1E)))
                    else
                      Switch(
                        value: _removeBackground,
                        activeColor: const Color(0xFF1C1C1E),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        onChanged: (v) => v ? _applyBgRemoval() : _disableBgRemoval(),
                      ),
                  ]),
                  // 배경 종류 선택 (항상 표시)
                  const SizedBox(height: 6),
                  Row(children: [
                    _bgTypeToggle(_t('어두운 배경', 'Dark BG'), true),
                    const SizedBox(width: 8),
                    _bgTypeToggle(_t('밝은 배경', 'Light BG'), false),
                  ]),
                  if (_removeBackground) ...[
                    const SizedBox(height: 4),
                    Row(children: [
                      Text(_t('임계값', 'Threshold'),
                          style: const TextStyle(fontSize: 11, color: Color(0xFF8E8E93))),
                      Expanded(child: _thinSlider(_bgThreshold, 10, 180, (v) {
                        setState(() => _bgThreshold = v);
                      }, onEnd: (_) { if (_removeBackground) _applyBgRemoval(); })),
                      SizedBox(width: 28, child: Text(_bgThreshold.toInt().toString(),
                          style: const TextStyle(fontSize: 11, color: Color(0xFF1C1C1E), fontWeight: FontWeight.w600))),
                    ]),
                  ],

                  const Divider(height: 16, color: Color(0xFFEEEEEE)),

                  // 지우개 토글
                  Row(children: [
                    const Icon(Icons.draw_rounded, size: 15, color: Color(0xFF1C1C1E)),
                    const SizedBox(width: 6),
                    Text(_t('선택 지우기', 'Selective Erase'),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1C1C1E))),
                    const Spacer(),
                    Switch(
                      value: _eraseMode,
                      activeColor: const Color(0xFF1C1C1E),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onChanged: (v) => setState(() => _eraseMode = v),
                    ),
                  ]),
                  if (_eraseMode) ...[
                    Row(children: [
                      Text(_t('브러시 크기', 'Size'),
                          style: const TextStyle(fontSize: 11, color: Color(0xFF8E8E93))),
                      Expanded(child: _thinSlider(_eraseRadius, 5, 60, (v) => setState(() => _eraseRadius = v))),
                      SizedBox(width: 28, child: Text(_eraseRadius.toInt().toString(),
                          style: const TextStyle(fontSize: 11, color: Color(0xFF1C1C1E), fontWeight: FontWeight.w600))),
                    ]),
                    Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                      TextButton.icon(
                        onPressed: _eraseStrokes.isNotEmpty ? _undoErase : null,
                        icon: const Icon(Icons.undo_rounded, size: 14),
                        label: Text(_t('실행 취소', 'Undo'),
                            style: const TextStyle(fontSize: 12)),
                        style: TextButton.styleFrom(foregroundColor: const Color(0xFF1C1C1E),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
                      ),
                      TextButton.icon(
                        onPressed: _eraseStrokes.isNotEmpty ? _resetErase : null,
                        icon: const Icon(Icons.refresh_rounded, size: 14),
                        label: Text(_t('초기화', 'Reset'),
                            style: const TextStyle(fontSize: 12)),
                        style: TextButton.styleFrom(foregroundColor: const Color(0xFF1C1C1E),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
                      ),
                    ]),
                    Text(
                      _t('사진 위에서 드래그하여 지울 영역 선택', 'Drag on photo to erase'),
                      style: const TextStyle(fontSize: 11, color: Color(0xFF8E8E93)),
                    ),
                  ],
                ]),
              ),
            ),

          // ── 프리뷰 ──
          Expanded(
            child: bothSelected
                ? Padding(
                    padding: const EdgeInsets.all(12),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: LayoutBuilder(builder: (context, constraints) {
                        final previewSize = Size(constraints.maxWidth, constraints.maxHeight);
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!_initialized) setState(() => _initPosition(previewSize));
                        });

                        return Screenshot(
                          key: _previewKey,
                          controller: _screenshotController,
                          child: Stack(fit: StackFit.expand, children: [
                            Image.file(File(_bgImage!.path), fit: BoxFit.cover),
                            if (_initialized && _insertUiImage != null)
                              Positioned(
                                left: _insertDx,
                                top: _insertDy,
                                child: GestureDetector(
                                  onScaleStart: (d) {
                                    if (_eraseMode) {
                                      _currentStroke = [d.localFocalPoint];
                                    } else {
                                      _widthAtScaleStart = _insertWidth;
                                    }
                                  },
                                  onScaleUpdate: (d) {
                                    if (_eraseMode) {
                                      setState(() => _currentStroke.add(d.localFocalPoint));
                                    } else {
                                      setState(() {
                                        _insertDx = (_insertDx + d.focalPointDelta.dx)
                                            .clamp(-_insertWidth * 0.5, previewSize.width - _insertWidth * 0.5);
                                        _insertDy = (_insertDy + d.focalPointDelta.dy)
                                            .clamp(-_insertWidth * 0.5, previewSize.height - _insertWidth * 0.5);
                                        _insertWidth = (_widthAtScaleStart * d.scale)
                                            .clamp(40.0, previewSize.width * 1.2);
                                      });
                                    }
                                  },
                                  onScaleEnd: (d) {
                                    if (_eraseMode && _currentStroke.isNotEmpty) {
                                      setState(() {
                                        _eraseStrokes.add(List.from(_currentStroke));
                                        _currentStroke = [];
                                      });
                                    }
                                  },
                                  child: _buildInsertWidget(),
                                ),
                              ),
                          ]),
                        );
                      }),
                    ),
                  )
                : Center(
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.touch_app_rounded, size: 48, color: Color(0xFFCCCCCC)),
                      const SizedBox(height: 12),
                      Text(_t('위에서 두 사진을 선택하세요', 'Select two photos above'),
                          style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 14)),
                    ]),
                  ),
          ),

          if (bothSelected && !_eraseMode)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 2),
              child: Text(
                _t('드래그로 위치 조정 • 두 손가락으로 크기 조절', 'Drag to move • Pinch to resize'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 11),
              ),
            ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: bothSelected ? _saveImage : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1C1C1E),
                  disabledBackgroundColor: const Color(0xFFCCCCCC),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: Text(_t('이미지 저장', 'Save Image'),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bgTypeToggle(String label, bool isDark) {
    final selected = _removeDark == isDark;
    return GestureDetector(
      onTap: () {
        setState(() => _removeDark = isDark);
        if (_removeBackground) _applyBgRemoval();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF1C1C1E) : const Color(0xFFF5F7FA),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? const Color(0xFF1C1C1E) : const Color(0xFFE5E5EA)),
        ),
        child: Text(label, style: TextStyle(
          fontSize: 11, fontWeight: FontWeight.w600,
          color: selected ? Colors.white : const Color(0xFF8E8E93),
        )),
      ),
    );
  }

  Widget _thinSlider(double value, double min, double max, ValueChanged<double> onChanged, {ValueChanged<double>? onEnd}) {
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        activeTrackColor: const Color(0xFF1C1C1E),
        inactiveTrackColor: const Color(0xFFE5E5EA),
        thumbColor: const Color(0xFF1C1C1E),
        overlayShape: SliderComponentShape.noOverlay,
        trackHeight: 2,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
      ),
      child: Slider(value: value, min: min, max: max, onChanged: onChanged, onChangeEnd: onEnd),
    );
  }

  Widget _pickerCard({required XFile? image, required String label,
      required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 110,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, 3))],
        ),
        child: image == null
            ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(width: 40, height: 40,
                    decoration: BoxDecoration(color: const Color(0xFFF0F0F0), borderRadius: BorderRadius.circular(12)),
                    child: Icon(icon, color: const Color(0xFF1C1C1E), size: 22)),
                const SizedBox(height: 8),
                Text(label, style: const TextStyle(color: Color(0xFF1C1C1E),
                    fontWeight: FontWeight.w600, fontSize: 12), textAlign: TextAlign.center),
              ])
            : Stack(children: [
                ClipRRect(borderRadius: BorderRadius.circular(14),
                    child: Image.file(File(image.path), fit: BoxFit.cover, width: double.infinity, height: 110)),
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
            color: selected ? Colors.white : const Color(0xFF8E8E93))),
      ),
    );
  }
}
