import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../models/running_record.dart';

class OcrService {
  static String lastRawText = '';

  static Future<RunningRecord> extractFromImage(String imagePath) async {
    final textRecognizer = TextRecognizer(script: TextRecognitionScript.korean);
    final inputImage = InputImage.fromFilePath(imagePath);
    final recognized = await textRecognizer.processImage(inputImage);
    await textRecognizer.close();

    final text = recognized.text;
    lastRawText = text;
    return RunningRecord(
      distance: _extractDistance(text),
      time: _extractTotalTime(text),
      pace: _extractPace(text),
      heartRate: _extractHeartRate(text),
      date: _extractDate(text),
    );
  }

  // ── 거리 ──────────────────────────────────────────────────────────────────
  static String _extractDistance(String text) {
    final lines = text.split('\n');

    // 라벨 주변 탐색 (거리 / distance)
    for (int i = 0; i < lines.length; i++) {
      final ll = lines[i].toLowerCase().replaceAll(' ', '');
      if (ll.contains('거리') || ll.contains('distance')) {
        for (int d = -3; d <= 3; d++) {
          final j = i + d;
          if (j < 0 || j >= lines.length || j == i) continue;
          final m = RegExp(r'(\d+[.,]\d+|\d+)\s*(km|킬로미터)', caseSensitive: false).firstMatch(lines[j]);
          if (m != null) return '${m.group(1)!.replaceAll(',', '.')} km';
        }
      }
    }

    // "킬로미터" 단위 우선 (가민 한국어 앱)
    final korUnit = RegExp(r'(\d+[.,]\d+|\d+)\s*킬로미터');
    final korMatch = korUnit.firstMatch(text);
    if (korMatch != null) return '${korMatch.group(1)!.replaceAll(',', '.')} km';

    // km 단위: 소수점 있는 값 우선 (지도 마커 "10 km" 보다 "11.90 km" 우선)
    final allKm = RegExp(r'(\d+[.,]\d+|\d+)\s*km', caseSensitive: false).allMatches(text).toList();
    if (allKm.isNotEmpty) {
      // 소수점 있는 값 먼저 찾기
      final decimal = allKm.where((m) => m.group(1)!.contains(RegExp(r'[.,]'))).toList();
      if (decimal.isNotEmpty) return '${decimal.first.group(1)!.replaceAll(',', '.')} km';
      return '${allKm.first.group(1)} km';
    }
    return '';
  }

  // ── 총 달린 시간 ──────────────────────────────────────────────────────────
  static String _extractTotalTime(String text) {
    final lines = text.split('\n');
    final timePattern = RegExp(r'(\d{1,3}:\d{2}(?::\d{2})?)');
    final labels = ['총 시간', '총시간', 'elapsed', 'duration', 'moving time', 'total time', '시간'];

    for (int i = 0; i < lines.length; i++) {
      final ll = lines[i].toLowerCase().replaceAll(' ', '');
      if (labels.any((l) => ll.contains(l.replaceAll(' ', '')))) {
        for (int d = -3; d <= 3; d++) {
          final j = i + d;
          if (j < 0 || j >= lines.length) continue;
          final m = timePattern.firstMatch(lines[j]);
          if (m != null) return m.group(1)!;
        }
      }
    }

    // 폴백: 가장 큰 시간값
    String best = '';
    int bestSec = 0;
    for (final m in timePattern.allMatches(text)) {
      final t = m.group(1)!;
      final parts = t.split(':');
      final sec = parts.length == 3
          ? int.parse(parts[0]) * 3600 + int.parse(parts[1]) * 60 + int.parse(parts[2])
          : int.parse(parts[0]) * 60 + int.parse(parts[1]);
      if (sec > bestSec) { bestSec = sec; best = t; }
    }
    return best;
  }

  // ── 페이스 ────────────────────────────────────────────────────────────────
  static String _extractPace(String text) {
    final lines = text.split('\n');
    final pacePattern = RegExp(r"(\d+[':\u2019\u201C]\d{2})");
    final paceLabels = ['페이스', 'pace', 'avg pace', 'average pace', '평균페이스'];

    // 라벨 주변 탐색
    for (int i = 0; i < lines.length; i++) {
      final ll = lines[i].toLowerCase().replaceAll(' ', '');
      if (paceLabels.any((l) => ll.contains(l.replaceAll(' ', '')))) {
        for (int d = -3; d <= 3; d++) {
          final j = i + d;
          if (j < 0 || j >= lines.length) continue;
          final m = pacePattern.firstMatch(lines[j]);
          if (m != null) return '${m.group(1)}/km';
        }
      }
    }

    // 단위 기반: /km 명시된 경우만
    final m = RegExp(r"(\d+[':\u2019]\d{2})\s*/\s*km", caseSensitive: false).firstMatch(text);
    if (m != null) return '${m.group(1)}/km';

    return '';
  }

  // ── 날짜 (항상 한국어 형식으로 정규화 저장 → _convertDate가 영어로 변환) ──
  static const _engMonthMap = {
    'january': 1, 'february': 2, 'march': 3, 'april': 4,
    'may': 5, 'june': 6, 'july': 7, 'august': 8,
    'september': 9, 'october': 10, 'november': 11, 'december': 12,
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4,
    'jun': 6, 'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };

  static String _extractDate(String text) {
    // 영어: "April 1, 2026 at 8:31 PM" → "4월1일 8:31 오후"
    final engFull = RegExp(
      r'(January|February|March|April|May|June|July|August|September|October|November|December|'
      r'Jan|Feb|Mar|Apr|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+(\d{1,2}),?\s+\d{4}'
      r'(?:\s+at\s+(\d{1,2}:\d{2})\s*(AM|PM|am|pm)?)?',
      caseSensitive: false,
    );
    final m1 = engFull.firstMatch(text);
    if (m1 != null) {
      final month = _engMonthMap[m1.group(1)!.toLowerCase()] ?? 1;
      final day = m1.group(2)!;
      final time = m1.group(3);
      final ampm = m1.group(4);
      String result = '${month}월${day}일';
      if (time != null) {
        final ampmKor = ampm?.toUpperCase() == 'PM' ? ' 오후' : (ampm != null ? ' 오전' : '');
        result += ' $time$ampmKor';
      }
      return result;
    }

    // 한국어: "4월 1일 @ 8:31 오후" / "4월 1일 오후 8:31" / "4월 1일"
    final korFull = RegExp(r'(\d{1,2}월\s*\d{1,2}일)\s*(?:@\s*)?(?:(오전|오후)\s*)?(\d{1,2}:\d{2})\s*(오전|오후)?');
    final m2 = korFull.firstMatch(text);
    if (m2 != null) {
      final date = m2.group(1)!.replaceAll(' ', '');
      final ampm = (m2.group(2) ?? m2.group(4) ?? '').trim();
      final time = m2.group(3)!;
      return '$date $time${ampm.isNotEmpty ? ' $ampm' : ''}';
    }
    final korDate = RegExp(r'(\d{1,2}월\s*\d{1,2}일)').firstMatch(text);
    if (korDate != null) return korDate.group(1)!.replaceAll(' ', '');

    // "2026.04.01" / "2026-04-01" → "4월1일"
    final m3 = RegExp(r'\d{4}[.\-/](\d{1,2})[.\-/](\d{1,2})').firstMatch(text);
    if (m3 != null) return '${int.parse(m3.group(1)!)}월${int.parse(m3.group(2)!)}일';

    return '';
  }

  // ── 심박수 (50~250 범위만 허용) ───────────────────────────────────────────
  static String _extractHeartRate(String text) {
    final lines = text.split('\n');

    bool validHR(String s) {
      final v = int.tryParse(s.trim());
      return v != null && v >= 50 && v <= 250;
    }

    // 라벨 주변 탐색 (bpm은 라벨이 아닌 단위이므로 제외)
    final hrLabels = ['심박', 'heart rate', 'avg hr', 'average heart', 'heartrate'];
    for (int i = 0; i < lines.length; i++) {
      final ll = lines[i].toLowerCase().replaceAll(' ', '');
      if (hrLabels.any((l) => ll.contains(l.replaceAll(' ', '')))) {
        for (int d = -3; d <= 3; d++) {
          final j = i + d;
          if (j < 0 || j >= lines.length) continue;
          final m = RegExp(r'(\d{2,3})').firstMatch(lines[j]);
          if (m != null && validHR(m.group(1)!)) return '${m.group(1)} bpm';
        }
      }
    }

    // 단위 기반 + 범위 검증
    for (final m in RegExp(r'(\d{2,3})\s*bpm', caseSensitive: false).allMatches(text)) {
      if (validHR(m.group(1)!)) return '${m.group(1)} bpm';
    }

    return '';
  }
}
