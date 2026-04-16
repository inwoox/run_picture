import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../models/running_record.dart';

/// 위치 기반 추출에 사용하는 텍스트 라인 래퍼
class _OcrLine {
  final String text;
  final Rect bounds;
  final int idx; // allLines 내 고유 인덱스 (동일 참조 비교 대신 사용)
  _OcrLine({required this.text, required this.bounds, required this.idx});
}

/// 감지된 러닝 앱 유형
enum _AppType { garmin, nikeRunClub, appleHealth, coros, unknown }

class OcrService {
  static String lastRawText = '';
  static String lastDebugLog = ''; // 릴리즈 모드 디버그용

  static Future<RunningRecord> extractFromImage(String imagePath) async {
    final textRecognizer = TextRecognizer(script: TextRecognitionScript.korean);
    final inputImage = InputImage.fromFilePath(imagePath);
    final recognized = await textRecognizer.processImage(inputImage);
    await textRecognizer.close();

    final text = recognized.text;
    lastRawText = text;

    // 위치(boundingBox) 기반 추출 먼저 시도 → 실패 시 기존 정규식 폴백
    final appType = _detectAppType(text);
    final pos = _extractFromBlocks(recognized);

    final record = RunningRecord(
      distance: pos['distance']?.isNotEmpty == true ? pos['distance']! : _extractDistance(text),
      time:     pos['time']?.isNotEmpty == true     ? pos['time']!     : _extractTotalTime(text),
      pace:     pos['pace']?.isNotEmpty == true     ? pos['pace']!     : _extractPace(text),
      heartRate: pos['heartRate']?.isNotEmpty == true ? pos['heartRate']! : _extractHeartRate(text),
      date: _extractDate(text),
    );

    // 디버그 로그 구성 (릴리즈 포함 항상 수집)
    final allLines = _flattenLines(recognized);
    final paceLines = StringBuffer();
    for (final line in allLines) {
      final p = _corosParsePace(line.text.trim());
      if (p != null) paceLines.writeln('  "${line.text.trim()}" → $p');
    }
    final rawLines = allLines.map((l) => '  [${l.idx}] "${l.text}"').join('\n');
    lastDebugLog =
        '▶ AppType: $appType\n'
        '▶ pos: dist=${pos['distance']} time=${pos['time']} pace=${pos['pace']} hr=${pos['heartRate']}\n'
        '▶ final: dist=${record.distance} time=${record.time} pace=${record.pace} hr=${record.heartRate}\n'
        '▶ Pace candidates (_corosParsePace):\n$paceLines'
        '▶ All OCR lines (${allLines.length}):\n$rawLines';

    return record;
  }

  // ── 위치 기반 추출 (앱 유형 감지 → 유형별 전략) ────────────────────────────
  static Map<String, String?> _extractFromBlocks(RecognizedText recognized) {
    final appType = _detectAppType(recognized.text);
    if (kDebugMode) debugPrint('[OCR-TYPE] $appType');

    switch (appType) {
      case _AppType.garmin:
        return _extractGarmin(recognized);
      case _AppType.nikeRunClub:
        return _extractNikeRunClub(recognized);
      case _AppType.appleHealth:
        return _extractAppleHealth(recognized);
      case _AppType.coros:
        return _extractCoros(recognized);
      case _AppType.unknown:
        return _extractGeneric(recognized);
    }
  }

  // ── 앱 유형 감지 ────────────────────────────────────────────────────────────
  /// OCR 텍스트에서 러닝 앱 유형을 식별.
  /// NRC를 먼저 검사(더 구체적 시그널)한 뒤 Garmin 검사.
  static _AppType _detectAppType(String text) {
    final t = text.toLowerCase().replaceAll(' ', '');

    // ── COROS ────────────────────────────────────────────────────────────────
    // 1차: "COROS" 브랜드명 (로고 텍스트)
    // 2차: 로고가 잘린 경우를 위한 COROS 고유 라벨 — "평균EffortPace", "최고(1Km)", "훈련부하"
    //      이 라벨들은 Garmin·NRC·Apple Health에 없어 오감지 위험 없음
    final isCorosLogo = t.contains('coros');
    final isCorosLabel = t.contains('effortpace') ||
        t.contains('최고(1km)') ||
        t.contains('최고(1㎞)') ||
        t.contains('훈련부하');
    if (isCorosLogo || isCorosLabel) return _AppType.coros;

    // ── Apple Health / Apple Watch ───────────────────────────────────────────
    // "운동 세부사항" 섹션 헤더가 Apple Health 고유 식별자
    // 활동 킬로칼로리, 등반 고도, 평균 파워 등도 Apple Health 전용
    if (t.contains('운동세부사항') || t.contains('활동킬로칼로리')) {
      return _AppType.appleHealth;
    }

    // ── Nike Run Club (한국어/영어) ──────────────────────────────────────────
    // 신호 1: 라벨이 제대로 OCR된 경우 ("킬로미터" + "고도상승"/"케이던스")
    final nrcKo = t.contains('킬로미터') &&
        (t.contains('고도상승') || t.contains('케이던스'));
    final nrcEn = t.contains('kilometers') &&
        (t.contains('elevation') || t.contains('cadence'));
    // 신호 2: 연결된 기기 모델명 (라벨 오인식이어도 기기명은 영문이라 잘 잡힘)
    //   Garmin 기기: Forerunner, Fenix, Vivoactive, Instinct, Epix, Venu
    //   Apple Watch 등
    final hasDevice = t.contains('forerunner') || t.contains('fenix') ||
        t.contains('vivoactive') || t.contains('instinct') ||
        t.contains('epix') || t.contains('venu') ||
        t.contains('applewatch');
    if (nrcKo || nrcEn || hasDevice) return _AppType.nikeRunClub;

    // ── Garmin Connect (한국어/영어) ─────────────────────────────────────────
    // 특징: "평균심박수"/"avgheartrate" + "평균페이스"/"avgpace" 조합
    //       공유뷰: 총칼로리/거리 / 앱직접뷰: 칼로리/킬로미터
    final garminSignals = [
      '평균심박수', 'avgheartrate',
      '총칼로리',   'totalcalories',
      '평균페이스', 'avgpace',
    ];
    final hits = garminSignals.where((s) => t.contains(s)).length;
    if (hits >= 2) return _AppType.garmin;

    return _AppType.unknown;
  }

  // ── Garmin Connect 전용 추출 ────────────────────────────────────────────────
  /// Garmin 레이아웃: 값(큰 글씨) → 라벨(작은 글씨) 순서로 위에서 아래로 배치.
  /// 라벨 boundingBox를 기준으로 바로 위에 있는 값 블록을 찾는다.
  static Map<String, String?> _extractGarmin(RecognizedText recognized) {
    final allLines = _flattenLines(recognized);
    if (allLines.isEmpty) return {};

    // Garmin Connect 라벨 정의 (슈파인더 공유뷰 기준: 총시간/총칼로리/거리)
    const garminLabels = <String, List<String>>{
      'distance':  ['거리', 'distance'],
      'heartRate': ['평균심박수', 'avgheartrate'],
      'pace':      ['평균페이스', 'avgpace'],
      'time':      ['총시간', 'totaltime'],
    };

    final result = <String, String?>{};

    for (final entry in garminLabels.entries) {
      final key = entry.key;
      final patterns = entry.value;

      // 1. 라벨 라인 탐색
      _OcrLine? labelLine;
      for (final line in allLines) {
        final ll = line.text.toLowerCase().replaceAll(' ', '');
        if (patterns.any((p) => ll == p || ll.contains(p))) {
          labelLine = line;
          break;
        }
      }
      if (labelLine == null) continue;

      // 2. 라벨 바로 위에서 숫자 포함 라인 탐색 (Garmin: 값이 라벨 위에 위치)
      _OcrLine? best;
      double bestScore = double.infinity;
      for (final line in allLines) {
        if (line.idx == labelLine.idx) continue;
        if (!_posHasNumeric(line.text)) continue;
        final score = _posScoreAbove(labelLine.bounds, line.bounds);
        if (score != null && score < bestScore) {
          bestScore = score;
          best = line;
        }
      }
      if (best == null) continue;

      // 3. 타입별 파싱
      final parsed = _parseValue(key, best.text);
      if (parsed != null && parsed.isNotEmpty) result[key] = parsed;

      if (kDebugMode) {
        debugPrint('[OCR-GARMIN] $key: label="${labelLine.text}" '
            'value="${best.text}" → $parsed');
      }
    }

    return result;
  }

  // ── Nike Run Club 전용 추출 ─────────────────────────────────────────────────
  /// NRC 레이아웃: 값(위) → 라벨(아래) 구조.
  /// 전략 1: 라벨이 OCR에서 정상 인식된 경우 → 라벨 위 값 위치 매칭
  /// 전략 2: 라벨이 오인식된 경우(|O|A, A|2 등) → 값 형식으로 직접 판별
  ///   - 거리:  소수점 숫자 (1~200 범위)
  ///   - 페이스: N'NN'' 또는 N'NN!! 형식 (2~20분)
  ///   - 시간:  h:mm:ss 또는 mm:ss (mm 2자리 이상, 폰시계 "8:48" 제외)
  ///   - 심박수: 단독 2~3자리 숫자 (50~250, ♡/bpm 선택적 포함)
  static Map<String, String?> _extractNikeRunClub(RecognizedText recognized) {
    final allLines = _flattenLines(recognized);
    if (allLines.isEmpty) return {};

    // 전략 1: 라벨 기반 위치 매칭
    const nrcLabels = <String, List<String>>{
      'distance':  ['킬로미터', 'kilometers'],
      'heartRate': ['평균심박수', 'avgheartrate'],
      'pace':      ['평균페이스', 'avgpace'],
      'time':      ['시간', 'time'],
    };
    final byLabel = <String, String?>{};
    for (final entry in nrcLabels.entries) {
      final key = entry.key;
      _OcrLine? labelLine;
      for (final line in allLines) {
        final ll = line.text.toLowerCase().replaceAll(' ', '');
        if (entry.value.any((p) => ll == p || ll.contains(p))) {
          labelLine = line;
          break;
        }
      }
      if (labelLine == null) continue;
      _OcrLine? best;
      double bestScore = double.infinity;
      for (final line in allLines) {
        if (line.idx == labelLine.idx) continue;
        if (!_posHasNumeric(line.text)) continue;
        final score = _posScoreAbove(labelLine.bounds, line.bounds);
        if (score != null && score < bestScore) { bestScore = score; best = line; }
      }
      if (best == null) continue;
      final parsed = _parseValue(key, best.text);
      if (parsed != null && parsed.isNotEmpty) byLabel[key] = parsed;
    }

    // 전략 2: 형식(포맷) 기반 직접 판별 (라벨 오인식 대비)
    final byFormat = _extractNrcByFormat(allLines);

    // 전략 1 우선, 없으면 전략 2
    final result = <String, String?>{};
    for (final key in ['distance', 'time', 'pace', 'heartRate']) {
      result[key] = byLabel[key] ?? byFormat[key];
    }

    if (kDebugMode) {
      debugPrint('[OCR-NRC] label=$byLabel format=$byFormat → $result');
    }
    return result;
  }

  /// NRC 형식 기반 값 추출: 라벨 없이 각 줄의 형식만으로 지표 판별
  static Map<String, String?> _extractNrcByFormat(List<_OcrLine> allLines) {
    final result = <String, String?>{};
    for (final line in allLines) {
      final t = line.text.trim();

      // 거리: "30.01" 또는 "30.01 km" — 소수점 단독 줄, 1~200 범위
      if (result['distance'] == null) {
        final m = RegExp(r'^(\d+[.,]\d+)\s*(?:km)?\s*$',
            caseSensitive: false).firstMatch(t);
        if (m != null) {
          final val = double.tryParse(m.group(1)!.replaceAll(',', '.')) ?? 0;
          if (val >= 1.0 && val <= 200.0) {
            result['distance'] = '${m.group(1)!.replaceAll(',', '.')} km';
          }
        }
      }

      // 페이스: "4'17''" 또는 "4'17!!" — 아포스트로피/느낌표 형식, 2~20분
      if (result['pace'] == null) {
        final m = RegExp(r"^(\d{1,2})'(\d{2})[''!]{1,2}\s*$").firstMatch(t);
        if (m != null) {
          final min = int.tryParse(m.group(1)!) ?? 99;
          final sec = int.tryParse(m.group(2)!) ?? 60;
          if (min >= 2 && min < 20 && sec < 60) {
            result['pace'] = "$min'${m.group(2)!}\"/km";
          }
        }
      }

      // 시간: "2:08:43"(h:mm:ss) 또는 "43:35"(mm:ss, 분 2자리 이상)
      // 분이 2자리 이상이어야 폰 시계 "8:48"(1자리 시) 제외
      if (result['time'] == null) {
        final mHms = RegExp(r'^(\d{1,3}:\d{2}:\d{2})\s*$').firstMatch(t);
        if (mHms != null) {
          final parts = mHms.group(1)!.split(':');
          final h = int.tryParse(parts[0]) ?? 99;
          final mn = int.tryParse(parts[1]) ?? 99;
          final sc = int.tryParse(parts[2]) ?? 99;
          if (h < 24 && mn < 60 && sc < 60) result['time'] = mHms.group(1);
        }
        if (result['time'] == null) {
          final mMs = RegExp(r'^(\d{2,3}:\d{2})\s*$').firstMatch(t);
          if (mMs != null) {
            final parts = mMs.group(1)!.split(':');
            final mn = int.tryParse(parts[0]) ?? 99;
            final sc = int.tryParse(parts[1]) ?? 99;
            if (mn < 600 && sc < 60) result['time'] = mMs.group(1);
          }
        }
      }

      // 심박수: "164" 또는 "164 ♡" — 단독 2~3자리, 50~250, ♡/bpm 선택적
      // "164 m"(고도)은 'm'이 패턴에 없어 제외됨
      if (result['heartRate'] == null) {
        final m = RegExp(r'^(\d{2,3})\s*(?:[♡❤]|bpm)?\s*$',
            caseSensitive: false).firstMatch(t);
        if (m != null) {
          final hr = int.tryParse(m.group(1)!) ?? 0;
          if (hr >= 50 && hr <= 250) result['heartRate'] = '${m.group(1)} bpm';
        }
      }
    }
    return result;
  }

  // ── COROS 전용 추출 ──────────────────────────────────────────────────────────
  /// COROS 한국어 라벨(거리·운동시간·평균페이스·평균심박수)은 OCR에서 거의 인식 안 됨.
  /// 유일하게 항상 인식되는 영문 라벨 "Effort Pace"를 위치 앵커로 사용.
  ///
  /// [페이스 추출 전략]
  ///   레이아웃:  [운동시간값]  [평균페이스값]  [EffortPace값]   ← 같은 행(row1)
  ///              [운동시간라벨] [평균페이스라벨] [Effort Pace]   ← 라벨 행(row2)
  ///   1) "Effort Pace" 라벨 위의 값 → EffortPace 값 (positional)
  ///   2) EffortPace 값과 같은 Y 범위 + 바로 왼쪽 값 → 평균페이스 값
  ///   파서: _corosParsePace — apostrophe 있는 표준형 + OCR 누락형("521\"" → 5'21") 모두 처리
  ///
  /// [시간 추출 전략]
  ///   COROS 위첨자: "34:03⁹⁸" → OCR: "34:0398" (trailing digits 부착)
  ///   _extractTotalTime standalone 탐색보다 먼저 처리하여 폰 시계 오인식 방지
  ///
  /// [거리·심박수]
  ///   라벨 없이도 regex fallback(_extractDistance, _extractHeartRate)이 정확 → pos에서 생략
  static Map<String, String?> _extractCoros(RecognizedText recognized) {
    final allLines = _flattenLines(recognized);
    if (allLines.isEmpty) return {};
    final result = <String, String?>{};

    // ── 페이스: "Effort Pace" 앵커 기반 ────────────────────────────────────────
    // "Effort Pace" 라벨 후보 전체 수집 (페이스 차트 헤더 등 복수 존재 가능)
    final epLabels = allLines
        .where((l) => l.text.toLowerCase().replaceAll(' ', '').contains('effortpace'))
        .toList();

    for (final epLabel in epLabels) {
      // 1) Effort Pace 라벨 바로 위 값 탐색 → EffortPace 값
      _OcrLine? epValue;
      double bestEpScore = double.infinity;
      for (final line in allLines) {
        if (line.idx == epLabel.idx) continue;
        if (!_posHasNumeric(line.text)) continue;
        final score = _posScoreAbove(epLabel.bounds, line.bounds);
        if (score != null && score < bestEpScore) {
          bestEpScore = score;
          epValue = line;
        }
      }
      if (epValue == null) continue;
      if (_corosParsePace(epValue.text) == null) continue; // 페이스 값이 아니면 다음 후보

      // 2) EffortPace 값과 같은 Y 범위 + 바로 왼쪽 값 → 평균페이스 값
      //    Y 판정: 두 bounding box의 Y 범위가 겹치면 같은 행으로 간주 (±10px 여유)
      final epTop = epValue.bounds.top;
      final epBottom = epValue.bounds.bottom;
      final epVcx = (epValue.bounds.left + epValue.bounds.right) / 2;

      _OcrLine? avgPaceValue;
      double bestDx = double.infinity;
      for (final line in allLines) {
        if (line.idx == epValue.idx) continue;
        if (!_posHasNumeric(line.text)) continue;
        final lineTop    = line.bounds.top;
        final lineBottom = line.bounds.bottom;
        final vcx        = (line.bounds.left + line.bounds.right) / 2;
        // Y 범위 겹침 여부
        final sameRow = epTop < lineBottom + 10 && lineTop < epBottom + 10;
        if (!sameRow) continue;
        if (vcx >= epVcx) continue; // 왼쪽만
        final dx = epVcx - vcx;
        if (dx < bestDx) { bestDx = dx; avgPaceValue = line; }
      }

      if (avgPaceValue != null) {
        final parsed = _corosParsePace(avgPaceValue.text);
        if (parsed != null) { result['pace'] = parsed; break; }
      }
      // 평균페이스 못 찾은 경우 EffortPace 값으로 대체
      final epParsed = _corosParsePace(epValue.text);
      if (epParsed != null) { result['pace'] = epParsed; break; }
    }

    // ── 운동시간: trailing-digit 패턴 ───────────────────────────────────────────
    {
      String? bestTime;
      int bestSec = 0;
      for (final line in allLines) {
        final t = line.text.trim();
        final m = RegExp(r'^(\d{1,3}:\d{2}(?::\d{2})?)\d{2,4}\s*$').firstMatch(t);
        if (m == null) continue;
        final tv = m.group(1)!;
        final parts = tv.split(':');
        int totalSec = 0; bool valid = false;
        if (parts.length == 2) {
          final min = int.tryParse(parts[0]) ?? 99;
          final sec = int.tryParse(parts[1]) ?? 99;
          if (min >= 1 && min < 600 && sec < 60) { totalSec = min * 60 + sec; valid = true; }
        } else if (parts.length == 3) {
          final h  = int.tryParse(parts[0]) ?? 99;
          final mn = int.tryParse(parts[1]) ?? 99;
          final sc = int.tryParse(parts[2]) ?? 99;
          if (h < 24 && mn < 60 && sc < 60) { totalSec = h * 3600 + mn * 60 + sc; valid = true; }
        }
        if (valid && totalSec > bestSec) { bestSec = totalSec; bestTime = tv; }
      }
      if (bestTime != null) result['time'] = bestTime;
    }

    return result;
  }

  /// COROS 페이스 파서: apostrophe 있는 표준형 + OCR 누락형 모두 처리.
  /// OCR 누락형: "521\" lkm" → 5'21", "508\"" → 5'08"
  ///   (대형 폰트 값에서 apostrophe가 사라지고 분·초가 붙어서 OCR됨)
  static String? _corosParsePace(String text) {
    // 표준형: apostrophe 있는 경우 (5'21", 5:21 등)
    final std = _posParseTPace(text);
    if (std != null) return std;
    // OCR 누락형: (?<!\d) [1자리분] [2자리초] [닫는따옴표]
    final m = RegExp(r'(?<!\d)(\d{1})(\d{2})["\u201D\u2033]').firstMatch(text);
    if (m == null) return null;
    final min = int.tryParse(m.group(1)!) ?? 99;
    final sec = int.tryParse(m.group(2)!) ?? 99;
    if (min < 2 || min >= 20 || sec >= 60) return null;
    return "$min'${m.group(2)!}\"/km";
  }

  // ── Apple Health / Apple Watch 전용 추출 ────────────────────────────────────
  /// Apple Health 레이아웃: 라벨(위) → 값(아래) 구조, 2열 그리드.
  /// 거리:    "거리"         → "8.00KM"
  /// 시간:    "경과 시간"(우선) 또는 "운동 시간" → "0:59:56"
  /// 페이스:  "평균 페이스"  → "7'29\"/KM"  (이미 /KM 포함)
  /// 심박수:  "평균 심박수"  → "163BPM"      (BPM 단위 포함)
  static Map<String, String?> _extractAppleHealth(RecognizedText recognized) {
    final allLines = _flattenLines(recognized);
    if (allLines.isEmpty) return {};

    // 각 지표별 라벨 후보 (우선순위 순서)
    const appleLabels = <String, List<String>>{
      'distance':  ['거리'],
      'heartRate': ['평균심박수'],
      'pace':      ['평균페이스'],
      // 시간: "경과 시간"(elapsed) 우선, "운동 시간"(workout) 폴백
      'time':      ['경과시간', '운동시간'],
    };

    final result = <String, String?>{};

    for (final entry in appleLabels.entries) {
      final key = entry.key;
      final patterns = entry.value;

      // 우선순위 순서로 라벨 탐색 (patterns 리스트 앞쪽이 우선)
      _OcrLine? labelLine;
      for (final pattern in patterns) {
        for (final line in allLines) {
          final ll = line.text.toLowerCase().replaceAll(' ', '');
          if (ll == pattern || ll.contains(pattern)) {
            labelLine = line;
            break;
          }
        }
        if (labelLine != null) break;
      }
      if (labelLine == null) continue;

      // 라벨 아래에서 가장 가까운 숫자 포함 라인 탐색 (Apple: 라벨 위, 값 아래)
      _OcrLine? best;
      double bestScore = double.infinity;
      for (final line in allLines) {
        if (line.idx == labelLine.idx) continue;
        if (!_posHasNumeric(line.text)) continue;
        final score = _posScoreBelow(labelLine.bounds, line.bounds);
        if (score != null && score < bestScore) {
          bestScore = score;
          best = line;
        }
      }
      if (best == null) continue;

      final parsed = _parseValue(key, best.text);
      if (parsed != null && parsed.isNotEmpty) result[key] = parsed;

      if (kDebugMode) {
        debugPrint('[OCR-APPLE] $key: label="${labelLine.text}" '
            'value="${best.text}" → $parsed');
      }
    }

    return result;
  }

  // ── Generic 추출 (앱 미감지 시 폴백) ────────────────────────────────────────
  /// 라벨 아래/오른쪽에서 값을 찾는 일반적인 레이아웃 전략.
  static Map<String, String?> _extractGeneric(RecognizedText recognized) {
    final allLines = _flattenLines(recognized);
    if (allLines.isEmpty) return {};

    const genericLabels = <String, List<String>>{
      'distance':  ['거리', 'distance', 'kilometers'],
      'time':      ['총시간', 'elapsed', 'duration', 'movingtime', 'totaltime'],
      'pace':      ['페이스', 'pace', 'avgpace'],
      'heartRate': ['심박수', 'heartrate', 'avghr'],
    };

    final result = <String, String?>{};

    for (final entry in genericLabels.entries) {
      final key = entry.key;
      final patterns = entry.value;

      _OcrLine? labelLine;
      for (final line in allLines) {
        final ll = line.text.toLowerCase().replaceAll(' ', '');
        if (patterns.any((p) => ll.contains(p))) {
          labelLine = line;
          break;
        }
      }
      if (labelLine == null) continue;

      _OcrLine? best;
      double bestScore = double.infinity;
      for (final line in allLines) {
        if (line.idx == labelLine.idx) continue;
        if (!_posHasNumeric(line.text)) continue;
        final score = _posScoreBelow(labelLine.bounds, line.bounds);
        if (score != null && score < bestScore) {
          bestScore = score;
          best = line;
        }
      }
      if (best == null) continue;

      final parsed = _parseValue(key, best.text);
      if (parsed != null && parsed.isNotEmpty) result[key] = parsed;
    }

    return result;
  }

  // ── 공통 유틸 ────────────────────────────────────────────────────────────────

  /// 모든 블록의 라인을 인덱스와 함께 평탄화
  static List<_OcrLine> _flattenLines(RecognizedText recognized) {
    final lines = <_OcrLine>[];
    int idx = 0;
    for (final block in recognized.blocks) {
      for (final line in block.lines) {
        lines.add(_OcrLine(text: line.text, bounds: line.boundingBox, idx: idx++));
      }
    }
    return lines;
  }

  /// Garmin용 점수: 값이 라벨 바로 위에 있을수록 낮은 점수(좋음).
  /// 값이 라벨보다 아래에 있으면 null(제외).
  static double? _posScoreAbove(Rect label, Rect value) {
    final lcx = (label.left + label.right) / 2;
    final lcy = (label.top + label.bottom) / 2;
    final vcx = (value.left + value.right) / 2;
    final vcy = (value.top + value.bottom) / 2;
    final dy = lcy - vcy; // 양수 = 값이 라벨 위 (Garmin에서 원하는 방향)
    // 값이 라벨 아래에 있으면 제외 (라벨 높이만큼의 여유는 허용)
    if (dy < -(label.height)) return null;
    // 아래에 있는 경우 페널티 5배
    final edy = dy < 0 ? (-dy) * 5.0 : dy;
    return (vcx - lcx) * (vcx - lcx) + edy * edy;
  }

  /// Generic용 점수: 값이 라벨 아래/오른쪽에 있을수록 낮은 점수(좋음).
  static double? _posScoreBelow(Rect label, Rect value) {
    final lcx = (label.left + label.right) / 2;
    final lcy = (label.top + label.bottom) / 2;
    final vcx = (value.left + value.right) / 2;
    final vcy = (value.top + value.bottom) / 2;
    final dy = vcy - lcy; // 양수 = 값이 라벨 아래 (원하는 방향)
    // 값이 라벨보다 현저히 위면 제외
    if (dy < -(label.height * 2)) return null;
    // 위에 있으면 페널티 3배
    final edy = dy < 0 ? (-dy) * 3.0 : dy;
    return (vcx - lcx) * (vcx - lcx) + edy * edy;
  }

  static bool _posHasNumeric(String text) => RegExp(r'\d').hasMatch(text);

  /// 지표 키에 따라 적절한 파서 호출
  static String? _parseValue(String key, String text) {
    switch (key) {
      case 'distance':  return _posParseDistance(text);
      case 'time':      return _posParseTime(text);
      case 'pace':      return _posParseTPace(text);
      case 'heartRate': return _posParseHR(text);
      default:          return null;
    }
  }

  /// 거리 파싱: "25.48 km", "25.48", "25,48" 등
  static String? _posParseDistance(String text) {
    final m = RegExp(r'(\d+[.,]\d+)').firstMatch(text);
    if (m == null) return null;
    final val = double.tryParse(m.group(1)!.replaceAll(',', '.')) ?? 0;
    if (val < 1.0 || val > 200.0) return null;
    return '${m.group(1)!.replaceAll(',', '.')} km';
  }

  /// 총 시간 파싱: "1:57:30", "41:51" 등
  static String? _posParseTime(String text) {
    final m = RegExp(r'(\d{1,3}:\d{2}(?::\d{2})?)').firstMatch(text);
    if (m == null) return null;
    final t = m.group(1)!;
    final parts = t.split(':');
    if (parts.length == 2) {
      final min = int.tryParse(parts[0]) ?? 99;
      final sec = int.tryParse(parts[1]) ?? 99;
      if (min < 600 && sec < 60) return t;
    } else if (parts.length == 3) {
      final h = int.tryParse(parts[0]) ?? 99;
      final mn = int.tryParse(parts[1]) ?? 99;
      final sc = int.tryParse(parts[2]) ?? 99;
      if (h < 24 && mn < 60 && sc < 60) return t;
    }
    return null;
  }

  /// 페이스 파싱: "5:54", "4:37 /km" 등 → "5'54\"/km" 형식으로 정규화
  static String? _posParseTPace(String text) {
    final m = RegExp(r"(\d{1,2})[:''](\d{2})").firstMatch(text);
    if (m == null) return null;
    final min = int.tryParse(m.group(1)!) ?? 99;
    final sec = int.tryParse(m.group(2)!) ?? 60;
    if (min < 2 || min >= 20 || sec >= 60) return null;
    return "$min'${m.group(2)!}\"/km";
  }

  /// 심박수 파싱: "147 bpm", "147", "1470(♡→0)" 등
  static String? _posParseHR(String text) {
    if (RegExp(r'^[-–—]+\s*[♡oO]?\s*$').hasMatch(text.trim())) return '';
    final mBpm = RegExp(r'(\d{2,3})\s*bpm', caseSensitive: false).firstMatch(text);
    if (mBpm != null) {
      final hr = int.tryParse(mBpm.group(1)!) ?? 0;
      if (hr >= 50 && hr <= 250) return '${mBpm.group(1)} bpm';
    }
    final mZero = RegExp(r'^(\d{2,3})0\s*$').firstMatch(text.trim());
    if (mZero != null) {
      final hr = int.tryParse(mZero.group(1)!) ?? 0;
      if (hr >= 50 && hr <= 250) return '${mZero.group(1)} bpm';
    }
    final mPlain = RegExp(r'\b(\d{2,3})\b').firstMatch(text);
    if (mPlain != null) {
      final hr = int.tryParse(mPlain.group(1)!) ?? 0;
      if (hr >= 50 && hr <= 250) return '${mPlain.group(1)} bpm';
    }
    return null;
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
          // trailing dots 제거 ("15.37.." → "15.37")
          final cleaned = lines[j].replaceAll(RegExp(r'\.+$'), '');
          // krm/im/k: Samsung Health에서 OCR이 "km"을 잘못 읽는 경우 대응
          final m = RegExp(r'(\d+[.,]\d+|\d+)\s*(km|krm|im|\bk\b|킬로미터)', caseSensitive: false).firstMatch(cleaned);
          if (m != null) return '${m.group(1)!.replaceAll(',', '.')} km';
          // 단위 없이 소수점 숫자만 있는 경우 ("15.37.." → "15.37")
          final mNum = RegExp(r'^(\d+[.,]\d+)$').firstMatch(cleaned.trim());
          if (mNum != null) {
            final val = double.tryParse(mNum.group(1)!.replaceAll(',', '.')) ?? 0;
            if (val >= 1.0 && val <= 200.0) return '${mNum.group(1)!.replaceAll(',', '.')} km';
          }
        }
      }
    }

    // "킬로미터" 단위 우선 (가민 한국어 앱)
    final korUnit = RegExp(r'(\d+[.,]\d+|\d+)\s*킬로미터');
    final korMatch = korUnit.firstMatch(text);
    if (korMatch != null) return '${korMatch.group(1)!.replaceAll(',', '.')} km';

    // Nike Run Club (영문): "Kilometers" 라벨 — 라벨 ±3줄 내 소수점 거리 탐색
    // "10.11\nKilometers" 패턴. 지도 마커 "2 km"/"4 km"보다 먼저 처리
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].trim().toLowerCase() == 'kilometers') {
        for (int d = -3; d <= 3; d++) {
          final j = i + d;
          if (j < 0 || j >= lines.length || j == i) continue;
          final cleaned = lines[j].replaceAll(RegExp(r'\.+$'), '');
          final mNum = RegExp(r'^(\d+[.,]\d+)$').firstMatch(cleaned.trim());
          if (mNum != null) {
            final val = double.tryParse(mNum.group(1)!.replaceAll(',', '.')) ?? 0;
            if (val >= 1.0 && val <= 200.0) return '${mNum.group(1)!.replaceAll(',', '.')} km';
          }
        }
      }
    }

    // COROS: "21.19.m" 형식 → "21.19km" 오인식 (k→. 오인식)
    // "21.19.m" 에서 마지막 ".m" 이 "km" 의 "k→." 오인식
    for (final mm in RegExp(r'(\d+[.,]\d+)\.m(?=\s|$)', caseSensitive: false, multiLine: true).allMatches(text)) {
      final val = double.tryParse(mm.group(1)!.replaceAll(',', '.')) ?? 0;
      if (val >= 1.0 && val <= 200.0) return '${mm.group(1)!.replaceAll(',', '.')} km';
    }

    // Garmin: "18.10.." 형식 — 소수점 거리 뒤에 점이 여러 개 붙는 경우 (km 단위 누락)
    // "18.10km" → "18.10.." 으로 OCR 오인식. 1.03 m (평균 보폭) 보다 먼저 처리해야 함
    for (final mm in RegExp(r'(\d+[.,]\d+)\.\.+(?:\s|$)', caseSensitive: false, multiLine: true).allMatches(text)) {
      final val = double.tryParse(mm.group(1)!.replaceAll(',', '.')) ?? 0;
      if (val >= 1.0 && val <= 200.0) return '${mm.group(1)!.replaceAll(',', '.')} km';
    }

    // COROS: "10.01." 형식 — 소수점 거리 뒤에 점 하나가 붙는 경우 (km 단위 누락)
    // "10.01km" → "10.01." 으로 OCR 오인식. 점 두 개 이상 패턴과 별개의 고유 패턴
    // ^ 앵커(multiLine)로 줄 시작 위치만 탐색 → "2026.04.11." 날짜 문자열 내 오인식 방지
    for (final mm in RegExp(r'^(\d+[.,]\d+)\.(?:\s|$)', caseSensitive: false, multiLine: true).allMatches(text)) {
      final val = double.tryParse(mm.group(1)!.replaceAll(',', '.')) ?? 0;
      if (val >= 1.0 && val <= 200.0) return '${mm.group(1)!.replaceAll(',', '.')} km';
    }

    // Strava/Nike: 소수점 거리가 단독 줄, 이후 5줄 내에 "km" 단독 줄이 있는 경우
    // "30.07\n144 bpm\n2:55:27\nkm" → "5:50 krm" 같은 오인식 패턴보다 먼저 처리
    for (int i = 0; i < lines.length; i++) {
      final mDecLine = RegExp(r'^(\d+[.,]\d+)$').firstMatch(lines[i].trim());
      if (mDecLine != null) {
        final raw = mDecLine.group(1)!;
        if (raw.contains(',') && RegExp(r',\d{3}$').hasMatch(raw)) continue;
        final val = double.tryParse(raw.replaceAll(',', '.')) ?? 0;
        if (val < 1.0 || val > 200.0) continue;
        for (int d = 1; d <= 5; d++) {
          final j = i + d;
          if (j >= lines.length) break;
          if (lines[j].trim().toLowerCase() == 'km') {
            return '${raw.replaceAll(',', '.')} km';
          }
        }
      }
    }

    // Garmin: "6.41km" 처럼 소수점 거리 + km 단위가 공백 없이 붙어있는 경우
    // COROS "1.2 m"(평균 보폭) 오인식보다 우선 처리
    // (?!\/) : "9.6km/h" 같은 속도 단위(km/h) 제외
    final mKmAttached = RegExp(r'(\d+[.,]\d+)km(?!\/)(?:\b|$)', caseSensitive: false).firstMatch(text);
    if (mKmAttached != null) {
      final val = double.tryParse(mKmAttached.group(1)!.replaceAll(',', '.')) ?? 0;
      if (val >= 1.0 && val <= 200.0) return '${mKmAttached.group(1)!.replaceAll(',', '.')} km';
    }

    // COROS: OCR이 "km"을 "m"으로 인식하는 경우 ("21.19 m" → "21.19 km")
    // 소수점 있는 합리적 거리 범위 (1~200), 뒤에 문자 없음 → 고도 "32 m"은 소수점 없으므로 미매칭
    for (final mm in RegExp(r'(\d+[.,]\d+)\s*m(?=\s|$)', caseSensitive: false, multiLine: true).allMatches(text)) {
      final val = double.tryParse(mm.group(1)!.replaceAll(',', '.')) ?? 0;
      if (val >= 1.0 && val <= 200.0) {
        return '${mm.group(1)!.replaceAll(',', '.')} km';
      }
    }

    // COROS: OCR이 "km"을 "n"으로 인식하는 경우 ("9.86 n" → "9.86 km", km→n 오인식)
    // 소수점 있는 합리적 거리 범위 (1~200), \b로 단독 단어 보장
    for (final mm in RegExp(r'(\d+[.,]\d+)\s+n\b(?=\s|$)', caseSensitive: false, multiLine: true).allMatches(text)) {
      final val = double.tryParse(mm.group(1)!.replaceAll(',', '.')) ?? 0;
      if (val >= 1.0 && val <= 200.0) return '${mm.group(1)!.replaceAll(',', '.')} km';
    }

    // Samsung Health: OCR이 "km"을 "krn"으로 잘못 인식하는 경우 ("11.21 krn" → km→krn, m→n)
    for (final mm in RegExp(r'(\d+[.,]\d+|\d+)\s*krn\b(?=\s|$)', caseSensitive: false).allMatches(text)) {
      final val = double.tryParse(mm.group(1)!.replaceAll(',', '.')) ?? 0;
      if (val >= 1.0 && val <= 200.0) return '${mm.group(1)!.replaceAll(',', '.')} km';
    }

    // COROS: OCR이 "km"을 "um"으로 잘못 인식하는 경우 ("18.02 um" → km→um, k→u 오인식)
    for (final mm in RegExp(r'(\d+[.,]\d+|\d+)\s*um\b(?=\s|$)', caseSensitive: false).allMatches(text)) {
      final val = double.tryParse(mm.group(1)!.replaceAll(',', '.')) ?? 0;
      if (val >= 1.0 && val <= 200.0) return '${mm.group(1)!.replaceAll(',', '.')} km';
    }

    // Samsung Health: OCR이 "km"을 "krm"/"im"/"k" 등으로 잘못 인식하는 경우
    for (final mm in RegExp(r'(\d+[.,]\d+|\d+)\s*(krm|im|\bk\b)(?=\s|$)', caseSensitive: false).allMatches(text)) {
      final val = double.tryParse(mm.group(1)!.replaceAll(',', '.')) ?? 0;
      if (val >= 1.0 && val <= 200.0) return '${mm.group(1)!.replaceAll(',', '.')} km';
    }

    // Garmin: 거리 단위("킬로미터")가 OCR에서 완전 누락된 경우
    // 상위 10줄에서 소수점 숫자만 단독으로 있는 줄 탐색 (예: "11.90" 한 줄 전체)
    // → 지도 마커 "10 km", "6 km" 같은 정수 km보다 우선
    final distLines = text.split('\n').take(10).toList();
    for (final line in distLines) {
      final mDecimal = RegExp(r'^(\d+[.,]\d+)$').firstMatch(line.trim());
      if (mDecimal != null) {
        final raw = mDecimal.group(1)!;
        // 쉼표 뒤 3자리는 천 단위 구분자 (1,384 = 칼로리) → 거리 아님
        if (raw.contains(',') && RegExp(r',\d{3}$').hasMatch(raw)) continue;
        final val = double.tryParse(raw.replaceAll(',', '.')) ?? 0;
        if (val >= 1.0 && val <= 200.0) {
          return '${raw.replaceAll(',', '.')} km';
        }
      }
    }

    // COROS: 알림/상태바가 포함된 캡처 — 거리가 11~15번째 줄에 위치
    // 상위 10줄 탐색에서 제외되는 경우 (알림바 3~5줄 + COROS 로고줄 등)
    final distLines15 = text.split('\n').take(15).toList();
    for (final line in distLines15) {
      final mDecimal15 = RegExp(r'^(\d+[.,]\d+)$').firstMatch(line.trim());
      if (mDecimal15 != null) {
        final raw = mDecimal15.group(1)!;
        if (raw.contains(',') && RegExp(r',\d{3}$').hasMatch(raw)) continue;
        final val = double.tryParse(raw.replaceAll(',', '.')) ?? 0;
        if (val >= 1.0 && val <= 200.0) return '${raw.replaceAll(',', '.')} km';
      }
    }

    // Samsung Health: "7.77" 단독 줄 + 몇 줄 뒤 "km" 단독 줄 패턴
    // "km" 단독 줄을 찾아 위 5줄 내에서 소수점 거리 역방향 탐색
    // "44:55" 같은 시간값은 소수점 없으므로 안전
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].trim().toLowerCase() == 'km') {
        for (int d = 1; d <= 5; d++) {
          final j = i - d;
          if (j < 0) break;
          final mDec = RegExp(r'^(\d+[.,]\d+)$').firstMatch(lines[j].trim());
          if (mDec != null) {
            final raw = mDec.group(1)!;
            if (raw.contains(',') && RegExp(r',\d{3}$').hasMatch(raw)) continue;
            final val = double.tryParse(raw.replaceAll(',', '.')) ?? 0;
            if (val >= 1.0 && val <= 200.0) return '${raw.replaceAll(',', '.')} km';
          }
        }
      }
    }

    // COROS: "km" 단독 줄 기준 위 6~10줄에서 소수점 거리 역방향 탐색
    // Samsung Health 패턴(1~5줄)으로 미처 잡지 못하는 경우 대응
    // "Ž|2(1Km)O" 같은 레이블 내 "1Km"이 allKm에 잡히기 전에 처리
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].trim().toLowerCase() == 'km') {
        for (int d = 6; d <= 10; d++) {
          final j = i - d;
          if (j < 0) break;
          final mDec = RegExp(r'^(\d+[.,]\d+)$').firstMatch(lines[j].trim());
          if (mDec != null) {
            final raw = mDec.group(1)!;
            if (raw.contains(',') && RegExp(r',\d{3}$').hasMatch(raw)) continue;
            final val = double.tryParse(raw.replaceAll(',', '.')) ?? 0;
            if (val >= 1.0 && val <= 200.0) return '${raw.replaceAll(',', '.')} km';
          }
        }
      }
    }

    // km 단위: 소수점 있는 값 우선 (지도 마커 "10 km" 보다 "11.90 km" 우선)
    // [^\S\n]* : 공백은 허용하되 줄바꿈은 불허 → "43:36\nkm" 오매칭 방지
    final allKm = RegExp(r'(\d+[.,]\d+|\d+)[^\S\n]*km', caseSensitive: false).allMatches(text).toList();
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

    // COROS: "58:06%" 형식 — 위첨자(98 등)가 "%"로 OCR 오인식
    // 단독 줄 판정 불가로 standalone 탐색에서 제외됨 → 폰 시계값보다 먼저 처리
    for (final line in lines) {
      final mPctTime = RegExp(r'^(\d{1,3}:\d{2}(?::\d{2})?)%\d*$').firstMatch(line.trim());
      if (mPctTime != null) return mPctTime.group(1)!;
    }

    // Samsung Health: 시계 아이콘(Ö 등) + 시간 "Ö 1:25:59" 형식
    // 아이콘 prefix로 standalone 판정 불가 → 폰 시계값 오인식 방지를 위해 먼저 처리
    for (final line in lines) {
      final mIconTime = RegExp(r'^[^\d\s]\s+(\d{1,3}:\d{2}:\d{2})\s*$').firstMatch(line.trim());
      if (mIconTime != null) return mIconTime.group(1)!;
    }

    // Strava: 아이콘 prefix + h:mm:ss — $ 앵커 없이 후행 비숫자 문자 허용
    // "Ō 1:01:46" 등 mIconTime($앵커)이 trailing chars로 실패할 때 대응
    // [^\d]+ → 최소 1개의 비숫자 prefix 필수(standalone h:mm:ss와 구별), \D*$ → 비숫자 후행 허용
    for (final line in lines) {
      final mIconHMSFlex = RegExp(r'^[^\d]+(\d{1,3}:\d{2}:\d{2})\D*$').firstMatch(line.trim());
      if (mIconHMSFlex != null) {
        final t = mIconHMSFlex.group(1)!;
        final parts = t.split(':');
        final h = int.tryParse(parts[0]) ?? 99;
        final m2 = int.tryParse(parts[1]) ?? 99;
        final s = int.tryParse(parts[2]) ?? 99;
        if (h < 24 && m2 < 60 && s < 60) return t;
      }
    }

    // COROS: "1:08:54 09" 형식 — h:mm:ss 뒤에 위첨자가 1~2자리 숫자로 OCR 오인식
    // mHMSCalorie(\d{3})와 달리 1~2자리 trailing 숫자 처리
    for (final line in lines) {
      final mHMSTrail2 = RegExp(r'^(\d{1,3}:\d{2}:\d{2})\s+\d{1,2}$').firstMatch(line.trim());
      if (mHMSTrail2 != null) {
        final t = mHMSTrail2.group(1)!;
        final parts = t.split(':');
        final h = int.tryParse(parts[0]) ?? 99;
        final m2 = int.tryParse(parts[1]) ?? 99;
        final s = int.tryParse(parts[2]) ?? 99;
        if (h < 24 && m2 < 60 && s < 60) return t;
      }
    }

    // 슈파인더: "1:27:0 633" 형식 — 초가 1자리로 OCR 오인식 + 칼로리가 같은 줄
    // 실제 시간 1:27:05인데 OCR이 "0" 뒤 "5"를 다음 줄로 분리 → 초를 0으로 처리
    // mHMSCalorie(\d{2} 초 요구)보다 먼저 처리
    for (final line in lines) {
      final mHMSShortCalorie = RegExp(r'^(\d{1,3}:\d{2}):(\d)\s+\d{2,3}$').firstMatch(line.trim());
      if (mHMSShortCalorie != null) {
        final mm = mHMSShortCalorie.group(1)!;
        final s = mHMSShortCalorie.group(2)!;
        final parts = mm.split(':');
        final h = int.tryParse(parts[0]) ?? 99;
        final m2 = int.tryParse(parts[1]) ?? 99;
        if (h < 24 && m2 < 60) return '$mm:0$s';
      }
    }

    // h:mm:ss 및 mm:ss standalone 선탐색 — trailing 패턴들이 "11:404" 등을 먼저 잡기 전에 처리
    // "56:22" 단독 줄이 있으면 "11:404" → mTrailDigitTime → "11:40" 방지
    // trailing이 붙은 줄은 remainder 비어있지 않아 탈락 → trailing 패턴에서 처리
    // 가장 큰 시간값 선택 (여러 standalone 중 운동시간이 더 크므로)
    {
      String earlyBest = '';
      int earlyBestSec = 0;
      for (final line in lines) {
        final mEarly = RegExp(r'^(\d{1,3}:\d{2}(?::\d{2})?)$').firstMatch(line.trim());
        if (mEarly == null) continue;
        final t = mEarly.group(1)!;
        final parts = t.split(':');
        final first = int.tryParse(parts[0]) ?? 99;
        final second = int.tryParse(parts[1]) ?? 99;
        if (second >= 60) continue;
        if (parts.length == 3) {
          final third = int.tryParse(parts[2]) ?? 99;
          if (first >= 24 || third >= 60) continue;
        }
        final sec = parts.length == 3
            ? first * 3600 + second * 60 + (int.tryParse(parts[2]) ?? 0)
            : first * 60 + second;
        if (sec > earlyBestSec) { earlyBestSec = sec; earlyBest = t; }
      }
      if (earlyBest.isNotEmpty) return earlyBest;
    }

    // Nike Run Club: "1:11:18 986" 형식 — h:mm:ss 뒤에 칼로리(3자리 숫자)가 붙어 standalone 탈락
    // 폰 시계(6:17 단독)보다 먼저 처리하여 오인식 방지
    for (final line in lines) {
      final mHMSCalorie = RegExp(r'^(\d{1,3}:\d{2}:\d{2})\s+\d{3}$').firstMatch(line.trim());
      if (mHMSCalorie != null) {
        final t = mHMSCalorie.group(1)!;
        final parts = t.split(':');
        final h = int.tryParse(parts[0]) ?? 99;
        final m2 = int.tryParse(parts[1]) ?? 99;
        final s = int.tryParse(parts[2]) ?? 99;
        if (h < 24 && m2 < 60 && s < 60) return t;
      }
    }

    // COROS: "56:1842" 형식 — mm:ss 뒤 위첨자가 3~4자리로 OCR 오인식
    // "56:18" 뒤 위첨자(42)가 붙어 "56:1842"가 됨. mTrailDigitTime(\d{1,2})으로 미처리
    // first<24 체크 대신 min<60으로 처리 (mm:ss 형식)
    for (final line in lines) {
      final mMMSSTrail = RegExp(r'^(\d{1,3}:\d{2})\d{2,4}\s*$').firstMatch(line.trim());
      if (mMMSSTrail != null) {
        final t = mMMSSTrail.group(1)!;
        final parts = t.split(':');
        final min = int.tryParse(parts[0]) ?? 99;
        final sec = int.tryParse(parts[1]) ?? 99;
        if (min < 60 && sec < 60 && min >= 1) return t;
      }
    }

    // COROS: "46:533" 형식 — 위첨자가 숫자(1자리)로 OCR 오인식, standalone 탈락 방지
    // "46:53" 뒤에 위첨자(73 등)가 1~2자리 숫자로 붙어 remainder 발생 → standalone 탈락
    // 폰 시계(10:15 단독)보다 먼저 처리해야 오인식 방지
    for (final line in lines) {
      final mTrailDigitTime = RegExp(r'^(\d{1,3}:\d{2}(?::\d{2})?)\d{1,2}\s*$').firstMatch(line.trim());
      if (mTrailDigitTime != null) {
        final t = mTrailDigitTime.group(1)!;
        final parts = t.split(':');
        final first = int.tryParse(parts[0]) ?? 99;
        final second = int.tryParse(parts[1]) ?? 99;
        if (second < 60 && (parts.length == 2 ? first < 24 : first < 24)) return t;
      }
    }

    // COROS: "46:59"" 형식 — 위첨자가 따옴표로 OCR 오인식, standalone 탈락 방지
    // 폰 시계(9:13 단독)보다 먼저 처리해야 오인식 방지
    for (final line in lines) {
      final mQuoteTimeEarly = RegExp(r'^(\d{1,3}:\d{2}(?::\d{2})?)[\"\u201D]\s*$').firstMatch(line.trim());
      if (mQuoteTimeEarly != null) return mQuoteTimeEarly.group(1)!;
    }

    // 단독 줄 시간값 우선 탐색 (헤더/날짜 텍스트 혼합 오인식 방지)
    // "2 211:16" 같이 다른 내용과 섞인 줄은 제외 → "34:55" 단독 줄만 신뢰
    {
      String standaloneBest = '';
      int standaloneBestSec = 0;
      for (final line in lines) {
        final trimmed = line.trim();
        final m = timePattern.firstMatch(trimmed);
        if (m == null) continue;
        // 줄에서 시간값 제거 후 남은 내용이 있으면 스킵 (혼합 줄)
        final remainder = trimmed.replaceFirst(m.group(0)!, '').trim();
        if (remainder.isNotEmpty) continue;
        final t = m.group(1)!;
        final parts = t.split(':');
        final sec = parts.length == 3
            ? int.parse(parts[0]) * 3600 + int.parse(parts[1]) * 60 + int.parse(parts[2])
            : int.parse(parts[0]) * 60 + int.parse(parts[1]);
        if (sec > standaloneBestSec) { standaloneBestSec = sec; standaloneBest = t; }
      }
      if (standaloneBest.isNotEmpty) return standaloneBest;
    }

    // COROS: "46:533" 형식 — mm:ss 뒤 위첨자가 1자리 숫자로 오인식
    // standalone 탐색 이후에 처리 — standalone(54:14 등)이 있으면 먼저 리턴되어 이 패턴에 도달 안함
    // "7:374" 같은 폰시계+배터리 혼합 줄은 standalone에서 54:14가 먼저 잡혀 탈락
    for (final line in lines) {
      final mMMSSTrail1 = RegExp(r'^(\d{2,3}:\d{2})\d\s*$').firstMatch(line.trim());
      if (mMMSSTrail1 != null) {
        final t = mMMSSTrail1.group(1)!;
        final parts = t.split(':');
        final min = int.tryParse(parts[0]) ?? 99;
        final sec = int.tryParse(parts[1]) ?? 99;
        if (min >= 1 && min < 60 && sec < 60) return t;
      }
    }

    // COROS: "48:55*1" 형식 — 초 단위가 위첨자로 표기되어 "*숫자"로 OCR 오인식
    // "48:55" 뒤에 "*1" 등이 붙어 단독 줄 판정 불가 → 별도 패턴으로 추출
    for (final line in lines) {
      final mStarTime = RegExp(r'^(\d{1,3}:\d{2}(?::\d{2})?)\*\d+$').firstMatch(line.trim());
      if (mStarTime != null) return mStarTime.group(1)!;
    }

    // COROS: "46:59"" 형식 — 페이스 따옴표(")가 시간 뒤에 붙어 standalone 탈락
    // "46:59" 뒤 따옴표는 OCR이 위첨자를 오인식한 것. mStarTime(*숫자)과 유사한 패턴
    for (final line in lines) {
      final mQuoteTime = RegExp(r'^(\d{1,3}:\d{2}(?::\d{2})?)[\"\u201D]\s*$').firstMatch(line.trim());
      if (mQuoteTime != null) return mQuoteTime.group(1)!;
    }

    // Garmin: "05:43" → "O5843" (0→O, :→8) OCR 오인식 대응
    // 단독 줄에 O + 1자리 분 + 8(콜론 오인식) + 2자리 초 형태
    for (final line in lines) {
      final mOTime = RegExp(r'^O(\d)8(\d{2})$').firstMatch(line.trim());
      if (mOTime != null) {
        final min = int.tryParse(mOTime.group(1)!) ?? 99;
        final sec = int.tryParse(mOTime.group(2)!) ?? 99;
        if (min < 60 && sec < 60) return '$min:${mOTime.group(2)}';
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

    // Apple Watch 건강앱: "548"/KM" — 아포스트로피 없음 + 따옴표 + /KM 공백 없이 붙음
    // mNoAposSlashKmFirst(\s+ 필수)로 미매칭 → 공백 없는 /km 전용 패턴
    for (final line in lines) {
      final mNoAposSlashKmNoSpace = RegExp(r'^(\d{1,2})(\d{2})[\"\u201D]/km\b', caseSensitive: false).firstMatch(line.trim());
      if (mNoAposSlashKmNoSpace != null) {
        final min = int.tryParse(mNoAposSlashKmNoSpace.group(1)!) ?? 99;
        final sec = int.tryParse(mNoAposSlashKmNoSpace.group(2)!) ?? 60;
        if (min < 20 && sec < 60) return "$min'${mNoAposSlashKmNoSpace.group(2)!}/km";
      }
    }

    // COROS: 아포스트로피 없음 + 따옴표 + 공백 + "/km" — mAposAmKm보다 먼저 처리
    // "4'41" /km" → "441" /km" (아포스트로피 누락, 슬래시 있는 /km)
    // mAposAmKm("Am")이 Effort Pace를 먼저 잡기 전에 평균 페이스 확정
    for (final line in lines) {
      final mNoAposSlashKmFirst = RegExp(r'^(\d{1,2})(\d{2})[\"\u201D]\s+/km\b', caseSensitive: false).firstMatch(line.trim());
      if (mNoAposSlashKmFirst != null) {
        final min = int.tryParse(mNoAposSlashKmFirst.group(1)!) ?? 99;
        final sec = int.tryParse(mNoAposSlashKmFirst.group(2)!) ?? 60;
        if (min < 20 && sec < 60) return "$min'${mNoAposSlashKmFirst.group(2)!}/km";
      }
    }

    // COROS: "/km"이 "Am"으로 OCR 오인식, 아포스트로피 없음, 공백도 없음
    // "6'09" /km" → "609"Am" (아포스트로피+공백 누락 + /km→Am 연속)
    // mAposAmKm("5'44"Am") 보다 먼저 처리 — 아포스트로피 없는 평균 페이스 우선
    for (final line in lines) {
      final mAmKmNoSpace = RegExp(r'^(\d{1,2})(\d{2})[\"\u201D]Am\b').firstMatch(line.trim());
      if (mAmKmNoSpace != null) {
        final min = int.tryParse(mAmKmNoSpace.group(1)!) ?? 99;
        final sec = int.tryParse(mAmKmNoSpace.group(2)!) ?? 60;
        if (min < 20 && sec < 60) return "$min'${mAmKmNoSpace.group(2)!}/km";
      }
    }

    // COROS: 아포스트로피 있음 + 따옴표 + "/km"이 "Am"으로 오인식
    // "7'34" /km" → "7'34"Am" (아포스트로피 보존, 따옴표+Am 연속)
    // 아포스트로피 없는 mAmKm보다 먼저 처리
    for (final line in lines) {
      final mAposAmKm = RegExp(r'^(\d{1,2})[^\d\s](\d{2})[\"\u201D]\s*Am\b').firstMatch(line.trim());
      if (mAposAmKm != null) {
        final min = int.tryParse(mAposAmKm.group(1)!) ?? 99;
        final sec = int.tryParse(mAposAmKm.group(2)!) ?? 60;
        if (min < 20 && sec < 60) return "$min'${mAposAmKm.group(2)!}/km";
      }
    }

    // Garmin/COROS: "/km"이 "Am"으로 OCR 오인식, 아포스트로피 없음
    // "5'16" /km" → "516" Am" (아포스트로피 누락 + /km→Am)
    // 아포스트로피+따옴표+/km 있는 최고1Km 페이스(5'07" /km)보다 먼저 처리해야 평균 페이스 우선 반환
    for (final line in lines) {
      final mAmKm = RegExp(r'^(\d{1,2})(\d{2})[\"\u201D]\s+Am\b').firstMatch(line.trim());
      if (mAmKm != null) {
        final min = int.tryParse(mAmKm.group(1)!) ?? 99;
        final sec = int.tryParse(mAmKm.group(2)!) ?? 60;
        if (min < 20 && sec < 60) return "$min'${mAmKm.group(2)!}/km";
      }
    }

    // COROS: "/km"이 "m"으로 OCR 오인식, 아포스트로피 없음
    // "5'23" /km" → "523" m" (아포스트로피 누락 + /km→m, m 단독)
    // mAmKm("Am"), mSlashAmKm("/Am")과 달리 "m" 단독 형태
    for (final line in lines) {
      final mSpaceM = RegExp(r'^(\d{1,2})(\d{2})[\"\u201D]\s+m\s*$').firstMatch(line.trim());
      if (mSpaceM != null) {
        final min = int.tryParse(mSpaceM.group(1)!) ?? 99;
        final sec = int.tryParse(mSpaceM.group(2)!) ?? 60;
        if (min < 20 && sec < 60) return "$min'${mSpaceM.group(2)!}/km";
      }
    }

    // COROS: "/km"이 "/Am"으로 OCR 오인식, 아포스트로피 없음
    // "5'25" /km" → "525" /Am" (아포스트로피 누락 + /km→/Am, 슬래시 포함)
    // mAmKm의 "Am" 단독 패턴과 달리 "/" 포함된 "/Am" 형태
    for (final line in lines) {
      final mSlashAmKm = RegExp(r'^(\d{1,2})(\d{2})[\"\u201D]\s+/Am\b').firstMatch(line.trim());
      if (mSlashAmKm != null) {
        final min = int.tryParse(mSlashAmKm.group(1)!) ?? 99;
        final sec = int.tryParse(mSlashAmKm.group(2)!) ?? 60;
        if (min < 20 && sec < 60) return "$min'${mSlashAmKm.group(2)!}/km";
      }
    }

    // COROS: 아포스트로피 없이 "427" /km" 형식 → 4'27/km — /km 공백 포함
    // "4'27" /km" → "427" /km" 오인식 (아포스트로피 누락, 따옴표+공백+/km)
    // mNoAposSpaceKm("km" 단독)과 별개로 슬래시 포함된 "/km" 형태
    for (final line in lines) {
      final mNoAposSlashKm = RegExp(r'^(\d{1,2})(\d{2})[\"\u201D]\s+/km\b', caseSensitive: false).firstMatch(line.trim());
      if (mNoAposSlashKm != null) {
        final min = int.tryParse(mNoAposSlashKm.group(1)!) ?? 99;
        final sec = int.tryParse(mNoAposSlashKm.group(2)!) ?? 60;
        if (min < 20 && sec < 60) return "$min'${mNoAposSlashKm.group(2)!}/km";
      }
    }

    // COROS: 아포스트로피 없이 "431" km" 형식 → 4'31/km — 최우선 처리
    // "4'31"/km" → "431" km" 오인식. 아포스트로피+따옴표 있는 최고1Km 페이스(3'59" /km)보다 먼저 처리해야 함
    for (final line in lines) {
      final mNoAposSpaceKm = RegExp(r'^(\d{1,2})(\d{2})[\"\u201D]\s+km\b', caseSensitive: false).firstMatch(line.trim());
      if (mNoAposSpaceKm != null) {
        final min = int.tryParse(mNoAposSpaceKm.group(1)!) ?? 99;
        final sec = int.tryParse(mNoAposSpaceKm.group(2)!) ?? 60;
        if (min < 20 && sec < 60) return "$min'${mNoAposSpaceKm.group(2)!}/km";
      }
    }

    // COROS/Garmin: "5'56 lkm", "5'56" Ikm", "4:16 Jkm" 형식 — /km 오인식(l/I/J) 최우선 처리
    // J→/ (Garmin), l/I/1→/ (COROS) 오인식 대응. km 단독은 거리값과 충돌하므로 제외
    for (final line in lines) {
      final m = RegExp(r'^(\d{1,2})[^\d\s](\d{2})[^\d\s]?\s+[IiLlJj1]km\b', caseSensitive: false).firstMatch(line.trim());
      if (m != null) {
        final min = int.tryParse(m.group(1)!) ?? 99;
        final sec = int.tryParse(m.group(2)!) ?? 60;
        if (min < 20 && sec < 60) return "$min'${m.group(2)!}/km";
      }
    }

    // '  :  '  "  ` 등 OCR이 다양하게 인식하는 구분자 허용 (. 제외 - 거리 소수점과 충돌)
    final pacePattern = RegExp(r"(\d+[':\u2018\u2019\u201C\u201D`]\d{2})");
    final paceLabels = ['페이스', 'pace', 'avg pace', 'average pace', '평균페이스', 'avg. pace', 'min/km', '분/km'];

    // COROS: "615"" + 다음 줄 "Ikm" — I→/ 오인식 (mQuoteNextKm의 lkm/1km과 별개의 I 오인식)
    // "6'15"/km" → "615"\n Ikm" 으로 분리되는 경우
    for (int i = 0; i < lines.length - 1; i++) {
      final mQuoteIkm = RegExp(r'^(\d{1,2})(\d{2})[\"\u201D]\s*$').firstMatch(lines[i].trim());
      if (mQuoteIkm != null) {
        final min = int.tryParse(mQuoteIkm.group(1)!) ?? 99;
        final sec = int.tryParse(mQuoteIkm.group(2)!) ?? 60;
        if (min < 20 && sec < 60) {
          final nt = lines[i + 1].trim().toLowerCase().replaceAll(' ', '');
          if (nt == 'ikm') return "$min'${mQuoteIkm.group(2)!}/km";
        }
      }
    }

    // COROS: "453"" + 다음 줄 "/km" 형식 (아포스트로피 없음, 따옴표만 있고 /km는 별도 줄)
    // "4'53"/km" → "453"\n/km" 으로 분리되는 경우. mSoloPace(차트 축 레이블 오인식)보다 먼저 처리
    for (int i = 0; i < lines.length - 1; i++) {
      final mQuoteNextKm = RegExp(r'^(\d{1,2})(\d{2})[\"\u201D]\s*$').firstMatch(lines[i].trim());
      if (mQuoteNextKm != null) {
        final min = int.tryParse(mQuoteNextKm.group(1)!) ?? 99;
        final sec = int.tryParse(mQuoteNextKm.group(2)!) ?? 60;
        if (min < 20 && sec < 60) {
          final nextTrimmed = lines[i + 1].trim().toLowerCase().replaceAll(' ', '');
          if (nextTrimmed == '/km' || nextTrimmed == 'lkm' || nextTrimmed == '1km') {
            return "$min'${mQuoteNextKm.group(2)!}/km";
          }
        }
      }
    }

    // Samsung Health: 아포스트로피 누락 페이스 "537"" + 바로 다음 줄에 bpm 패턴
    // 차트 축 레이블(3'22" 등)보다 먼저 처리 — 축 레이블은 아포스트로피가 있어 이 패턴에 불매칭
    // 아포스트로피 없는 \d{1,2}\d{2}" 형태 + 다음 줄 bpm → 평균 페이스로 확정
    for (int i = 0; i < lines.length - 1; i++) {
      final mBpmAdjacent = RegExp(r'^(\d{1,2})(\d{2})[\"\u201D]\s*$').firstMatch(lines[i].trim());
      if (mBpmAdjacent != null) {
        final min = int.tryParse(mBpmAdjacent.group(1)!) ?? 99;
        final sec = int.tryParse(mBpmAdjacent.group(2)!) ?? 60;
        if (min < 20 && sec < 60) {
          final nextLine = lines[i + 1].toLowerCase().replaceAll(' ', '');
          if (nextLine.contains('bpm')) return "$min'${mBpmAdjacent.group(2)}/km";
        }
      }
    }

    // COROS: 아포스트로피/따옴표 모두 없이 "444" 형식 + 다음 줄 "/km" or "lkm"(OCR 오인식)
    // "4'44"/km" → "444" + "/km" 두 줄로 분리되는 경우
    for (int i = 0; i < lines.length - 1; i++) {
      final trimmed = lines[i].trim();
      final mRawDigits = RegExp(r'^(\d{1,2})(\d{2})$').firstMatch(trimmed);
      if (mRawDigits != null) {
        final min = int.tryParse(mRawDigits.group(1)!) ?? 99;
        final sec = int.tryParse(mRawDigits.group(2)!) ?? 60;
        if (min < 20 && sec < 60) {
          final nextTrimmed = lines[i + 1].trim().toLowerCase().replaceAll(' ', '');
          if (nextTrimmed == '/km' || nextTrimmed == 'lkm' || nextTrimmed == '1km') {
            return "$min'${mRawDigits.group(2)!}/km";
          }
        }
      }
    }

    // COROS: "437"" + 이후 2~6줄 내 "/km" 단독 줄 (mQuoteNextKm 1줄 범위의 확장)
    // "4'37"/km" → "437"" + 수 줄 뒤 "/km" 분리 패턴. mPaceAposNoQuoteKm보다 먼저 처리해야
    // "4'04" /km"(최고1Km)보다 "437"(평균 페이스)을 우선 반환
    for (int i = 0; i < lines.length; i++) {
      final mQuoteFarKm = RegExp(r'^(\d{1,2})(\d{2})[\"\u201D]\s*$').firstMatch(lines[i].trim());
      if (mQuoteFarKm != null) {
        final min = int.tryParse(mQuoteFarKm.group(1)!) ?? 99;
        final sec = int.tryParse(mQuoteFarKm.group(2)!) ?? 60;
        if (min < 20 && sec < 60) {
          for (int d = 2; d <= 6; d++) {
            final j = i + d;
            if (j >= lines.length) break;
            final nt = lines[j].trim().toLowerCase().replaceAll(' ', '');
            if (nt == '/km' || nt == 'lkm' || nt == '1km') {
              return "$min'${mQuoteFarKm.group(2)!}/km";
            }
          }
        }
      }
    }

    // Garmin 공유카드: "403"" 단독 줄, /km 없음 — bpm+km이 텍스트에 있어 러닝 데이터임을 확인
    // "4'03"" → "403"" 오인식 (아포스트로피+따옴표 → 따옴표만). /km 단위 완전 누락
    // bpm과 km 단어가 모두 텍스트에 있을 때만 페이스로 신뢰
    if (text.toLowerCase().contains('bpm') && RegExp(r'\bkm\b', caseSensitive: false).hasMatch(text)) {
      for (final line in lines) {
        final mQuoteNokm = RegExp(r'^(\d{1,2})(\d{2})[\"\u201D]\s*$').firstMatch(line.trim());
        if (mQuoteNokm != null) {
          final min = int.tryParse(mQuoteNokm.group(1)!) ?? 99;
          final sec = int.tryParse(mQuoteNokm.group(2)!) ?? 60;
          if (min < 20 && sec < 60) return "$min'${mQuoteNokm.group(2)!}/km";
        }
      }
    }

    // COROS: 아포스트로피 있고 따옴표 없는 페이스 + 같은 줄 km 변형 ("5'56 lkm" 등)
    // 따옴표까지 누락된 경우 — mPaceWithKmVariant(따옴표 필수)와 구분되는 고유 패턴
    // 아포스트로피는 어떤 비숫자·비공백 문자든 허용 (OCR 유니코드 오인식 대응)
    for (final line in lines) {
      final mPaceAposNoQuoteKm = RegExp(
        r"^(\d{1,2})[^\d\s](\d{2})\s+(?:lkm|1km|\/km)\b",
        caseSensitive: false,
      ).firstMatch(line.trim());
      if (mPaceAposNoQuoteKm != null) {
        final min = int.tryParse(mPaceAposNoQuoteKm.group(1)!) ?? 99;
        final sec = int.tryParse(mPaceAposNoQuoteKm.group(2)!) ?? 60;
        if (min < 20 && sec < 60) return "$min'${mPaceAposNoQuoteKm.group(2)!}/km";
      }
    }

    // COROS: 아포스트로피 있는 페이스 + 같은 줄에 km 변형 ("5'56" lkm", "5'56" Am" 등)
    // "/km" → "lkm"(l/1 오인식) or "Am"(/ → A, k 누락) 오인식 처리
    // mSoloPace(단독 줄)보다 먼저 처리해 차트 축 레이블 오인식 방지
    for (final line in lines) {
      final mPaceWithKmVariant = RegExp(
        r"^(\d{1,2})[^\d\s](\d{2})[\u0022\u201D]\s+(?:lkm|1km|\/km|Am|km)\b",
        caseSensitive: false,
      ).firstMatch(line.trim());
      if (mPaceWithKmVariant != null) {
        final min = int.tryParse(mPaceWithKmVariant.group(1)!) ?? 99;
        final sec = int.tryParse(mPaceWithKmVariant.group(2)!) ?? 60;
        if (min < 20 && sec < 60) return "$min'${mPaceWithKmVariant.group(2)!}/km";
      }
    }

    // COROS: 아포스트로피 있고 따옴표 없는 페이스 "5'56" + 다음 줄 "/km" (따옴표 OCR 누락)
    // "5'56\n/km" 형식 — mPaceWithKmVariant(따옴표 필수)와 구분되는 고유 패턴
    for (int i = 0; i < lines.length - 1; i++) {
      final mAposNoDQuote = RegExp(r"^(\d{1,2})[^\d\s](\d{2})\s*$").firstMatch(lines[i].trim());
      if (mAposNoDQuote != null) {
        final min = int.tryParse(mAposNoDQuote.group(1)!) ?? 99;
        final sec = int.tryParse(mAposNoDQuote.group(2)!) ?? 60;
        if (min < 20 && sec < 60) {
          final nextTrimmed = lines[i + 1].trim().toLowerCase().replaceAll(' ', '');
          if (nextTrimmed == '/km' || nextTrimmed == 'lkm' || nextTrimmed == '1km') {
            return "$min'${mAposNoDQuote.group(2)!}/km";
          }
        }
      }
    }

    // COROS: 아포스트로피 없이 "539" km" 형식 → 5'39/km (mSoloPace보다 먼저 처리)
    // 차트 축 레이블(6'05" 등)은 아포스트로피가 있어 이 패턴에 불매칭
    // "539" km" 같이 " 뒤에 공백+km이 있는 경우만 매칭
    for (final line in lines) {
      final mPaceSpaceKm = RegExp(r'^(\d{1,2})(\d{2})[\"\u201D]\s+km\b', caseSensitive: false).firstMatch(line.trim());
      if (mPaceSpaceKm != null) {
        final min = int.tryParse(mPaceSpaceKm.group(1)!) ?? 99;
        final sec = int.tryParse(mPaceSpaceKm.group(2)!) ?? 60;
        if (min < 20 && sec < 60) return "$min'${mPaceSpaceKm.group(2)!}/km";
      }
    }

    // Garmin: 단독 줄에 "4'03"" 형태 페이스 (라벨 탐색 전 우선 처리)
    // min/km 라벨이 있는 줄에서 ±3줄 탐색 시 "25:56" 같은 시간값 오인식 방지
    for (final line in lines) {
      final mSoloPace = RegExp(r"^(\d{1,2})[\u0027\u2019](\d{2})[\u0022\u201D\u0027\u2019]\s*$").firstMatch(line.trim());
      if (mSoloPace != null) {
        final min = int.tryParse(mSoloPace.group(1)!) ?? 99;
        if (min < 20) return "${mSoloPace.group(1)}'${mSoloPace.group(2)}/km";
      }
    }

    // Garmin: 접두 아이콘 문자 + 페이스 "Ö 5'36"" 형식 (mSoloPace 보다 먼저 처리)
    // 러닝 중 아이콘(Ö 등) + 공백 + 페이스 표기. "^" 앵커가 있는 mSoloPace는 이 형식에 불매칭
    for (final line in lines) {
      final mIconPace = RegExp(r'^[^\d\s]\s+(\d{1,2})[\u0027\u2018\u2019\u201C](\d{2})[\u0022\u201D\u0027\u2019]\s*$').firstMatch(line.trim());
      if (mIconPace != null) {
        final min = int.tryParse(mIconPace.group(1)!) ?? 99;
        if (min < 20) return "${mIconPace.group(1)}'${mIconPace.group(2)}/km";
      }
    }

    // 라벨 주변 탐색
    for (int i = 0; i < lines.length; i++) {
      final ll = lines[i].toLowerCase().replaceAll(' ', '');
      if (paceLabels.any((l) => ll.contains(l.replaceAll(' ', '')))) {
        // COROS: "(min/km)" 같은 그래프 축 라벨 줄은 스킵 (숫자 없는 순수 단위 라벨)
        if (ll.contains('min') && ll.contains('/km') && !RegExp(r'\d').hasMatch(ll)) continue;
        for (int d = -3; d <= 3; d++) {
          final j = i + d;
          if (j < 0 || j >= lines.length) continue;
          final m = pacePattern.firstMatch(lines[j]);
          if (m != null) return '${m.group(1)}/km';
        }
      }
    }

    // "/km" 또는 "(km" 단위가 있는 라인 주변에서 분:초 패턴 탐색
    // OCR이 /km 을 (km 으로 잘못 읽는 경우 대응
    for (int i = 0; i < lines.length; i++) {
      final ll = lines[i].toLowerCase().replaceAll(' ', '');
      if (ll.contains('/km') || ll.contains('(km') || ll.contains('|km') || ll.contains('jkm') || ll.contains('분/km')) {
        // COROS: "(min/km)" 같은 그래프 축 라벨 줄은 스킵 (숫자 없는 순수 단위 라벨)
        if (ll.contains('min') && ll.contains('/km') && !RegExp(r'\d').hasMatch(ll)) continue;
        // 해당 라인 자체에서 먼저 찾기 (아포스트로피 있는 경우)
        final mSame = RegExp(r"(\d+[':\u2018\u2019\u201C\u201D`]\d{2})", caseSensitive: false).firstMatch(lines[i]);
        if (mSame != null) {
          final val = mSame.group(1)!;
          final sep = val.indexOf(RegExp(r"[':\u2018\u2019\u201C\u201D`]"));
          final minutes = int.tryParse(val.substring(0, sep)) ?? 99;
          if (minutes < 20) return '$val/km';
        }
        // Samsung Health: "0647" /km" - 아포스트로피 누락, 큰따옴표만 있는 경우
        // 같은 줄에서 먼저 처리해 ±5줄 탐색의 날짜값 오인식 방지
        final mSameDropped = RegExp(r'(\d{1,2})(\d{2})["\u201D]', caseSensitive: false).firstMatch(lines[i]);
        if (mSameDropped != null) {
          final minInt = int.tryParse(mSameDropped.group(1)!) ?? 99;
          final sec = mSameDropped.group(2)!;
          if (minInt < 20) return "$minInt'$sec/km";
        }
        // 주변 ±5줄에서 찾기
        for (int d = -5; d <= 5; d++) {
          if (d == 0) continue;
          final j = i + d;
          if (j < 0 || j >= lines.length) continue;
          final m = pacePattern.firstMatch(lines[j]);
          if (m != null) {
            final val = m.group(1)!;
            final sep = val.indexOf(RegExp(r"[':\u2018\u2019\u201C\u201D`]"));
            final minutes = int.tryParse(val.substring(0, sep)) ?? 99;
            if (minutes < 20) return '$val/km';
          }
        }
      }
    }

    // "5분30초" 형식 지원
    final minsec = RegExp(r"(\d+)분\s*(\d+)초").firstMatch(text);
    if (minsec != null) return "${minsec.group(1)}'${minsec.group(2)}/km";

    // OCR이 "8'21"" 를 "821"" 로 읽는 경우: 아포스트로피 누락 대응
    // 예) "821"/KM" → 8분21초 → "8'21/km"
    final mDropped = RegExp(r'(\d{1,2})(\d{2})["\u201D]\s*[/(]\s*km', caseSensitive: false).firstMatch(text);
    if (mDropped != null) {
      final min = mDropped.group(1)!;
      final sec = mDropped.group(2)!;
      if ((int.tryParse(min) ?? 99) < 20) return "$min'$sec/km";
    }

    // COROS: "513" km" → 아포스트로피 누락 + 슬래시 없이 공백+km
    // "5'13"/km" 가 "513" km" 으로 OCR되는 경우 (Garmin 폴백보다 앞에 처리해야 그래프 축값 오인식 방지)
    for (final line in lines) {
      final mCorosPace = RegExp(r'(\d{1,2})(\d{2})["\u201D][^\S\n]*km', caseSensitive: false).firstMatch(line);
      if (mCorosPace != null) {
        final min = int.tryParse(mCorosPace.group(1)!) ?? 99;
        final sec = mCorosPace.group(2)!;
        if (min < 20) return "$min'$sec/km";
      }
    }

    // COROS: "km"이 "hn"으로 OCR 오인식 ("623"hn" → 6'23/km)
    // k→h, m→n 로 각각 잘못 인식되는 경우
    for (final line in lines) {
      final mHnPace = RegExp(r'(\d{1,2})(\d{2})[\"\u201D][^\S\n]*hn\b', caseSensitive: false).firstMatch(line);
      if (mHnPace != null) {
        final min = int.tryParse(mHnPace.group(1)!) ?? 99;
        final sec = mHnPace.group(2)!;
        if (min < 20) return "$min'$sec/km";
      }
    }

    // Samsung Health: "/km"이 "[km"으로 OCR 오인식 ("5:50 [km" → 5:50/km, /→[ 오인식)
    for (final line in lines) {
      final mBracketKm = RegExp(r'^(\d+:\d{2})\s+\[km\b', caseSensitive: false).firstMatch(line.trim());
      if (mBracketKm != null) {
        final val = mBracketKm.group(1)!;
        final minutes = int.tryParse(val.split(':')[0]) ?? 99;
        if (minutes < 20) return '$val/km';
      }
    }

    // Strava/Nike: "5:50 krm" 형식 — "/km"이 "krm"으로 OCR 오인식
    // k→k, /→r 로 각각 잘못 인식되는 경우. mSpaceKm(공백+km) 보다 먼저 처리
    for (final line in lines) {
      final mKrmPace = RegExp(r'^(\d+:\d{2})\s+krm\b', caseSensitive: false).firstMatch(line.trim());
      if (mKrmPace != null) {
        final val = mKrmPace.group(1)!;
        final minutes = int.tryParse(val.split(':')[0]) ?? 99;
        if (minutes < 20) return '$val/km';
      }
    }

    // Garmin/Samsung: OCR이 "/km" → " km" (슬래시 누락)으로 읽는 경우
    // "4:39 km" 형태 — 같은 줄에 분:초 + 공백 + km, 분 < 20
    for (final line in lines) {
      final mSpaceKm = RegExp(r'(\d+:\d{2})[^\S\n]+km', caseSensitive: false).firstMatch(line);
      if (mSpaceKm != null) {
        final val = mSpaceKm.group(1)!;
        final minutes = int.tryParse(val.split(':')[0]) ?? 99;
        if (minutes < 20) return '$val/km';
      }
    }

    // Samsung Health: "0629"/km" 형식 — 앞에 0 + /km 직접 붙음 (mLeadZeroPace는 줄끝$ 필요)
    // "06'29" /km" → "0629"/km" 로 OCR됨. 따옴표 바로 뒤 /km 연속
    for (final line in lines) {
      final mLeadZeroKm = RegExp(r'^0(\d)(\d{2})[\"\u201D]/km\b', caseSensitive: false).firstMatch(line.trim());
      if (mLeadZeroKm != null) {
        final min = int.tryParse(mLeadZeroKm.group(1)!) ?? 99;
        final sec = int.tryParse(mLeadZeroKm.group(2)!) ?? 60;
        if (min < 20 && sec < 60) return "$min'${mLeadZeroKm.group(2)!}/km";
      }
    }

    // Samsung Health: "0704"" 형식 — 분 앞에 0이 붙은 페이스, 아포스트로피·/km 모두 없는 경우
    // "07'04"" → "0704"" 로 OCR됨. 단독 줄에 0+1자리분+2자리초+따옴표 구조
    for (final line in lines) {
      final mLeadZeroPace = RegExp(r'^0(\d)(\d{2})[\"\u201D]\s*$').firstMatch(line.trim());
      if (mLeadZeroPace != null) {
        final min = int.tryParse(mLeadZeroPace.group(1)!) ?? 99;
        final sec = int.tryParse(mLeadZeroPace.group(2)!) ?? 60;
        if (min < 20 && sec < 60) return "$min'${mLeadZeroPace.group(2)!}/km";
      }
    }

    // Garmin: "/km" 단위·라벨 없이 "4'39"" 형식만 있는 경우 폴백
    // 아포스트로피(분) + 2자리(초) + 큰따옴표 조합은 페이스 고유 표기
    // \u0027=', \u0022=", \u201D=", \u2019=' (raw 문자열에서 "와 ' 직접 사용 불가 → Unicode 이스케이프)
    final mGarminPace = RegExp(r'(\d+[\u0027\u2019]\d{2})[\u0022\u0027\u201D\u2019]').firstMatch(text);
    if (mGarminPace != null) {
      final val = mGarminPace.group(1)!;
      final sep = val.indexOf(RegExp(r"['\u2019]"));
      final minutes = int.tryParse(val.substring(0, sep)) ?? 99;
      if (minutes < 20) return '$val/km';
    }

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

    // 한국어: "2026년 4월 1일 @ 8:31 오후" / "4월 1일 오후 8:31" / "4월 1일"
    final korFull = RegExp(r'(?:\d{4}년\s*)?(\d{1,2}월\s*\d{1,2}일)\s*(?:@\s*)?(?:(오전|오후)\s*)?(\d{1,2}:\d{2})\s*(오전|오후)?');
    final m2 = korFull.firstMatch(text);
    if (m2 != null) {
      final date = m2.group(1)!.replaceAll(' ', '');
      final ampm = (m2.group(2) ?? m2.group(4) ?? '').trim();
      final time = m2.group(3)!;
      return '$date $time${ampm.isNotEmpty ? ' $ampm' : ''}';
    }
    final korDate = RegExp(r'(?:\d{4}년\s*)?(\d{1,2}월\s*\d{1,2}일)').firstMatch(text);
    if (korDate != null) return korDate.group(1)!.replaceAll(' ', '');

    // "2026.04.01" / "2026-04-01" / "2026. 4. 5." (COROS: 공백 포함) → "4월1일"
    final m3 = RegExp(r'\d{4}\s*[.\-/]\s*(\d{1,2})\s*[.\-/]\s*(\d{1,2})').firstMatch(text);
    if (m3 != null) return '${int.parse(m3.group(1)!)}월${int.parse(m3.group(2)!)}일';

    // Samsung Health: "$ 4 1 @ 8:31 g" 형태 (한글 아이콘/텍스트가 기호로 OCR됨)
    // $ = 러닝 아이콘, 4 1 = 4월 1일, @ = @, 8:31 = 시간
    final mSamsungDate = RegExp(r'[\$§]\s*(\d{1,2})\s+(\d{1,2})\s*@\s*(\d{1,2}:\d{2})').firstMatch(text);
    if (mSamsungDate != null) {
      final month = int.tryParse(mSamsungDate.group(1)!) ?? 0;
      final day = int.tryParse(mSamsungDate.group(2)!) ?? 0;
      final time = mSamsungDate.group(3)!;
      if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
        return '${month}월${day}일 $time';
      }
    }

    // Apple Health: 한글 누락으로 "4월 3일 (금)" → "43 ()" 로 OCR되는 경우
    // 상위 10줄에서만 탐색, 콜론 없는 줄에서 \d{1,2}\d{1,2} + "(" 패턴
    final topLines = text.split('\n').take(10).toList();
    for (final line in topLines) {
      if (line.contains(':')) continue; // 시간 데이터 제외
      final mApple = RegExp(r'(\d{1,2})\s?(\d{1,2})\s*\(').firstMatch(line);
      if (mApple != null) {
        final month = int.tryParse(mApple.group(1)!) ?? 0;
        final day = int.tryParse(mApple.group(2)!) ?? 0;
        if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
          return '${month}월${day}일';
        }
      }
    }

    return '';
  }

  // ── 심박수 (50~250 범위만 허용) ───────────────────────────────────────────
  static String _extractHeartRate(String text) {
    final lines = text.split('\n');

    bool validHR(String s) {
      final v = int.tryParse(s.trim());
      return v != null && v >= 50 && v <= 250;
    }

    // bpm 단위 명시된 경우 none-패턴보다 먼저 처리
    // "|O|2A" 등 none-패턴이 bpm 명시 케이스보다 먼저 ''를 반환하는 오인식 방지
    // 예) Strava: "149 bpm" + "|O|2A" 공존 시 bpm을 먼저 잡아야 함
    for (final m in RegExp(r'(\d{2,3})\s*bpm', caseSensitive: false).allMatches(text)) {
      if (validHR(m.group(1)!)) return '${m.group(1)} bpm';
    }

    // Garmin: 심장 아이콘(♡)이 "O"/"o"로 OCR + "--" (데이터 없음) → HR 없음
    // "--O" / "-- O" 줄이 있으면 심박수 기록 자체가 없는 것이므로 빈 값 반환
    for (final line in lines) {
      if (RegExp(r'^--\s*[oO]\s*$').hasMatch(line.trim())) return '';
    }

    // 슈파인더: "--♡"(심박수 없음)이 "I|o|" 또는 "B|O|A" 형태로 OCR 오인식
    // "|o|", "IoI", "|0|", "B|O|A" 등 바 + 원형 + 바 (앞뒤 문자 포함) 패턴 → HR 없음
    for (final line in lines) {
      if (RegExp(r'[|IB]\s*[oO0]\s*[|IA]').hasMatch(line.trim())) return '';
    }

    // 슈파인더/Nike Run Club: "--♡"(심박수 없음)이 "Q0" (Q+숫자영) 형태로 OCR 오인식
    // "Qo"(알파벳 o)와 구분 — 숫자 0으로 오인식된 케이스 대응
    for (final line in lines) {
      if (RegExp(r'^Q0\s*$').hasMatch(line.trim())) return '';
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

    // Garmin: "bpm"이 "bem"으로 OCR 오인식 ("131 bem" → 131 bpm, p→e 오인식)
    for (final m in RegExp(r'(\d{2,3})\s*bem\b', caseSensitive: false).allMatches(text)) {
      if (validHR(m.group(1)!)) return '${m.group(1)} bpm';
    }

    // COROS: "bpm"이 "vpm"으로 OCR 오인식 ("163 vpm" → 163 bpm, b→v 오인식)
    for (final m in RegExp(r'(\d{2,3})\s*vpm\b', caseSensitive: false).allMatches(text)) {
      if (validHR(m.group(1)!)) return '${m.group(1)} bpm';
    }

    // COROS: "bpm"이 "pm"으로 OCR 오인식 ("145 pm" → 145 bpm, b 누락)
    for (final m in RegExp(r'(\d{2,3})\s*pm\b', caseSensitive: false).allMatches(text)) {
      if (validHR(m.group(1)!)) return '${m.group(1)} bpm';
    }

    // COROS: "bpm"이 "bam"으로 OCR 오인식 ("145 bam" → 145 bpm, p→a 오인식)
    for (final m in RegExp(r'(\d{2,3})\s*bam\b', caseSensitive: false).allMatches(text)) {
      if (validHR(m.group(1)!)) return '${m.group(1)} bpm';
    }

    // COROS: "bam" OCR \b 실패 대비 — word boundary 없이 재시도
    // "169 bam" → \b word boundary 예외 상황 (트레일링 공백/특수문자) 포괄
    for (final m in RegExp(r'(\d{2,3})\s+bam', caseSensitive: false).allMatches(text)) {
      if (validHR(m.group(1)!)) return '${m.group(1)} bpm';
    }

    // COROS: "bpm"이 "b_m" 형태(중간 문자가 a/e/o/i/u 외 변형) OCR 오인식
    // "169 bam" → bam이지만 'm'이 유사문자(ṃ 등)인 경우 포괄 — b+임의문자+m
    for (final line in lines) {
      final mBxm = RegExp(r'^(\d{2,3})\s+b.m\b', caseSensitive: false).firstMatch(line.trim());
      if (mBxm != null && validHR(mBxm.group(1)!)) return '${mBxm.group(1)} bpm';
    }

    // COROS: "bpm"이 "ym"으로 OCR 오인식 ("136 ym" → 136 bpm, bp→y 오인식)
    for (final m in RegExp(r'(\d{2,3})\s*ym\b', caseSensitive: false).allMatches(text)) {
      if (validHR(m.group(1)!)) return '${m.group(1)} bpm';
    }

    // 단위 기반 + 범위 검증
    for (final m in RegExp(r'(\d{2,3})\s*bpm', caseSensitive: false).allMatches(text)) {
      if (validHR(m.group(1)!)) return '${m.group(1)} bpm';
    }

    // Garmin: 심장 아이콘(♡)이 OCR에서 "o"로 인식되는 경우 ("150 o" → 150 bpm)
    // 줄 끝에 숫자 + 공백 + "o" 단독으로 있는 패턴
    for (final line in lines) {
      final mHeartIcon = RegExp(r'^(\d{2,3})\s+o\s*$', caseSensitive: false).firstMatch(line.trim());
      if (mHeartIcon != null && validHR(mHeartIcon.group(1)!)) {
        return '${mHeartIcon.group(1)} bpm';
      }
    }

    // Garmin: 심장 아이콘(♡)이 OCR에서 ">"로 인식되는 경우 ("140 >" → 140 bpm)
    for (final line in lines) {
      final mHeartGt = RegExp(r'^(\d{2,3})\s+>\s*$').firstMatch(line.trim());
      if (mHeartGt != null && validHR(mHeartGt.group(1)!)) {
        return '${mHeartGt.group(1)} bpm';
      }
    }

    // Nike Run Club: 심장 아이콘(♡)이 OCR에서 "~"로 인식되는 경우 ("128 ~" → 128 bpm)
    for (final line in lines) {
      final mHeartTilde = RegExp(r'^(\d{2,3})\s+~\s*$').firstMatch(line.trim());
      if (mHeartTilde != null && validHR(mHeartTilde.group(1)!)) {
        return '${mHeartTilde.group(1)} bpm';
      }
    }

    // 슈파인더: "147 ♡"에서 ♡가 "0"으로 OCR되어 "1470" 단독 줄로 인식
    // 앞 2~3자리가 유효 HR이고 뒤에 0이 붙은 형태 → ♡ 오인식으로 처리
    for (final line in lines) {
      final mHeartZero = RegExp(r'^(\d{2,3})0\s*$').firstMatch(line.trim());
      if (mHeartZero != null && validHR(mHeartZero.group(1)!)) {
        return '${mHeartZero.group(1)} bpm';
      }
    }

    // Nike Run Club: 심박수 없음("--♡")이 "-" 단독 줄로 OCR, bpm 라벨도 없는 경우
    // 케이던스(193 등)가 HR로 오인식되는 것을 방지 — 폴백 숫자 탐색 전에 처리
    if (!text.toLowerCase().contains('bpm')) {
      for (final line in lines) {
        if (line.trim() == '-' || line.trim() == '--') return '';
      }
    }

    // Garmin: ♡ 아이콘이 OCR에서 완전히 누락, 케이던스 라벨도 없는 경우
    // 유효 HR 단독 숫자 + 근처 칼로리(>300) + 텍스트 전체에 케이던스 관련 단어 없음
    // → 케이던스 오인식 위험 없으므로 HR로 반환 ("140\n783" 패턴)
    final hasCadenceLabel = text.toLowerCase().contains('케이던스') ||
        text.toLowerCase().contains('cadence') ||
        text.toLowerCase().contains('spm') ||
        text.toLowerCase().contains('steps/min');
    if (!hasCadenceLabel) {
      for (int i = 0; i < lines.length; i++) {
        final trimmed = lines[i].trim();
        if (!RegExp(r'^\d{2,3}$').hasMatch(trimmed) || !validHR(trimmed)) continue;
        for (int d = -2; d <= 2; d++) {
          final j = i + d;
          if (j < 0 || j >= lines.length || j == i) continue;
          final nearTrimmed = lines[j].trim();
          if (RegExp(r'^\d+$').hasMatch(nearTrimmed)) {
            final nearNum = int.tryParse(nearTrimmed) ?? 0;
            if (nearNum > 300 && nearNum < 10000) return '$trimmed bpm';
          }
        }
      }
    }

    // Garmin: 라벨·단위 모두 누락된 경우 폴백
    // 2~3자리 숫자만 단독으로 있는 줄 탐색 (50~250 범위, 다른 문자 없음)
    // → "802" (칼로리), "47 m" (고도) 등은 범위 초과 또는 단위 포함으로 미매칭
    // → 케이던스 라벨(케이던스/cadence/spm) 근처 숫자는 스킵
    const cadenceLabels = ['케이던스', 'cadence', 'spm', 'steps/min'];
    for (int i = 0; i < lines.length; i++) {
      final trimmed = lines[i].trim();
      if (!RegExp(r'^\d{2,3}$').hasMatch(trimmed) || !validHR(trimmed)) continue;
      // 주변 ±3줄에 케이던스 라벨 있으면 스킵
      bool nearCadence = false;
      for (int d = -3; d <= 3; d++) {
        final j = i + d;
        if (j < 0 || j >= lines.length) continue;
        final ll = lines[j].toLowerCase().replaceAll(' ', '');
        if (cadenceLabels.any((l) => ll.contains(l.replaceAll(' ', '')))) {
          nearCadence = true;
          break;
        }
      }
      // 주변 ±2줄에 칼로리로 보이는 큰 단독 숫자(>300)가 있으면 케이던스로 추정 → 스킵
      // Garmin 그리드: 칼로리(457) 바로 옆에 케이던스(185)가 배치되는 패턴
      bool nearCalorieNum = false;
      for (int d = -2; d <= 2; d++) {
        final j = i + d;
        if (j < 0 || j >= lines.length || j == i) continue;
        final nearTrimmed = lines[j].trim();
        if (RegExp(r'^\d+$').hasMatch(nearTrimmed)) {
          final nearNum = int.tryParse(nearTrimmed) ?? 0;
          if (nearNum > 300 && nearNum < 10000) { nearCalorieNum = true; break; }
        }
      }
      if (!nearCadence && !nearCalorieNum) return '$trimmed bpm';
    }

    return '';
  }
}
