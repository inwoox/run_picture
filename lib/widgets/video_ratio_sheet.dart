import 'package:flutter/material.dart';

const _kOptions = <(String, double?)>[
  ('원본', null),
  ('9:16', 9.0 / 16.0),
  ('4:5',  4.0 / 5.0),
  ('1:1',  1.0),
];

/// 반환값: 선택된 비율 (null = 원본). 시트를 닫아도 null(원본) 반환.
Future<double?> showVideoRatioSheet(BuildContext context) async {
  final result = await showModalBottomSheet<double?>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const _VideoRatioSheet(),
  );
  return result; // null = 원본 (또는 dismiss)
}

class _VideoRatioSheet extends StatefulWidget {
  const _VideoRatioSheet();
  @override
  State<_VideoRatioSheet> createState() => _VideoRatioSheetState();
}

class _VideoRatioSheetState extends State<_VideoRatioSheet> {
  double? _selected; // null = 원본

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).padding.bottom),
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
          const Text('출력 비율 선택',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                  color: Color(0xFF1C1C1E))),
          const SizedBox(height: 4),
          Text('선택한 비율로 중앙 기준 잘라내어 저장됩니다.',
              style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          const SizedBox(height: 20),

          // 비율 버튼 그리드
          Row(
            children: _kOptions.map((opt) {
              final (label, ratio) = opt;
              final isSelected = ratio == _selected;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _selected = ratio),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF1C1C1E)
                          : const Color(0xFFF2F2F7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 비율 미리보기 사각형
                        _RatioBox(ratio: ratio, selected: isSelected),
                        const SizedBox(height: 8),
                        Text(label,
                            style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700,
                              color: isSelected ? Colors.white : const Color(0xFF1C1C1E),
                            )),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 20),

          ElevatedButton(
            onPressed: () => Navigator.pop(context, _selected),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1C1C1E),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            child: const Text('선택 완료',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

class _RatioBox extends StatelessWidget {
  final double? ratio; // null = 원본 (16:9 기준 표시)
  final bool selected;
  const _RatioBox({required this.ratio, required this.selected});

  @override
  Widget build(BuildContext context) {
    final r = ratio ?? (16.0 / 9.0); // 원본은 가로형으로 표시
    final maxH = 32.0;
    final maxW = 32.0;
    double w, h;
    if (r >= 1.0) {
      // 가로 or 정사각
      w = maxW;
      h = maxW / r;
    } else {
      // 세로
      h = maxH;
      w = maxH * r;
    }
    return Container(
      width: maxW,
      height: maxH,
      alignment: Alignment.center,
      child: Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: selected ? Colors.white.withOpacity(0.3) : Colors.grey[300],
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: selected ? Colors.white : const Color(0xFF1C1C1E),
            width: 1.5,
          ),
        ),
      ),
    );
  }
}
