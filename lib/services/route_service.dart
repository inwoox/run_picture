import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

class RouteService {
  /// 캡처 이미지에서 러닝 코스 경로 형태를 추출합니다.
  /// 반환값: 검정 픽셀(투명 배경) PNG bytes, 경로 미발견 시 null
  static Future<Uint8List?> extractRouteShape(String imagePath) async {
    return compute(_extractTask, imagePath);
  }
}

Uint8List? _extractTask(String imagePath) {
  final bytes = File(imagePath).readAsBytesSync();
  final src = img.decodeImage(bytes);
  if (src == null) return null;

  // 성능을 위해 축소
  const targetW = 480;
  final targetH = (src.height * targetW / src.width).round();
  final small = img.copyResize(src, width: targetW, height: targetH);

  // 1단계: 고채도 픽셀의 지배적 색상(hue) 찾기
  final hueCount = List<int>.filled(36, 0); // 10° 단위 버킷
  for (final p in small) {
    final r = p.r / 255.0;
    final g = p.g / 255.0;
    final b = p.b / 255.0;
    final hsv = _toHsv(r, g, b);
    if (hsv[1] > 0.45 && hsv[2] > 0.3) {
      hueCount[(hsv[0] / 10).floor() % 36]++;
    }
  }

  // 가장 많은 버킷 찾기
  int maxBucket = 0, maxCount = 0;
  for (int i = 0; i < 36; i++) {
    if (hueCount[i] > maxCount) {
      maxCount = hueCount[i];
      maxBucket = i;
    }
  }

  // 고채도 픽셀이 충분하지 않으면 코스 없음
  if (maxCount < 80) return null;

  final targetHue = maxBucket * 10.0;

  // 2단계: 경로 색상 픽셀만 추출 → 검정 픽셀 / 투명 배경
  final out = img.Image(width: targetW, height: targetH, numChannels: 4);
  out.clear(img.ColorRgba8(0, 0, 0, 0));

  int count = 0;
  for (final p in small) {
    final r = p.r / 255.0;
    final g = p.g / 255.0;
    final b = p.b / 255.0;
    final hsv = _toHsv(r, g, b);
    final hueDiff = ((hsv[0] - targetHue + 180) % 360 - 180).abs();
    if (hsv[1] > 0.4 && hsv[2] > 0.25 && hueDiff < 28) {
      out.setPixel(p.x, p.y, img.ColorRgba8(0, 0, 0, 255));
      count++;
    }
  }

  // 전체 픽셀의 0.2% 이상이어야 코스로 인정
  if (count < (targetW * targetH * 0.002).round()) return null;

  return Uint8List.fromList(img.encodePng(out));
}

List<double> _toHsv(double r, double g, double b) {
  final max = r > g ? (r > b ? r : b) : (g > b ? g : b);
  final min = r < g ? (r < b ? r : b) : (g < b ? g : b);
  final delta = max - min;

  double h = 0;
  if (delta > 0) {
    if (max == r) {
      h = 60 * (((g - b) / delta) % 6);
    } else if (max == g) {
      h = 60 * ((b - r) / delta + 2);
    } else {
      h = 60 * ((r - g) / delta + 4);
    }
  }
  if (h < 0) h += 360;

  return [h, max == 0 ? 0.0 : delta / max, max];
}
