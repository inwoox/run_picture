import 'dart:io';
import 'package:flutter/material.dart';

const _ratioOptions = [
  ('1:1',  1.0),
  ('4:5',  4.0 / 5.0),
  ('9:16', 9.0 / 16.0),
];

/// 반환값: (ratio, alignment). 취소 시 null.
Future<(double, Alignment)?> showRatioPickerSheet(
    BuildContext context, String imagePath) {
  return showModalBottomSheet<(double, Alignment)>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _RatioPickerSheet(imagePath: imagePath),
  );
}

class _RatioPickerSheet extends StatefulWidget {
  final String imagePath;
  const _RatioPickerSheet({required this.imagePath});
  @override
  State<_RatioPickerSheet> createState() => _RatioPickerSheetState();
}

class _RatioPickerSheetState extends State<_RatioPickerSheet> {
  double _ratio = 4.0 / 5.0;
  Alignment _alignment = Alignment.center;

  void _onPanUpdate(DragUpdateDetails d, BoxConstraints constraints) {
    setState(() {
      _alignment = Alignment(
        (_alignment.x - d.delta.dx * 2 / constraints.maxWidth).clamp(-1.0, 1.0),
        (_alignment.y - d.delta.dy * 2 / constraints.maxHeight).clamp(-1.0, 1.0),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: const BoxDecoration(
        color: Color(0xFFF5F7FA),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(children: [
        // 핸들
        Container(
          margin: const EdgeInsets.only(top: 12),
          width: 36, height: 4,
          decoration: BoxDecoration(
              color: const Color(0xFFE5E5EA),
              borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(height: 16),
        const Text('비율 선택',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                color: Color(0xFF1C1C1E))),
        const SizedBox(height: 4),
        const Text('드래그로 위치 조정 · 보이는 영역이 저장됩니다',
            style: TextStyle(fontSize: 12, color: Color(0xFF8E8E93))),
        const SizedBox(height: 20),

        // 이미지 미리보기 + 드래그 위치 조정
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: AspectRatio(
                aspectRatio: _ratio,
                child: LayoutBuilder(builder: (context, constraints) {
                  return GestureDetector(
                    onPanUpdate: (d) => _onPanUpdate(d, constraints),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.file(
                        File(widget.imagePath),
                        fit: BoxFit.cover,
                        alignment: _alignment,
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ),

        const SizedBox(height: 20),

        // 비율 버튼 — 변경 시 alignment 초기화
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: _ratioOptions.map((opt) {
            final (label, ratio) = opt;
            final selected = (_ratio - ratio).abs() < 0.001;
            return GestureDetector(
              onTap: () => setState(() {
                _ratio = ratio;
                _alignment = Alignment.center; // 비율 바꾸면 중앙으로 리셋
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.symmetric(horizontal: 6),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 11),
                decoration: BoxDecoration(
                  color: selected ? const Color(0xFF1C1C1E) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: selected
                          ? const Color(0xFF1C1C1E)
                          : const Color(0xFFE5E5EA)),
                ),
                child: Text(label,
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700,
                        color: selected ? Colors.white : const Color(0xFF8E8E93))),
              ),
            );
          }).toList(),
        ),

        // 확인 버튼
        Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20,
              24 + MediaQuery.of(context).padding.bottom),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context, (_ratio, _alignment)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1C1C1E),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: const Text('선택 완료',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),
        ),
      ]),
    );
  }
}
