import 'package:flutter/material.dart';
import '../models/running_record.dart';
import '../models/overlay_style.dart';

Future<RunningRecord?> showOcrConfirmSheet(
  BuildContext context,
  RunningRecord record,
  LabelLanguage language,
) {
  return showModalBottomSheet<RunningRecord>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _OcrConfirmSheet(record: record, language: language),
  );
}

class _OcrConfirmSheet extends StatefulWidget {
  final RunningRecord record;
  final LabelLanguage language;
  const _OcrConfirmSheet({required this.record, required this.language});

  @override
  State<_OcrConfirmSheet> createState() => _OcrConfirmSheetState();
}

class _OcrConfirmSheetState extends State<_OcrConfirmSheet> {
  // 거리: "10.01 km" → "10.01"
  late final TextEditingController _distCtrl;

  // 시간: "39:43" → min="39" sec="43" / "1:05:00" → h="1" min="05" sec="00"
  late final TextEditingController _timeHourCtrl;
  late final TextEditingController _timeMinCtrl;
  late final TextEditingController _timeSecCtrl;
  bool _timeHasHours = false;

  // 페이스: "3:58/km" or "5'10\"/km" → min="3" sec="58"
  late final TextEditingController _paceMinCtrl;
  late final TextEditingController _paceSecCtrl;

  // 심박수: "187 bpm" → "187"
  late final TextEditingController _hrCtrl;

  // 메모 (자유 입력)
  late final TextEditingController _memoCtrl;

  String _t(String ko, String en) =>
      widget.language == LabelLanguage.korean ? ko : en;

  @override
  void initState() {
    super.initState();

    // 거리 파싱
    final distRaw = widget.record.distance
        .replaceAll(RegExp(r'\s*km', caseSensitive: false), '')
        .trim();
    _distCtrl = TextEditingController(text: distRaw);

    // 시간 파싱
    final timeParts = widget.record.time.split(':');
    if (timeParts.length >= 3) {
      _timeHasHours = true;
      _timeHourCtrl = TextEditingController(text: timeParts[0]);
      _timeMinCtrl  = TextEditingController(text: timeParts[1]);
      _timeSecCtrl  = TextEditingController(text: timeParts[2]);
    } else if (timeParts.length == 2) {
      _timeHasHours = false;
      _timeHourCtrl = TextEditingController();
      _timeMinCtrl  = TextEditingController(text: timeParts[0]);
      _timeSecCtrl  = TextEditingController(text: timeParts[1]);
    } else {
      _timeHasHours = false;
      _timeHourCtrl = TextEditingController();
      _timeMinCtrl  = TextEditingController(text: widget.record.time);
      _timeSecCtrl  = TextEditingController();
    }

    // 페이스 파싱: "3:58/km" 또는 "5'10\"/km"
    final paceRaw = widget.record.pace
        .replaceAll('/km', '')
        .replaceAll("'", ':')
        .replaceAll('"', '')
        .trim();
    final paceParts = paceRaw.split(':');
    if (paceParts.length >= 2) {
      _paceMinCtrl = TextEditingController(text: paceParts[0]);
      _paceSecCtrl = TextEditingController(text: paceParts[1]);
    } else {
      _paceMinCtrl = TextEditingController(text: paceRaw);
      _paceSecCtrl = TextEditingController();
    }

    // 심박수 파싱
    final hrRaw = widget.record.heartRate
        .replaceAll(RegExp(r'\s*bpm', caseSensitive: false), '')
        .trim();
    _hrCtrl = TextEditingController(text: hrRaw);

    // 메모
    _memoCtrl = TextEditingController(text: widget.record.memo);
  }

  @override
  void dispose() {
    _distCtrl.dispose();
    _timeHourCtrl.dispose();
    _timeMinCtrl.dispose();
    _timeSecCtrl.dispose();
    _paceMinCtrl.dispose();
    _paceSecCtrl.dispose();
    _hrCtrl.dispose();
    _memoCtrl.dispose();
    super.dispose();
  }

  void _confirm() {
    // 거리 조합: "10.01" → "10.01 km"
    final dist = _distCtrl.text.trim();
    final distFinal = dist.isEmpty ? '' : '$dist km';

    // 시간 조합: "39" + "43" → "39:43"
    final tMin = _timeMinCtrl.text.trim();
    final tSec = _timeSecCtrl.text.trim().padLeft(2, '0');
    String timeFinal = '';
    if (tMin.isNotEmpty || tSec != '00') {
      if (_timeHasHours) {
        final tH = _timeHourCtrl.text.trim();
        timeFinal = '$tH:${tMin.padLeft(2, '0')}:$tSec';
      } else {
        timeFinal = '$tMin:$tSec';
      }
    }

    // 페이스 조합: "3" + "58" → "3:58/km"
    final pMin = _paceMinCtrl.text.trim();
    final pSec = _paceSecCtrl.text.trim().padLeft(2, '0');
    String paceFinal = '';
    if (pMin.isNotEmpty || pSec != '00') {
      paceFinal = '$pMin:$pSec/km';
    }

    // 심박수 조합: "187" → "187 bpm"
    final hr = _hrCtrl.text.trim();
    final hrFinal = hr.isEmpty ? '' : '$hr bpm';

    Navigator.pop(
      context,
      RunningRecord(
        distance:  distFinal,
        time:      timeFinal,
        pace:      paceFinal,
        heartRate: hrFinal,
        memo:      _memoCtrl.text.trim(),
        date:      widget.record.date,
        calories:  widget.record.calories,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(_t('기록 확인 · 수정', 'Review & Edit'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                  color: Color(0xFF1C1C1E))),
          const SizedBox(height: 4),
          Text(
            _t('OCR로 읽은 값을 확인하고 틀린 항목은 직접 수정하세요.',
               'Check OCR values and correct any errors.'),
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 20),

          // 거리: [ 10.01 ] km
          _row(
            icon: Icons.straighten,
            label: _t('거리', 'Distance'),
            child: Row(children: [
              _box(_distCtrl,
                  const TextInputType.numberWithOptions(decimal: true), 72),
              _unit('km'),
            ]),
          ),

          // 총 시간: [ 39 ] 분  [ 43 ] 초
          _row(
            icon: Icons.timer_outlined,
            label: _t('총 시간', 'Total Time'),
            child: Row(children: [
              if (_timeHasHours) ...[
                _box(_timeHourCtrl, TextInputType.number, 36),
                _unit(_t('시', 'h')),
                const SizedBox(width: 4),
              ],
              _box(_timeMinCtrl, TextInputType.number, 44),
              _unit(_t('분', 'min')),
              const SizedBox(width: 4),
              _box(_timeSecCtrl, TextInputType.number, 44),
              _unit(_t('초', 'sec')),
            ]),
          ),

          // 평균 페이스: [ 3 ] 분  [ 58 ] 초/km
          _row(
            icon: Icons.speed,
            label: _t('평균 페이스', 'Avg Pace'),
            child: Row(children: [
              _box(_paceMinCtrl, TextInputType.number, 36),
              _unit(_t('분', 'min')),
              const SizedBox(width: 4),
              _box(_paceSecCtrl, TextInputType.number, 44),
              _unit(_t('초/km', 'sec/km')),
            ]),
          ),

          // 평균 심박수: [ 187 ] bpm
          _row(
            icon: Icons.favorite_border,
            label: _t('평균 심박수', 'Avg HR'),
            child: Row(children: [
              _box(_hrCtrl, TextInputType.number, 60),
              _unit('bpm'),
            ]),
          ),

          // 메모 (자유 텍스트)
          _row(
            icon: Icons.edit_note_rounded,
            label: _t('메모', 'Memo'),
            child: TextField(
              controller: _memoCtrl,
              keyboardType: TextInputType.text,
              style: const TextStyle(fontSize: 14, color: Color(0xFF1C1C1E)),
              decoration: InputDecoration(
                hintText: _t('입력 시 영상/사진에 표시됩니다', 'Shown on photo/video if entered'),
                hintStyle: TextStyle(fontSize: 11, color: Colors.grey[400]),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                filled: true,
                fillColor: const Color(0xFFF5F7FA),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(
                      color: Color(0xFF1C1C1E), width: 1.5),
                ),
              ),
            ),
            isLast: true,
          ),

          const SizedBox(height: 24),

          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context, null),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFDDDDDD)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text(_t('취소', 'Cancel'),
                    style: const TextStyle(color: Color(0xFF555555))),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: _confirm,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1C1C1E),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text(_t('확인', 'Confirm'),
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _row({
    required IconData icon,
    required String label,
    required Widget child,
    bool isLast = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
      child: Row(children: [
        Icon(icon, size: 18, color: const Color(0xFF888888)),
        const SizedBox(width: 10),
        SizedBox(
          width: 76,
          child: Text(label,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                  color: Color(0xFF333333))),
        ),
        Expanded(child: child),
      ]),
    );
  }

  Widget _box(TextEditingController ctrl, TextInputType keyboard, double width) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: ctrl,
        keyboardType: keyboard,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600,
            color: Color(0xFF1C1C1E)),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          filled: true,
          fillColor: const Color(0xFFF5F7FA),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF1C1C1E), width: 1.5),
          ),
        ),
      ),
    );
  }

  Widget _unit(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(text,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500,
              color: Color(0xFF555555))),
    );
  }
}
