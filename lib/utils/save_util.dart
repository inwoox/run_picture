import 'package:flutter/material.dart';

/// 저장 중 로딩 다이얼로그 표시
void showSavingDialog(BuildContext context) {
  showDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black38,
    builder: (_) => PopScope(
      canPop: false,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Column(mainAxisSize: MainAxisSize.min, children: [
            CircularProgressIndicator(
                color: Color(0xFF1C1C1E), strokeWidth: 2.5),
            SizedBox(height: 16),
            Text('저장 중...',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                    color: Color(0xFF1C1C1E),
                    decoration: TextDecoration.none)),
          ]),
        ),
      ),
    ),
  );
}

/// 로딩 다이얼로그 닫기
void hideSavingDialog(BuildContext context) {
  if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
}
