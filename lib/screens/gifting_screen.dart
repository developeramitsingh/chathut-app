import 'package:flutter/material.dart';

class GiftingScreen extends StatelessWidget {
  final bool nested;
  const GiftingScreen({super.key, this.nested = false});

  final List<Map<String, Object>> gifts = const [
    {'name': 'Rose', 'price': 50, 'icon': '🌹'},
    {'name': 'Diamond', 'price': 150, 'icon': '💎'},
    {'name': 'Rocket', 'price': 300, 'icon': '🚀'},
    {'name': 'Crown', 'price': 300, 'icon': '👑'},
  ];

  @override
  Widget build(BuildContext context) {
    final grid = GridView.count(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      physics: nested ? const NeverScrollableScrollPhysics() : null,
      shrinkWrap: nested,
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 0.9,
      children: gifts.map((gift) {
        final name = gift['name'] as String;
        final price = gift['price'] as int;
        final icon = gift['icon'] as String;
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF191433),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white10),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(icon, style: const TextStyle(fontSize: 42)),
                Column(
                  children: [
                    Text(name, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text('$price coins', style: const TextStyle(color: Colors.white70)),
                  ],
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF4F8A),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
                  ),
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sent $name'))),
                  child: const Text('Send', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF17132F),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Your Wallet', style: TextStyle(color: Colors.white70, fontSize: 14)),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: const [
                    Text('2,560', style: TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900)),
                    Icon(Icons.account_balance_wallet, color: Colors.pinkAccent, size: 32),
                  ],
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: 0.72,
                  color: const Color(0xFFFF4F8A),
                  backgroundColor: Colors.white12,
                ),
                const SizedBox(height: 6),
                const Text('72% to next reward', style: TextStyle(color: Colors.white54, fontSize: 13)),
              ],
            ),
          ),
        ),
        if (nested)
          SizedBox(height: 520, child: grid)
        else
          Expanded(child: grid),
      ],
    );
  }
}
