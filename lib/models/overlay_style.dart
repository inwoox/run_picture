import 'package:flutter/material.dart';

enum OverlayPosition { topLeft, topRight, bottomLeft, bottomRight }
enum LayoutDirection { horizontal, vertical }
enum LabelLanguage { korean, english }

class OverlayStyle {
  final String fontFamily;
  final Color textColor;
  final Color backgroundColor;
  final double backgroundOpacity;
  final double fontSize;
  final double dateFontSize;
  final OverlayPosition position;
  final OverlayPosition datePosition;
  final bool showBackground;
  final LayoutDirection layoutDirection;
  final LabelLanguage labelLanguage;
  final String customText;
  final double customTextFontSize;
  final double customTextDx; // 0.0~1.0 비율
  final double customTextDy;

  const OverlayStyle({
    this.fontFamily = 'Roboto',
    this.textColor = Colors.white,
    this.backgroundColor = Colors.black,
    this.backgroundOpacity = 0.5,
    this.fontSize = 14,
    this.dateFontSize = 14,
    this.position = OverlayPosition.bottomLeft,
    this.datePosition = OverlayPosition.topLeft,
    this.showBackground = false,
    this.layoutDirection = LayoutDirection.horizontal,
    this.labelLanguage = LabelLanguage.korean,
    this.customText = '',
    this.customTextFontSize = 14,
    this.customTextDx = 0.5,
    this.customTextDy = 0.5,
  });

  OverlayStyle copyWith({
    String? fontFamily,
    Color? textColor,
    Color? backgroundColor,
    double? backgroundOpacity,
    double? fontSize,
    double? dateFontSize,
    OverlayPosition? position,
    OverlayPosition? datePosition,
    bool? showBackground,
    LayoutDirection? layoutDirection,
    LabelLanguage? labelLanguage,
    String? customText,
    double? customTextFontSize,
    double? customTextDx,
    double? customTextDy,
  }) {
    return OverlayStyle(
      fontFamily: fontFamily ?? this.fontFamily,
      textColor: textColor ?? this.textColor,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      backgroundOpacity: backgroundOpacity ?? this.backgroundOpacity,
      fontSize: fontSize ?? this.fontSize,
      dateFontSize: dateFontSize ?? this.dateFontSize,
      position: position ?? this.position,
      datePosition: datePosition ?? this.datePosition,
      showBackground: showBackground ?? this.showBackground,
      layoutDirection: layoutDirection ?? this.layoutDirection,
      labelLanguage: labelLanguage ?? this.labelLanguage,
      customText: customText ?? this.customText,
      customTextFontSize: customTextFontSize ?? this.customTextFontSize,
      customTextDx: customTextDx ?? this.customTextDx,
      customTextDy: customTextDy ?? this.customTextDy,
    );
  }

  String label(String ko, String en) =>
      labelLanguage == LabelLanguage.korean ? ko : en;
}
