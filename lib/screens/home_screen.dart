import 'package:flutter/material.dart';
import '../models/overlay_style.dart';
import 'record_photo_screen.dart';
import 'photo_in_photo_screen.dart';
import 'running_card_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  LabelLanguage _language = LabelLanguage.korean;

  String _t(String ko, String en) => _language == LabelLanguage.korean ? ko : en;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('RUN PICTURE',
            style: TextStyle(fontFamily: 'SUIT', color: Color(0xFF1C1C1E),
                fontWeight: FontWeight.w700, fontSize: 20, letterSpacing: 1.0)),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              _langToggle('한', LabelLanguage.korean),
              const SizedBox(width: 6),
              _langToggle('EN', LabelLanguage.english),
            ]),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Expanded(
              child: _menuCard(
                icon: Icons.directions_run_rounded,
                title: _t('기록 사진 생성', 'Create Record Photo'),
                subtitle: _t('러닝 기록을 사진에 오버레이', 'Overlay running stats on a photo'),
                onTap: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => RecordPhotoScreen(language: _language),
                )),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _menuCard(
                icon: Icons.photo_library_rounded,
                title: _t('사진 속에 사진 추가', 'Photo in Photo'),
                subtitle: _t('사진 안에 다른 사진 삽입', 'Insert a photo inside another'),
                onTap: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => PhotoInPhotoScreen(language: _language),
                )),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _menuCard(
                icon: Icons.style_rounded,
                title: _t('러닝 카드 생성', 'Running Card'),
                subtitle: _t('템플릿으로 러닝 기록 카드 만들기', 'Create a styled running card'),
                onTap: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => RunningCardScreen(language: _language),
                )),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _menuCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              color: const Color(0xFFF0F0F0),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(icon, color: const Color(0xFF1C1C1E), size: 36),
          ),
          const SizedBox(height: 16),
          Text(title, style: const TextStyle(
              fontFamily: 'SUIT', color: Color(0xFF1C1C1E),
              fontWeight: FontWeight.w700, fontSize: 18)),
          const SizedBox(height: 6),
          Text(subtitle, style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 13)),
        ]),
      ),
    );
  }

  Widget _langToggle(String label, LabelLanguage lang) {
    final selected = _language == lang;
    return GestureDetector(
      onTap: () => setState(() => _language = lang),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF1C1C1E) : const Color(0xFFF5F7FA),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: selected ? const Color(0xFF1C1C1E) : const Color(0xFFE5E5EA)),
        ),
        child: Text(label, style: TextStyle(
          fontSize: 11, fontWeight: FontWeight.w600,
          color: selected ? Colors.white : const Color(0xFF8E8E93),
        )),
      ),
    );
  }
}
