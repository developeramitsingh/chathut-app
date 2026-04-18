import 'dart:async';

import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import 'call_screen.dart';

class RoomDetailScreen extends StatefulWidget {
  final Map<String, dynamic> room;

  const RoomDetailScreen({super.key, required this.room});

  @override
  State<RoomDetailScreen> createState() => _RoomDetailScreenState();
}

class _RoomDetailScreenState extends State<RoomDetailScreen> {
  late Map<String, dynamic> _room;
  bool _isLoading = false;
  bool _isConnectingAudio = false;
  bool _callInProgress = false;
  String? _message;
  StreamSubscription<Map<String, dynamic>>? _roomUpdateSubscription;
  StreamSubscription<Map<String, dynamic>>? _incomingCallSubscription;

  @override
  void initState() {
    super.initState();
    _room = widget.room;
    _subscribeToRoom();
  }

  Map<String, dynamic>? get _currentUser => ApiService.currentUser;
  String? get _currentUserId => _currentUser?['_id']?.toString() ?? _currentUser?['id']?.toString();

  bool get _isHost => _currentUserId != null && _currentUserId == _room['hostId']?.toString();

  bool get _isFemaleSpeaker => _currentUserId != null && _currentUserId == _room['femaleSpeakerId']?.toString();

  bool get _isNormalSpeaker => _currentUserId != null && _currentUserId == _room['otherSpeakerId']?.toString();

  bool get _isRoomParticipant => _isHost || _isFemaleSpeaker || _isNormalSpeaker;

  bool _isInRoom(String userId) {
    return userId == _room['hostId']?.toString() ||
        userId == _room['femaleSpeakerId']?.toString() ||
        userId == _room['otherSpeakerId']?.toString();
  }

  bool get _isQueued {
    final currentUser = ApiService.currentUser;
    if (currentUser == null || _room['queue'] == null) return false;
    final queue = List<dynamic>.from(_room['queue'] as List<dynamic>);
    final currentId = currentUser['_id']?.toString() ?? currentUser['id']?.toString();
    return queue.any((entry) {
      final map = entry as Map<String, dynamic>;
      return map['userId']?.toString() == currentId || map['userName'] == currentUser['name'];
    });
  }

  int get _queuePosition {
    final currentUser = ApiService.currentUser;
    if (currentUser == null || _room['queue'] == null) return -1;
    final queue = List<dynamic>.from(_room['queue'] as List<dynamic>);
    final currentId = currentUser['_id']?.toString() ?? currentUser['id']?.toString();
    for (var i = 0; i < queue.length; i++) {
      final map = queue[i] as Map<String, dynamic>;
      if (map['userId']?.toString() == currentId || map['userName'] == currentUser['name']) {
        return i + 1;
      }
    }
    return -1;
  }

  bool get _hasFemaleSpeaker => _room['femaleSpeaker'] != null;
  bool get _hasNormalSpeaker => _room['otherSpeaker'] != null;
  bool get _isPartner => ApiService.currentUser?['role'] == 'partner';
  bool get _isNormalUser => ApiService.currentUser?['role'] == 'user';

  bool get _canCallPartner => _isHost && _room['femaleSpeakerId'] != null;
  bool get _canCallHost => _isFemaleSpeaker && _room['hostId'] != null;
  bool get _canCallCoSpeaker => _isHost && _room['otherSpeakerId'] != null;

  Future<void> _refreshRoom() async {
    if (_room['_id'] == null && _room['id'] == null) return;
    final roomId = _room['_id']?.toString() ?? _room['id'].toString();
    try {
      final updated = await ApiService.getRoom(roomId);
      if (!mounted) return;
      setState(() {
        _room = updated;
      });
      _attemptAutoConnect();
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
        final message = role == 'coSpeaker' || role == 'normalSpeaker'
            ? (_hasNormalSpeaker ? 'Queued for the speaker seat' : 'Joined as normal speaker')
            : role == 'femaleSpeaker'
                ? 'Joined as female speaker'
                : 'Joined room successfully';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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

  Future<void> _leaveRoom() async {
    if (_room['_id'] == null && _room['id'] == null) return;
    final roomId = _room['_id']?.toString() ?? _room['id'].toString();
    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      await ApiService.leaveRoom(roomId: roomId);
      await _refreshRoom();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Left room successfully')));
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
  void dispose() {
    _roomUpdateSubscription?.cancel();
    _incomingCallSubscription?.cancel();
    if (_room['_id'] != null || _room['id'] != null) {
      final roomId = _room['_id']?.toString() ?? _room['id'].toString();
      SocketService.instance.unsubscribeRoom(roomId);
    }
    super.dispose();
  }

  void _subscribeToRoom() {
    final roomId = _room['_id']?.toString() ?? _room['id']?.toString();
    if (roomId == null || roomId.isEmpty) return;
    SocketService.instance.subscribeRoom(roomId);
    _roomUpdateSubscription = SocketService.instance.roomUpdateStream.listen(_handleRoomUpdated);
    _incomingCallSubscription = SocketService.instance.incomingCallStream.listen(_handleIncomingCall);
  }

  void _handleRoomUpdated(Map<String, dynamic> event) {
    final roomId = _room['_id']?.toString() ?? _room['id']?.toString();
    final updatedId = event['_id']?.toString() ?? event['id']?.toString();
    if (roomId != updatedId) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _room = event;
    });
    _attemptAutoConnect();
  }

  void _handleIncomingCall(Map<String, dynamic> event) {
    final callerId = event['callerId']?.toString();
    final callerName = event['callerName']?.toString() ?? 'Caller';
    if (callerId == null || _callInProgress) {
      return;
    }
    if (!_isInRoom(callerId)) {
      return;
    }
    if (!_isRoomParticipant) {
      return;
    }
    _acceptIncomingRoomCall(callerId, callerName);
  }

  Future<void> _acceptIncomingRoomCall(String callerId, String callerName) async {
    if (_callInProgress) return;
    setState(() {
      _callInProgress = true;
    });
    SocketService.instance.acceptCall(callerId);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CallScreen(
          partnerId: callerId,
          partnerName: callerName,
          isCaller: false,
        ),
      ),
    );
    if (!mounted) return;
    setState(() {
      _callInProgress = false;
    });
  }

  void _attemptAutoConnect() {
    if (_callInProgress) return;
    if (!_isRoomParticipant) return;

    if (_isHost) {
      final femaleSpeakerId = _room['femaleSpeakerId']?.toString();
      if (femaleSpeakerId != null && femaleSpeakerId.isNotEmpty) {
        _startRoomAudioCall(
          targetId: femaleSpeakerId,
          targetName: _room['femaleSpeaker'] as String? ?? 'Partner',
        );
        return;
      }
      final otherSpeakerId = _room['otherSpeakerId']?.toString();
      if (otherSpeakerId != null && otherSpeakerId.isNotEmpty) {
        _startRoomAudioCall(
          targetId: otherSpeakerId,
          targetName: _room['otherSpeaker'] as String? ?? 'Co-speaker',
        );
      }
      return;
    }

    final hostId = _room['hostId']?.toString();
    if (hostId != null && hostId.isNotEmpty) {
      _startRoomAudioCall(
        targetId: hostId,
        targetName: _room['hostName'] as String? ?? 'Host',
      );
    }
  }

  Future<void> _startRoomAudioCall({
    required String targetId,
    required String targetName,
  }) async {
    if (_callInProgress || !_isRoomParticipant) return;
    if (!SocketService.instance.isConnected) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Not connected to live service.')));
      return;
    }

    setState(() {
      _callInProgress = true;
      _isConnectingAudio = true;
    });

    SocketService.instance.callPartner(targetId);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CallScreen(
          partnerId: targetId,
          partnerName: targetName,
          isCaller: true,
        ),
      ),
    );

    if (!mounted) return;
    setState(() {
      _callInProgress = false;
      _isConnectingAudio = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final hostName = _room['hostName'] as String? ?? 'Host';
    final roomName = _room['name'] as String? ?? 'Live Room';
    final femaleSpeaker = _room['femaleSpeaker'] as String?;
    final otherSpeaker = _room['otherSpeaker'] as String?;
    final listeners = _room['listeners']?.toString() ?? '0';
    final queue = List<Map<String, dynamic>>.from(_room['queue'] as List<dynamic>? ?? []);

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
            Text('Room participants', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _ParticipantTile(label: 'Host', value: hostName, isActive: _isHost, icon: Icons.person),
                _ParticipantTile(label: 'Partner', value: femaleSpeaker ?? 'Open', isActive: _isFemaleSpeaker, icon: Icons.female),
                _ParticipantTile(label: 'Co-speaker', value: otherSpeaker ?? 'Open', isActive: _isNormalSpeaker, icon: Icons.mic),
              ],
            ),
            const SizedBox(height: 16),
            Text('Waiting list', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            if (queue.isEmpty)
              const Text('No users waiting to join yet.', style: TextStyle(color: Colors.white54))
            else
              Column(
                children: queue.map((entry) {
                  final name = entry['userName']?.toString() ?? 'Waiting user';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: const Color(0xFF3A2F6E),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            name.isNotEmpty ? name[0].toUpperCase() : '?',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Text(name, style: const TextStyle(color: Colors.white70))),
                      ],
                    ),
                  );
                }).toList(),
              ),
            const SizedBox(height: 16),
            if (_message != null) ...[
              Text(_message!, style: const TextStyle(color: Colors.redAccent)),
              const SizedBox(height: 12),
            ],
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else ...[
              ElevatedButton(
                onPressed: _isHost || _isFemaleSpeaker || _isNormalSpeaker ? null : () => _joinRoom('listener'),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF5E4FFF), padding: const EdgeInsets.symmetric(vertical: 16)),
                child: const Text('Join as Listener'),
              ),
              const SizedBox(height: 12),
              if (_isFemaleSpeaker)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text('You are the partner speaker in this room.', style: TextStyle(color: Colors.white70)),
              )
            else if (!_hasFemaleSpeaker && _isPartner && !_isHost)
                ElevatedButton(
                  onPressed: () => _joinRoom('femaleSpeaker'),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF5AA2), padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: const Text('Join as Partner Speaker'),
                ),
              if (_canCallPartner)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: ElevatedButton(
                    onPressed: _isConnectingAudio ? null : () => _startRoomAudioCall(
                      targetId: _room['femaleSpeakerId']?.toString() ?? '',
                      targetName: _room['femaleSpeaker'] as String? ?? 'Partner',
                    ),
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3AA047), padding: const EdgeInsets.symmetric(vertical: 16)),
                    child: Text(_isConnectingAudio ? 'Connecting audio...' : 'Start audio with partner'),
                  ),
                ),
              if (_canCallHost)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: ElevatedButton(
                    onPressed: _isConnectingAudio ? null : () => _startRoomAudioCall(
                      targetId: _room['hostId']?.toString() ?? '',
                      targetName: _room['hostName'] as String? ?? 'Host',
                    ),
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3AA047), padding: const EdgeInsets.symmetric(vertical: 16)),
                    child: Text(_isConnectingAudio ? 'Connecting audio...' : 'Call host for room audio'),
                  ),
                ),
              if (_canCallCoSpeaker)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: ElevatedButton(
                    onPressed: _isConnectingAudio ? null : () => _startRoomAudioCall(
                      targetId: _room['otherSpeakerId']?.toString() ?? '',
                      targetName: _room['otherSpeaker'] as String? ?? 'Co-speaker',
                    ),
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3AA047), padding: const EdgeInsets.symmetric(vertical: 16)),
                    child: Text(_isConnectingAudio ? 'Connecting audio...' : 'Call co-speaker'),
                  ),
                ),
              if (!_hasFemaleSpeaker && !_isPartner && !_isHost)
                const Text('Only partner female users can take the female speaker role.', style: TextStyle(color: Colors.white54)),
              const SizedBox(height: 12),
              if (!_hasNormalSpeaker && _isNormalUser && !_isHost)
                ElevatedButton(
                  onPressed: () => _joinRoom('coSpeaker'),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF8E44AD), padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: const Text('Take Speaker Seat'),
                ),
              if (_hasNormalSpeaker && _isNormalUser && !_isNormalSpeaker && !_isQueued)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: ElevatedButton(
                    onPressed: () => _joinRoom('coSpeaker'),
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF8E44AD), padding: const EdgeInsets.symmetric(vertical: 16)),
                    child: const Text('Queue for Speaker Seat'),
                  ),
                ),
              if (_isQueued)
                Text('You are queued for the speaker seat at position $_queuePosition.', style: const TextStyle(color: Colors.white70)),
              if (_isFemaleSpeaker || _isNormalSpeaker || _isQueued)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: ElevatedButton(
                    onPressed: _leaveRoom,
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFB03060), padding: const EdgeInsets.symmetric(vertical: 16)),
                    child: const Text('Leave Room / Leave Queue'),
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

class _ParticipantTile extends StatelessWidget {
  final String label;
  final String value;
  final bool isActive;
  final IconData icon;

  const _ParticipantTile({required this.label, required this.value, required this.isActive, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF2E5A34) : const Color(0xFF151A3C),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: isActive ? const Color(0xFF3AA047) : const Color(0xFF2A2F57)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Colors.white70, size: 18),
                const SizedBox(width: 8),
                Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 8),
            Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14), overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text(isActive ? 'You are here' : 'Status', style: const TextStyle(color: Color.fromRGBO(255, 255, 255, 0.65), fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
