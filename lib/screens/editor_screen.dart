import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:screenshot/screenshot.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'dart:io';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import '../models/running_record.dart';
import '../models/overlay_style.dart';
import '../utils/save_util.dart';

class EditorScreen extends StatefulWidget {
  final XFile image;
  final RunningRecord record;
  final LabelLanguage language;
  final double ratio;
  final Alignment alignment;

  const EditorScreen({super.key, required this.image, required this.record,
      this.language = LabelLanguage.korean, this.ratio = 9.0 / 16.0,
      this.alignment = Alignment.center});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  final ScreenshotController _screenshotController = ScreenshotController();
  final GlobalKey _previewKey = GlobalKey();
  late OverlayStyle _style;

  @override
  void initState() {
    super.initState();
    _style = OverlayStyle(labelLanguage: widget.language);
  }

  static const List<String> _fonts = [
    'SUIT', 'Roboto', 'Oswald', 'Montserrat', 'Raleway',
    'Bebas Neue', 'Anton', 'Russo One', 'Orbitron',
    // 손글씨 / 붓글씨 (OFL 상업 허용)
    'Nanum Pen Script',
    'Nanum Brush Script',
    'Black Han Sans',
    'Gaegu',
    'Caveat',
    'Pacifico',
  ];

  static const Set<String> _localFonts = {'SUIT'};

  static const List<List<OverlayPosition>> _positionGrid = [
    [OverlayPosition.topLeft,    OverlayPosition.topRight],
    [OverlayPosition.bottomLeft, OverlayPosition.bottomRight],
  ];

  // 언어에 따라 텍스트 반환
  String _t(String ko, String en) =>
      _style.labelLanguage == LabelLanguage.korean ? ko : en;

  // 한글 날짜 → 영어 변환 ("4월1일 8:31 오후" → "Apr 1 8:31 PM")
  String _convertDate(String date) {
    if (_style.labelLanguage == LabelLanguage.korean) return date;
    const months = {
      '1': 'Jan', '2': 'Feb', '3': 'Mar', '4': 'Apr',
      '5': 'May', '6': 'Jun', '7': 'Jul', '8': 'Aug',
      '9': 'Sep', '10': 'Oct', '11': 'Nov', '12': 'Dec',
    };
    String result = date;
    // "4월1일" → "Apr 1"
    result = result.replaceAllMapped(
      RegExp(r'(\d{1,2})월\s*(\d{1,2})일'),
      (m) => '${months[m.group(1)] ?? m.group(1)} ${m.group(2)}',
    );
    result = result.replaceAll('오전', 'AM').replaceAll('오후', 'PM');
    return result;
  }

  Map<OverlayPosition, String> get _positionLabels => {
    OverlayPosition.topLeft:     _t('좌상', 'TL'),
    OverlayPosition.topRight:    _t('우상', 'TR'),
    OverlayPosition.bottomLeft:  _t('좌하', 'BL'),
    OverlayPosition.bottomRight: _t('우하', 'BR'),
  };

  Alignment _getAlignment(OverlayPosition pos) => switch (pos) {
    OverlayPosition.topLeft     => Alignment.topLeft,
    OverlayPosition.topRight    => Alignment.topRight,
    OverlayPosition.bottomLeft  => Alignment.bottomLeft,
    OverlayPosition.bottomRight => Alignment.bottomRight,
  };

  TextStyle _makeTextStyle(double size) {
    if (_localFonts.contains(_style.fontFamily)) {
      return TextStyle(fontFamily: _style.fontFamily,
          color: _style.textColor, fontSize: size, fontWeight: FontWeight.bold);
    }
    try {
      return GoogleFonts.getFont(_style.fontFamily,
          color: _style.textColor, fontSize: size, fontWeight: FontWeight.bold);
    } catch (_) {
      return TextStyle(color: _style.textColor, fontSize: size, fontWeight: FontWeight.bold);
    }
  }

  Widget _wrapBackground(Widget child) {
    if (!_style.showBackground) return child;
    return Container(
      decoration: BoxDecoration(
        color: _style.backgroundColor.withOpacity(_style.backgroundOpacity),
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
  }

  Widget _buildStatsOverlay() {
    final textStyle = _makeTextStyle(_style.fontSize);
    final labelStyle = textStyle.copyWith(fontSize: _style.fontSize * 0.65, fontWeight: FontWeight.normal);
    final fields = <Widget>[];

    void addField(String label, String value, IconData icon) {
      if (value.isEmpty) return;
      fields.add(Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: _style.textColor, size: _style.fontSize),
        const SizedBox(width: 5),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: labelStyle),
          Text(value, style: textStyle),
        ]),
      ]));
    }

    addField(_t('거리', 'Distance'), widget.record.distance, Icons.directions_run_rounded);
    addField(_t('총 시간', 'Total Time'), widget.record.time, Icons.timer_rounded);
    addField(_t('평균 페이스', 'Avg Pace'), widget.record.pace, Icons.speed_rounded);
    addField(_t('평균 심박수', 'Avg HR'), widget.record.heartRate, Icons.favorite_rounded);

    if (fields.isEmpty) return const SizedBox();

    final content = Padding(
      padding: const EdgeInsets.all(10),
      child: _style.layoutDirection == LayoutDirection.horizontal
          ? Wrap(spacing: 14, runSpacing: 6, children: fields)
          : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
              children: fields.map((f) => Padding(padding: const EdgeInsets.only(bottom: 6), child: f)).toList()),
    );
    return _wrapBackground(content);
  }

  Widget _buildDateOverlay() {
    if (widget.record.date.isEmpty) return const SizedBox();
    return _wrapBackground(Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: Text(_convertDate(widget.record.date), style: _makeTextStyle(_style.dateFontSize)),
    ));
  }

  Future<void> _saveImage() async {
    showSavingDialog(context);
    try {
      final bytes = await _screenshotController.capture(pixelRatio: 3.0);
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

  void _showFontPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(width: 36, height: 4, decoration: BoxDecoration(color: const Color(0xFFE5E5EA), borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            Text(_t('폰트 선택', 'Select Font'),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1C1C1E))),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _fonts.length,
                itemBuilder: (_, i) {
                  final selected = _style.fontFamily == _fonts[i];
                  final color = selected ? const Color(0xFF1C1C1E) : const Color(0xFF1C1C1E);
                  TextStyle fontStyle;
                  if (_localFonts.contains(_fonts[i])) {
                    fontStyle = TextStyle(fontFamily: _fonts[i], fontSize: 18,
                        fontWeight: FontWeight.bold, color: color);
                  } else {
                    try {
                      fontStyle = GoogleFonts.getFont(_fonts[i], fontSize: 18,
                          fontWeight: FontWeight.bold, color: color);
                    } catch (_) {
                      fontStyle = TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color);
                    }
                  }
                  return ListTile(
                    onTap: () { setState(() => _style = _style.copyWith(fontFamily: _fonts[i])); Navigator.pop(context); },
                    title: Text(_fonts[i], style: fontStyle),
                    trailing: selected ? const Icon(Icons.check_rounded, color: Color(0xFF1C1C1E)) : null,
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _pickColor(bool isText) {
    Color current = isText ? _style.textColor : _style.backgroundColor;
    showDialog(context: context, builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(isText ? _t('텍스트 색상', 'Text Color') : _t('배경 색상', 'Background Color'),
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
      content: SingleChildScrollView(child: ColorPicker(pickerColor: current, onColorChanged: (c) {
        setState(() { _style = isText ? _style.copyWith(textColor: c) : _style.copyWith(backgroundColor: c); });
      })),
      actions: [TextButton(onPressed: () => Navigator.pop(context),
          child: Text(_t('확인', 'OK'), style: const TextStyle(color: Colors.white)))],
    ));
  }

  Widget _buildPositionGrid(OverlayPosition current, ValueChanged<OverlayPosition> onChanged) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(2, (row) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(2, (col) {
          final pos = _positionGrid[row][col];
          final selected = pos == current;
          return GestureDetector(
            onTap: () => onChanged(pos),
            child: Container(
              width: 52, height: 36,
              margin: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: selected ? const Color(0xFF1C1C1E) : const Color(0xFFF5F7FA),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: selected ? const Color(0xFF1C1C1E) : const Color(0xFFE5E5EA)),
              ),
              child: Center(child: Text(_positionLabels[pos]!,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                      color: selected ? Colors.white : const Color(0xFF8E8E93)))),
            ),
          );
        }),
      )),
    );
  }

  Widget _sizeRow(String label, double value, ValueChanged<double> onChanged) {
    return Row(children: [
      SizedBox(width: 60, child: Text(label, style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 13))),
      Expanded(
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: const Color(0xFF1C1C1E),
            inactiveTrackColor: const Color(0xFFE5E5EA),
            thumbColor: const Color(0xFF1C1C1E),
            overlayShape: SliderComponentShape.noOverlay,
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
          ),
          child: Slider(value: value, min: 12, max: 20, divisions: 8, onChanged: onChanged),
        ),
      ),
      SizedBox(width: 28, child: Text('${value.toInt()}',
          style: const TextStyle(color: Color(0xFF1C1C1E), fontSize: 13, fontWeight: FontWeight.w600))),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final isEn = _style.labelLanguage == LabelLanguage.english;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Color(0xFF1C1C1E), size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('PaceGraphy',
            style: TextStyle(fontFamily: 'SUIT', color: Color(0xFF1C1C1E), fontWeight: FontWeight.w700, fontSize: 20, letterSpacing: 1.0)),
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
          Expanded(
            flex: 11,
            child: Center(
              child: AspectRatio(
                aspectRatio: widget.ratio,
                child: Screenshot(
                  key: _previewKey,
                  controller: _screenshotController,
                  child: MediaQuery(
                    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(1.0)),
                    child: Stack(fit: StackFit.expand, children: [
                      Image.file(File(widget.image.path), fit: BoxFit.cover, alignment: widget.alignment),
                      Positioned.fill(child: Align(
                        alignment: _getAlignment(_style.position),
                        child: Padding(padding: const EdgeInsets.all(12), child: _buildStatsOverlay()),
                      )),
                      if (widget.record.date.isNotEmpty)
                        Positioned.fill(child: Align(
                          alignment: _getAlignment(_style.datePosition),
                          child: Padding(padding: const EdgeInsets.all(12), child: _buildDateOverlay()),
                        )),
                    ]),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 9,
            child: Container(
              color: Colors.white,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 폰트
                    _label(_t('폰트', 'Font')),
                    GestureDetector(
                      onTap: _showFontPicker,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F7FA),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE5E5EA)),
                        ),
                        child: Row(children: [
                          Expanded(child: Builder(builder: (_) {
                            if (_localFonts.contains(_style.fontFamily)) {
                              return Text(_style.fontFamily,
                                  style: TextStyle(fontFamily: _style.fontFamily,
                                      fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF1C1C1E)));
                            }
                            try {
                              return Text(_style.fontFamily,
                                  style: GoogleFonts.getFont(_style.fontFamily,
                                      fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF1C1C1E)));
                            } catch (_) {
                              return Text(_style.fontFamily,
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1C1C1E)));
                            }
                          })),
                          const Icon(Icons.expand_more_rounded, color: Color(0xFF8E8E93)),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // 레이아웃
                    _label(_t('레이아웃', 'Layout')),
                    Row(children: [
                      _iconToggle(Icons.view_stream_rounded, _t('가로', 'Horizontal'), LayoutDirection.horizontal),
                      const SizedBox(width: 8),
                      _iconToggle(Icons.view_agenda_rounded, _t('세로', 'Vertical'), LayoutDirection.vertical),
                    ]),
                    const SizedBox(height: 20),

                    // 글자 크기
                    _label(_t('글자 크기', 'Font Size')),
                    _sizeRow(_t('기록', 'Stats'), _style.fontSize,
                        (v) => setState(() => _style = _style.copyWith(fontSize: v))),
                    _sizeRow(_t('날짜', 'Date'), _style.dateFontSize,
                        (v) => setState(() => _style = _style.copyWith(dateFontSize: v))),
                    const SizedBox(height: 20),

                    // 위치
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _label(_t('기록 위치', 'Stats Position')),
                        _buildPositionGrid(_style.position,
                            (pos) => setState(() => _style = _style.copyWith(position: pos))),
                      ]),
                      const SizedBox(width: 24),
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _label(_t('날짜 위치', 'Date Position')),
                        _buildPositionGrid(_style.datePosition,
                            (pos) => setState(() => _style = _style.copyWith(datePosition: pos))),
                      ]),
                    ]),
                    const SizedBox(height: 20),

                    // 색상/배경
                    _label(_t('색상 / 배경', 'Color / Background')),
                    Row(children: [
                      _colorCircle(_t('텍스트', 'Text'), _style.textColor, () => _pickColor(true)),
                      const SizedBox(width: 20),
                      _colorCircle(_t('배경색', 'BG Color'), _style.backgroundColor, () => _pickColor(false)),
                      const Spacer(),
                      Row(children: [
                        Switch(
                          value: _style.showBackground,
                          activeColor: const Color(0xFF1C1C1E),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          onChanged: (v) => setState(() => _style = _style.copyWith(showBackground: v)),
                        ),
                        Text(_t('배경', 'BG'), style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 13)),
                      ]),
                    ]),
                    if (_style.showBackground) ...[
                      const SizedBox(height: 8),
                      Row(children: [
                        SizedBox(width: 60, child: Text(_t('투명도', 'Opacity'),
                            style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 13))),
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              activeTrackColor: const Color(0xFF1C1C1E),
                              inactiveTrackColor: const Color(0xFFE5E5EA),
                              thumbColor: const Color(0xFF1C1C1E),
                              overlayShape: SliderComponentShape.noOverlay,
                              trackHeight: 3,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                            ),
                            child: Slider(value: _style.backgroundOpacity, min: 0, max: 1,
                                onChanged: (v) => setState(() => _style = _style.copyWith(backgroundOpacity: v))),
                          ),
                        ),
                        SizedBox(width: 36, child: Text('${(_style.backgroundOpacity * 100).toInt()}%',
                            style: const TextStyle(color: Color(0xFF1C1C1E), fontSize: 13, fontWeight: FontWeight.w600))),
                      ]),
                    ],
                    const SizedBox(height: 20),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _saveImage,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1C1C1E),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                        child: Text(_t('이미지 저장', 'Save Image'),
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(text, style: const TextStyle(color: Color(0xFF1C1C1E), fontSize: 14, fontWeight: FontWeight.w600)),
  );

  Widget _langToggle(String label, LabelLanguage lang) {
    final selected = _style.labelLanguage == lang;
    return GestureDetector(
      onTap: () => setState(() => _style = _style.copyWith(labelLanguage: lang)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF1C1C1E) : const Color(0xFFF5F7FA),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: selected ? const Color(0xFF1C1C1E) : const Color(0xFFE5E5EA)),
        ),
        child: Text(label, style: TextStyle(fontSize: 11,
            color: selected ? Colors.white : const Color(0xFF8E8E93),
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal)),
      ),
    );
  }

  Widget _iconToggle(IconData icon, String label, LayoutDirection dir) {
    final selected = _style.layoutDirection == dir;
    return GestureDetector(
      onTap: () => setState(() => _style = _style.copyWith(layoutDirection: dir)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF1C1C1E) : const Color(0xFFF5F7FA),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? const Color(0xFF1C1C1E) : const Color(0xFFE5E5EA)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: selected ? Colors.white : const Color(0xFF8E8E93)),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(fontSize: 13,
              color: selected ? Colors.white : const Color(0xFF8E8E93),
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal)),
        ]),
      ),
    );
  }

  Widget _colorCircle(String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFE5E5EA), width: 2),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 4, offset: const Offset(0, 2))]),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 13)),
      ]),
    );
  }
}
