import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/running_record.dart';
import '../models/overlay_style.dart';

const _localFonts = {'SUIT'};

TextStyle runCardTs(String font, {
  double? fontSize,
  FontWeight? fontWeight,
  Color? color,
  double? height,
  double? letterSpacing,
  List<Shadow>? shadows,
}) {
  final base = TextStyle(
    fontSize: fontSize, fontWeight: fontWeight,
    color: color, height: height, letterSpacing: letterSpacing,
    shadows: shadows,
  );
  if (_localFonts.contains(font)) return base.copyWith(fontFamily: font);
  try { return GoogleFonts.getFont(font, textStyle: base); }
  catch (_) { return base.copyWith(fontFamily: font); }
}

enum RunCardTemplate { minimal, center, grid, side, badge, split, dark }

const kRunCardAccentColors = [
  Color(0xFF1C1C1E),
  Color(0xFFE53935),
  Color(0xFF1565C0),
  Color(0xFF2E7D32),
  Color(0xFFE65100),
  Color(0xFF6A1B9A),
];

const kRunCardFonts = [
  'Nanum Pen Script', 'Gaegu', 'Caveat',
  'SUIT', 'Inter', 'Roboto', 'Oswald',
  'Bebas Neue', 'Space Grotesk',
];

const double kCardRatio = 4.0 / 5.0;

const _dark = Color(0xFF1C1C1E);
const _grey = Color(0xFF8E8E93);

List<Shadow> _sh(bool t) => t
    ? [const Shadow(blurRadius: 4, color: Colors.black54, offset: Offset(0.5, 0.5))]
    : [];

// Shadow for overlay text: white text gets black shadow, dark text gets none.
List<Shadow> _shFor(Color c) => c.computeLuminance() > 0.5
    ? [const Shadow(blurRadius: 6, color: Colors.black54, offset: Offset(0.5, 0.5))]
    : [];

Widget buildRunningCard(
  RunCardTemplate type,
  RunningRecord record,
  Color accent,
  String font,
  LabelLanguage language, {
  bool transparent = false,
}) {
  switch (type) {
    case RunCardTemplate.minimal:
      return RunMinimalCard(record: record, accent: accent, font: font, language: language, transparent: transparent);
    case RunCardTemplate.center:
      return RunCenterCard(record: record, accent: accent, font: font, language: language, transparent: transparent);
    case RunCardTemplate.grid:
      return RunGridCard(record: record, accent: accent, font: font, language: language, transparent: transparent);
    case RunCardTemplate.side:
      return RunSideCard(record: record, accent: accent, font: font, language: language, transparent: transparent);
    case RunCardTemplate.badge:
      return RunBadgeCard(record: record, accent: accent, font: font, language: language, transparent: transparent);
    case RunCardTemplate.split:
      return RunSplitCard(record: record, accent: accent, font: font, language: language, transparent: transparent);
    case RunCardTemplate.dark:
      return RunDarkCard(record: record, accent: accent, font: font, language: language, transparent: transparent);
  }
}

List<Widget> buildStatRow(String font, RunningRecord r, String Function(String, String) t, {bool transparent = false}) {
  final sh = _sh(transparent);
  final items = <Widget>[];
  void add(String label, String value) {
    if (items.isNotEmpty) {
      items.add(Container(
        width: 1, height: 32,
        color: transparent ? Colors.black26 : const Color(0xFFEEEEEE),
        margin: const EdgeInsets.only(right: 14),
      ));
    }
    items.add(Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: runCardTs(font, fontSize: 10, color: transparent ? _dark : _grey,
          letterSpacing: 1.5, fontWeight: FontWeight.w600, shadows: sh)),
      const SizedBox(height: 4),
      Text(value, style: runCardTs(font, fontSize: 15,
          fontWeight: FontWeight.w800, color: _dark, shadows: sh)),
    ])));
  }
  if (r.time.isNotEmpty)      add(t('총 시간', 'TIME'), r.time);
  if (r.pace.isNotEmpty)      add(t('평균 페이스', 'PACE'), r.pace);
  if (r.heartRate.isNotEmpty) add(t('평균 심박수', 'HR'), r.heartRate);
  return items;
}

List<Widget> buildCenteredStats(String font, RunningRecord r, Color accent,
    String Function(String, String) t, {bool transparent = false}) {
  final sh = _sh(transparent);
  final items = <Widget>[];
  void add(String label, String value) {
    items.add(Column(children: [
      Text(value, style: runCardTs(font, fontSize: 20, fontWeight: FontWeight.w800, color: _dark, shadows: sh)),
      const SizedBox(height: 4),
      Text(label, style: runCardTs(font, fontSize: 10, color: transparent ? _dark : _grey,
          letterSpacing: 1.5, fontWeight: FontWeight.w500, shadows: sh)),
    ]));
  }
  if (r.time.isNotEmpty)      add(t('총 시간', 'TIME'), r.time);
  if (r.pace.isNotEmpty)      add(t('평균 페이스', 'PACE'), r.pace);
  if (r.heartRate.isNotEmpty) add(t('평균 심박수', 'HR'), r.heartRate);
  return items;
}

// ── 1. Minimal ──────────────────────────────────────────────────────────────
class RunMinimalCard extends StatelessWidget {
  final RunningRecord record;
  final Color accent;
  final String font;
  final LabelLanguage language;
  final bool transparent;
  const RunMinimalCard({super.key, required this.record, required this.accent,
      required this.font, required this.language, this.transparent = false});
  String _t(String ko, String en) => language == LabelLanguage.korean ? ko : en;

  @override
  Widget build(BuildContext context) {
    final dist = record.distance.replaceAll(RegExp(r'\s*km'), '').trim();
    final sh = _sh(transparent);
    return AspectRatio(
      aspectRatio: kCardRatio,
      child: Container(
        color: transparent ? Colors.transparent : Colors.white,
        padding: const EdgeInsets.fromLTRB(36, 32, 36, 32),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: transparent ? const SizedBox() : Text(record.date,
                style: runCardTs(font, fontSize: 12, color: _grey, shadows: sh))),
            Text('PaceGraphy', style: runCardTs(font, fontSize: 9,
                fontWeight: FontWeight.w800, color: accent, letterSpacing: 2, shadows: sh)),
          ]),
          const Spacer(flex: 2),
          if (dist.isNotEmpty) ...[
            Text(_t('거리', 'DISTANCE'), style: runCardTs(font, fontSize: 10,
                color: _grey, letterSpacing: 2.5, fontWeight: FontWeight.w500, shadows: sh)),
            const SizedBox(height: 2),
            FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
              child: Text(dist, style: runCardTs(font, fontSize: 86,
                  fontWeight: FontWeight.w900, color: _dark, height: 1.0, shadows: sh)),
            ),
            Text('km', style: runCardTs(font, fontSize: 20,
                fontWeight: FontWeight.w700, color: accent, shadows: sh)),
          ],
          const SizedBox(height: 28),
          Container(height: 2, color: accent),
          const SizedBox(height: 24),
          Row(children: buildStatRow(font, record, _t, transparent: transparent)),
          const Spacer(flex: 3),
        ]),
      ),
    );
  }
}

// ── 2. Center ──────────────────────────────────────────────────────────────
class RunCenterCard extends StatelessWidget {
  final RunningRecord record;
  final Color accent;
  final String font;
  final LabelLanguage language;
  final bool transparent;
  const RunCenterCard({super.key, required this.record, required this.accent,
      required this.font, required this.language, this.transparent = false});
  String _t(String ko, String en) => language == LabelLanguage.korean ? ko : en;

  @override
  Widget build(BuildContext context) {
    final dist = record.distance.replaceAll(RegExp(r'\s*km'), '').trim();
    final sh = _sh(transparent);
    return AspectRatio(
      aspectRatio: kCardRatio,
      child: Container(
        color: transparent ? Colors.transparent : Colors.white,
        padding: const EdgeInsets.fromLTRB(28, 32, 28, 32),
        child: Column(children: [
          Text('PaceGraphy', style: runCardTs(font, fontSize: 10,
              fontWeight: FontWeight.w800, color: accent, letterSpacing: 3, shadows: sh)),
          if (!transparent && record.date.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(record.date, style: runCardTs(font, fontSize: 12, color: _grey, shadows: sh)),
          ],
          const Spacer(flex: 3),
          if (dist.isNotEmpty) ...[
            Text(_t('오늘 달린 거리', 'TODAY\'S DISTANCE'), style: runCardTs(font,
                fontSize: 10, color: _grey, letterSpacing: 2, shadows: sh)),
            const SizedBox(height: 8),
            FittedBox(fit: BoxFit.scaleDown,
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(dist, style: runCardTs(font, fontSize: 96,
                    fontWeight: FontWeight.w900, color: _dark, height: 1.0, shadows: sh)),
                const SizedBox(width: 6),
                Padding(padding: const EdgeInsets.only(bottom: 12),
                  child: Text('km', style: runCardTs(font, fontSize: 22,
                      fontWeight: FontWeight.w700, color: accent, shadows: sh))),
              ]),
            ),
          ],
          const Spacer(flex: 2),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: transparent ? Colors.transparent : const Color(0xFFF5F7FA),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: buildCenteredStats(font, record, accent, _t, transparent: transparent)),
          ),
          const Spacer(flex: 1),
        ]),
      ),
    );
  }
}

// ── 3. Grid ───────────────────────────────────────────────────────────────
class RunGridCard extends StatelessWidget {
  final RunningRecord record;
  final Color accent;
  final String font;
  final LabelLanguage language;
  final bool transparent;
  const RunGridCard({super.key, required this.record, required this.accent,
      required this.font, required this.language, this.transparent = false});
  String _t(String ko, String en) => language == LabelLanguage.korean ? ko : en;

  @override
  Widget build(BuildContext context) {
    final dist = record.distance.replaceAll(RegExp(r'\s*km'), '').trim();
    final sh = _sh(transparent);
    final stats = <(String, String)>[
      if (record.time.isNotEmpty)      (_t('총 시간', 'TIME'),     record.time),
      if (record.pace.isNotEmpty)      (_t('평균 페이스', 'PACE'),  record.pace),
      if (record.heartRate.isNotEmpty) (_t('평균 심박수', 'HR'),    record.heartRate),
    ];
    return AspectRatio(
      aspectRatio: kCardRatio,
      child: Container(
        color: transparent ? Colors.transparent : Colors.white,
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('PaceGraphy', style: runCardTs(font, fontSize: 9,
                fontWeight: FontWeight.w800, color: accent, letterSpacing: 2, shadows: sh)),
            const Spacer(),
            if (!transparent && record.date.isNotEmpty)
              Text(record.date, style: runCardTs(font, fontSize: 11, color: _grey, shadows: sh)),
          ]),
          const Spacer(flex: 1),
          if (dist.isNotEmpty) ...[
            FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(dist, style: runCardTs(font, fontSize: 80,
                    fontWeight: FontWeight.w900, color: _dark, height: 1.0, shadows: sh)),
                const SizedBox(width: 8),
                Padding(padding: const EdgeInsets.only(bottom: 8),
                  child: Text('km', style: runCardTs(font, fontSize: 18,
                      fontWeight: FontWeight.w700, color: accent, shadows: sh))),
              ]),
            ),
          ],
          const SizedBox(height: 20),
          ...stats.map((s) => Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: transparent ? Colors.transparent : const Color(0xFFF5F7FA),
              borderRadius: BorderRadius.circular(12),
              border: Border(left: BorderSide(color: accent, width: 3)),
            ),
            child: Row(children: [
              Text(s.$1, style: runCardTs(font, fontSize: 12, color: transparent ? _dark : _grey,
                  fontWeight: FontWeight.w600, shadows: sh)),
              const Spacer(),
              Text(s.$2, style: runCardTs(font, fontSize: 22,
                  fontWeight: FontWeight.w800, color: _dark, shadows: sh)),
            ]),
          )),
          const Spacer(flex: 1),
        ]),
      ),
    );
  }
}

// ── 4. Side ───────────────────────────────────────────────────────────────
class RunSideCard extends StatelessWidget {
  final RunningRecord record;
  final Color accent;
  final String font;
  final LabelLanguage language;
  final bool transparent;
  const RunSideCard({super.key, required this.record, required this.accent,
      required this.font, required this.language, this.transparent = false});
  String _t(String ko, String en) => language == LabelLanguage.korean ? ko : en;

  @override
  Widget build(BuildContext context) {
    final dist = record.distance.replaceAll(RegExp(r'\s*km'), '').trim();
    final sh = _sh(transparent);
    final stats = <(String, String)>[
      if (record.time.isNotEmpty)      (_t('총 시간', 'TIME'),     record.time),
      if (record.pace.isNotEmpty)      (_t('평균 페이스', 'PACE'),  record.pace),
      if (record.heartRate.isNotEmpty) (_t('평균 심박수', 'HR'),    record.heartRate),
    ];
    return AspectRatio(
      aspectRatio: kCardRatio,
      child: Container(
        color: transparent ? Colors.transparent : Colors.white,
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            width: 110,
            color: transparent ? Colors.transparent : accent,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('PACE\nGRAPHY', style: runCardTs(font, fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: transparent ? accent : Colors.white.withOpacity(0.7),
                  letterSpacing: 1.5, height: 1.4, shadows: sh)),
              const Spacer(),
              ...stats.expand((s) => [
                Text(s.$1, style: runCardTs(font, fontSize: 10,
                    color: transparent ? _dark : Colors.white.withOpacity(0.65),
                    letterSpacing: 1.5, fontWeight: FontWeight.w600, shadows: sh)),
                const SizedBox(height: 3),
                Text(s.$2, style: runCardTs(font, fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: transparent ? _dark : Colors.white, shadows: sh)),
                const SizedBox(height: 18),
              ]),
              if (!transparent && record.date.isNotEmpty)
                Text(record.date, style: runCardTs(font, fontSize: 10,
                    color: transparent ? _grey : Colors.white.withOpacity(0.55), shadows: sh)),
            ]),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Spacer(flex: 2),
                if (dist.isNotEmpty) ...[
                  Text(_t('거리', 'DIST'), style: runCardTs(font, fontSize: 10,
                      color: _grey, letterSpacing: 2.5, fontWeight: FontWeight.w500, shadows: sh)),
                  const SizedBox(height: 4),
                  FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
                    child: Text(dist, style: runCardTs(font, fontSize: 72,
                        fontWeight: FontWeight.w900, color: _dark, height: 1.0, shadows: sh)),
                  ),
                  Text('km', style: runCardTs(font, fontSize: 18,
                      fontWeight: FontWeight.w700, color: accent, shadows: sh)),
                ],
                const Spacer(flex: 3),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

// ── 5. Badge ──────────────────────────────────────────────────────────────
class RunBadgeCard extends StatelessWidget {
  final RunningRecord record;
  final Color accent;
  final String font;
  final LabelLanguage language;
  final bool transparent;
  const RunBadgeCard({super.key, required this.record, required this.accent,
      required this.font, required this.language, this.transparent = false});
  String _t(String ko, String en) => language == LabelLanguage.korean ? ko : en;

  @override
  Widget build(BuildContext context) {
    final dist = record.distance.replaceAll(RegExp(r'\s*km'), '').trim();
    final sh = _sh(transparent);
    final stats = <(String, String)>[
      if (record.time.isNotEmpty)      (_t('총 시간', 'TIME'),     record.time),
      if (record.pace.isNotEmpty)      (_t('평균 페이스', 'PACE'),  record.pace),
      if (record.heartRate.isNotEmpty) (_t('평균 심박수', 'HR'),    record.heartRate),
    ];
    return AspectRatio(
      aspectRatio: kCardRatio,
      child: Container(
        color: transparent ? Colors.transparent : Colors.white,
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
        child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('PaceGraphy', style: runCardTs(font, fontSize: 9,
                fontWeight: FontWeight.w800, color: accent, letterSpacing: 2, shadows: sh)),
            if (!transparent && record.date.isNotEmpty)
              Text(record.date, style: runCardTs(font, fontSize: 11, color: _grey, shadows: sh)),
          ]),
          const Spacer(flex: 2),
          Container(
            width: 160, height: 160,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: accent, width: 3),
              color: transparent ? Colors.transparent : const Color(0xFFF8F8F8),
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(_t('거리', 'DIST'), style: runCardTs(font, fontSize: 10,
                  color: _grey, letterSpacing: 2, fontWeight: FontWeight.w600, shadows: sh)),
              const SizedBox(height: 2),
              if (dist.isNotEmpty)
                FittedBox(
                  child: Text(dist, style: runCardTs(font, fontSize: 52,
                      fontWeight: FontWeight.w900, color: _dark, height: 1.0, shadows: sh)),
                ),
              Text('km', style: runCardTs(font, fontSize: 14,
                  fontWeight: FontWeight.w700, color: accent, shadows: sh)),
            ]),
          ),
          const Spacer(flex: 2),
          if (stats.isNotEmpty)
            Row(children: [
              for (int i = 0; i < stats.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: transparent ? Colors.transparent : const Color(0xFFF5F7FA),
                      borderRadius: BorderRadius.circular(12),
                      border: Border(top: BorderSide(color: accent, width: 2.5)),
                    ),
                    child: Column(children: [
                      Text(stats[i].$2, style: runCardTs(font, fontSize: 17,
                          fontWeight: FontWeight.w800, color: _dark, shadows: sh)),
                      const SizedBox(height: 4),
                      Text(stats[i].$1, style: runCardTs(font, fontSize: 10,
                          color: transparent ? _dark : _grey, letterSpacing: 1.5, fontWeight: FontWeight.w600, shadows: sh)),
                    ]),
                  ),
                ),
              ],
            ]),
          const Spacer(flex: 1),
        ]),
      ),
    );
  }
}

// ── 6. Split ──────────────────────────────────────────────────────────────
class RunSplitCard extends StatelessWidget {
  final RunningRecord record;
  final Color accent;
  final String font;
  final LabelLanguage language;
  final bool transparent;
  const RunSplitCard({super.key, required this.record, required this.accent,
      required this.font, required this.language, this.transparent = false});
  String _t(String ko, String en) => language == LabelLanguage.korean ? ko : en;

  @override
  Widget build(BuildContext context) {
    final dist = record.distance.replaceAll(RegExp(r'\s*km'), '').trim();
    final sh = _sh(transparent);
    final stats = <(String, String)>[
      if (record.time.isNotEmpty)      (_t('총 시간', 'TIME'),     record.time),
      if (record.pace.isNotEmpty)      (_t('평균 페이스', 'PACE'),  record.pace),
      if (record.heartRate.isNotEmpty) (_t('평균 심박수', 'HR'),    record.heartRate),
    ];
    return AspectRatio(
      aspectRatio: kCardRatio,
      child: Column(children: [
        Expanded(
          flex: 5,
          child: Container(
            width: double.infinity,
            color: transparent ? Colors.transparent : accent,
            padding: const EdgeInsets.fromLTRB(28, 28, 28, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('PaceGraphy', style: runCardTs(font, fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: transparent ? accent : Colors.white.withOpacity(0.6),
                  letterSpacing: 2, shadows: sh)),
              const Spacer(),
              Text(_t('거리', 'DISTANCE'), style: runCardTs(font, fontSize: 11,
                  color: transparent ? _grey : Colors.white.withOpacity(0.7),
                  letterSpacing: 2.5, fontWeight: FontWeight.w500, shadows: sh)),
              const SizedBox(height: 4),
              if (dist.isNotEmpty)
                FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
                  child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(dist, style: runCardTs(font, fontSize: 80,
                        fontWeight: FontWeight.w900,
                        color: transparent ? _dark : Colors.white,
                        height: 1.0, shadows: sh)),
                    const SizedBox(width: 8),
                    Padding(padding: const EdgeInsets.only(bottom: 10),
                      child: Text('km', style: runCardTs(font, fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: transparent ? accent : Colors.white.withOpacity(0.8),
                          shadows: sh))),
                  ]),
                ),
              const SizedBox(height: 8),
            ]),
          ),
        ),
        Expanded(
          flex: 4,
          child: Container(
            width: double.infinity,
            color: transparent ? Colors.transparent : Colors.white,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Column(children: [
              if (stats.isNotEmpty)
                Expanded(
                  child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    for (int i = 0; i < stats.length; i++) ...[
                      if (i > 0)
                        Container(width: 1, color: const Color(0xFFEEEEEE),
                            margin: const EdgeInsets.symmetric(horizontal: 12)),
                      Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Text(stats[i].$2, style: runCardTs(font, fontSize: 20,
                            fontWeight: FontWeight.w800, color: _dark, shadows: sh)),
                        const SizedBox(height: 6),
                        Text(stats[i].$1, style: runCardTs(font, fontSize: 10,
                            color: transparent ? _dark : _grey, letterSpacing: 1.5, fontWeight: FontWeight.w600, shadows: sh)),
                      ])),
                    ],
                  ]),
                ),
              if (!transparent && record.date.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(record.date, style: runCardTs(font, fontSize: 11, color: _grey, shadows: sh)),
              ],
            ]),
          ),
        ),
      ]),
    );
  }
}

// ── 7. Dark ───────────────────────────────────────────────────────────────
class RunDarkCard extends StatelessWidget {
  final RunningRecord record;
  final Color accent;
  final String font;
  final LabelLanguage language;
  final bool transparent;
  const RunDarkCard({super.key, required this.record, required this.accent,
      required this.font, required this.language, this.transparent = false});
  String _t(String ko, String en) => language == LabelLanguage.korean ? ko : en;

  @override
  Widget build(BuildContext context) {
    final dist = record.distance.replaceAll(RegExp(r'\s*km'), '').trim();
    const bg = Color(0xFF1C1C1E);
    const cardBg = Color(0xFF2C2C2E);
    const textDim = Color(0xFF8E8E93);
    final sh = _sh(transparent);

    final allStats = <(String, String)>[
      if (dist.isNotEmpty)             (_t('거리', 'DIST'),         '$dist km'),
      if (record.time.isNotEmpty)      (_t('시간', 'TIME'),         record.time),
      if (record.pace.isNotEmpty)      (_t('평균 페이스', 'PACE'),  record.pace),
      if (record.heartRate.isNotEmpty) (_t('평균 심박수', 'HR'),    record.heartRate),
    ];

    return AspectRatio(
      aspectRatio: kCardRatio,
      child: Container(
        color: transparent ? Colors.transparent : bg,
        padding: const EdgeInsets.fromLTRB(22, 28, 22, 28),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('PaceGraphy', style: runCardTs(font, fontSize: 9,
                fontWeight: FontWeight.w800, color: accent, letterSpacing: 2, shadows: sh)),
            const Spacer(),
            if (!transparent && record.date.isNotEmpty)
              Text(record.date, style: runCardTs(font, fontSize: 11,
                  color: transparent ? _grey : textDim, shadows: sh)),
          ]),
          const SizedBox(height: 16),
          Container(height: 2, width: 40, color: accent),
          const SizedBox(height: 20),
          Expanded(
            child: GridView.count(
              crossAxisCount: 2,
              childAspectRatio: 1.9,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              physics: const NeverScrollableScrollPhysics(),
              shrinkWrap: true,
              children: allStats.map((s) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: transparent ? Colors.transparent : cardBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(s.$1, style: runCardTs(font, fontSize: 10,
                      color: transparent ? _dark : textDim,
                      letterSpacing: 1.5, fontWeight: FontWeight.w600, shadows: sh)),
                  const SizedBox(height: 4),
                  Text(s.$2, style: runCardTs(font, fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: transparent ? _dark : Colors.white, shadows: sh)),
                ]),
              )).toList(),
            ),
          ),
        ]),
      ),
    );
  }
}

// ══ Overlay-only templates ════════════════════════════════════════════════════
//
// All cards are designed at _kRefWidth (400px) and scaled via FittedBox.
// No lines, no icons — pure typography.

// These fonts render visually smaller than their point size suggests — scale up.
const _overlayScaleUpFonts = {
  'Nanum Pen Script', 'Gaegu', 'Caveat', 'Bebas Neue',
};

// Public wrapper so external widgets can use the same overlay text style.
TextStyle overlayTs(String font, {
  required double fontSize,
  FontWeight? fontWeight,
  Color? color,
  double? height,
  double? letterSpacing,
  List<Shadow>? shadows,
}) => _ots(font,
  fontSize: fontSize, fontWeight: fontWeight, color: color,
  height: height, letterSpacing: letterSpacing, shadows: shadows,
);

// Overlay text style helper — applies 1.2× size for script fonts.
TextStyle _ots(String font, {
  required double fontSize,
  FontWeight? fontWeight,
  Color? color,
  double? height,
  double? letterSpacing,
  List<Shadow>? shadows,
}) => runCardTs(font,
  fontSize: fontSize * (_overlayScaleUpFonts.contains(font) ? 1.2 : 1.0),
  fontWeight: fontWeight,
  color: color,
  height: height,
  letterSpacing: letterSpacing,
  shadows: shadows,
);

enum OverlayTemplate { poster, wide, tall, list, grid }

double getOverlayCardAspectRatio(OverlayTemplate t) => switch (t) {
  OverlayTemplate.poster => 3.0,
  OverlayTemplate.wide   => 5.0,
  OverlayTemplate.tall   => 2.4,
  OverlayTemplate.list   => 2.2,
  OverlayTemplate.grid   => 2.5,
};

Widget buildOverlayCard(
  OverlayTemplate type,
  RunningRecord record,
  Color accent,
  String font,
  LabelLanguage language, {
  bool showHeartRate = true,
}) {
  switch (type) {
    case OverlayTemplate.poster:
      return OverlayPosterCard(record: record, accent: accent, font: font, language: language, showHeartRate: showHeartRate);
    case OverlayTemplate.wide:
      return OverlayWideCard(record: record, accent: accent, font: font, language: language, showHeartRate: showHeartRate);
    case OverlayTemplate.tall:
      return OverlayTallCard(record: record, accent: accent, font: font, language: language, showHeartRate: showHeartRate);
    case OverlayTemplate.list:
      return OverlayListCard(record: record, accent: accent, font: font, language: language, showHeartRate: showHeartRate);
    case OverlayTemplate.grid:
      return OverlayGridCard(record: record, accent: accent, font: font, language: language, showHeartRate: showHeartRate);
  }
}

// ── Overlay: Poster (3.0:1) ───────────────────────────────────────────────────
class OverlayPosterCard extends StatelessWidget {
  final RunningRecord record;
  final Color accent;
  final String font;
  final LabelLanguage language;
  final bool showHeartRate;
  const OverlayPosterCard({super.key, required this.record, required this.accent,
      required this.font, required this.language, this.showHeartRate = true});
  String _t(String ko, String en) => language == LabelLanguage.korean ? ko : en;

  @override
  Widget build(BuildContext context) {
    final sh = _shFor(accent);
    final dist = record.distance.replaceAll(RegExp(r'\s*km'), '').trim();
    final stats = <(String, String)>[];
    if (record.time.isNotEmpty)                        stats.add((record.time,      _t('시간',   'TIME')));
    if (record.pace.isNotEmpty)                        stats.add((record.pace,      _t('페이스', 'PACE')));
    if (record.heartRate.isNotEmpty && showHeartRate)  stats.add((record.heartRate, _t('심박',   'HR')));

    return AspectRatio(
      aspectRatio: 3.0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (dist.isNotEmpty)
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(dist, maxLines: 1, softWrap: false,
                    style: _ots(font, fontSize: 74,
                        fontWeight: FontWeight.w900, color: accent, height: 1.0, shadows: sh)),
                const SizedBox(width: 5),
                Padding(padding: const EdgeInsets.only(bottom: 6),
                  child: Text('km', maxLines: 1, softWrap: false,
                      style: _ots(font, fontSize: 17,
                          fontWeight: FontWeight.w700, color: accent, shadows: sh))),
              ]),
            if (dist.isNotEmpty) const SizedBox(height: 10),
            if (stats.isNotEmpty)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: stats.map((s) => Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.center,
                      child: Text(s.$1, maxLines: 1, softWrap: false,
                          style: _ots(font, fontSize: 24,
                              fontWeight: FontWeight.w800, color: accent, shadows: sh))),
                    const SizedBox(height: 2),
                    Text(s.$2, maxLines: 1, softWrap: false, textAlign: TextAlign.center,
                        style: _ots(font, fontSize: 11,
                            fontWeight: FontWeight.w600, color: accent,
                            letterSpacing: 0.5, shadows: sh)),
                  ],
                )).toList()),
          ],
        ),
      ),
    );
  }
}

// ── Overlay: Wide (5.0:1) ─────────────────────────────────────────────────────
// All columns use the same fixed fontSize — no per-column FittedBox so text
// sizes are visually identical regardless of content length or font choice.
class OverlayWideCard extends StatelessWidget {
  final RunningRecord record;
  final Color accent;
  final String font;
  final LabelLanguage language;
  final bool showHeartRate;
  const OverlayWideCard({super.key, required this.record, required this.accent,
      required this.font, required this.language, this.showHeartRate = true});
  String _t(String ko, String en) => language == LabelLanguage.korean ? ko : en;

  @override
  Widget build(BuildContext context) {
    final sh = _shFor(accent);
    final dist = record.distance.replaceAll(RegExp(r'\s*km'), '').trim();
    final cols = <(String, String)>[];
    if (dist.isNotEmpty)                               cols.add(('$dist km',       _t('거리',   'DIST')));
    if (record.time.isNotEmpty)                        cols.add((record.time,      _t('시간',   'TIME')));
    if (record.pace.isNotEmpty)                        cols.add((record.pace,      _t('페이스', 'PACE')));
    if (record.heartRate.isNotEmpty && showHeartRate)  cols.add((record.heartRate, _t('심박',   'HR')));

    return AspectRatio(
      aspectRatio: 5.0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            for (int i = 0; i < cols.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.center,
                      child: Text(cols[i].$1, maxLines: 1, softWrap: false,
                          style: _ots(font, fontSize: 19,
                              fontWeight: FontWeight.w800, color: accent, shadows: sh)),
                    ),
                    const SizedBox(height: 2),
                    Text(cols[i].$2, maxLines: 1, softWrap: false, textAlign: TextAlign.center,
                        style: _ots(font, fontSize: 11,
                            fontWeight: FontWeight.w600, color: accent,
                            letterSpacing: 0.5, shadows: sh)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Overlay: Tall (2.4:1) ─────────────────────────────────────────────────────
class OverlayTallCard extends StatelessWidget {
  final RunningRecord record;
  final Color accent;
  final String font;
  final LabelLanguage language;
  final bool showHeartRate;
  const OverlayTallCard({super.key, required this.record, required this.accent,
      required this.font, required this.language, this.showHeartRate = true});
  String _t(String ko, String en) => language == LabelLanguage.korean ? ko : en;

  @override
  Widget build(BuildContext context) {
    final sh = _shFor(accent);
    final dist = record.distance.replaceAll(RegExp(r'\s*km'), '').trim();
    final stats = <(String, String)>[];
    if (record.time.isNotEmpty)                        stats.add((record.time,      _t('시간',   'TIME')));
    if (record.pace.isNotEmpty)                        stats.add((record.pace,      _t('페이스', 'PACE')));
    if (record.heartRate.isNotEmpty && showHeartRate)  stats.add((record.heartRate, _t('심박',   'HR')));

    return AspectRatio(
      aspectRatio: 2.4,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (dist.isNotEmpty) ...[
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Flexible(
                  child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
                    child: Text(dist, maxLines: 1, softWrap: false,
                        style: _ots(font, fontSize: 106,
                            fontWeight: FontWeight.w900, color: accent, height: 1.0, shadows: sh))),
                ),
                const SizedBox(width: 5),
                Padding(padding: const EdgeInsets.only(bottom: 7),
                  child: Text('km', maxLines: 1, softWrap: false,
                      style: _ots(font, fontSize: 17,
                          fontWeight: FontWeight.w700, color: accent, shadows: sh))),
              ]),
              const SizedBox(height: 4),
            ],
            if (stats.isNotEmpty)
              Row(children: stats.map((s) => Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
                  FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.center,
                    child: Text(s.$1, maxLines: 1, softWrap: false,
                        style: _ots(font, fontSize: 22,
                            fontWeight: FontWeight.w800, color: accent, shadows: sh))),
                  const SizedBox(height: 2),
                  Text(s.$2, maxLines: 1, softWrap: false, textAlign: TextAlign.center,
                      style: _ots(font, fontSize: 11,
                          fontWeight: FontWeight.w600, color: accent,
                          letterSpacing: 0.5, shadows: sh)),
                ]),
              )).toList()),
          ],
        ),
      ),
    );
  }
}

// ── Overlay: List (2.2:1) ─────────────────────────────────────────────────────
// Vertical list — each stat on its own row: value left, label right.
// Equivalent of 가로형 but stacked vertically.
class OverlayListCard extends StatelessWidget {
  final RunningRecord record;
  final Color accent;
  final String font;
  final LabelLanguage language;
  final bool showHeartRate;
  const OverlayListCard({super.key, required this.record, required this.accent,
      required this.font, required this.language, this.showHeartRate = true});
  String _t(String ko, String en) => language == LabelLanguage.korean ? ko : en;

  @override
  Widget build(BuildContext context) {
    final sh = _shFor(accent);
    final dist = record.distance.replaceAll(RegExp(r'\s*km'), '').trim();
    final rows = <(String, String)>[];
    if (dist.isNotEmpty)                               rows.add(('$dist km',       _t('거리',   'DIST')));
    if (record.time.isNotEmpty)                        rows.add((record.time,      _t('시간',   'TIME')));
    if (record.pace.isNotEmpty)                        rows.add((record.pace,      _t('페이스', 'PACE')));
    if (record.heartRate.isNotEmpty && showHeartRate)  rows.add((record.heartRate, _t('심박',   'HR')));
    if (rows.isEmpty) return const AspectRatio(aspectRatio: 2.2, child: SizedBox());

    return AspectRatio(
      aspectRatio: 2.2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Column(
          children: [
            for (int i = 0; i < rows.length; i++) ...[
              if (i > 0) const SizedBox(height: 4),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 52,
                      child: Text(rows[i].$2, maxLines: 1, softWrap: false,
                          style: _ots(font, fontSize: 11,
                              fontWeight: FontWeight.w600, color: accent,
                              letterSpacing: 0.5, shadows: sh)),
                    ),
                    const SizedBox(width: 10),
                    Text(rows[i].$1, maxLines: 1, softWrap: false,
                        style: _ots(font, fontSize: 22,
                            fontWeight: FontWeight.w800, color: accent, shadows: sh)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Overlay: Grid (2.5:1) ─────────────────────────────────────────────────────
// 2×2 grid — [dist, time] on left column, [pace, hr] on right column.
class OverlayGridCard extends StatelessWidget {
  final RunningRecord record;
  final Color accent;
  final String font;
  final LabelLanguage language;
  final bool showHeartRate;
  const OverlayGridCard({super.key, required this.record, required this.accent,
      required this.font, required this.language, this.showHeartRate = true});
  String _t(String ko, String en) => language == LabelLanguage.korean ? ko : en;

  @override
  Widget build(BuildContext context) {
    final sh = _shFor(accent);
    final dist = record.distance.replaceAll(RegExp(r'\s*km'), '').trim();
    final items = <(String, String)>[];
    if (dist.isNotEmpty)                               items.add(('$dist km',       _t('거리',   'DIST')));
    if (record.time.isNotEmpty)                        items.add((record.time,      _t('시간',   'TIME')));
    if (record.pace.isNotEmpty)                        items.add((record.pace,      _t('페이스', 'PACE')));
    if (record.heartRate.isNotEmpty && showHeartRate)  items.add((record.heartRate, _t('심박',   'HR')));
    if (items.isEmpty) return const AspectRatio(aspectRatio: 2.5, child: SizedBox());

    Widget cell(String val, String lbl) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
          child: Text(val, maxLines: 1, softWrap: false,
              style: _ots(font, fontSize: 19,
                  fontWeight: FontWeight.w800, color: accent, shadows: sh))),
        const SizedBox(height: 2),
        Text(lbl, maxLines: 1, softWrap: false,
            style: _ots(font, fontSize: 10,
                fontWeight: FontWeight.w600, color: accent,
                letterSpacing: 0.5, shadows: sh)),
      ],
    );

    final col1 = items.length >= 2 ? items.sublist(0, 2) : items;
    final col2 = items.length > 2 ? items.sublist(2) : <(String, String)>[];

    return AspectRatio(
      aspectRatio: 2.5,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  cell(col1[0].$1, col1[0].$2),
                  if (col1.length > 1) ...[
                    const SizedBox(height: 6),
                    cell(col1[1].$1, col1[1].$2),
                  ],
                ],
              ),
            ),
            if (col2.isNotEmpty) ...[
              const SizedBox(width: 7),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    cell(col2[0].$1, col2[0].$2),
                    if (col2.length > 1) ...[
                      const SizedBox(height: 6),
                      cell(col2[1].$1, col2[1].$2),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
