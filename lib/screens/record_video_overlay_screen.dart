import 'dart:io';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:screenshot/screenshot.dart';
import 'package:video_player/video_player.dart';
import '../models/running_record.dart';
import '../models/overlay_style.dart';
import '../widgets/running_cards.dart';

const double _kRefWidth = 257.0; // 400 / 1.56 → 같은 슬라이더 위치에서 텍스트 1.56배

class RecordVideoOverlayScreen extends StatefulWidget {
  final XFile video;
  final RunningRecord record;
  final LabelLanguage language;
  final double? outputRatio; // null = 원본 비율

  const RecordVideoOverlayScreen({
    super.key,
    required this.video,
    required this.record,
    required this.language,
    this.outputRatio,
  });

  @override
  State<RecordVideoOverlayScreen> createState() =>
      _RecordVideoOverlayScreenState();
}

// Snapshot of editable UI state for undo/redo.
typedef _VSnap = ({
  OverlayTemplate template,
  Color textColor,
  String font,
  ({Offset pos, double width}) overlay,
  double memoFontSize,
});

class _RecordVideoOverlayScreenState extends State<RecordVideoOverlayScreen> {
  // ── Video ────────────────────────────────────────────────────────────────
  VideoPlayerController? _vpc;
  bool _videoReady = false;
  Size _videoSize = Size.zero;

  // ── Overlay state (same as photo overlay screen) ──────────────────────
  OverlayTemplate _template = OverlayTemplate.poster;
  Color _textColor = const Color(0xFF1C1C1E);
  String _font = 'Nanum Pen Script';
  bool _showHeartRate = true;
  double _memoFontSize = 18.0;
  bool get _individualDrag => _template == OverlayTemplate.custom;

  late final ValueNotifier<({Offset pos, double width})> _overlayNotifier;
  late final Map<String, ValueNotifier<Offset>> _itemPositions;
  late final ValueNotifier<Offset> _memoPosition;
  Size _dispSize = Size.zero;

  // ── Saving ───────────────────────────────────────────────────────────────
  bool _saving = false;

  // ── Undo / Redo ──────────────────────────────────────────────────────────
  final List<_VSnap> _undoStack = [];
  final List<_VSnap> _redoStack = [];

  _VSnap _snap() => (
    template: _template,
    textColor: _textColor,
    font: _font,
    overlay: _overlayNotifier.value,
    memoFontSize: _memoFontSize,
  );

  void _push() {
    _undoStack.add(_snap());
    if (_undoStack.length > 50) _undoStack.removeAt(0);
    _redoStack.clear();
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(_snap());
    final s = _undoStack.removeLast();
    _overlayNotifier.value = s.overlay;
    setState(() {
      _template = s.template;
      _textColor = s.textColor;
      _font = s.font;
      _memoFontSize = s.memoFontSize;
    });
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(_snap());
    final s = _redoStack.removeLast();
    _overlayNotifier.value = s.overlay;
    setState(() {
      _template = s.template;
      _textColor = s.textColor;
      _font = s.font;
      _memoFontSize = s.memoFontSize;
    });
  }

  String _t(String ko, String en) =>
      widget.language == LabelLanguage.korean ? ko : en;

  @override
  void initState() {
    super.initState();
    _overlayNotifier =
        ValueNotifier((pos: const Offset(0.05, 0.05), width: 0.66));
    _itemPositions = {
      'dist': ValueNotifier(Offset.zero),
      'time': ValueNotifier(Offset.zero),
      'pace': ValueNotifier(Offset.zero),
      'hr': ValueNotifier(Offset.zero),
    };
    _memoPosition = ValueNotifier(const Offset(0.05, 0.80));
    _initVideo();
  }

  Future<void> _initVideo() async {
    final controller =
        VideoPlayerController.file(File(widget.video.path));
    await controller.initialize();
    if (!mounted) { controller.dispose(); return; }
    controller.setLooping(true);
    controller.play();
    setState(() {
      _vpc = controller;
      _videoSize = controller.value.size;
      _videoReady = true;
    });
  }

  @override
  void dispose() {
    _vpc?.dispose();
    _overlayNotifier.dispose();
    for (final n in _itemPositions.values) n.dispose();
    _memoPosition.dispose();
    super.dispose();
  }

  // ── Card drag ────────────────────────────────────────────────────────────
  void _onDragStart(DragStartDetails _) {
    _push();
    setState(() {});
  }

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

  // ── Memo drag ────────────────────────────────────────────────────────────
  void _onMemoDrag(DragUpdateDetails d) {
    if (_dispSize == Size.zero) return;
    final pos = _memoPosition.value;
    _memoPosition.value = Offset(
      pos.dx + d.delta.dx / _dispSize.width,
      pos.dy + d.delta.dy / _dispSize.height,
    );
  }

  // ── Set initial positions matching template layout ────────────────────────
  void _setInitialPositions() {
    final ov = _overlayNotifier.value;
    final dW = _dispSize.width;
    final dH = _dispSize.height;
    if (dW == 0 || dH == 0) return;

    final ox = ov.pos.dx;
    final oy = ov.pos.dy;
    final w = ov.width;
    final ratio = getOverlayCardAspectRatio(_template);
    final h = w * dW / (ratio * dH);

    Offset at(double fx, double fy) => Offset(ox + fx * w, oy + fy * h);

    final active = _activeItems();
    final statsItems = active.where((e) => e.key != 'dist').toList();
    final allKeys = active.map((e) => e.key).toList();
    final sN = statsItems.length;
    final aN = allKeys.length;

    switch (_template) {
      case OverlayTemplate.poster:
      case OverlayTemplate.classic:
        _itemPositions['dist']!.value = at(0.05, 0.08);
        for (int i = 0; i < sN; i++) {
          _itemPositions[statsItems[i].key]!.value =
              at(0.05 + i * 0.90 / sN, 0.71);
        }
      case OverlayTemplate.wide:
        for (int i = 0; i < aN; i++) {
          _itemPositions[allKeys[i]]!.value = at(i * 1.0 / aN + 0.02, 0.20);
        }
      case OverlayTemplate.tall:
        _itemPositions['dist']!.value = at(0.05, 0.06);
        for (int i = 0; i < sN; i++) {
          _itemPositions[statsItems[i].key]!.value =
              at(0.05 + i * 0.90 / sN, 0.72);
        }
      case OverlayTemplate.list:
        for (int i = 0; i < aN; i++) {
          _itemPositions[allKeys[i]]!.value = at(0.05, (i + 0.5) / aN);
        }
      case OverlayTemplate.grid:
        _itemPositions['dist']!.value = at(0.05, 0.25);
        _itemPositions['time']!.value = at(0.05, 0.62);
        _itemPositions['pace']!.value = at(0.53, 0.25);
        _itemPositions['hr']!.value = at(0.53, 0.62);

      case OverlayTemplate.custom:
        for (int i = 0; i < aN; i++) {
          _itemPositions[allKeys[i]]!.value = at(0.05, (i + 0.5) / aN);
        }
    }
  }

  // ── Active items ─────────────────────────────────────────────────────────
  List<({String key, String value, String label})> _activeItems() {
    final dist =
        widget.record.distance.replaceAll(RegExp(r'\s*km'), '').trim();
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

  // ── Individual stat item styled to match template ─────────────────────────
  Widget _buildStatItem(String key, String value, String label, double scale) {
    final shadows = _textColor.computeLuminance() > 0.5
        ? [const Shadow(
            blurRadius: 6, color: Colors.black54, offset: Offset(0.5, 0.5))]
        : <Shadow>[];
    final distNum = value.replaceAll(' km', '').trim();

    switch (_template) {
      case OverlayTemplate.poster:
        if (key == 'dist') {
          return Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(distNum,
                  style: overlayTs(_font,
                      fontSize: 74 * scale,
                      fontWeight: FontWeight.w900,
                      color: _textColor,
                      height: 1.0,
                      shadows: shadows)),
              SizedBox(width: 5 * scale),
              Padding(
                padding: EdgeInsets.only(bottom: 6 * scale),
                child: Text('km',
                    style: overlayTs(_font,
                        fontSize: 17 * scale,
                        fontWeight: FontWeight.w700,
                        color: _textColor,
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
                style: overlayTs(_font,
                    fontSize: 26 * scale,
                    fontWeight: FontWeight.w800,
                    color: _textColor,
                    shadows: shadows)),
            SizedBox(height: 2 * scale),
            Text(label,
                style: overlayTs(_font,
                    fontSize: 11 * scale,
                    fontWeight: FontWeight.w600,
                    color: _textColor,
                    letterSpacing: 0.5,
                    shadows: shadows)),
          ],
        );
      case OverlayTemplate.classic:
        if (key == 'dist') {
          return Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(distNum,
                  style: overlayTs(_font,
                      fontSize: 111 * scale,
                      fontWeight: FontWeight.w900,
                      color: _textColor,
                      height: 1.0,
                      shadows: shadows)),
              SizedBox(width: 5 * scale),
              Padding(
                padding: EdgeInsets.only(bottom: 6 * scale),
                child: Text('km',
                    style: overlayTs(_font,
                        fontSize: 26 * scale,
                        fontWeight: FontWeight.w700,
                        color: _textColor,
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
                style: overlayTs(_font,
                    fontSize: 26 * scale,
                    fontWeight: FontWeight.w800,
                    color: _textColor,
                    shadows: shadows)),
            SizedBox(height: 2 * scale),
            Text(label,
                style: overlayTs(_font,
                    fontSize: 11 * scale,
                    fontWeight: FontWeight.w600,
                    color: _textColor,
                    letterSpacing: 0.5,
                    shadows: shadows)),
          ],
        );
      case OverlayTemplate.wide:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(value,
                style: overlayTs(_font,
                    fontSize: 26 * scale,
                    fontWeight: FontWeight.w800,
                    color: _textColor,
                    shadows: shadows)),
            SizedBox(height: 2 * scale),
            Text(label,
                style: overlayTs(_font,
                    fontSize: 11 * scale,
                    fontWeight: FontWeight.w600,
                    color: _textColor,
                    letterSpacing: 0.5,
                    shadows: shadows)),
          ],
        );
      case OverlayTemplate.tall:
        if (key == 'dist') {
          return Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(distNum,
                  style: overlayTs(_font,
                      fontSize: 106 * scale,
                      fontWeight: FontWeight.w900,
                      color: _textColor,
                      height: 1.0,
                      shadows: shadows)),
              SizedBox(width: 5 * scale),
              Padding(
                padding: EdgeInsets.only(bottom: 7 * scale),
                child: Text('km',
                    style: overlayTs(_font,
                        fontSize: 17 * scale,
                        fontWeight: FontWeight.w700,
                        color: _textColor,
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
                style: overlayTs(_font,
                    fontSize: 22 * scale,
                    fontWeight: FontWeight.w800,
                    color: _textColor,
                    shadows: shadows)),
            SizedBox(height: 2 * scale),
            Text(label,
                style: overlayTs(_font,
                    fontSize: 11 * scale,
                    fontWeight: FontWeight.w600,
                    color: _textColor,
                    letterSpacing: 0.5,
                    shadows: shadows)),
          ],
        );
      case OverlayTemplate.list:
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(label,
                style: overlayTs(_font,
                    fontSize: 26 * scale,
                    fontWeight: FontWeight.w600,
                    color: _textColor,
                    letterSpacing: 0.5,
                    shadows: shadows)),
            SizedBox(width: 12 * scale),
            Text(value,
                style: overlayTs(_font,
                    fontSize: 26 * scale,
                    fontWeight: FontWeight.w800,
                    color: _textColor,
                    shadows: shadows)),
          ],
        );
      case OverlayTemplate.grid:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: overlayTs(_font,
                    fontSize: 19 * scale,
                    fontWeight: FontWeight.w800,
                    color: _textColor,
                    shadows: shadows)),
            SizedBox(height: 2 * scale),
            Text(label,
                style: overlayTs(_font,
                    fontSize: 10 * scale,
                    fontWeight: FontWeight.w600,
                    color: _textColor,
                    letterSpacing: 0.5,
                    shadows: shadows)),
          ],
        );

      case OverlayTemplate.custom:
        if (key == 'dist') {
          return Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(distNum,
                  style: overlayTs(_font,
                      fontSize: 74 * scale,
                      fontWeight: FontWeight.w900,
                      color: _textColor,
                      height: 1.0,
                      shadows: shadows)),
              SizedBox(width: 5 * scale),
              Padding(
                padding: EdgeInsets.only(bottom: 6 * scale),
                child: Text('km',
                    style: overlayTs(_font,
                        fontSize: 17 * scale,
                        fontWeight: FontWeight.w700,
                        color: _textColor,
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
                style: overlayTs(_font,
                    fontSize: 26 * scale,
                    fontWeight: FontWeight.w800,
                    color: _textColor,
                    shadows: shadows)),
            SizedBox(height: 2 * scale),
            Text(label,
                style: overlayTs(_font,
                    fontSize: 11 * scale,
                    fontWeight: FontWeight.w600,
                    color: _textColor,
                    letterSpacing: 0.5,
                    shadows: shadows)),
          ],
        );
    }
  }

  // ── Build overlay widget at display size (for FFmpeg capture) ─────────────
  // Captured with pixelRatio = videoW / dispW → output = exact video resolution.
  Widget _buildDisplayOverlay() {
    final ov = _overlayNotifier.value;
    final dW = _dispSize.width;
    final dH = _dispSize.height;
    final ratio = getOverlayCardAspectRatio(_template);
    final cardRefW = (_template == OverlayTemplate.poster || _template == OverlayTemplate.wide)
        ? _kRefWidth / 1.5
        : _kRefWidth;
    final textScale = ov.width * dW / cardRefW;

    return Material(
      color: Colors.transparent,
      child: SizedBox(
        width: dW,
        height: dH,
        child: Stack(clipBehavior: Clip.none, children: [
          if (!_individualDrag)
            Positioned(
              left: ov.pos.dx * dW,
              top: ov.pos.dy * dH,
              width: dW * ov.width,
              height: dW * ov.width / ratio,
              child: FittedBox(
                fit: BoxFit.fill,
                child: SizedBox(
                  width: cardRefW,
                  height: cardRefW / ratio,
                  child: buildOverlayCard(
                    _template, widget.record,
                    _textColor, _font, widget.language,
                    showHeartRate: _showHeartRate,
                  ),
                ),
              ),
            ),
          if (_individualDrag)
            ..._activeItems().map((item) {
              final pos = _itemPositions[item.key]!.value;
              return Positioned(
                left: pos.dx * dW,
                top: pos.dy * dH,
                child: _buildStatItem(
                    item.key, item.value, item.label, textScale),
              );
            }),

          // ── 메모 (캡처 포함) ──
          if (widget.record.memo.isNotEmpty)
            Positioned(
              left: _memoPosition.value.dx * dW,
              top: _memoPosition.value.dy * dH,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(Icons.directions_run,
                      color: _textColor,
                      size: _memoFontSize * 1.2),
                  const SizedBox(width: 4),
                  Text(
                    widget.record.memo,
                    style: overlayTs(_font,
                      fontSize: _memoFontSize,
                      fontWeight: FontWeight.w600,
                      color: _textColor,
                      shadows: const [],
                    ),
                  ),
                ],
              ),
            ),
        ]),
      ),
    );
  }

  // ── Save: capture overlay → FFmpeg composite ──────────────────────────────
  Future<void> _save() async {
    if (!_videoReady || _dispSize == Size.zero) return;
    setState(() => _saving = true);
    try {
      // 출력 사이즈 계산 (crop 방식: 업스케일 없이 중앙 잘라내기)
      final videoAR = _videoSize.width / _videoSize.height;
      final R = widget.outputRatio ?? videoAR;
      int outW, outH;
      if (widget.outputRatio == null) {
        // 원본 비율: 1920px 상한만 적용
        if (_videoSize.width > 1920) {
          outW = 1920;
          outH = (1920 / videoAR).round();
        } else {
          outW = _videoSize.width.toInt();
          outH = _videoSize.height.toInt();
        }
      } else {
        // Cover crop: videoAR >= R → 높이 기준 잘라내기, videoAR < R → 너비 기준 잘라내기
        if (videoAR >= R) {
          outH = _videoSize.height.toInt().clamp(1, 1920);
          outW = (outH * R).round();
        } else {
          outW = _videoSize.width.toInt().clamp(1, 1920);
          outH = (outW / R).round();
        }
      }
      if (outW % 2 != 0) outW += 1;
      if (outH % 2 != 0) outH += 1;

      // 오버레이 PNG 캡처 (출력 해상도 기준)
      final pr = (outW / _dispSize.width).clamp(0.5, 6.0);
      final overlayBytes = await ScreenshotController().captureFromWidget(
        _buildDisplayOverlay(),
        pixelRatio: pr,
        delay: const Duration(milliseconds: 300),
        context: context,
      );

      final tmp = await getTemporaryDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final overlayPath = '${tmp.path}/ovl_$ts.png';
      await File(overlayPath).writeAsBytes(overlayBytes);

      final outPath = '${tmp.path}/rp_video_$ts.mp4';

      // 비율 변환: crop(잘라내기), 원본이면 scale만
      final needsCrop = widget.outputRatio != null &&
          (videoAR - R).abs() > 0.01;
      final vidFilter = needsCrop
          ? '[0:v]crop=${outW}:${outH}:(iw-${outW})/2:(ih-${outH})/2[vid]'
          : '[0:v]scale=${outW}:${outH}[vid]';

      final useToolbox = Platform.isIOS;
      final session = await FFmpegKit.executeWithArguments([
        '-i', widget.video.path,
        '-i', overlayPath,
        '-filter_complex',
        '$vidFilter;[1:v]scale=${outW}:${outH}[ovl];[vid][ovl]overlay=0:0:format=auto,format=yuv420p[vout]',
        '-map', '[vout]',
        '-map', '0:a?',
        '-c:v', useToolbox ? 'h264_videotoolbox' : 'libx264',
        if (useToolbox) ...[ '-b:v', '8000k' ]
        else ...[ '-crf', '23', '-preset', 'ultrafast' ],
        '-c:a', 'copy',
        '-movflags', '+faststart',
        '-y', outPath,
      ]);
      final rc = await session.getReturnCode();

      await File(overlayPath).delete();

      if (!ReturnCode.isSuccess(rc)) {
        final log = await session.getOutput();
        throw Exception('FFmpeg error: $log');
      }

      await Gal.putVideo(outPath, album: 'PaceGraphy');
      await File(outPath).delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('사진첩에 저장되었습니다!',
              style: TextStyle(
                  color: Color(0xFF1C1C1E), fontWeight: FontWeight.w600)),
          backgroundColor: Colors.white,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${_t('저장 실패', 'Save failed')}: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: Color(0xFF1C1C1E), size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('PaceGraphy',
              style: TextStyle(
                  fontFamily: 'SUIT',
                  color: Color(0xFF1C1C1E),
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  letterSpacing: 1.0)),
          Text(_t('기록 영상 생성', 'Create Record Video'),
              style: const TextStyle(
                  fontFamily: 'SUIT',
                  color: Color(0xFF8E8E93),
                  fontWeight: FontWeight.w500,
                  fontSize: 11)),
        ]),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.undo_rounded,
                color: _undoStack.isEmpty ? const Color(0xFFCCCCCC) : const Color(0xFF1C1C1E),
                size: 22),
            onPressed: _undoStack.isEmpty ? null : _undo,
            tooltip: '실행 취소',
          ),
          IconButton(
            icon: Icon(Icons.redo_rounded,
                color: _redoStack.isEmpty ? const Color(0xFFCCCCCC) : const Color(0xFF1C1C1E),
                size: 22),
            onPressed: _redoStack.isEmpty ? null : _redo,
            tooltip: '다시 실행',
          ),
          _saving
              ? const Padding(
                  padding: EdgeInsets.only(right: 16),
                  child: Center(
                    child: SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                          color: Color(0xFF1C1C1E), strokeWidth: 2),
                    ),
                  ),
                )
              : TextButton(
                  onPressed: _save,
                  child: Text(_t('저장', 'Save'),
                      style: const TextStyle(
                          color: Color(0xFF1C1C1E),
                          fontWeight: FontWeight.w700,
                          fontSize: 15)),
                ),
        ],
      ),
      body: Column(
        children: [
          // ── Video + overlay ──
          Expanded(
            child: LayoutBuilder(builder: (context, constraints) {
              final maxW = constraints.maxWidth;
              final maxH = constraints.maxHeight;

              if (!_videoReady) {
                return const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                );
              }

              final videoAR = _videoSize.width / _videoSize.height;
              final displayAR = widget.outputRatio ?? videoAR;
              double dW, dH;
              if (maxW / maxH < displayAR) {
                dW = maxW; dH = maxW / displayAR;
              } else {
                dH = maxH; dW = maxH * displayAR;
              }
              _dispSize = Size(dW, dH);

              return Center(
                child: SizedBox(
                  width: dW, height: dH,
                  child: GestureDetector(
                    onPanStart: _individualDrag ? null : _onDragStart,
                    onPanUpdate: _individualDrag ? null : _onDrag,
                    onTap: () {
                      if (_vpc == null) return;
                      _vpc!.value.isPlaying
                          ? _vpc!.pause()
                          : _vpc!.play();
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Stack(clipBehavior: Clip.none, children: [
                      // ── Video preview (cover crop: 비율에 맞게 중앙 잘라내기) ──
                      if (widget.outputRatio != null)
                        Positioned.fill(
                          child: ClipRect(
                            child: OverflowBox(
                              alignment: Alignment.center,
                              minWidth:  videoAR >= widget.outputRatio! ? dH * videoAR : dW,
                              maxWidth:  videoAR >= widget.outputRatio! ? dH * videoAR : dW,
                              minHeight: videoAR >= widget.outputRatio! ? dH : dW / videoAR,
                              maxHeight: videoAR >= widget.outputRatio! ? dH : dW / videoAR,
                              child: VideoPlayer(_vpc!),
                            ),
                          ),
                        )
                      else
                        Positioned.fill(child: VideoPlayer(_vpc!)),

                      // ── Card mode ──
                      if (!_individualDrag)
                        ValueListenableBuilder(
                          valueListenable: _overlayNotifier,
                          builder: (_, ov, __) {
                            final ratio =
                                getOverlayCardAspectRatio(_template);
                            final cardW = dW * ov.width;
                            final cardH = cardW / ratio;
                            final refW = (_template == OverlayTemplate.poster || _template == OverlayTemplate.wide)
                                ? _kRefWidth / 1.5
                                : _kRefWidth;
                            return Positioned(
                              left: ov.pos.dx * dW,
                              top: ov.pos.dy * dH,
                              width: cardW,
                              height: cardH,
                              child: FittedBox(
                                fit: BoxFit.fill,
                                child: SizedBox(
                                  width: refW,
                                  height: refW / ratio,
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
                      if (_individualDrag)
                        ..._activeItems().map((item) {
                          final posN = _itemPositions[item.key]!;
                          return ValueListenableBuilder<Offset>(
                            valueListenable: posN,
                            builder: (_, pos, __) => Positioned(
                              left: pos.dx * dW,
                              top: pos.dy * dH,
                              child: GestureDetector(
                                onPanUpdate: (d) =>
                                    _onItemDrag(item.key, d),
                                child: ValueListenableBuilder(
                                  valueListenable: _overlayNotifier,
                                  builder: (_, ov, __) {
                                    final refW = (_template == OverlayTemplate.poster || _template == OverlayTemplate.wide)
                                        ? _kRefWidth / 1.5
                                        : _kRefWidth;
                                    return _buildStatItem(
                                      item.key, item.value, item.label,
                                      ov.width * dW / refW,
                                    );
                                  },
                                ),
                              ),
                            ),
                          );
                        }),

                      // ── 메모 (항상 독립 드래그) ──
                      if (widget.record.memo.isNotEmpty)
                        ValueListenableBuilder<Offset>(
                          valueListenable: _memoPosition,
                          builder: (_, pos, __) => Positioned(
                            left: pos.dx * dW,
                            top: pos.dy * dH,
                            child: GestureDetector(
                              onPanUpdate: _onMemoDrag,
                              child: ValueListenableBuilder(
                                valueListenable: _overlayNotifier,
                                builder: (_, ov, __) => Row(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Icon(Icons.directions_run,
                                        color: _textColor,
                                        size: _memoFontSize * 1.2),
                                    const SizedBox(width: 4),
                                    Text(
                                      widget.record.memo,
                                      style: overlayTs(_font,
                                        fontSize: _memoFontSize,
                                        fontWeight: FontWeight.w600,
                                        color: _textColor,
                                        shadows: const [],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),

                      // ── Hint ──
                      Positioned(
                        bottom: 10, left: 0, right: 0,
                        child: IgnorePointer(
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.black45,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Text(
                                _individualDrag
                                    ? _t('각 항목을 드래그하여 위치 조절',
                                        'Drag each item to reposition')
                                    : _t('드래그하여 기록 위치 조절 · 탭하여 재생/정지',
                                        'Drag to reposition · Tap to play/pause'),
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

                      // ── Saving overlay ──
                      if (_saving)
                        Positioned.fill(
                          child: Container(
                            color: Colors.black54,
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const CircularProgressIndicator(
                                      color: Colors.white),
                                  const SizedBox(height: 16),
                                  Text(
                                    _t('영상 처리 중...', 'Processing video...'),
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontFamily: 'SUIT',
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ]),
                  ),
                ),
              );
            }),
          ),

          // ── Controls ──
          Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Color(0xFFEEEEEE), width: 0.5)),
            ),
            padding: const EdgeInsets.fromLTRB(0, 12, 0, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              // Template chips
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  children: OverlayTemplate.values
                      .where((t) => t != OverlayTemplate.tall)
                      .map((t) {
                    final labels = {
                      OverlayTemplate.poster:  _t('포스터', 'Poster'),
                      OverlayTemplate.classic: _t('클래식', 'Classic'),
                      OverlayTemplate.wide:    _t('가로형', 'Wide'),
                      OverlayTemplate.list:    _t('리스트', 'List'),
                      OverlayTemplate.grid:    _t('그리드', 'Grid'),
                      OverlayTemplate.custom:  _t('커스텀', 'Custom'),
                    };
                    final selected = _template == t;
                    return GestureDetector(
                      onTap: () {
                        _push();
                        if (t == OverlayTemplate.custom) _setInitialPositions();
                        setState(() => _template = t);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: selected
                              ? const Color(0xFF1C1C1E)
                              : const Color(0xFFF2F2F7),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(labels[t]!,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: selected
                                    ? Colors.white
                                    : const Color(0xFF555555))),
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
                      onTap: () { _push(); setState(() => _textColor = c); },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: sel ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: sel
                                ? const Color(0xFF1C1C1E)
                                : const Color(0xFFDDDDDD),
                          ),
                        ),
                        child: Text(
                            isWhite ? _t('흰색', 'White') : _t('검정', 'Black'),
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: sel
                                    ? Colors.white
                                    : const Color(0xFF555555))),
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
                            onTap: () { _push(); setState(() => _font = f); },
                            child: Container(
                              margin: const EdgeInsets.only(right: 6),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: sel
                                    ? const Color(0xFF1C1C1E)
                                    : const Color(0xFFF2F2F7),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(f.split(' ').first,
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: sel
                                          ? Colors.white
                                          : const Color(0xFF555555))),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ]),
              ),

              const SizedBox(height: 8),

              // 기록 크기 슬라이더
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(children: [
                  Text(_t('기록 크기', 'Size'),
                      style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF8E8E93),
                          fontWeight: FontWeight.w600)),
                  Expanded(
                    child: ValueListenableBuilder(
                      valueListenable: _overlayNotifier,
                      builder: (_, ov, __) => SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 2,
                          thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 7),
                          overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 14),
                          activeTrackColor: const Color(0xFF1C1C1E),
                          inactiveTrackColor: const Color(0xFFDDDDDD),
                          thumbColor: const Color(0xFF1C1C1E),
                          overlayColor: Colors.black12,
                        ),
                        child: Slider(
                          value: ov.width.clamp(0.2, 0.95),
                          min: 0.2,
                          max: 0.95,
                          onChangeStart: (_) => _push(),
                          onChanged: (v) {
                            _overlayNotifier.value = (pos: ov.pos, width: v);
                          },
                        ),
                      ),
                    ),
                  ),
                ]),
              ),

              // 메모 크기 슬라이더
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(children: [
                  Text(_t('메모 크기', 'Memo'),
                      style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF8E8E93),
                          fontWeight: FontWeight.w600)),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 2,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                        activeTrackColor: const Color(0xFF1C1C1E),
                        inactiveTrackColor: const Color(0xFFDDDDDD),
                        thumbColor: const Color(0xFF1C1C1E),
                        overlayColor: Colors.black12,
                      ),
                      child: Slider(
                        value: _memoFontSize,
                        min: 10.0, max: 60.0,
                        onChangeStart: (_) => _push(),
                        onChanged: (v) => setState(() => _memoFontSize = v),
                      ),
                    ),
                  ),
                ]),
              ),

              const SizedBox(height: 8),
              SizedBox(height: MediaQuery.of(context).padding.bottom),
            ]),
          ),
        ],
      ),
    );
  }
}
