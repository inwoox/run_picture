import 'dart:io';
import 'dart:typed_data';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

// ── Isolate helpers ────────────────────────────────────────────────────────

class _BgParams {
  final Uint8List bytes;
  final double sensitivity; // 5~100: 높을수록 많이 제거
  const _BgParams(this.bytes, this.sensitivity);
}

Uint8List _bgRemoveTask(_BgParams p) {
  final decoded = img.decodeImage(p.bytes);
  if (decoded == null) return p.bytes;

  final src = decoded.numChannels == 4 ? decoded : decoded.convert(numChannels: 4);

  // 테두리 픽셀 샘플링으로 배경 밝기 판단
  double sumBright = 0;
  int n = 0;
  void sample(int x, int y) {
    final px = src.getPixel(x, y);
    sumBright += (px.rNormalized + px.gNormalized + px.bNormalized) / 3.0 * 255.0;
    n++;
  }
  for (int x = 0; x < src.width; x++) {
    sample(x, 0); sample(x, src.height - 1);
  }
  for (int y = 1; y < src.height - 1; y++) {
    sample(0, y); sample(src.width - 1, y);
  }

  final avgBright = n > 0 ? sumBright / n : 128.0;
  final dark = avgBright < 128;
  // sensitivity: dark → 낮은 밝기 픽셀 제거 / light → 높은 밝기 픽셀 제거
  final threshold = dark ? p.sensitivity : (255.0 - p.sensitivity);

  final out = img.Image.from(src);
  for (int y = 0; y < out.height; y++) {
    for (int x = 0; x < out.width; x++) {
      final px = out.getPixel(x, y);
      final bright = (px.rNormalized + px.gNormalized + px.bNormalized) / 3.0 * 255.0;
      if (dark ? bright < threshold : bright > threshold) {
        out.setPixelRgba(x, y, 0, 0, 0, 0);
      }
    }
  }
  return Uint8List.fromList(img.encodePng(out));
}

Uint8List _invertTask(Uint8List bytes) {
  final src = img.decodeImage(bytes);
  if (src == null) return bytes;
  final out = src.clone();
  for (final p in out) {
    if (p.a.toInt() == 0) continue;
    out.setPixelRgba(p.x, p.y,
        255 - p.r.toInt(), 255 - p.g.toInt(), 255 - p.b.toInt(), p.a.toInt());
  }
  return Uint8List.fromList(img.encodePng(out));
}

class _ResizeParams {
  final Uint8List bytes;
  final int width;
  const _ResizeParams(this.bytes, this.width);
}

Uint8List _resizeTask(_ResizeParams p) {
  final src = img.decodeImage(p.bytes);
  if (src == null) return p.bytes;
  return Uint8List.fromList(
      img.encodePng(img.copyResize(src, width: p.width)));
}

// ── Crop Page ──────────────────────────────────────────────────────────────

class _CropPage extends StatefulWidget {
  final Uint8List imageBytes;
  const _CropPage({required this.imageBytes});
  @override
  State<_CropPage> createState() => _CropPageState();
}

class _CropPageState extends State<_CropPage> {
  double _l = 0.05, _t = 0.05, _r = 0.95, _b = 0.95;
  final double _hs = 24;
  late Size _imgSize;
  Size _screen = Size.zero;

  // 드래그 중 전체 rebuild 없이 오버레이만 업데이트
  late final _cropNotifier = ValueNotifier<({double l, double t, double r, double b})>(
      (l: 0.05, t: 0.05, r: 0.95, b: 0.95));

  @override
  void initState() {
    super.initState();
    final decoded = img.decodeImage(widget.imageBytes);
    _imgSize = decoded != null
        ? Size(decoded.width.toDouble(), decoded.height.toDouble())
        : const Size(1, 1);
  }

  @override
  void dispose() {
    _cropNotifier.dispose();
    super.dispose();
  }

  Rect _imageRect(Size screen, Size imgSize) {
    final scale = (screen.width / imgSize.width).clamp(0.0, screen.height / imgSize.height);
    final rw = imgSize.width * scale, rh = imgSize.height * scale;
    return Rect.fromLTWH((screen.width - rw) / 2, (screen.height - rh) / 2, rw, rh);
  }

  void _onHandle(int corner, DragUpdateDetails d) {
    final ir = _imageRect(_screen, _imgSize);
    final dx = d.delta.dx / ir.width, dy = d.delta.dy / ir.height;
    const min = 0.05;
    switch (corner) {
      case 0: _l = (_l + dx).clamp(0.0, _r - min); _t = (_t + dy).clamp(0.0, _b - min);
      case 1: _r = (_r + dx).clamp(_l + min, 1.0);  _t = (_t + dy).clamp(0.0, _b - min);
      case 2: _l = (_l + dx).clamp(0.0, _r - min); _b = (_b + dy).clamp(_t + min, 1.0);
      case 3: _r = (_r + dx).clamp(_l + min, 1.0);  _b = (_b + dy).clamp(_t + min, 1.0);
    }
    _cropNotifier.value = (l: _l, t: _t, r: _r, b: _b);
  }

  void _onRectDrag(DragUpdateDetails d) {
    final ir = _imageRect(_screen, _imgSize);
    final dx = d.delta.dx / ir.width, dy = d.delta.dy / ir.height;
    final w = _r - _l, h = _b - _t;
    _l = (_l + dx).clamp(0.0, 1.0 - w); _r = _l + w;
    _t = (_t + dy).clamp(0.0, 1.0 - h); _b = _t + h;
    _cropNotifier.value = (l: _l, t: _t, r: _r, b: _b);
  }

  Future<void> _confirm() async {
    final crop = _cropNotifier.value;
    final decoded = img.decodeImage(widget.imageBytes);
    if (decoded == null || !mounted) return;
    final x = (crop.l * decoded.width).round();
    final y = (crop.t * decoded.height).round();
    final w = ((crop.r - crop.l) * decoded.width).round().clamp(1, decoded.width - x);
    final h = ((crop.b - crop.t) * decoded.height).round().clamp(1, decoded.height - y);
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
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('범위 지정',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontFamily: 'SUIT')),
        actions: [
          TextButton(
            onPressed: _confirm,
            child: const Text('완료',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: LayoutBuilder(builder: (ctx, constraints) {
        _screen = Size(constraints.maxWidth, constraints.maxHeight);
        final ir = _imageRect(_screen, _imgSize);

        return Stack(children: [
          // 이미지 (정적) — RepaintBoundary로 드래그 중 재페인트 차단
          Positioned.fill(
            child: RepaintBoundary(
              child: Image.memory(widget.imageBytes, fit: BoxFit.contain),
            ),
          ),
          // 동적 크롭 오버레이 — ValueListenableBuilder로 이미지 재빌드 없이 업데이트
          ValueListenableBuilder<({double l, double t, double r, double b})>(
            valueListenable: _cropNotifier,
            builder: (_, crop, __) {
              final left = ir.left + crop.l * ir.width;
              final top = ir.top + crop.t * ir.height;
              final right = ir.left + crop.r * ir.width;
              final bottom = ir.top + crop.b * ir.height;

              return Stack(children: [
                Positioned.fill(child: CustomPaint(
                    painter: _DimPainter(Rect.fromLTRB(left, top, right, bottom)))),
                Positioned(
                  left: left, top: top, width: right - left, height: bottom - top,
                  child: GestureDetector(
                    onPanUpdate: _onRectDrag,
                    child: Container(
                      decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 1.5)),
                    ),
                  ),
                ),
                for (int i = 0; i < 4; i++)
                  Positioned(
                    left: (i == 0 || i == 2) ? left - _hs / 2 : right - _hs / 2,
                    top:  (i == 0 || i == 1) ? top - _hs / 2  : bottom - _hs / 2,
                    width: _hs, height: _hs,
                    child: GestureDetector(
                      onPanUpdate: (d) => _onHandle(i, d),
                      child: Container(
                        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                      ),
                    ),
                  ),
              ]);
            },
          ),
        ]);
      }),
    );
  }
}

class _DimPainter extends CustomPainter {
  final Rect crop;
  const _DimPainter(this.crop);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withValues(alpha: 0.55);
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height)),
        Path()..addRect(crop),
      ),
      paint,
    );
  }
  @override
  bool shouldRepaint(_DimPainter old) => old.crop != crop;
}

// ── 비율 옵션 ───────────────────────────────────────────────────────────────

const _videoRatioOptions = [
  ('원본', 0.0),
  ('1:1',  1.0),
  ('4:5',  4.0 / 5.0),
  ('9:16', 9.0 / 16.0),
  ('16:9', 16.0 / 9.0),
];

// ── Screen ─────────────────────────────────────────────────────────────────

class VideoPhotoScreen extends StatefulWidget {
  const VideoPhotoScreen({super.key});

  @override
  State<VideoPhotoScreen> createState() => _VideoPhotoScreenState();
}

class _VideoPhotoScreenState extends State<VideoPhotoScreen> {
  // 0=영상선택  1=사진편집  2=위치조정  3=처리중  4=완료
  int _step = 0;

  // Video
  File? _videoFile;
  VideoPlayerController? _vc;
  double _videoRatio = 0.0; // 0 = 원본 비율

  // Photo
  Uint8List? _origBytes;
  Uint8List? _photoBytes;
  bool _bgRemoved = false;
  bool _inverted = false;
  bool _photoLoading = false;
  double _bgSensitivity = 35.0; // 배경 제거 임계값 (5~120)

  // Overlay (normalized: 0.0 – 1.0 of video area)
  Offset _normPos = const Offset(0.1, 0.1);
  double _normWidth = 0.4;
  double _lastScale = 1.0;
  // 드래그 중 VideoPlayer 재빌드 없이 오버레이만 업데이트
  late final _overlayNotifier = ValueNotifier<({Offset pos, double width})>(
      (pos: _normPos, width: _normWidth));

  // Video display size (captured in LayoutBuilder, used in export)
  double _vDispW = 0;
  double _vDispH = 0;

  String _status = '';
  final _picker = ImagePicker();

  @override
  void dispose() {
    _vc?.dispose();
    _overlayNotifier.dispose();
    super.dispose();
  }

  // ── Video ────────────────────────────────────────────────────────────────

  Future<void> _pickVideo() async {
    final x = await _picker.pickVideo(source: ImageSource.gallery);
    if (x == null || !mounted) return;
    final file = File(x.path);
    final vc = VideoPlayerController.file(file);
    await vc.initialize();
    await vc.seekTo(Duration.zero);
    setState(() {
      _videoFile = file;
      _vc = vc;
      _videoRatio = 0.0;
      _step = 1;
    });
  }

  // ── Photo ────────────────────────────────────────────────────────────────

  Future<void> _pickPhoto() async {
    final x = await _picker.pickImage(source: ImageSource.gallery);
    if (x == null || !mounted) return;
    final bytes = await x.readAsBytes();

    final cropped = await Navigator.push<Uint8List>(
      context,
      MaterialPageRoute(builder: (_) => _CropPage(imageBytes: bytes)),
    );
    if (cropped == null || !mounted) return;

    setState(() {
      _origBytes = cropped;
      _photoBytes = cropped;
      _bgRemoved = false;
      _inverted = false;
    });
  }

  Future<void> _applyBgRemove() async {
    if (_origBytes == null || _photoLoading) return;
    setState(() => _photoLoading = true);
    final base = await compute(_bgRemoveTask, _BgParams(_origBytes!, _bgSensitivity));
    final finalBytes = _inverted ? await compute(_invertTask, base) : base;
    setState(() { _photoBytes = finalBytes; _bgRemoved = true; _photoLoading = false; });
  }

  Future<void> _toggleBgRemove() async {
    if (_origBytes == null || _photoLoading) return;
    if (_bgRemoved) {
      setState(() => _photoLoading = true);
      final finalBytes = _inverted ? await compute(_invertTask, _origBytes!) : _origBytes!;
      setState(() { _photoBytes = finalBytes; _bgRemoved = false; _photoLoading = false; });
    } else {
      await _applyBgRemove();
    }
  }

  Future<void> _toggleInvert() async {
    if (_origBytes == null || _photoLoading) return;
    setState(() => _photoLoading = true);
    final base = _bgRemoved
        ? await compute(_bgRemoveTask, _BgParams(_origBytes!, _bgSensitivity))
        : _origBytes!;
    final finalBytes = _inverted ? base : await compute(_invertTask, base);
    setState(() { _photoBytes = finalBytes; _inverted = !_inverted; _photoLoading = false; });
  }

  // ── Export ───────────────────────────────────────────────────────────────

  Future<void> _export() async {
    if (_videoFile == null || _photoBytes == null) return;
    setState(() {
      _step = 3;
      _status = '사진 준비 중...';
    });

    try {
      final tmp = await getTemporaryDirectory();

      final videoW = _vc!.value.size.width.toInt();
      final videoH = _vc!.value.size.height.toInt();

      // 선택된 비율로 크롭 영역 계산
      int cropW = videoW, cropH = videoH, cropX = 0, cropY = 0;
      if (_videoRatio > 0) {
        final nativeRatio = videoW / videoH;
        if ((_videoRatio - nativeRatio).abs() > 0.01) {
          if (_videoRatio > nativeRatio) {
            // 더 넓은 비율 → 위아래 크롭
            cropW = videoW;
            cropH = (videoW / _videoRatio).round();
            cropY = (videoH - cropH) ~/ 2;
          } else {
            // 더 좁은 비율 → 좌우 크롭
            cropH = videoH;
            cropW = (videoH * _videoRatio).round();
            cropX = (videoW - cropW) ~/ 2;
          }
        }
      }

      // 오버레이 좌표를 크롭된 영상 기준으로 변환
      final scaleX = cropW / _vDispW;
      final scaleY = cropH / _vDispH;
      final ovX = (_normPos.dx * _vDispW * scaleX).round();
      final ovY = (_normPos.dy * _vDispH * scaleY).round();
      final ovW = (_normWidth * _vDispW * scaleX).round().clamp(1, cropW);

      // 오버레이 사진을 Dart에서 미리 리사이즈 → ffmpeg scale 단계 불필요
      final resizedBytes = await compute(_resizeTask, _ResizeParams(_photoBytes!, ovW));
      final photoPath = '${tmp.path}/pg_overlay.png';
      await File(photoPath).writeAsBytes(resizedBytes);

      final outPath = '${tmp.path}/pg_output_${DateTime.now().millisecondsSinceEpoch}.mp4';

      setState(() => _status = '영상 합성 중...');

      final hasCrop = cropW != videoW || cropH != videoH;
      final filterComplex = hasCrop
          ? '[0:v]crop=$cropW:$cropH:$cropX:$cropY[cv];[cv][1:v]overlay=$ovX:$ovY'
          : '[0:v][1:v]overlay=$ovX:$ovY';

      // 1차: iOS VideoToolbox 하드웨어 인코더 (소프트웨어보다 5~10배 빠름)
      var cmd = '-y -threads 0 '
          '-i "${_videoFile!.path}" '
          '-i "$photoPath" '
          '-filter_complex "$filterComplex" '
          '-c:v h264_videotoolbox -b:v 6000k '
          '-c:a copy '
          '"$outPath"';

      var session = await FFmpegKit.execute(cmd);
      var rc = await session.getReturnCode();

      if (!ReturnCode.isSuccess(rc)) {
        // 폴백: 소프트웨어 ultrafast
        cmd = '-y -threads 0 '
            '-i "${_videoFile!.path}" '
            '-i "$photoPath" '
            '-filter_complex "$filterComplex" '
            '-c:v libx264 -preset ultrafast -crf 23 '
            '-c:a copy '
            '"$outPath"';
        session = await FFmpegKit.execute(cmd);
        rc = await session.getReturnCode();
      }

      if (!ReturnCode.isSuccess(rc)) {
        final logs = await session.getLogs();
        final msg = logs.map((l) => l.getMessage()).join('\n');
        throw Exception(msg.length > 300 ? msg.substring(0, 300) : msg);
      }

      setState(() => _status = '갤러리에 저장 중...');
      await Gal.putVideo(outPath, album: 'PaceGraphy');

      if (mounted) setState(() => _step = 4);
    } catch (e) {
      if (mounted) {
        setState(() => _step = 2);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('오류: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  static const _titles = ['영상 선택', '사진 편집', '위치 조정', '처리 중', '완료'];

  @override
  Widget build(BuildContext context) {
    final step = _step.clamp(0, 4);
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Color(0xFF1C1C1E)),
          onPressed: () {
            if (_step == 0 || _step >= 3) {
              Navigator.pop(context);
            } else {
              setState(() => _step--);
            }
          },
        ),
        title: Text(
          _titles[step],
          style: const TextStyle(
              color: Color(0xFF1C1C1E), fontWeight: FontWeight.w700, fontSize: 18,
              fontFamily: 'SUIT'),
        ),
        bottom: step < 3
            ? PreferredSize(
                preferredSize: const Size.fromHeight(3),
                child: LinearProgressIndicator(
                  value: (step + 1) / 3,
                  backgroundColor: const Color(0xFFE5E5EA),
                  valueColor:
                      const AlwaysStoppedAnimation(Color(0xFF1C1C1E)),
                ),
              )
            : null,
      ),
      body: IndexedStack(
        index: step,
        children: [
          _buildPickVideo(),
          _buildEditPhoto(),
          _buildPosition(),
          _buildProcessing(),
          _buildDone(),
        ],
      ),
    );
  }

  // ── Step 0: 영상 선택 ───────────────────────────────────────────────────

  Widget _buildPickVideo() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F0F0),
                borderRadius: BorderRadius.circular(28),
              ),
              child: const Icon(Icons.video_library_rounded,
                  size: 64, color: Color(0xFF1C1C1E)),
            ),
            const SizedBox(height: 32),
            const Text('영상에 사진 추가',
                style: TextStyle(
                    color: Color(0xFF1C1C1E),
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'SUIT')),
            const SizedBox(height: 12),
            const Text(
              '영상을 선택하고 사진을 올려놓으세요\n배경 제거와 색 반전도 가능합니다',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Color(0xFF8E8E93), fontSize: 15, height: 1.6),
            ),
            const SizedBox(height: 48),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _pickVideo,
                icon: const Icon(Icons.video_library_rounded),
                label: const Text('갤러리에서 영상 선택',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1C1C1E),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Step 1: 사진 편집 ───────────────────────────────────────────────────

  Widget _buildEditPhoto() {
    return Column(
      children: [
        // 영상 미리보기 + 비율 선택
        if (_vc != null && _vc!.value.isInitialized) ...[
          Container(
            color: Colors.black,
            constraints: const BoxConstraints(maxHeight: 220),
            child: Center(
              child: AspectRatio(
                aspectRatio: _videoRatio > 0 ? _videoRatio : _vc!.value.aspectRatio,
                child: ClipRect(
                  child: FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: _vc!.value.size.width,
                      height: _vc!.value.size.height,
                      child: VideoPlayer(_vc!),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Container(
            color: Colors.black,
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: _videoRatioOptions.map((opt) {
                final (label, ratio) = opt;
                final selected = (_videoRatio - ratio).abs() < 0.001;
                return GestureDetector(
                  onTap: () => setState(() {
                    _videoRatio = ratio;
                    _normPos = const Offset(0.1, 0.1);
                    _normWidth = 0.4;
                    _overlayNotifier.value = (pos: _normPos, width: _normWidth);
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: selected ? Colors.white : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selected ? Colors.white : Colors.white.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Text(label,
                        style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600,
                          color: selected ? const Color(0xFF1C1C1E) : Colors.white60,
                        )),
                  ),
                );
              }).toList(),
            ),
          ),
        ],

        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('추가할 사진',
                    style: TextStyle(
                        color: Color(0xFF1C1C1E),
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'SUIT')),
                const SizedBox(height: 12),
                _photoBytes == null
                    ? _photoPlaceholder()
                    : _photoEditorCard(),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),

        _bottomBtn(
          label: '위치 조정하기',
          icon: Icons.tune_rounded,
          enabled: _photoBytes != null,
          onPressed: () => setState(() => _step = 2),
        ),
      ],
    );
  }

  Widget _photoPlaceholder() {
    return GestureDetector(
      onTap: _pickPhoto,
      child: Container(
        width: double.infinity,
        height: 140,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE5E5EA), width: 1.5),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_photo_alternate_rounded,
                color: Color(0xFF1C1C1E), size: 40),
            SizedBox(height: 10),
            Text('사진 선택',
                style: TextStyle(
                    color: Color(0xFF1C1C1E),
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'SUIT')),
            SizedBox(height: 4),
            Text('탭하여 갤러리에서 선택',
                style: TextStyle(color: Color(0xFF8E8E93), fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _photoEditorCard() {
    return Column(
      children: [
        Stack(
          alignment: Alignment.topRight,
          children: [
            Container(
              width: double.infinity,
              height: 200,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 4))],
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.memory(_photoBytes!, fit: BoxFit.contain),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: GestureDetector(
                onTap: _photoLoading ? null : _pickPhoto,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('변경',
                      style:
                          TextStyle(color: Colors.white, fontSize: 13)),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _chip(
                icon: Icons.auto_fix_high_rounded,
                label: '배경 제거',
                active: _bgRemoved,
                loading: _photoLoading,
                onTap: _toggleBgRemove,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _chip(
                icon: Icons.invert_colors_rounded,
                label: '색 반전',
                active: _inverted,
                loading: _photoLoading,
                onTap: _toggleInvert,
              ),
            ),
          ],
        ),
        // 배경 제거 임계값 슬라이더 (배경 제거 활성 시 표시)
        if (_bgRemoved) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Text('제거 강도', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1C1C1E))),
                  const Spacer(),
                  Text(_bgSensitivity.round().toString(),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF1C1C1E))),
                ]),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: const Color(0xFF1C1C1E),
                    inactiveTrackColor: const Color(0xFFE5E5EA),
                    thumbColor: const Color(0xFF1C1C1E),
                    overlayShape: SliderComponentShape.noOverlay,
                    trackHeight: 2,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  ),
                  child: Slider(
                    value: _bgSensitivity,
                    min: 5, max: 120,
                    onChanged: (v) => setState(() => _bgSensitivity = v),
                    onChangeEnd: (_) => _applyBgRemove(),
                  ),
                ),
                const Text('← 적게 제거     많이 제거 →',
                    style: TextStyle(fontSize: 10, color: Color(0xFF8E8E93))),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ── Step 2: 위치 조정 ───────────────────────────────────────────────────

  Widget _buildPosition() {
    if (_vc == null || _photoBytes == null) return const SizedBox();

    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(builder: (ctx, constraints) {
            // 선택된 비율(또는 원본)로 영상 표시 크기 결정
            final displayRatio = _videoRatio > 0 ? _videoRatio : _vc!.value.aspectRatio;
            final vW = constraints.maxWidth;
            final vH = (vW / displayRatio).clamp(0.0, constraints.maxHeight);
            _vDispW = vW;
            _vDispH = vH;

            return GestureDetector(
              onTap: () {},
              child: Container(
                color: Colors.black,
                child: Stack(
                  children: [
                    // 영상 — RepaintBoundary로 드래그 중 재페인트 차단
                    RepaintBoundary(
                      child: SizedBox(
                        width: vW,
                        height: vH,
                        child: ClipRect(
                          child: FittedBox(
                            fit: BoxFit.cover,
                            child: SizedBox(
                              width: _vc!.value.size.width,
                              height: _vc!.value.size.height,
                              child: VideoPlayer(_vc!),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // 오버레이 — ValueNotifier로 VideoPlayer 재빌드 없이 업데이트
                    ValueListenableBuilder<({Offset pos, double width})>(
                      valueListenable: _overlayNotifier,
                      builder: (_, ov, __) => Positioned(
                        left: ov.pos.dx * vW,
                        top: ov.pos.dy * vH,
                        width: ov.width * vW,
                        child: GestureDetector(
                          onScaleStart: (_) => _lastScale = 1.0,
                          onScaleUpdate: (d) {
                            final scaleDelta = d.scale / _lastScale;
                            _lastScale = d.scale;
                            _normWidth = (_normWidth * scaleDelta).clamp(0.05, 0.95);
                            _normPos = Offset(
                              (_normPos.dx + d.focalPointDelta.dx / vW).clamp(0.0, 0.95),
                              (_normPos.dy + d.focalPointDelta.dy / vH).clamp(0.0, 0.95),
                            );
                            _overlayNotifier.value = (pos: _normPos, width: _normWidth);
                          },
                          child: Image.memory(_photoBytes!, fit: BoxFit.contain),
                        ),
                      ),
                    ),

                    // 힌트
                    Positioned(
                      bottom: 12,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 7),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            '드래그로 이동  ·  핀치로 크기 조절',
                            style: TextStyle(
                                color: Colors.white70, fontSize: 13),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
        // 사진 크기 조정 슬라이더
        ValueListenableBuilder<({Offset pos, double width})>(
          valueListenable: _overlayNotifier,
          builder: (_, ov, __) => Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Row(children: [
              const Icon(Icons.photo_size_select_large_rounded, size: 16, color: Color(0xFF8E8E93)),
              const SizedBox(width: 8),
              const Text('사진 크기 조정', style: TextStyle(fontSize: 13, color: Color(0xFF8E8E93), fontWeight: FontWeight.w500)),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: const Color(0xFF1C1C1E),
                    inactiveTrackColor: const Color(0xFFE5E5EA),
                    thumbColor: const Color(0xFF1C1C1E),
                    overlayShape: SliderComponentShape.noOverlay,
                    trackHeight: 2,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  ),
                  child: Slider(
                    value: ov.width,
                    min: 0.05, max: 0.95,
                    onChanged: (v) {
                      _normWidth = v;
                      _overlayNotifier.value = (pos: _normPos, width: v);
                    },
                  ),
                ),
              ),
              SizedBox(
                width: 36,
                child: Text('${(ov.width * 100).round()}%',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF1C1C1E))),
              ),
            ]),
          ),
        ),
        _bottomBtn(
          label: '영상 저장하기',
          icon: Icons.save_alt_rounded,
          onPressed: _export,
        ),
      ],
    );
  }

  // ── Step 3: 처리 중 ─────────────────────────────────────────────────────

  Widget _buildProcessing() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 56,
              height: 56,
              child: CircularProgressIndicator(
                  color: Color(0xFF1C1C1E), strokeWidth: 3),
            ),
            const SizedBox(height: 32),
            Text(_status,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Color(0xFF1C1C1E),
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'SUIT')),
            const SizedBox(height: 10),
            const Text('잠시만 기다려 주세요',
                style: TextStyle(color: Color(0xFF8E8E93), fontSize: 14)),
          ],
        ),
      ),
    );
  }

  // ── Step 4: 완료 ────────────────────────────────────────────────────────

  Widget _buildDone() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F0F0),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_rounded,
                  size: 60, color: Color(0xFF1C1C1E)),
            ),
            const SizedBox(height: 28),
            const Text('저장 완료!',
                style: TextStyle(
                    color: Color(0xFF1C1C1E),
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'SUIT')),
            const SizedBox(height: 10),
            const Text('PaceGraphy 앨범에 저장됐습니다',
                style: TextStyle(color: Color(0xFF8E8E93), fontSize: 15)),
            const SizedBox(height: 48),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF1C1C1E),
                      side: const BorderSide(color: Color(0xFFE5E5EA)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('홈으로',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => setState(() {
                      _step = 0;
                      _vc?.dispose();
                      _vc = null;
                      _videoFile = null;
                      _photoBytes = null;
                      _origBytes = null;
                      _bgRemoved = false;
                      _inverted = false;
                    }),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1C1C1E),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('다시',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── 공통 위젯 ────────────────────────────────────────────────────────────

  Widget _chip({
    required IconData icon,
    required String label,
    required bool active,
    required bool loading,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active ? const Color(0xFF1C1C1E) : const Color(0xFFE5E5EA),
          ),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: loading
            ? const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Color(0xFF1C1C1E)),
                ),
              )
            : Column(
                children: [
                  Icon(icon,
                      color: active ? Colors.white : const Color(0xFF8E8E93),
                      size: 26),
                  const SizedBox(height: 5),
                  Text(label,
                      style: TextStyle(
                          color: active ? Colors.white : const Color(0xFF8E8E93),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'SUIT')),
                ],
              ),
      ),
    );
  }

  Widget _bottomBtn({
    required String label,
    required IconData icon,
    Color color = const Color(0xFF1C1C1E),
    bool enabled = true,
    required VoidCallback? onPressed,
  }) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: enabled ? onPressed : null,
            icon: Icon(icon),
            label: Text(label,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(
              backgroundColor: color,
              disabledBackgroundColor: const Color(0xFFE5E5EA),
              foregroundColor: Colors.white,
              disabledForegroundColor: const Color(0xFF8E8E93),
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
      ),
    );
  }
}
