import 'package:flutter/material.dart';

class ChatRoomScreen extends StatelessWidget {
  final bool nested;
  const ChatRoomScreen({super.key, this.nested = false});

  final List<Map<String, Object>> rooms = const [
    {'title': 'General', 'members': 230},
    {'title': 'Music Fans', 'members': 125},
    {'title': 'Movie Night', 'members': 98},
    {'title': 'Fitness Buddies', 'members': 72},
  ];

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      shrinkWrap: nested,
      physics: nested ? const NeverScrollableScrollPhysics() : null,
      itemCount: rooms.length,
      itemBuilder: (context, index) {
        final room = rooms[index];
        final title = room['title'] as String;
        final members = room['members'] as int;
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF161130),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white10),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFF9B5BFF), Color(0xFFFF4F8A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: const Icon(Icons.chat, color: Colors.white),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text('$members active members', style: const TextStyle(color: Colors.white60, fontSize: 14)),
                  ],
                ),
              ),
              ElevatedButton(
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Joined $title room'))),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF4F8A),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                ),
                child: const Text('Join', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
      },
    );
  }
}
