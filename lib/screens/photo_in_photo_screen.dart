import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:screenshot/screenshot.dart';
import 'package:image/image.dart' as img;
import 'dart:io';
import 'dart:typed_data';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import '../models/overlay_style.dart';
import '../app_settings.dart';
import '../utils/save_util.dart';
import '../widgets/ratio_picker_sheet.dart';

// ── 삽입 사진 크롭 페이지 ────────────────────────────────────────────────────
class _CropPage extends StatefulWidget {
  final Uint8List imageBytes;
  const _CropPage({required this.imageBytes});
  @override
  State<_CropPage> createState() => _CropPageState();
}

class _CropPageState extends State<_CropPage> {
  // 정규화된 크롭 영역 (0~1)
  double _l = 0.05, _t = 0.05, _r = 0.95, _b = 0.95;
  final double _handleSize = 22;

  // 이미지가 화면에서 실제 렌더링되는 Rect 계산 (BoxFit.contain)
  Rect _imageRect(Size screen, Size imgSize) {
    final sw = screen.width, sh = screen.height;
    final iw = imgSize.width, ih = imgSize.height;
    final scale = (sw / iw).clamp(0.0, sh / ih);
    final rw = iw * scale, rh = ih * scale;
    return Rect.fromLTWH((sw - rw) / 2, (sh - rh) / 2, rw, rh);
  }

  void _onHandleDrag(int corner, DragUpdateDetails d, Size screen, Size imgSize) {
    final r = _imageRect(screen, imgSize);
    final dx = d.delta.dx / r.width, dy = d.delta.dy / r.height;
    setState(() {
      const minSize = 0.05;
      switch (corner) {
        case 0: // 좌상
          _l = (_l + dx).clamp(0.0, _r - minSize);
          _t = (_t + dy).clamp(0.0, _b - minSize);
        case 1: // 우상
          _r = (_r + dx).clamp(_l + minSize, 1.0);
          _t = (_t + dy).clamp(0.0, _b - minSize);
        case 2: // 좌하
          _l = (_l + dx).clamp(0.0, _r - minSize);
          _b = (_b + dy).clamp(_t + minSize, 1.0);
        case 3: // 우하
          _r = (_r + dx).clamp(_l + minSize, 1.0);
          _b = (_b + dy).clamp(_t + minSize, 1.0);
      }
    });
  }

  void _onRectDrag(DragUpdateDetails d, Size screen, Size imgSize) {
    final r = _imageRect(screen, imgSize);
    final dx = d.delta.dx / r.width, dy = d.delta.dy / r.height;
    final w = _r - _l, h = _b - _t;
    setState(() {
      _l = (_l + dx).clamp(0.0, 1.0 - w);
      _r = _l + w;
      _t = (_t + dy).clamp(0.0, 1.0 - h);
      _b = _t + h;
    });
  }

  Future<void> _confirm(Size screen, Size imgSize) async {
    final decoded = img.decodeImage(widget.imageBytes);
    if (decoded == null || !mounted) return;
    final x = (_l * decoded.width).round();
    final y = (_t * decoded.height).round();
    final w = ((_r - _l) * decoded.width).round().clamp(1, decoded.width - x);
    final h = ((_b - _t) * decoded.height).round().clamp(1, decoded.height - y);
    final cropped = img.copyCrop(decoded, x: x, y: y, width: w, height: h);
    final result = Uint8List.fromList(img.encodePng(cropped));
    if (mounted) Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        leading: TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('취소', style: TextStyle(color: Colors.white70)),
        ),
        title: const Text('범위 선택', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: () async {
              final s = MediaQuery.of(context).size;
              final dec = img.decodeImage(widget.imageBytes);
              if (dec == null) return;
              await _confirm(s, Size(dec.width.toDouble(), dec.height.toDouble()));
            },
            child: const Text('확인', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: FutureBuilder<ui.Image>(
        future: () async {
          final codec = await ui.instantiateImageCodec(widget.imageBytes);
          return (await codec.getNextFrame()).image;
        }(),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: Colors.white));
          final uiImg = snap.data!;
          final imgSize = Size(uiImg.width.toDouble(), uiImg.height.toDouble());
          return LayoutBuilder(builder: (context, constraints) {
            final screen = Size(constraints.maxWidth, constraints.maxHeight);
            final ir = _imageRect(screen, imgSize);
            // 크롭 사각형 (픽셀 좌표)
            final cl = ir.left + _l * ir.width;
            final ct = ir.top + _t * ir.height;
            final cr = ir.left + _r * ir.width;
            final cb = ir.top + _b * ir.height;
            final cropRect = Rect.fromLTRB(cl, ct, cr, cb);

            Widget handle(int corner, double cx, double cy) {
              return Positioned(
                left: cx - _handleSize / 2,
                top: cy - _handleSize / 2,
                child: GestureDetector(
                  onPanUpdate: (d) => _onHandleDrag(corner, d, screen, imgSize),
                  child: Container(
                    width: _handleSize, height: _handleSize,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 4)],
                    ),
                  ),
                ),
              );
            }

            return Stack(children: [
              // 이미지
              Positioned.fill(child: Image.memory(widget.imageBytes, fit: BoxFit.contain)),
              // 어두운 오버레이 (크롭 영역 외부)
              Positioned.fill(
                child: CustomPaint(painter: _CropOverlayPainter(cropRect)),
              ),
              // 크롭 영역 드래그 (이동)
              Positioned(
                left: cl, top: ct, width: cr - cl, height: cb - ct,
                child: GestureDetector(
                  onPanUpdate: (d) => _onRectDrag(d, screen, imgSize),
                  child: Container(color: Colors.transparent),
                ),
              ),
              // 코너 핸들
              handle(0, cl, ct),
              handle(1, cr, ct),
              handle(2, cl, cb),
              handle(3, cr, cb),
            ]);
          });
        },
      ),
    );
  }
}

class _CropOverlayPainter extends CustomPainter {
  final Rect cropRect;
  _CropOverlayPainter(this.cropRect);
  @override
  void paint(Canvas canvas, Size size) {
    final dark = Paint()..color = Colors.black.withOpacity(0.55);
    // 크롭 영역 제외 4개 사각형 어둡게
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, cropRect.top), dark);
    canvas.drawRect(Rect.fromLTWH(0, cropRect.bottom, size.width, size.height - cropRect.bottom), dark);
    canvas.drawRect(Rect.fromLTWH(0, cropRect.top, cropRect.left, cropRect.height), dark);
    canvas.drawRect(Rect.fromLTWH(cropRect.right, cropRect.top, size.width - cropRect.right, cropRect.height), dark);
    // 크롭 테두리
    canvas.drawRect(cropRect, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 1.5);
    // 3분할 가이드선
    final guide = Paint()..color = Colors.white.withOpacity(0.35)..strokeWidth = 0.8;
    for (int i = 1; i < 3; i++) {
      final x = cropRect.left + cropRect.width * i / 3;
      final y = cropRect.top + cropRect.height * i / 3;
      canvas.drawLine(Offset(x, cropRect.top), Offset(x, cropRect.bottom), guide);
      canvas.drawLine(Offset(cropRect.left, y), Offset(cropRect.right, y), guide);
    }
  }
  @override
  bool shouldRepaint(_CropOverlayPainter old) => old.cropRect != cropRect;
}

// ── 배경 자동 감지 (isolate): 테두리 픽셀 평균 밝기로 판단 ──────────────────
bool _detectBgTask(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return true;
  // rNormalized(0.0~1.0)로 읽어 uint8/uint16 무관하게 0-255 환산
  int total = 0, count = 0;
  final w = decoded.width, h = decoded.height;
  for (int x = 0; x < w; x++) {
    for (final row in [0, h - 1]) {
      final p = decoded.getPixel(x, row);
      total += ((p.rNormalized + p.gNormalized + p.bNormalized) / 3 * 255).round();
      count++;
    }
  }
  for (int y = 1; y < h - 1; y++) {
    for (final col in [0, w - 1]) {
      final p = decoded.getPixel(col, y);
      total += ((p.rNormalized + p.gNormalized + p.bNormalized) / 3 * 255).round();
      count++;
    }
  }
  return count > 0 ? (total / count) < 128 : false;
}

// ── 배경 제거 (isolate) ─────────────────────────────────────────────────────
Future<Uint8List> _bgRemoveTask(Map<String, dynamic> args) async {
  final bytes = args['bytes'] as Uint8List;
  final threshold = args['threshold'] as int;
  final removeDark = args['removeDark'] as bool;
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;
  final result = img.Image(width: decoded.width, height: decoded.height, numChannels: 4);
  // JPEG는 alpha 채널 없음(numChannels==3) → 모든 픽셀 불투명 처리
  // PNG·이미 처리된 이미지는 alpha 존재 시 투명 픽셀 보존
  final hasAlpha = decoded.numChannels >= 4;
  for (int y = 0; y < decoded.height; y++) {
    for (int x = 0; x < decoded.width; x++) {
      final pixel = decoded.getPixel(x, y);
      // rNormalized(0.0~1.0)으로 읽어 uint8/uint16 모두 0-255 환산
      final r = (pixel.rNormalized * 255).round();
      final g = (pixel.gNormalized * 255).round();
      final b = (pixel.bNormalized * 255).round();
      // alpha 채널이 있는 이미지만 투명 픽셀 보존
      if (hasAlpha && (pixel.aNormalized * 255).round() < 128) {
        result.setPixelRgba(x, y, 0, 0, 0, 0);
        continue;
      }
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

enum _EraseToolType { brush, rect }

// ── 지우개 CustomPainter ────────────────────────────────────────────────────
class _ErasePainter extends CustomPainter {
  final ui.Image image;
  final List<dynamic> history; // List<Offset>=브러시획, Rect=사각형
  final List<Offset> currentStroke;
  final Rect? currentRect;
  final double radius;
  final bool invertColors;

  const _ErasePainter({
    required this.image,
    required this.history,
    required this.currentStroke,
    required this.currentRect,
    required this.radius,
    this.invertColors = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(Rect.fromLTWH(0, 0, size.width, size.height), Paint());

    final src = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    final imagePaint = Paint()..filterQuality = FilterQuality.high;
    if (invertColors) {
      imagePaint.colorFilter = const ColorFilter.matrix([
        -1, 0, 0, 0, 255,
         0,-1, 0, 0, 255,
         0, 0,-1, 0, 255,
         0, 0, 0, 1,   0,
      ]);
    }
    canvas.drawImageRect(image, src, Rect.fromLTWH(0, 0, size.width, size.height), imagePaint);

    final brushPaint = Paint()
      ..blendMode = BlendMode.dstOut
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final rectFillPaint = Paint()..blendMode = BlendMode.dstOut;

    void drawStroke(List<Offset> pts) {
      if (pts.isEmpty) return;
      if (pts.length == 1) {
        canvas.drawCircle(pts[0], radius, Paint()..blendMode = BlendMode.dstOut);
        return;
      }
      final path = Path()..moveTo(pts[0].dx, pts[0].dy);
      for (int i = 1; i < pts.length; i++) path.lineTo(pts[i].dx, pts[i].dy);
      canvas.drawPath(path, brushPaint);
    }

    for (final item in history) {
      if (item is List<Offset>) drawStroke(item);
      else if (item is Rect) canvas.drawRect(item, rectFillPaint);
    }
    drawStroke(currentStroke);
    if (currentRect != null) canvas.drawRect(currentRect!, rectFillPaint);

    canvas.restore();

    // 사각형 선택 테두리 (erase layer 밖에서 그려야 보임)
    if (currentRect != null) {
      canvas.drawRect(currentRect!, Paint()
        ..style = PaintingStyle.stroke
        ..color = const Color(0xCCFFFFFF)
        ..strokeWidth = 1.5);
    }
  }

  @override
  bool shouldRepaint(_ErasePainter old) => true;
}

// ── 메인 화면 ────────────────────────────────────────────────────────────────
class PhotoInPhotoScreen extends StatefulWidget {
  const PhotoInPhotoScreen({super.key});

  @override
  State<PhotoInPhotoScreen> createState() => _PhotoInPhotoScreenState();
}

class _PhotoInPhotoScreenState extends State<PhotoInPhotoScreen> {
  final ScreenshotController _screenshotController = ScreenshotController();
  final GlobalKey _previewKey = GlobalKey();

  XFile? _bgImage;
  XFile? _insertImage;
  double _bgRatio = 4.0 / 5.0;
  Alignment _bgAlignment = Alignment.center;
  // 위치/크기
  double _insertDx = 0, _insertDy = 0, _insertWidth = 0;
  double _widthAtScaleStart = 0;
  bool _initialized = false;

  // 배경 제거
  bool _removeBackground = false;
  bool _isProcessingBg = false;
  Uint8List? _processedBytes;
  double _bgThreshold = 60;
  bool? _removeDark = null; // null=자동, true=어두운배경(가민), false=밝은배경(스트라바)
  bool _invertColors = false; // 색상 반전

  // 지우개
  bool _eraseMode = false;
  _EraseToolType _eraseToolType = _EraseToolType.brush;
  double _eraseRadius = 5;
  List<dynamic> _eraseHistory = []; // List<Offset>=브러시, Rect=사각형
  List<Offset> _currentStroke = [];
  Rect? _currentRect;
  Offset? _rectStart;
  ui.Image? _insertUiImage;

  @override
  void dispose() {
    _insertUiImage?.dispose();
    super.dispose();
  }

  String _t(String ko, String en) => languageNotifier.value == LabelLanguage.korean ? ko : en;

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
    if (img == null || !mounted) return;
    final result = await showRatioPickerSheet(context, img.path);
    if (result == null || !mounted) return;
    final (ratio, alignment) = result;
    setState(() { _bgImage = img; _bgRatio = ratio; _bgAlignment = alignment; _initialized = false; });
  }

  Future<void> _pickInsert() async {
    final image = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 100);
    if (image == null || !mounted) return;

    // File()로 직접 읽어야 simulator에서 objective_c 오류 우회
    final originalBytes = await File(image.path).readAsBytes();
    if (!mounted) return;

    // 크롭 페이지로 이동 (취소 시 null 반환)
    final croppedBytes = await Navigator.push<Uint8List?>(
      context,
      MaterialPageRoute(builder: (_) => _CropPage(imageBytes: originalBytes)),
    );
    if (!mounted) return;

    final bytes = croppedBytes ?? originalBytes;

    // 임시 파일로 저장
    final tmp = await getTemporaryDirectory();
    final tmpFile = File('${tmp.path}/insert_${DateTime.now().millisecondsSinceEpoch}.png');
    await tmpFile.writeAsBytes(bytes);

    setState(() {
      _insertImage = XFile(tmpFile.path);
      _initialized = false;
      _removeBackground = false;
      _processedBytes = null;
      _eraseHistory = [];
      _currentStroke = [];
      _currentRect = null;
      _rectStart = null;
      _invertColors = false;
      _removeDark = null;
      _insertUiImage = null;
    });

    await _loadUiImageFromBytes(bytes);
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
      final removeDark = _removeDark ?? await compute(_detectBgTask, bytes);
      final result = await compute(_bgRemoveTask, {'bytes': bytes, 'threshold': _bgThreshold.toInt(), 'removeDark': removeDark});
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
    if (_eraseHistory.isNotEmpty) setState(() => _eraseHistory.removeLast());
  }

  void _resetErase() => setState(() { _eraseHistory = []; _currentStroke = []; _currentRect = null; _rectStart = null; });

  Future<void> _saveImage() async {
    showSavingDialog(context);
    try {
      final bytes = await _screenshotController.capture(pixelRatio: 5.0);
      if (bytes == null) { hideSavingDialog(context); _alert(_t('캡처 실패', 'Capture failed'), isError: true); return; }
      final tmp = await getTemporaryDirectory();
      final file = File('${tmp.path}/rp_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes);
      await Gal.putImage(file.path, album: 'PaceGraphy');
      await file.delete();
      hideSavingDialog(context);
      _alert(_t('사진첩에 저장되었습니다!', 'Saved to photo library!'));
    } catch (e) {
      hideSavingDialog(context);
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
          history: _eraseHistory,
          currentStroke: _currentStroke,
          currentRect: _currentRect,
          radius: _eraseRadius,
          invertColors: _invertColors,
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
        title: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('PaceGraphy',
              style: TextStyle(fontFamily: 'SUIT', color: Color(0xFF1C1C1E),
                  fontWeight: FontWeight.w700, fontSize: 18, letterSpacing: 1.0)),
          Text(_t('사진 속에 사진 추가', 'Photo in Photo'),
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
      body: Column(
        children: [
          // ── 사진 선택 ──
          Padding(
            padding: EdgeInsets.fromLTRB(16, bothSelected ? 4 : 16, 16, 0),
            child: Row(children: [
              Expanded(child: _pickerCard(image: _bgImage, label: _t('배경 사진', 'Background'),
                  icon: Icons.add_photo_alternate_rounded, onTap: _pickBg,
                  height: bothSelected ? 52 : 110)),
              const SizedBox(width: 12),
              Expanded(child: _pickerCard(image: _insertImage, label: _t('삽입할 사진', 'Insert Photo'),
                  icon: Icons.photo_library_rounded, onTap: _pickInsert,
                  height: bothSelected ? 52 : 110)),
            ]),
          ),

          // ── 프리뷰 ──
          Expanded(
            child: bothSelected
                ? Padding(
                    padding: const EdgeInsets.all(12),
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: _bgRatio,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: LayoutBuilder(builder: (context, constraints) {
                        final previewSize = Size(constraints.maxWidth, constraints.maxHeight);
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!_initialized) setState(() => _initPosition(previewSize));
                        });

                        // 지우개 모드: 프리뷰 전체에서 드래그 감지 후 삽입 이미지 좌표로 변환
                        Offset _toLocal(Offset p) =>
                            Offset(p.dx - _insertDx, p.dy - _insertDy);

                        return Listener(
                          behavior: _eraseMode ? HitTestBehavior.opaque : HitTestBehavior.deferToChild,
                          onPointerDown: _eraseMode ? (e) {
                            final p = _toLocal(e.localPosition);
                            if (_eraseToolType == _EraseToolType.brush) {
                              setState(() => _currentStroke = [p]);
                            } else {
                              setState(() { _rectStart = p; _currentRect = null; });
                            }
                          } : null,
                          onPointerMove: _eraseMode ? (e) {
                            final p = _toLocal(e.localPosition);
                            if (_eraseToolType == _EraseToolType.brush) {
                              setState(() => _currentStroke.add(p));
                            } else if (_rectStart != null) {
                              setState(() => _currentRect = Rect.fromPoints(_rectStart!, p));
                            }
                          } : null,
                          onPointerUp: _eraseMode ? (e) {
                            if (_eraseToolType == _EraseToolType.brush && _currentStroke.isNotEmpty) {
                              setState(() {
                                _eraseHistory.add(List<Offset>.from(_currentStroke));
                                _currentStroke = [];
                              });
                            } else if (_eraseToolType == _EraseToolType.rect && _currentRect != null) {
                              setState(() {
                                _eraseHistory.add(_currentRect!);
                                _currentRect = null;
                                _rectStart = null;
                              });
                            }
                          } : null,
                          child: Screenshot(
                          key: _previewKey,
                          controller: _screenshotController,
                          child: Stack(fit: StackFit.expand, children: [
                            Image.file(File(_bgImage!.path), fit: BoxFit.cover, alignment: _bgAlignment),
                            if (_initialized && _insertUiImage != null)
                              Positioned(
                                left: _insertDx,
                                top: _insertDy,
                                child: _eraseMode
                                    ? _buildInsertWidget()
                                    : GestureDetector(
                                        onScaleStart: (d) => _widthAtScaleStart = _insertWidth,
                                        onScaleUpdate: (d) {
                                          setState(() {
                                            _insertDx += d.focalPointDelta.dx;
                                            _insertDy += d.focalPointDelta.dy;
                                            _insertWidth = (_widthAtScaleStart * d.scale)
                                                .clamp(40.0, previewSize.width * 1.2);
                                          });
                                        },
                                        child: _buildInsertWidget(),
                                      ),
                              ),
                          ]),
                        ));
                      }),
                        ),
                      ),
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Container(
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
                        _guideStep('1', _t('배경 사진 선택', 'Select background photo'),
                            _t('합성의 배경이 될 사진을 선택하세요', 'Choose the base photo')),
                        _guideStep('2', _t('삽입할 사진 선택', 'Select insert photo'),
                            _t('위에 올릴 사진을 선택하세요 (기록 캡처 등)', 'Choose the photo to place on top')),
                        _guideStep('3', _t('위치·크기 조정 · 배경 제거', 'Adjust · Remove BG'),
                            _t('드래그로 위치, 두 손가락으로 크기 조정 / 배경 제거·지우개로 불필요한 부분 제거', 'Drag to move, pinch to resize / Remove background or use eraser')),
                        _guideStep('4', _t('저장', 'Save'),
                            _t('완성되면 이미지 저장을 눌러 저장하세요', 'Tap Save Image when done'),
                            isLast: true),
                      ]),
                    ),
                  ),
          ),

          // ── 편집 도구 (삽입 사진 선택 시, 프리뷰 아래 스크롤 가능) ──
          if (_insertImage != null)
            SizedBox(
              height: (_bgRatio - 9.0 / 16.0).abs() < 0.001 ? 130 : 200,
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
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
                      Row(children: [
                        _bgTypeToggle(_t('자동', 'Auto'), null),
                        const SizedBox(width: 8),
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
                      const Divider(height: 14, color: Color(0xFFEEEEEE)),
                      // 색상 반전 토글
                      Row(children: [
                        const Icon(Icons.invert_colors_rounded, size: 15, color: Color(0xFF1C1C1E)),
                        const SizedBox(width: 6),
                        Text(_t('색상 반전', 'Invert Colors'),
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1C1C1E))),
                        const Spacer(),
                        Switch(
                          value: _invertColors,
                          activeThumbColor: const Color(0xFF1C1C1E),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          onChanged: (v) => setState(() => _invertColors = v),
                        ),
                      ]),
                      const Divider(height: 14, color: Color(0xFFEEEEEE)),
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
                        const SizedBox(height: 4),
                        Row(children: [
                          _eraseToolToggle(Icons.brush_rounded, _t('브러시', 'Brush'), _EraseToolType.brush),
                          const SizedBox(width: 8),
                          _eraseToolToggle(Icons.crop_square_rounded, _t('사각형', 'Rect'), _EraseToolType.rect),
                        ]),
                        if (_eraseToolType == _EraseToolType.brush) ...[
                          const SizedBox(height: 4),
                          Row(children: [
                            Text(_t('브러시 크기', 'Size'),
                                style: const TextStyle(fontSize: 11, color: Color(0xFF8E8E93))),
                            Expanded(child: _thinSlider(_eraseRadius, 5, 10, (v) => setState(() => _eraseRadius = v))),
                            SizedBox(width: 28, child: Text(_eraseRadius.toInt().toString(),
                                style: const TextStyle(fontSize: 11, color: Color(0xFF1C1C1E), fontWeight: FontWeight.w600))),
                          ]),
                        ],
                        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                          TextButton.icon(
                            onPressed: _eraseHistory.isNotEmpty ? _undoErase : null,
                            icon: const Icon(Icons.undo_rounded, size: 14),
                            label: Text(_t('실행 취소', 'Undo'), style: const TextStyle(fontSize: 12)),
                            style: TextButton.styleFrom(foregroundColor: const Color(0xFF1C1C1E),
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
                          ),
                          TextButton.icon(
                            onPressed: _eraseHistory.isNotEmpty ? _resetErase : null,
                            icon: const Icon(Icons.refresh_rounded, size: 14),
                            label: Text(_t('초기화', 'Reset'), style: const TextStyle(fontSize: 12)),
                            style: TextButton.styleFrom(foregroundColor: const Color(0xFF1C1C1E),
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
                          ),
                        ]),
                        Text(
                          _eraseToolType == _EraseToolType.brush
                              ? _t('사진 위에서 드래그하여 지울 영역 선택', 'Drag on photo to erase')
                              : _t('드래그로 지울 사각형 영역 선택', 'Drag to select rect area'),
                          style: const TextStyle(fontSize: 11, color: Color(0xFF8E8E93)),
                        ),
                      ],
                    ]),
                  ),
                ),
              ),
            ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: bothSelected ? _saveImage : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1C1C1E),
                  disabledBackgroundColor: const Color(0xFFCCCCCC),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
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

  Widget _eraseToolToggle(IconData icon, String label, _EraseToolType type) {
    final selected = _eraseToolType == type;
    return GestureDetector(
      onTap: () => setState(() => _eraseToolType = type),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF1C1C1E) : const Color(0xFFF5F7FA),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? const Color(0xFF1C1C1E) : const Color(0xFFE5E5EA)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: selected ? Colors.white : const Color(0xFF8E8E93)),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w600,
            color: selected ? Colors.white : const Color(0xFF8E8E93),
          )),
        ]),
      ),
    );
  }

  Widget _bgTypeToggle(String label, bool? isDark) {
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
            color: selected ? Colors.white : const Color(0xFF8E8E93))),
      ),
    );
  }
}
