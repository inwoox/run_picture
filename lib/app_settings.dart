import 'package:flutter/foundation.dart';
import 'models/overlay_style.dart';

/// 앱 전역 설정 — 이미지에 삽입되는 텍스트는 제외하고 UI 텍스트에만 적용
final fontSizeNotifier = ValueNotifier<bool>(false); // false=보통, true=크게
final languageNotifier = ValueNotifier<LabelLanguage>(LabelLanguage.korean);
