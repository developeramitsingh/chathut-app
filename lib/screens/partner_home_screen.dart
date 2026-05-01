import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import 'call_screen.dart';
import 'login_screen.dart';
import 'room_detail_screen.dart';

class PartnerHomeScreen extends StatefulWidget {
  const PartnerHomeScreen({super.key});

  @override
  State<PartnerHomeScreen> createState() => _PartnerHomeScreenState();
}

class _PartnerHomeScreenState extends State<PartnerHomeScreen> {
  StreamSubscription<Map<String, dynamic>>? _incomingCallSubscription;
  StreamSubscription<void>? _callEndedSubscription;
  bool _isOnCall = false;
  String? _incomingCallerName;
  String? _incomingCallerId;
  List<Map<String, dynamic>> _rooms = [];
  bool _roomsLoading = true;
  String? _roomsError;

  @override
  void initState() {
    super.initState();
    _incomingCallSubscription = SocketService.instance.incomingCallStream
        .listen((data) {
          // Don't intercept when inside a room — RoomDetailScreen handles this
          if (_isOnCall || !mounted) return;
          final route = ModalRoute.of(context);
          if (route == null || !route.isCurrent) return;
          setState(() {
            _incomingCallerName = data['callerName'] as String? ?? 'Caller';
            _incomingCallerId = data['callerId'] as String?;
          });
        });

    _callEndedSubscription = SocketService.instance.callEndedStream.listen((_) {
      if (_isOnCall) {
        if (!mounted) return;
        Navigator.of(context).maybePop();
        setState(() {
          _isOnCall = false;
          _incomingCallerName = null;
          _incomingCallerId = null;
        });
      }
    });

    _loadRooms();
  }

  @override
  void dispose() {
    _incomingCallSubscription?.cancel();
    _callEndedSubscription?.cancel();
    super.dispose();
  }

  Future<void> _acceptCall() async {
    if (_incomingCallerId == null) return;
    SocketService.instance.acceptCall(_incomingCallerId!);
    _openCallScreen(
      partnerId: _incomingCallerId!,
      partnerName: _incomingCallerName ?? 'Caller',
      isCaller: false,
    );
    setState(() {
      _incomingCallerName = null;
      _incomingCallerId = null;
      _isOnCall = true;
    });
  }

  Future<void> _rejectCall() async {
    if (_incomingCallerId == null) return;
    SocketService.instance.rejectCall(_incomingCallerId!);
    setState(() {
      _incomingCallerId = null;
      _incomingCallerName = null;
    });
  }

  Future<void> _loadRooms() async {
    setState(() {
      _roomsLoading = true;
      _roomsError = null;
    });

    try {
      final rooms = await ApiService.getRooms();
      if (!mounted) return;
      setState(() {
        _rooms = rooms
            .map(
              (room) => Map<String, dynamic>.from(room as Map<String, dynamic>),
            )
            .toList();
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _roomsError = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _roomsLoading = false;
        });
      }
    }
  }

  Future<void> _joinPartnerSeat(String roomId) async {
    try {
      await ApiService.requestJoinRoom(roomId: roomId, role: 'femaleSpeaker');
      await _loadRooms();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Join request sent to host')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _logout() async {
    SocketService.instance.disconnect();
    ApiService.logout();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
    );
  }

  void _openCallScreen({
    required String partnerId,
    required String partnerName,
    required bool isCaller,
  }) {
    if (!mounted) return;
    setState(() {
      _isOnCall = true;
    });
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CallScreen(
          partnerId: partnerId,
          partnerName: partnerName,
          isCaller: isCaller,
        ),
      ),
    ).then((_) {
      if (mounted) {
        setState(() {
          _isOnCall = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = ApiService.currentUser;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Partner Dashboard'),
        actions: [
          IconButton(onPressed: _logout, icon: const Icon(Icons.logout)),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Welcome, ${user?['name'] ?? 'Partner'}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'You are now available to accept incoming calls from users.',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 24),
            if (_incomingCallerName != null)
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1B3E),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0xFFFF5AA2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Incoming call',
                      style: TextStyle(color: Colors.white70, fontSize: 16),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _incomingCallerName ?? 'Caller',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _acceptCall,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFF5AA2),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            child: const Text('Accept Call'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _rejectCall,
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0xFFFF5AA2)),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            child: const Text(
                              'Reject',
                              style: TextStyle(color: Color(0xFFFF5AA2)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            if (_incomingCallerName == null)
              const Text(
                'Waiting for user calls…',
                style: TextStyle(color: Colors.white54, fontSize: 16),
              ),
            const SizedBox(height: 24),
            const Text(
              'Available Rooms',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            if (_roomsLoading)
              const Center(child: CircularProgressIndicator())
            else if (_roomsError != null)
              Text(
                _roomsError!,
                style: const TextStyle(color: Colors.redAccent),
              )
            else if (_rooms.isEmpty)
              const Text(
                'No active rooms at the moment.',
                style: TextStyle(color: Colors.white54),
              )
            else
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.only(top: 12),
                  itemCount: _rooms.length,
                  itemBuilder: (context, index) {
                    final room = _rooms[index];
                    final roomName = room['name'] as String? ?? 'Live Room';
                    final hostName = room['hostName'] as String? ?? 'Host';
                    final femaleSpeaker = room['femaleSpeaker'] as String?;
                    final otherSpeaker = room['otherSpeaker'] as String?;
                    final currentName = user?['name']?.toString() ?? '';
                    final isOwnPartnerSeat = femaleSpeaker == currentName;
                    final canJoinPartner = femaleSpeaker == null;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1B1A3D),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            roomName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Host: $hostName',
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Partner seat: ${femaleSpeaker ?? 'Open'}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            'Speaker seat: ${otherSpeaker ?? 'Open'}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: isOwnPartnerSeat || !canJoinPartner
                                      ? null
                                      : () => _joinPartnerSeat(
                                          room['_id']?.toString() ??
                                              room['id'].toString(),
                                        ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFFF5AA2),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                  ),
                                  child: Text(
                                    isOwnPartnerSeat
                                        ? 'You are partner'
                                        : (canJoinPartner
                                              ? 'Join as Partner'
                                              : 'Partner taken'),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            RoomDetailScreen(room: room),
                                      ),
                                    );
                                  },
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(
                                      color: Color(0xFFFF5AA2),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                  ),
                                  child: const Text(
                                    'View',
                                    style: TextStyle(color: Color(0xFFFF5AA2)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
