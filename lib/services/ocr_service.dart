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
      calories: _extractCalories(text),
      heartRate: _extractHeartRate(text),
      date: _extractDateWithStartTime(text),
    );
  }

  // 거리: 10.01 km / 5.42km
  static String _extractDistance(String text) {
    final patterns = [
      RegExp(r'(\d+[.,]\d+)\s*km', caseSensitive: false),
      RegExp(r'(\d+)\s*km', caseSensitive: false),
    ];
    for (final p in patterns) {
      final m = p.firstMatch(text);
      if (m != null) return '${m.group(1)} km';
    }
    return '';
  }

  // 총 달린 시간
  static String _extractTotalTime(String text) {
    final lines = text.split('\n');
    final timePattern = RegExp(r'(\d{1,3}:\d{2}(?::\d{2})?)');
    final totalLabels = ['총 시간', '총시간', 'elapsed', 'duration', 'moving time', 'total time'];

    // 가민/스트라바: 값이 라벨 위에 있는 경우 (라벨 앞 줄에서 시간 탐색)
    for (int i = 0; i < lines.length; i++) {
      final lineLower = lines[i].toLowerCase().replaceAll(' ', '');
      if (totalLabels.any((l) => lineLower.contains(l.replaceAll(' ', '')))) {
        for (int j = i - 1; j >= (i - 3 < 0 ? 0 : i - 3); j--) {
          final m = timePattern.firstMatch(lines[j]);
          if (m != null) return m.group(1)!;
        }
        // 라벨 뒤에 있는 경우
        for (int j = i + 1; j <= (i + 3 < lines.length ? i + 3 : lines.length - 1); j++) {
          final m = timePattern.firstMatch(lines[j]);
          if (m != null) return m.group(1)!;
        }
      }
    }

    // 폴백: 모든 시간값 중 가장 큰 값
    String best = '';
    int bestSeconds = 0;
    for (final m in timePattern.allMatches(text)) {
      final t = m.group(1)!;
      final parts = t.split(':');
      int seconds = parts.length == 3
          ? int.parse(parts[0]) * 3600 + int.parse(parts[1]) * 60 + int.parse(parts[2])
          : int.parse(parts[0]) * 60 + int.parse(parts[1]);
      if (seconds > bestSeconds) { bestSeconds = seconds; best = t; }
    }
    return best;
  }

  // 페이스: 5'55"/km / 4:39 /km
  static String _extractPace(String text) {
    final patterns = [
      RegExp(r"(\d+[':\u2019]\d{2})\s*/km", caseSensitive: false),
      RegExp(r"(\d+[':\u2019]\d{2})\s*[/\\]?\s*km", caseSensitive: false),
      RegExp(r"페이스[^\d]*(\d+[':\u2019]\d{2})", caseSensitive: false),
      RegExp(r"pace[^\d]*(\d+[':\u2019]\d{2})", caseSensitive: false),
    ];
    for (final p in patterns) {
      final m = p.firstMatch(text);
      if (m != null) return "${m.group(1)}/km";
    }
    return '';
  }

  // 칼로리
  static String _extractCalories(String text) {
    final patterns = [
      RegExp(r'(\d+)\s*kcal', caseSensitive: false),
      RegExp(r'(\d+)\s*cal(?!ories)', caseSensitive: false),
      RegExp(r'칼로리[^\d]*(\d+)'),
    ];
    for (final p in patterns) {
      final m = p.firstMatch(text);
      if (m != null) return '${m.group(1)} kcal';
    }
    return '';
  }

  // 심박수
  static String _extractHeartRate(String text) {
    final patterns = [
      RegExp(r'(\d{2,3})\s*bpm', caseSensitive: false),
      RegExp(r'심박[^\d]*(\d{2,3})'),
      RegExp(r'hr[^\d]*(\d{2,3})', caseSensitive: false),
    ];
    for (final p in patterns) {
      final m = p.firstMatch(text);
      if (m != null) return '${m.group(1)} bpm';
    }
    return '';
  }

  // 날짜 + 시작시간 조합 (라벨 없이 표시용)
  static String _extractDateWithStartTime(String text) {
    // 한국어: "4월 1일" + 시간 (@ 또는 공백 구분)
    final koreanFull = RegExp(r'(\d{1,2}월\s*\d{1,2}일).{0,10}?(\d{1,2}:\d{2})\s*(오전|오후)?');
    final m1 = koreanFull.firstMatch(text);
    if (m1 != null) {
      final date = m1.group(1)!.replaceAll(' ', '');
      final time = m1.group(2)!;
      final ampm = m1.group(3) ?? '';
      return '$date $time${ampm.isNotEmpty ? ' $ampm' : ''}';
    }

    // 한국어 날짜만: "4월 1일"
    final koreanDate = RegExp(r'(\d{1,2}월\s*\d{1,2}일)');
    final m2 = koreanDate.firstMatch(text);
    if (m2 != null) return m2.group(1)!.replaceAll(' ', '');

    // 숫자 날짜: 2026.04.01
    final numericDate = RegExp(r'(\d{4})[.\-/](\d{1,2})[.\-/](\d{1,2})');
    final m3 = numericDate.firstMatch(text);
    if (m3 != null) {
      return '${m3.group(1)}.${m3.group(2)!.padLeft(2, '0')}.${m3.group(3)!.padLeft(2, '0')}';
    }

    // 영어 날짜: Apr 1, 2026
    final engDate = RegExp(r'(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+(\d{1,2}),?\s+(\d{4})', caseSensitive: false);
    final m4 = engDate.firstMatch(text);
    if (m4 != null) return '${m4.group(1)} ${m4.group(2)}, ${m4.group(3)}';

    return '';
  }
}
