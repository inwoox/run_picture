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

const double _kRefWidth = 400.0;

class RecordVideoOverlayScreen extends StatefulWidget {
  final XFile video;
  final RunningRecord record;
  final LabelLanguage language;

  const RecordVideoOverlayScreen({
    super.key,
    required this.video,
    required this.record,
    required this.language,
  });

  @override
  State<RecordVideoOverlayScreen> createState() =>
      _RecordVideoOverlayScreenState();
}

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
  bool _individualDrag = false;

  late final ValueNotifier<({Offset pos, double width})> _overlayNotifier;
  late final Map<String, ValueNotifier<Offset>> _itemPositions;
  Size _dispSize = Size.zero;

  // ── Saving ───────────────────────────────────────────────────────────────
  bool _saving = false;

  String _t(String ko, String en) =>
      widget.language == LabelLanguage.korean ? ko : en;

  @override
  void initState() {
    super.initState();
    _overlayNotifier =
        ValueNotifier((pos: const Offset(0.05, 0.05), width: 0.55));
    _itemPositions = {
      'dist': ValueNotifier(Offset.zero),
      'time': ValueNotifier(Offset.zero),
      'pace': ValueNotifier(Offset.zero),
      'hr': ValueNotifier(Offset.zero),
    };
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
    }
  }

  void _toggleIndividualDrag() {
    if (!_individualDrag) _setInitialPositions();
    setState(() => _individualDrag = !_individualDrag);
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
                    fontSize: 24 * scale,
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
                    fontSize: 19 * scale,
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
                    fontSize: 11 * scale,
                    fontWeight: FontWeight.w600,
                    color: _textColor,
                    letterSpacing: 0.5,
                    shadows: shadows)),
            SizedBox(width: 10 * scale),
            Text(value,
                style: overlayTs(_font,
                    fontSize: 22 * scale,
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
    }
  }

  // ── Build overlay widget at display size (for FFmpeg capture) ─────────────
  // Captured with pixelRatio = videoW / dispW → output = exact video resolution.
  Widget _buildDisplayOverlay() {
    final ov = _overlayNotifier.value;
    final dW = _dispSize.width;
    final dH = _dispSize.height;
    final ratio = getOverlayCardAspectRatio(_template);
    final textScale = ov.width * dW / _kRefWidth;

    return Material(
      color: Colors.transparent,
      child: SizedBox(
        width: dW,
        height: dH,
        child: Stack(children: [
          if (!_individualDrag)
            Positioned(
              left: ov.pos.dx * dW,
              top: ov.pos.dy * dH,
              width: dW * ov.width,
              height: dW * ov.width / ratio,
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
        ]),
      ),
    );
  }

  // ── Save: capture overlay → FFmpeg composite ──────────────────────────────
  Future<void> _save() async {
    if (!_videoReady || _dispSize == Size.zero) return;
    setState(() => _saving = true);
    try {
      final videoW = _videoSize.width;
      final dispW = _dispSize.width;

      // Capture overlay at video resolution (pixelRatio scales display→video)
      final pr = (videoW / dispW).clamp(0.5, 6.0);
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
      final vW = _videoSize.width.toInt();
      final vH = _videoSize.height.toInt();

      // Scale overlay PNG to exact video dimensions, then composite with alpha
      final cmd = '-i "${widget.video.path}" -i "$overlayPath" '
          '-filter_complex '
          '"[1:v]scale=${vW}:${vH}[ovl];[0:v][ovl]overlay=0:0:format=auto,format=yuv420p[vout]" '
          '-map "[vout]" -map 0:a? '
          '-c:v libx264 -crf 18 -preset fast -c:a copy '
          '-movflags +faststart -y "$outPath"';

      final session = await FFmpegKit.execute(cmd);
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
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('PaceGraphy',
              style: TextStyle(
                  fontFamily: 'SUIT',
                  color: Colors.white,
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
          _saving
              ? const Padding(
                  padding: EdgeInsets.only(right: 16),
                  child: Center(
                    child: SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    ),
                  ),
                )
              : TextButton(
                  onPressed: _save,
                  child: Text(_t('저장', 'Save'),
                      style: const TextStyle(
                          color: Colors.white,
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
              double dW, dH;
              if (maxW / maxH < videoAR) {
                dW = maxW; dH = maxW / videoAR;
              } else {
                dH = maxH; dW = maxH * videoAR;
              }
              _dispSize = Size(dW, dH);

              return Center(
                child: SizedBox(
                  width: dW, height: dH,
                  child: GestureDetector(
                    onPanUpdate: _individualDrag ? null : _onDrag,
                    onTap: () {
                      if (_vpc == null) return;
                      _vpc!.value.isPlaying
                          ? _vpc!.pause()
                          : _vpc!.play();
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Stack(children: [
                      // ── Video preview ──
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
                                  builder: (_, ov, __) => _buildStatItem(
                                    item.key, item.value, item.label,
                                    ov.width * dW / _kRefWidth,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),

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
            color: const Color(0xFF1C1C1E),
            padding: const EdgeInsets.fromLTRB(0, 12, 0, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              // Template chips
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  children: OverlayTemplate.values.map((t) {
                    final labels = {
                      OverlayTemplate.poster: _t('포스터', 'Poster'),
                      OverlayTemplate.wide: _t('가로형', 'Wide'),
                      OverlayTemplate.tall: _t('세로형', 'Tall'),
                      OverlayTemplate.list: _t('리스트', 'List'),
                      OverlayTemplate.grid: _t('그리드', 'Grid'),
                    };
                    final selected = _template == t;
                    return GestureDetector(
                      onTap: () => setState(() => _template = t),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: selected
                              ? Colors.white
                              : const Color(0xFF2C2C2E),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(labels[t]!,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: selected
                                    ? const Color(0xFF1C1C1E)
                                    : const Color(0xFF8E8E93))),
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
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: sel ? Colors.white : const Color(0xFF2C2C2E),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: sel
                                ? Colors.white
                                : const Color(0xFF3C3C3E),
                          ),
                        ),
                        child: Text(
                            isWhite ? _t('흰색', 'White') : _t('검정', 'Black'),
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: sel
                                    ? const Color(0xFF1C1C1E)
                                    : const Color(0xFF8E8E93))),
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
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: sel
                                    ? Colors.white
                                    : const Color(0xFF2C2C2E),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(f.split(' ').first,
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: sel
                                          ? const Color(0xFF1C1C1E)
                                          : const Color(0xFF8E8E93))),
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
                          activeTrackColor: Colors.white,
                          inactiveTrackColor: const Color(0xFF3C3C3E),
                          thumbColor: Colors.white,
                          overlayColor: Colors.white24,
                        ),
                        child: Slider(
                          value: ov.width.clamp(0.2, 0.95),
                          min: 0.2,
                          max: 0.95,
                          onChanged: (v) {
                            _overlayNotifier.value =
                                (pos: ov.pos, width: v);
                          },
                        ),
                      ),
                    ),
                  ),
                ]),
              ),

              const SizedBox(height: 8),

              // HR + Individual drag row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(children: [
                  Text(_t('심박수', 'HR'),
                      style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF8E8E93),
                          fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () =>
                        setState(() => _showHeartRate = !_showHeartRate),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: _showHeartRate
                            ? Colors.white
                            : const Color(0xFF2C2C2E),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _showHeartRate
                              ? Colors.white
                              : const Color(0xFF3C3C3E),
                        ),
                      ),
                      child: Text(
                          _showHeartRate
                              ? _t('표시', 'Show')
                              : _t('숨김', 'Hide'),
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _showHeartRate
                                  ? const Color(0xFF1C1C1E)
                                  : const Color(0xFF8E8E93))),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(_t('개별 드래그', 'Free Place'),
                      style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF8E8E93),
                          fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _toggleIndividualDrag,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: _individualDrag
                            ? Colors.white
                            : const Color(0xFF2C2C2E),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _individualDrag
                              ? Colors.white
                              : const Color(0xFF3C3C3E),
                        ),
                      ),
                      child: Text(
                          _individualDrag
                              ? _t('켜짐', 'ON')
                              : _t('꺼짐', 'OFF'),
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _individualDrag
                                  ? const Color(0xFF1C1C1E)
                                  : const Color(0xFF8E8E93))),
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
