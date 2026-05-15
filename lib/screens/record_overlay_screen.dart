import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:screenshot/screenshot.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import '../models/running_record.dart';
import '../models/overlay_style.dart';
import '../utils/save_util.dart';
import '../widgets/running_cards.dart';

const double _kRefWidth = 400.0;

// ── 배경 효과 ────────────────────────────────────────────────────────────────
enum _BgEffect { none, sketch, colorSketch }

class _SketchParams {
  final Uint8List bytes;
  final int blurRadius;
  const _SketchParams(this.bytes, this.blurRadius);
}

class _ColorSketchParams {
  final Uint8List bytes;
  final double colorTint;
  const _ColorSketchParams(this.bytes, this.colorTint);
}

Uint8List _sketchEffectTask(_SketchParams p) {
  var decoded = img.decodeImage(p.bytes);
  if (decoded == null) return p.bytes;
  if (decoded.width > 1500) decoded = img.copyResize(decoded, width: 1500);
  final w = decoded.width, h = decoded.height;
  final gray = img.Image(width: w, height: h);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final px = decoded.getPixel(x, y);
      final v = (px.rNormalized * 0.299 + px.gNormalized * 0.587 + px.bNormalized * 0.114);
      final vi = (v * 255).round().clamp(0, 255);
      gray.setPixelRgb(x, y, vi, vi, vi);
    }
  }
  final inv = img.Image(width: w, height: h);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final v = 255 - (gray.getPixel(x, y).rNormalized * 255).round();
      inv.setPixelRgb(x, y, v, v, v);
    }
  }
  final blurred = img.gaussianBlur(inv, radius: p.blurRadius);
  final result = img.Image(width: w, height: h);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final g = (gray.getPixel(x, y).rNormalized * 255).round();
      final b = (blurred.getPixel(x, y).rNormalized * 255).round();
      final dodge = b >= 255 ? 255 : (g * 255 / (255 - b)).clamp(0.0, 255.0).round();
      result.setPixelRgb(x, y, dodge, dodge, dodge);
    }
  }
  return Uint8List.fromList(img.encodeJpg(result, quality: 88));
}

Uint8List _colorSketchTask(_ColorSketchParams p) {
  var decoded = img.decodeImage(p.bytes);
  if (decoded == null) return p.bytes;
  if (decoded.width > 1500) decoded = img.copyResize(decoded, width: 1500);
  final w = decoded.width, h = decoded.height;
  final gray = img.Image(width: w, height: h);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final px = decoded.getPixel(x, y);
      final v = px.rNormalized * 0.299 + px.gNormalized * 0.587 + px.bNormalized * 0.114;
      final vi = (v * 255).round().clamp(0, 255);
      gray.setPixelRgb(x, y, vi, vi, vi);
    }
  }
  final inv = img.Image(width: w, height: h);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final v = 255 - (gray.getPixel(x, y).rNormalized * 255).round();
      inv.setPixelRgb(x, y, v, v, v);
    }
  }
  final invBlurred = img.gaussianBlur(inv, radius: 12);
  final dodgeMap = List.filled(w * h, 255);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final gv = (gray.getPixel(x, y).rNormalized * 255).round();
      final bv = (invBlurred.getPixel(x, y).rNormalized * 255).round();
      dodgeMap[y * w + x] =
          bv >= 255 ? 255 : (gv * 255 / (255 - bv)).clamp(0.0, 255.0).round();
    }
  }
  const lineThresh = 230;
  const darkOrigThresh = 40;
  final colorTint = p.colorTint;
  final result = img.Image(width: w, height: h);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final dodge = dodgeMap[y * w + x];
      final origGray = (gray.getPixel(x, y).rNormalized * 255).round();
      if (dodge < lineThresh && origGray >= darkOrigThresh) {
        result.setPixelRgb(x, y, 0, 0, 0);
      } else {
        final orig = decoded.getPixel(x, y);
        final origR = (orig.rNormalized * 255).round();
        final origG = (orig.gNormalized * 255).round();
        final origB = (orig.bNormalized * 255).round();
        final r = (dodge * (1 - colorTint) + origR * colorTint).round().clamp(0, 255);
        final g = (dodge * (1 - colorTint) + origG * colorTint).round().clamp(0, 255);
        final b = (dodge * (1 - colorTint) + origB * colorTint).round().clamp(0, 255);
        result.setPixelRgb(x, y, r, g, b);
      }
    }
  }
  return Uint8List.fromList(img.encodeJpg(result, quality: 90));
}

class RecordOverlayScreen extends StatefulWidget {
  final XFile bgImage;
  final RunningRecord record;
  final LabelLanguage language;

  const RecordOverlayScreen({
    super.key,
    required this.bgImage,
    required this.record,
    required this.language,
  });

  @override
  State<RecordOverlayScreen> createState() => _RecordOverlayScreenState();
}

class _RecordOverlayScreenState extends State<RecordOverlayScreen> {
  final ScreenshotController _sc = ScreenshotController();

  OverlayTemplate _template = OverlayTemplate.poster;
  Color _textColor = const Color(0xFF1C1C1E);
  String _font = 'Nanum Pen Script';
  bool _showHeartRate = true;
  bool _individualDrag = false;

  late final ValueNotifier<({Offset pos, double width})> _overlayNotifier;
  late final Map<String, ValueNotifier<Offset>> _itemPositions;

  Size _dispSize = Size.zero;

  // ── Background effect ─────────────────────────────────────────────────────
  _BgEffect _bgEffect = _BgEffect.none;
  Uint8List? _bgEffectBytes;
  bool _bgProcessing = false;
  double _sketchSharpness = 5.0;
  double _colorTintValue = 0.35;

  String _t(String ko, String en) =>
      widget.language == LabelLanguage.korean ? ko : en;

  @override
  void initState() {
    super.initState();
    _overlayNotifier = ValueNotifier((pos: const Offset(0.05, 0.05), width: 0.55));
    _itemPositions = {
      'dist': ValueNotifier(Offset.zero),
      'time': ValueNotifier(Offset.zero),
      'pace': ValueNotifier(Offset.zero),
      'hr':   ValueNotifier(Offset.zero),
    };
  }

  @override
  void dispose() {
    _overlayNotifier.dispose();
    for (final n in _itemPositions.values) n.dispose();
    super.dispose();
  }

  // ── Card drag ────────────────────────────────────────────────────────────
  void _onDrag(DragUpdateDetails d) {
    if (_dispSize == Size.zero) return;
    final ov = _overlayNotifier.value;
    _overlayNotifier.value = (
      pos: Offset(
        ov.pos.dx + d.delta.dx / _dispSize.width,
        ov.pos.dy + d.delta.dy / _dispSize.height,
      ),
      width: ov.width,
    );
  }

  // ── Individual item drag ─────────────────────────────────────────────────
  void _onItemDrag(String key, DragUpdateDetails d) {
    if (_dispSize == Size.zero) return;
    final pos = _itemPositions[key]!.value;
    _itemPositions[key]!.value = Offset(
      pos.dx + d.delta.dx / _dispSize.width,
      pos.dy + d.delta.dy / _dispSize.height,
    );
  }

  // ── Compute initial positions to match current template layout ────────────
  void _setInitialPositions() {
    final ov = _overlayNotifier.value;
    final dW = _dispSize.width;
    final dH = _dispSize.height;
    if (dW == 0 || dH == 0) return;

    final ox = ov.pos.dx;  // card left (normalized)
    final oy = ov.pos.dy;  // card top (normalized)
    final w  = ov.width;   // card width (normalized fraction of dW)
    final ratio = getOverlayCardAspectRatio(_template);
    final h = w * dW / (ratio * dH); // card height (normalized fraction of dH)

    // Converts card-relative fractions → absolute normalized screen coords
    Offset at(double fx, double fy) => Offset(ox + fx * w, oy + fy * h);

    final active = _activeItems();
    final statsItems = active.where((e) => e.key != 'dist').toList();
    final allKeys   = active.map((e) => e.key).toList();
    final sN = statsItems.length;
    final aN = allKeys.length;

    switch (_template) {
      case OverlayTemplate.poster:
        // dist: top-left of card content (ref: left=20/400, dist top≈10/133)
        _itemPositions['dist']!.value = at(0.05, 0.08);
        // stats: spaceEvenly row below dist (ref: top≈94/133 ≈ 0.71)
        for (int i = 0; i < sN; i++) {
          _itemPositions[statsItems[i].key]!.value =
              at(0.05 + i * 0.90 / sN, 0.71);
        }

      case OverlayTemplate.wide:
        // All items in a horizontal row, centered vertically
        for (int i = 0; i < aN; i++) {
          _itemPositions[allKeys[i]]!.value = at(i * 1.0 / aN + 0.02, 0.20);
        }

      case OverlayTemplate.tall:
        // dist: top, stats: horizontal row below (ref: top≈120/167 ≈ 0.72)
        _itemPositions['dist']!.value = at(0.05, 0.06);
        for (int i = 0; i < sN; i++) {
          _itemPositions[statsItems[i].key]!.value =
              at(0.05 + i * 0.90 / sN, 0.72);
        }

      case OverlayTemplate.list:
        // All items stacked vertically, equal vertical spacing
        for (int i = 0; i < aN; i++) {
          _itemPositions[allKeys[i]]!.value = at(0.05, (i + 0.5) / aN);
        }

      case OverlayTemplate.grid:
        // col1=[dist,time] left, col2=[pace,hr] right
        _itemPositions['dist']!.value = at(0.05, 0.25);
        _itemPositions['time']!.value = at(0.05, 0.62);
        _itemPositions['pace']!.value = at(0.53, 0.25);
        _itemPositions['hr']!.value   = at(0.53, 0.62);
    }
  }

  // ── Toggle individual drag ────────────────────────────────────────────────
  void _toggleIndividualDrag() {
    if (!_individualDrag) _setInitialPositions();
    setState(() => _individualDrag = !_individualDrag);
  }

  Future<void> _applyBgEffect(_BgEffect effect) async {
    setState(() { _bgEffect = effect; _bgProcessing = true; });
    if (effect == _BgEffect.none) {
      setState(() { _bgEffectBytes = null; _bgProcessing = false; });
      return;
    }
    try {
      final bytes = await File(widget.bgImage.path).readAsBytes();
      final Uint8List result;
      if (effect == _BgEffect.colorSketch) {
        result = await compute(_colorSketchTask, _ColorSketchParams(bytes, _colorTintValue));
      } else {
        final blurRadius = (22 - _sketchSharpness * 2).clamp(4, 20).round();
        result = await compute(_sketchEffectTask, _SketchParams(bytes, blurRadius));
      }
      if (mounted) setState(() { _bgEffectBytes = result; _bgProcessing = false; });
    } catch (_) {
      if (mounted) setState(() { _bgProcessing = false; });
    }
  }

  // ── Active stat items ─────────────────────────────────────────────────────
  List<({String key, String value, String label})> _activeItems() {
    final dist = widget.record.distance.replaceAll(RegExp(r'\s*km'), '').trim();
    final isKo = widget.language == LabelLanguage.korean;
    return [
      if (dist.isNotEmpty)
        (key: 'dist', value: '$dist km', label: isKo ? '거리' : 'DIST'),
      if (widget.record.time.isNotEmpty)
        (key: 'time', value: widget.record.time, label: isKo ? '시간' : 'TIME'),
      if (widget.record.pace.isNotEmpty)
        (key: 'pace', value: widget.record.pace, label: isKo ? '페이스' : 'PACE'),
      if (widget.record.heartRate.isNotEmpty && _showHeartRate)
        (key: 'hr', value: widget.record.heartRate, label: isKo ? '심박' : 'HR'),
    ];
  }

  // ── Individual stat item — styled exactly like current template ───────────
  // scale = ov.width * dW / _kRefWidth  (same FittedBox scale as card mode)
  Widget _buildStatItem(String key, String value, String label, double scale) {
    final shadows = _textColor.computeLuminance() > 0.5
        ? [const Shadow(blurRadius: 6, color: Colors.black54, offset: Offset(0.5, 0.5))]
        : <Shadow>[];

    final distNum = value.replaceAll(' km', '').trim();

    switch (_template) {
      // ── Poster: dist = large number+km, others = value/label column ────
      case OverlayTemplate.poster:
        if (key == 'dist') {
          return Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(distNum,
                  style: overlayTs(_font, fontSize: 74 * scale,
                      fontWeight: FontWeight.w900, color: _textColor,
                      height: 1.0, shadows: shadows)),
              SizedBox(width: 5 * scale),
              Padding(
                padding: EdgeInsets.only(bottom: 6 * scale),
                child: Text('km',
                    style: overlayTs(_font, fontSize: 17 * scale,
                        fontWeight: FontWeight.w700, color: _textColor,
                        shadows: shadows)),
              ),
            ],
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(value,
                style: overlayTs(_font, fontSize: 24 * scale,
                    fontWeight: FontWeight.w800, color: _textColor, shadows: shadows)),
            SizedBox(height: 2 * scale),
            Text(label,
                style: overlayTs(_font, fontSize: 11 * scale,
                    fontWeight: FontWeight.w600, color: _textColor,
                    letterSpacing: 0.5, shadows: shadows)),
          ],
        );

      // ── Wide: all items = value/label column ────────────────────────────
      case OverlayTemplate.wide:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(value,
                style: overlayTs(_font, fontSize: 19 * scale,
                    fontWeight: FontWeight.w800, color: _textColor, shadows: shadows)),
            SizedBox(height: 2 * scale),
            Text(label,
                style: overlayTs(_font, fontSize: 11 * scale,
                    fontWeight: FontWeight.w600, color: _textColor,
                    letterSpacing: 0.5, shadows: shadows)),
          ],
        );

      // ── Tall: dist = very large number+km, others = value/label column ──
      case OverlayTemplate.tall:
        if (key == 'dist') {
          return Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(distNum,
                  style: overlayTs(_font, fontSize: 106 * scale,
                      fontWeight: FontWeight.w900, color: _textColor,
                      height: 1.0, shadows: shadows)),
              SizedBox(width: 5 * scale),
              Padding(
                padding: EdgeInsets.only(bottom: 7 * scale),
                child: Text('km',
                    style: overlayTs(_font, fontSize: 17 * scale,
                        fontWeight: FontWeight.w700, color: _textColor,
                        shadows: shadows)),
              ),
            ],
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(value,
                style: overlayTs(_font, fontSize: 22 * scale,
                    fontWeight: FontWeight.w800, color: _textColor, shadows: shadows)),
            SizedBox(height: 2 * scale),
            Text(label,
                style: overlayTs(_font, fontSize: 11 * scale,
                    fontWeight: FontWeight.w600, color: _textColor,
                    letterSpacing: 0.5, shadows: shadows)),
          ],
        );

      // ── List: label | value horizontal row ──────────────────────────────
      case OverlayTemplate.list:
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(label,
                style: overlayTs(_font, fontSize: 11 * scale,
                    fontWeight: FontWeight.w600, color: _textColor,
                    letterSpacing: 0.5, shadows: shadows)),
            SizedBox(width: 10 * scale),
            Text(value,
                style: overlayTs(_font, fontSize: 22 * scale,
                    fontWeight: FontWeight.w800, color: _textColor, shadows: shadows)),
          ],
        );

      // ── Grid: value/label column, left-aligned ───────────────────────────
      case OverlayTemplate.grid:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: overlayTs(_font, fontSize: 19 * scale,
                    fontWeight: FontWeight.w800, color: _textColor, shadows: shadows)),
            SizedBox(height: 2 * scale),
            Text(label,
                style: overlayTs(_font, fontSize: 10 * scale,
                    fontWeight: FontWeight.w600, color: _textColor,
                    letterSpacing: 0.5, shadows: shadows)),
          ],
        );
    }
  }

  Future<void> _save() async {
    showSavingDialog(context);
    try {
      final bytes = await _sc.capture(pixelRatio: 3.0);
      if (bytes == null) { hideSavingDialog(context); return; }
      final tmp = await getTemporaryDirectory();
      final file = File('${tmp.path}/rp_overlay_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes);
      await Gal.putImage(file.path, album: 'PaceGraphy');
      await file.delete();
      if (mounted) hideSavingDialog(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_t('사진첩에 저장되었습니다!', 'Saved to photo library!'),
              style: const TextStyle(color: Color(0xFF1C1C1E), fontWeight: FontWeight.w600)),
          backgroundColor: Colors.white,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) hideSavingDialog(context);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${_t('저장 실패', 'Save failed')}: $e'),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('PaceGraphy',
              style: TextStyle(fontFamily: 'SUIT', color: Colors.white,
                  fontWeight: FontWeight.w700, fontSize: 18, letterSpacing: 1.0)),
          Text(_t('기록 사진 생성', 'Create Record Photo'),
              style: const TextStyle(fontFamily: 'SUIT', color: Color(0xFF8E8E93),
                  fontWeight: FontWeight.w500, fontSize: 11)),
        ]),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _save,
            child: Text(_t('저장', 'Save'),
                style: const TextStyle(color: Colors.white,
                    fontWeight: FontWeight.w700, fontSize: 15)),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Photo + overlay ──
          Expanded(
            child: LayoutBuilder(builder: (context, constraints) {
              final maxW = constraints.maxWidth;
              final maxH = constraints.maxHeight;

              final img = File(widget.bgImage.path);
              return FutureBuilder<Size>(
                future: _getImageSize(img),
                builder: (context, snap) {
                  final photoAR = snap.hasData
                      ? snap.data!.width / snap.data!.height
                      : 9.0 / 16.0;

                  double dW, dH;
                  if (maxW / maxH < photoAR) {
                    dW = maxW; dH = maxW / photoAR;
                  } else {
                    dH = maxH; dW = maxH * photoAR;
                  }
                  _dispSize = Size(dW, dH);

                  return Center(
                    child: SizedBox(
                      width: dW, height: dH,
                      child: GestureDetector(
                        onPanUpdate: _individualDrag ? null : _onDrag,
                        behavior: HitTestBehavior.opaque,
                        child: Stack(children: [
                          Screenshot(
                            controller: _sc,
                            child: Stack(children: [
                              Positioned.fill(
                                child: _bgEffectBytes != null
                                    ? Image.memory(_bgEffectBytes!, fit: BoxFit.cover)
                                    : Image.file(img, fit: BoxFit.cover),
                              ),

                              // ── Card mode ──
                              if (!_individualDrag)
                                ValueListenableBuilder(
                                  valueListenable: _overlayNotifier,
                                  builder: (_, ov, __) {
                                    final ratio = getOverlayCardAspectRatio(_template);
                                    final cardW = dW * ov.width;
                                    final cardH = cardW / ratio;
                                    return Positioned(
                                      left: ov.pos.dx * dW,
                                      top: ov.pos.dy * dH,
                                      width: cardW,
                                      height: cardH,
                                      child: FittedBox(
                                        fit: BoxFit.fill,
                                        child: SizedBox(
                                          width: _kRefWidth,
                                          height: _kRefWidth / ratio,
                                          child: buildOverlayCard(
                                            _template, widget.record,
                                            _textColor, _font, widget.language,
                                            showHeartRate: _showHeartRate,
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),

                              // ── Individual drag mode ──
                              // Each item uses the same visual style as the template.
                              // scale = ov.width * dW / _kRefWidth matches card FittedBox scale.
                              if (_individualDrag)
                                ..._activeItems().map((item) {
                                  final posN = _itemPositions[item.key]!;
                                  return ValueListenableBuilder<Offset>(
                                    valueListenable: posN,
                                    builder: (_, pos, __) => Positioned(
                                      left: pos.dx * dW,
                                      top: pos.dy * dH,
                                      child: GestureDetector(
                                        onPanUpdate: (d) => _onItemDrag(item.key, d),
                                        child: ValueListenableBuilder(
                                          valueListenable: _overlayNotifier,
                                          builder: (_, ov, __) => _buildStatItem(
                                            item.key, item.value, item.label,
                                            ov.width * dW / _kRefWidth,
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                }),
                            ]),
                          ),

                          // ── Hint text (not captured) ──
                          Positioned(
                            bottom: 10, left: 0, right: 0,
                            child: IgnorePointer(
                              child: Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: Colors.black45,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Text(
                                    _individualDrag
                                        ? _t('각 항목을 드래그하여 위치 조절', 'Drag each item to reposition')
                                        : _t('드래그하여 기록 위치 조절', 'Drag to reposition'),
                                    style: const TextStyle(
                                      fontFamily: 'SUIT',
                                      color: Colors.white70,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ]),
                      ),
                    ),
                  );
                },
              );
            }),
          ),

          // ── Controls ──
          Container(
            color: const Color(0xFF1C1C1E),
            padding: const EdgeInsets.fromLTRB(0, 12, 0, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Template chips
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  children: OverlayTemplate.values.map((t) {
                    final labels = {
                      OverlayTemplate.poster: _t('포스터', 'Poster'),
                      OverlayTemplate.wide:   _t('가로형', 'Wide'),
                      OverlayTemplate.tall:   _t('세로형', 'Tall'),
                      OverlayTemplate.list:   _t('리스트', 'List'),
                      OverlayTemplate.grid:   _t('그리드', 'Grid'),
                    };
                    final selected = _template == t;
                    return GestureDetector(
                      onTap: () => setState(() => _template = t),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: selected ? Colors.white : const Color(0xFF2C2C2E),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(labels[t]!,
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                                color: selected ? const Color(0xFF1C1C1E) : const Color(0xFF8E8E93))),
                      ),
                    );
                  }).toList(),
                ),
              ),

              const SizedBox(height: 12),

              // Color + Font row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(children: [
                  ...[const Color(0xFF1C1C1E), Colors.white].map((c) {
                    final sel = _textColor == c;
                    final isWhite = c == Colors.white;
                    return GestureDetector(
                      onTap: () => setState(() => _textColor = c),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: sel ? Colors.white : const Color(0xFF2C2C2E),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: sel ? Colors.white : const Color(0xFF3C3C3E),
                          ),
                        ),
                        child: Text(isWhite ? _t('흰색', 'White') : _t('검정', 'Black'),
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                                color: sel ? const Color(0xFF1C1C1E) : const Color(0xFF8E8E93))),
                      ),
                    );
                  }),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SizedBox(
                      height: 28,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: kRunCardFonts.map((f) {
                          final sel = _font == f;
                          return GestureDetector(
                            onTap: () => setState(() => _font = f),
                            child: Container(
                              margin: const EdgeInsets.only(right: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: sel ? Colors.white : const Color(0xFF2C2C2E),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(f.split(' ').first,
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                                      color: sel ? const Color(0xFF1C1C1E) : const Color(0xFF8E8E93))),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ]),
              ),

              const SizedBox(height: 8),

              // Size slider
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(children: [
                  Text(_t('크기', 'Size'),
                      style: const TextStyle(fontSize: 11, color: Color(0xFF8E8E93),
                          fontWeight: FontWeight.w600)),
                  Expanded(
                    child: ValueListenableBuilder(
                      valueListenable: _overlayNotifier,
                      builder: (_, ov, __) => SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 2,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                          activeTrackColor: Colors.white,
                          inactiveTrackColor: const Color(0xFF3C3C3E),
                          thumbColor: Colors.white,
                          overlayColor: Colors.white24,
                        ),
                        child: Slider(
                          value: ov.width.clamp(0.2, 0.95),
                          min: 0.2, max: 0.95,
                          onChanged: (v) {
                            _overlayNotifier.value = (pos: ov.pos, width: v);
                          },
                        ),
                      ),
                    ),
                  ),
                ]),
              ),

              const SizedBox(height: 8),

              // Heart rate + Individual drag row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(children: [
                  Text(_t('심박수', 'HR'),
                      style: const TextStyle(fontSize: 11, color: Color(0xFF8E8E93),
                          fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => setState(() => _showHeartRate = !_showHeartRate),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: _showHeartRate ? Colors.white : const Color(0xFF2C2C2E),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _showHeartRate ? Colors.white : const Color(0xFF3C3C3E),
                        ),
                      ),
                      child: Text(_showHeartRate ? _t('표시', 'Show') : _t('숨김', 'Hide'),
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                              color: _showHeartRate ? const Color(0xFF1C1C1E) : const Color(0xFF8E8E93))),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(_t('개별 드래그', 'Free Place'),
                      style: const TextStyle(fontSize: 11, color: Color(0xFF8E8E93),
                          fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _toggleIndividualDrag,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: _individualDrag ? Colors.white : const Color(0xFF2C2C2E),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _individualDrag ? Colors.white : const Color(0xFF3C3C3E),
                        ),
                      ),
                      child: Text(_individualDrag ? _t('켜짐', 'ON') : _t('꺼짐', 'OFF'),
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                              color: _individualDrag ? const Color(0xFF1C1C1E) : const Color(0xFF8E8E93))),
                    ),
                  ),
                ]),
              ),

              const SizedBox(height: 8),

              // BG Effect row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(children: [
                  Text(_t('배경 효과', 'BG Effect'),
                      style: const TextStyle(fontSize: 11, color: Color(0xFF8E8E93),
                          fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  if (_bgProcessing)
                    const SizedBox(width: 14, height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  else ...[
                    _bgEffectChip(_t('없음', 'None'), _BgEffect.none),
                    const SizedBox(width: 6),
                    _bgEffectChip(_t('스케치', 'Sketch'), _BgEffect.sketch),
                    const SizedBox(width: 6),
                    _bgEffectChip(_t('채색', 'Color'), _BgEffect.colorSketch),
                  ],
                ]),
              ),
              if (_bgEffect == _BgEffect.sketch && !_bgProcessing) ...[
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(children: [
                    Text(_t('선명도', 'Sharpness'),
                        style: const TextStyle(fontSize: 11, color: Color(0xFF8E8E93))),
                    Expanded(child: _darkSlider(
                      _sketchSharpness, 1, 10,
                      (v) => setState(() => _sketchSharpness = v),
                      onEnd: (_) => _applyBgEffect(_BgEffect.sketch),
                    )),
                    SizedBox(width: 28, child: Text(_sketchSharpness.round().toString(),
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white))),
                  ]),
                ),
              ],
              if (_bgEffect == _BgEffect.colorSketch && !_bgProcessing) ...[
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(children: [
                    Text(_t('색 강도', 'Color'),
                        style: const TextStyle(fontSize: 11, color: Color(0xFF8E8E93))),
                    Expanded(child: _darkSlider(
                      _colorTintValue, 0.1, 0.6,
                      (v) => setState(() => _colorTintValue = v),
                      onEnd: (_) => _applyBgEffect(_BgEffect.colorSketch),
                    )),
                    SizedBox(width: 28, child: Text('${(_colorTintValue * 100).round()}%',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white))),
                  ]),
                ),
              ],

              const SizedBox(height: 8),
              SizedBox(height: MediaQuery.of(context).padding.bottom),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _bgEffectChip(String label, _BgEffect effect) {
    final selected = _bgEffect == effect;
    return GestureDetector(
      onTap: () => _applyBgEffect(effect),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? Colors.white : const Color(0xFF2C2C2E),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(label, style: TextStyle(
          fontSize: 12, fontWeight: FontWeight.w600,
          color: selected ? const Color(0xFF1C1C1E) : const Color(0xFF8E8E93),
        )),
      ),
    );
  }

  Widget _darkSlider(double value, double min, double max, ValueChanged<double> onChanged,
      {ValueChanged<double>? onEnd}) {
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 2,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
        activeTrackColor: Colors.white,
        inactiveTrackColor: const Color(0xFF3C3C3E),
        thumbColor: Colors.white,
        overlayColor: Colors.white24,
      ),
      child: Slider(value: value, min: min, max: max, onChanged: onChanged, onChangeEnd: onEnd),
    );
  }

  Future<Size> _getImageSize(File file) async {
    final bytes = await file.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return Size(frame.image.width.toDouble(), frame.image.height.toDouble());
  }
}
