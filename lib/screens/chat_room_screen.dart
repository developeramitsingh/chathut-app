import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import 'live_chat_screen.dart';

class ChatRoomScreen extends StatefulWidget {
  final bool nested;
  const ChatRoomScreen({super.key, this.nested = false});

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  List<Map<String, dynamic>> _livePartners = [];
  bool _isLoading = true;
  String? _error;
  StreamSubscription<List<Map<String, dynamic>>>? _liveUsersSub;

  @override
  void initState() {
    super.initState();
    _liveUsersSub = SocketService.instance.liveUsersStream.listen((users) {
      if (!mounted) return;
      setState(() {
        _livePartners = users;
        _isLoading = false;
        _error = null;
      });
    });
    _loadLivePartners();
  }

  @override
  void dispose() {
    _liveUsersSub?.cancel();
    super.dispose();
  }

  Future<void> _loadLivePartners() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    if (SocketService.instance.isConnected) {
      SocketService.instance.requestLiveUsers();
      return;
    }

    try {
      final users = await ApiService.getLiveUsers();
      if (!mounted) return;
      setState(() {
        _livePartners = users
            .map((item) => Map<String, dynamic>.from(item as Map<String, dynamic>))
            .toList();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _openLiveChat(Map<String, dynamic> partner) {
    final partnerId = partner['id']?.toString();
    final partnerName = partner['name']?.toString() ?? 'Partner';
    if (partnerId == null || partnerId.isEmpty) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LiveChatScreen(
          partnerId: partnerId,
          partnerName: partnerName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _loadLivePartners, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_livePartners.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(
          child: Text(
            'No active partners available for live chat.',
            style: TextStyle(color: Colors.white54),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      shrinkWrap: widget.nested,
      physics: widget.nested ? const NeverScrollableScrollPhysics() : null,
      itemCount: _livePartners.length,
      itemBuilder: (context, index) {
        final partner = _livePartners[index];
        final name = partner['name']?.toString() ?? 'Partner';
        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF161130),
            borderRadius: BorderRadius.circular(18),
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
                    Text(
                      name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Active now • Live chat is free',
                      style: TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                  ],
                ),
              ),
              ElevatedButton(
                onPressed: () => _openLiveChat(partner),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3A9B5F),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Chat', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
      },
    );
  }
}
