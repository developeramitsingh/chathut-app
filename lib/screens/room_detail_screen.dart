import 'package:flutter/material.dart';
import '../services/api_service.dart';

class RoomDetailScreen extends StatefulWidget {
  final Map<String, dynamic> room;

  const RoomDetailScreen({super.key, required this.room});

  @override
  State<RoomDetailScreen> createState() => _RoomDetailScreenState();
}

class _RoomDetailScreenState extends State<RoomDetailScreen> {
  late Map<String, dynamic> _room;
  bool _isLoading = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _room = widget.room;
  }

  bool get _isHost {
    final currentUser = ApiService.currentUser;
    return currentUser != null && currentUser['name'] == _room['hostName'];
  }

  bool get _hasFemaleSpeaker => _room['femaleSpeaker'] != null;
  bool get _hasCoSpeaker => _room['otherSpeaker'] != null;
  String get _currentGender => ApiService.currentUser?['gender'] ?? '';

  Future<void> _refreshRoom() async {
    if (_room['_id'] == null && _room['id'] == null) return;
    final roomId = _room['_id']?.toString() ?? _room['id'].toString();
    try {
      final updated = await ApiService.getRoom(roomId);
      if (!mounted) return;
      setState(() {
        _room = updated;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _message = e.toString();
      });
    }
  }

  Future<void> _joinRoom(String role) async {
    if (_room['_id'] == null && _room['id'] == null) return;
    final roomId = _room['_id']?.toString() ?? _room['id'].toString();
    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      await ApiService.joinRoom(roomId: roomId, role: role);
      await _refreshRoom();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Joined room successfully')));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _message = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hostName = _room['hostName'] as String? ?? 'Host';
    final roomName = _room['name'] as String? ?? 'Live Room';
    final femaleSpeaker = _room['femaleSpeaker'] as String?;
    final otherSpeaker = _room['otherSpeaker'] as String?;
    final listeners = _room['listeners']?.toString() ?? '0';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Room details'),
        backgroundColor: const Color(0xFF10133D),
      ),
      backgroundColor: const Color(0xFF0D1030),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF2B1E67), Color(0xFF321D61)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const CircleAvatar(
                        radius: 26,
                        backgroundColor: Color(0xFFFF5AA2),
                        child: Icon(Icons.mic, color: Colors.white),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(roomName, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text('Host: $hostName', style: const TextStyle(color: Colors.white70, fontSize: 14)),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      _InfoBadge(label: 'Listeners', value: listeners),
                      const SizedBox(width: 12),
                      _InfoBadge(label: 'Live', value: 'Yes'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text('Room roles', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            _RoleCard(title: 'Host', value: hostName, icon: Icons.person),
            const SizedBox(height: 10),
            _RoleCard(title: 'Female Speaker', value: femaleSpeaker ?? 'Open', icon: Icons.female),
            const SizedBox(height: 10),
            _RoleCard(title: 'Co-speaker', value: otherSpeaker ?? 'Open', icon: Icons.mic),
            const SizedBox(height: 16),
            if (_message != null) ...[
              Text(_message!, style: const TextStyle(color: Colors.redAccent)),
              const SizedBox(height: 12),
            ],
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else ...[
              ElevatedButton(
                onPressed: _isHost ? null : () => _joinRoom('listener'),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF5E4FFF), padding: const EdgeInsets.symmetric(vertical: 16)),
                child: const Text('Join as Listener'),
              ),
              const SizedBox(height: 12),
              if (!_hasFemaleSpeaker && _currentGender == 'female' && !_isHost)
                ElevatedButton(
                  onPressed: () => _joinRoom('femaleSpeaker'),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF5AA2), padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: const Text('Take Female Speaker Role'),
                ),
              if (!_hasFemaleSpeaker && _currentGender != 'female' && !_isHost)
                const Text('Only female users can take the female speaker role.', style: TextStyle(color: Colors.white54)),
              if (!_hasCoSpeaker && !_isHost)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: ElevatedButton(
                    onPressed: () => _joinRoom('coSpeaker'),
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF8E44AD), padding: const EdgeInsets.symmetric(vertical: 16)),
                    child: const Text('Take Co-speaker Role'),
                  ),
                ),
            ],
            const Spacer(),
            TextButton(
              onPressed: _refreshRoom,
              child: const Text('Refresh room details', style: TextStyle(color: Colors.white70)),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoBadge extends StatelessWidget {
  final String label;
  final String value;

  const _InfoBadge({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF150A2B),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;

  const _RoleCard({required this.title, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF151A3C),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white70),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
