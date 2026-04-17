import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'room_detail_screen.dart';

class AudioRoomScreen extends StatefulWidget {
  final bool nested;
  const AudioRoomScreen({super.key, this.nested = false});

  @override
  State<AudioRoomScreen> createState() => _AudioRoomScreenState();
}

class _AudioRoomScreenState extends State<AudioRoomScreen> {
  List<Map<String, dynamic>> _rooms = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRooms();
  }

  Future<void> _loadRooms() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final rooms = await ApiService.getRooms();
      if (!mounted) return;
      setState(() {
        _rooms = rooms.map((room) => Map<String, dynamic>.from(room as Map<String, dynamic>)).toList();
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
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

  Future<void> _createRoom() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF121738),
          title: const Text('Create room', style: TextStyle(color: Colors.white)),
          content: TextField(
            controller: controller,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: 'Room name',
              hintStyle: TextStyle(color: Colors.white54),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Create'),
            ),
          ],
        );
      },
    );

    if (name == null || name.isEmpty) return;

    try {
      await ApiService.createRoom(name: name);
      await _loadRooms();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Room created successfully')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Loading rooms...', style: TextStyle(color: Colors.white70)),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(child: Text(_error!, style: const TextStyle(color: Colors.white70)));
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Live Connect', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              ElevatedButton.icon(
                onPressed: _createRoom,
                icon: const Icon(Icons.add),
                label: const Text('Create'),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF5AA2)),
              ),
            ],
          ),
        ),
        if (widget.nested)
          ListView.builder(
            padding: const EdgeInsets.all(16),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _rooms.length,
            itemBuilder: (context, index) {
              final room = _rooms[index];
              return GestureDetector(
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => RoomDetailScreen(room: room)),
                  );
                  await _loadRooms();
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF251B52), Color(0xFF321D61)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const CircleAvatar(
                            radius: 22,
                            backgroundColor: Color(0xFFFF4F8A),
                            child: Icon(Icons.mic, color: Colors.white),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(room['name'] as String, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                                const SizedBox(height: 4),
                                Text('Host ${room['hostName']}', style: const TextStyle(color: Colors.white60, fontSize: 13)),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF5AA2),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Text('${room['listeners']} listening', style: const TextStyle(color: Colors.white, fontSize: 12)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          _RoleChip(label: 'Female', value: room['femaleSpeaker'] as String?),
                          const SizedBox(width: 12),
                          _RoleChip(label: 'Co-speaker', value: room['otherSpeaker'] as String?),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          )
        else
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _rooms.length,
              itemBuilder: (context, index) {
                final room = _rooms[index];
                return GestureDetector(
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => RoomDetailScreen(room: room)),
                    );
                    await _loadRooms();
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF251B52), Color(0xFF321D61)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const CircleAvatar(
                              radius: 22,
                              backgroundColor: Color(0xFFFF4F8A),
                              child: Icon(Icons.mic, color: Colors.white),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(room['name'] as String, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                                  const SizedBox(height: 4),
                                  Text('Host ${room['hostName']}', style: const TextStyle(color: Colors.white60, fontSize: 13)),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF5AA2),
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Text('${room['listeners']} listening', style: const TextStyle(color: Colors.white, fontSize: 12)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            _RoleChip(label: 'Female', value: room['femaleSpeaker'] as String?),
                            const SizedBox(width: 12),
                            _RoleChip(label: 'Co-speaker', value: room['otherSpeaker'] as String?),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _RoleChip extends StatelessWidget {
  final String label;
  final String? value;

  const _RoleChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF150A2B),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 4),
            Text(value ?? 'Open', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}
