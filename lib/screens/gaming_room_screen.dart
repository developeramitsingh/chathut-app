import 'package:flutter/material.dart';

class GamingRoomScreen extends StatelessWidget {
  final bool nested;
  const GamingRoomScreen({super.key, this.nested = false});

  final List<Map<String, Object>> games = const [
    {'title': 'Brawl Clash', 'players': 14},
    {'title': 'Trivia Royale', 'players': 24},
    {'title': 'Speed Run', 'players': 9},
    {'title': 'Mystery Quest', 'players': 18},
  ];

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      shrinkWrap: nested,
      physics: nested ? const NeverScrollableScrollPhysics() : null,
      itemCount: games.length,
      itemBuilder: (context, index) {
        final game = games[index];
        final title = game['title'] as String;
        final players = game['players'] as int;
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1F143E), Color(0xFF291B56)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text('$players players online', style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.videogame_asset, color: Colors.pinkAccent),
                      SizedBox(width: 8),
                      Text('Quick match', style: TextStyle(color: Colors.white70)),
                    ],
                  ),
                  ElevatedButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Entering $title')));
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF4F8A),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    ),
                    child: const Text('Play', style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
