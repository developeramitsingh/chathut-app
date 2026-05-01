import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';

class LiveChatScreen extends StatefulWidget {
  final String partnerId;
  final String partnerName;
  final List<Map<String, dynamic>> initialPartnerMessages;

  const LiveChatScreen({
    super.key,
    required this.partnerId,
    required this.partnerName,
    this.initialPartnerMessages = const [],
  });

  @override
  State<LiveChatScreen> createState() => _LiveChatScreenState();
}

class _LiveChatScreenState extends State<LiveChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final List<Map<String, dynamic>> _messages = [];
  StreamSubscription<Map<String, dynamic>>? _incomingChatSub;

  @override
  void initState() {
    super.initState();
    if (widget.initialPartnerMessages.isNotEmpty) {
      _messages.addAll(
        widget.initialPartnerMessages.map(
          (item) => {
            'fromMe': false,
            'text': item['text']?.toString() ?? '',
            'time':
                item['time']?.toString() ?? DateTime.now().toIso8601String(),
          },
        ),
      );
    }

    _incomingChatSub = SocketService.instance.incomingDirectChatMessageStream
        .listen((event) {
      final fromId = event['fromId']?.toString();
      if (fromId != widget.partnerId) return;
      if (!mounted) return;
      setState(() {
        _messages.add({
          'fromMe': false,
          'text': event['message']?.toString() ?? '',
          'time': event['sentAt']?.toString() ?? DateTime.now().toIso8601String(),
        });
      });
    });
  }

  @override
  void dispose() {
    _incomingChatSub?.cancel();
    _messageController.dispose();
    super.dispose();
  }

  String _formatTime(String value) {
    try {
      final date = DateTime.parse(value).toLocal();
      final hh = date.hour.toString().padLeft(2, '0');
      final mm = date.minute.toString().padLeft(2, '0');
      return '$hh:$mm';
    } catch (_) {
      return '';
    }
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    SocketService.instance.sendDirectChatMessage(widget.partnerId, text);

    setState(() {
      _messages.add({
        'fromMe': true,
        'text': text,
        'time': DateTime.now().toIso8601String(),
      });
    });

    _messageController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final myName = ApiService.currentUser?['name']?.toString() ?? 'You';

    return Scaffold(
      backgroundColor: const Color(0xFF0D1030),
      appBar: AppBar(
        backgroundColor: const Color(0xFF10133D),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.partnerName, style: const TextStyle(color: Colors.white)),
            const Text(
              'Live Chat (Free)',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? const Center(
                    child: Text(
                      'Start your live chat.',
                      style: TextStyle(color: Colors.white54),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final item = _messages[index];
                      final fromMe = item['fromMe'] == true;
                      final text = item['text']?.toString() ?? '';
                      final time = _formatTime(item['time']?.toString() ?? '');

                      return Align(
                        alignment:
                            fromMe ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          constraints: const BoxConstraints(maxWidth: 280),
                          decoration: BoxDecoration(
                            color: fromMe
                                ? const Color(0xFFFF5AA2)
                                : const Color(0xFF1A1F4D),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (!fromMe)
                                Text(
                                  widget.partnerName,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                  ),
                                ),
                              if (fromMe)
                                Text(
                                  myName,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                  ),
                                ),
                              Text(
                                text,
                                style: const TextStyle(color: Colors.white),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                time,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Type your message',
                        hintStyle: const TextStyle(color: Colors.white54),
                        filled: true,
                        fillColor: const Color(0xFF1A1F4D),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: _sendMessage,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF5AA2),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
