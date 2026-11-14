import 'package:flutter/material.dart';

class OnboardingScreen extends StatefulWidget {
  final Future<void> Function() onDone;
  const OnboardingScreen({super.key, required this.onDone});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  static const pages = [
    ('🥚', 'Meet your creature',
        'You will raise a creature from egg to dragon. But it can ONLY grow when you complete your daily tasks.'),
    ('⚔️', 'The rules',
        'Finish ALL your tasks for a perfect day. Perfect days evolve your creature, build your streak, and defeat the weekly boss. Miss a day and it loses energy — unless a 🧊 streak freeze saves you.'),
    ('🔒', 'No cheats',
        "Checked tasks lock until tomorrow. No store, no skipping, no way to feed your creature except doing the work. Your data never leaves your device."),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: pages.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) => Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(pages[i].$1,
                          style: const TextStyle(fontSize: 80)),
                      const SizedBox(height: 24),
                      Text(pages[i].$2,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 26, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 16),
                      Text(pages[i].$3,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 16)),
                    ],
                  ),
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < pages.length; i++)
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i == _page ? Colors.teal : Colors.grey,
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    if (_page < pages.length - 1) {
                      _controller.nextPage(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOut);
                    } else {
                      widget.onDone();
                    }
                  },
                  child: Text(
                      _page < pages.length - 1 ? 'Next' : 'Start my journey'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
