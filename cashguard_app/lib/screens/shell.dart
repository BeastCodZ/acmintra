import 'package:flutter/material.dart';
import '../theme.dart';
import 'home_screen.dart';
import 'finance_screen.dart';
import 'history_screen.dart';
import 'profile_screen.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;
  final _homeKey = GlobalKey<HomeScreenState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CP.bg,
      extendBody: true,
      body: IndexedStack(
        index: _tab,
        children: [
          HomeScreen(
              key: _homeKey,
              onOpenFinance: () => setState(() => _tab = 1)),
          const FinanceScreen(),
          const HistoryScreen(),
          const ProfileScreen(),
        ],
      ),
      bottomNavigationBar: Container(
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: CP.card,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: CP.stroke),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 24,
                offset: const Offset(0, 8)),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _navIcon(Icons.home_rounded, 0, 'Home'),
            _navIcon(Icons.pie_chart_rounded, 1, 'Finance'),
            GestureDetector(
              onTap: () {
                setState(() => _tab = 0);
                _homeKey.currentState?.scanWithCamera();
              },
              child: Container(
                width: 52, height: 52,
                decoration: const BoxDecoration(
                    color: CP.lavender, shape: BoxShape.circle),
                child: const Icon(Icons.add_rounded,
                    color: CP.lavenderDark, size: 28),
              ),
            ),
            _navIcon(Icons.history_rounded, 2, 'History'),
            _navIcon(Icons.person_rounded, 3, 'Profile'),
          ],
        ),
      ),
    );
  }

  Widget _navIcon(IconData icon, int index, String label) {
    final active = _tab == index;
    return GestureDetector(
      onTap: () => setState(() => _tab = index),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 42, height: 34,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(100),
              color: active ? CP.card2 : Colors.transparent,
            ),
            child: Icon(icon, color: active ? CP.text : CP.sub, size: 21),
          ),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  color: active ? CP.text : CP.sub,
                  fontSize: 10,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500)),
        ],
      ),
    );
  }
}
