import 'package:flutter/material.dart';
import '../models/running_record.dart';
import '../models/overlay_style.dart';

/// OCR 결과 확인/수정 bottom sheet.
/// 추출된 거리·시간·페이스·심박수를 보여주고, 틀린 값을 직접 수정할 수 있다.
/// [확인] 누르면 수정된 RunningRecord 반환, [취소] 누르면 null 반환.
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
  late final TextEditingController _distanceCtrl;
  late final TextEditingController _timeCtrl;
  late final TextEditingController _paceCtrl;
  late final TextEditingController _hrCtrl;

  String _t(String ko, String en) =>
      widget.language == LabelLanguage.korean ? ko : en;

  @override
  void initState() {
    super.initState();
    _distanceCtrl = TextEditingController(text: widget.record.distance);
    _timeCtrl     = TextEditingController(text: widget.record.time);
    _paceCtrl     = TextEditingController(text: widget.record.pace);
    _hrCtrl       = TextEditingController(text: widget.record.heartRate);
  }

  @override
  void dispose() {
    _distanceCtrl.dispose();
    _timeCtrl.dispose();
    _paceCtrl.dispose();
    _hrCtrl.dispose();
    super.dispose();
  }

  void _confirm() {
    Navigator.pop(
      context,
      RunningRecord(
        distance:  _distanceCtrl.text.trim(),
        time:      _timeCtrl.text.trim(),
        pace:      _paceCtrl.text.trim(),
        heartRate: _hrCtrl.text.trim(),
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
          // 핸들
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

          Text(
            _t('기록 확인 · 수정', 'Review & Edit'),
            style: const TextStyle(
              fontSize: 16, fontWeight: FontWeight.w700,
              color: Color(0xFF1C1C1E),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _t('OCR로 읽은 값을 확인하고 틀린 항목은 직접 수정하세요.',
               'Check OCR values and correct any errors.'),
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 20),

          _Field(
            icon: Icons.straighten,
            label: _t('거리', 'Distance'),
            hint: _t('예: 10.5 km', 'e.g. 10.5 km'),
            controller: _distanceCtrl,
          ),
          _Field(
            icon: Icons.timer_outlined,
            label: _t('총 시간', 'Total Time'),
            hint: _t('예: 54:30 또는 1:05:00', 'e.g. 54:30 or 1:05:00'),
            controller: _timeCtrl,
          ),
          _Field(
            icon: Icons.speed,
            label: _t('평균 페이스', 'Avg Pace'),
            hint: _t("예: 5'10\"/km", "e.g. 5'10\"/km"),
            controller: _paceCtrl,
          ),
          _Field(
            icon: Icons.favorite_border,
            label: _t('평균 심박수', 'Avg Heart Rate'),
            hint: _t('예: 148 bpm', 'e.g. 148 bpm'),
            controller: _hrCtrl,
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
}

class _Field extends StatelessWidget {
  final IconData icon;
  final String label;
  final String hint;
  final TextEditingController controller;
  final bool isLast;

  const _Field({
    required this.icon,
    required this.label,
    required this.hint,
    required this.controller,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF888888)),
          const SizedBox(width: 10),
          SizedBox(
            width: 90,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF333333))),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              style: const TextStyle(fontSize: 14, color: Color(0xFF1C1C1E)),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle:
                    TextStyle(fontSize: 12, color: Colors.grey[400]),
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
          ),
        ],
      ),
    );
  }
}
