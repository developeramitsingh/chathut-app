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
  int _walletBalance = 0;
  int _totalEarnings = 0;
  int _lastCallMinutes = 0;
  int _lastCallChargedCoins = 0;
  int _lastCallEarnedCoins = 0;
  bool _hasLastCallSummary = false;
  StreamSubscription<Map<String, dynamic>>? _callCoinsSettledSubscription;
  StreamSubscription<Map<String, dynamic>>? _callEarningsCreditedSubscription;

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
      _loadWalletSummary();
    });

      _callCoinsSettledSubscription = SocketService.instance.callCoinsSettledStream
        .listen((event) {
          final minutesRaw = event['minutes'];
          final chargedRaw = event['chargedCoins'];
          final walletRaw = event['walletBalance'];
          if (!mounted) return;
          setState(() {
          _lastCallMinutes = minutesRaw is int
            ? minutesRaw
            : int.tryParse(minutesRaw?.toString() ?? '0') ?? 0;
          _lastCallChargedCoins = chargedRaw is int
            ? chargedRaw
            : int.tryParse(chargedRaw?.toString() ?? '0') ?? 0;
          _lastCallEarnedCoins = 0;
          _walletBalance = walletRaw is int
            ? walletRaw
            : int.tryParse(walletRaw?.toString() ?? '0') ?? _walletBalance;
          _hasLastCallSummary = true;
          });
        });

      _callEarningsCreditedSubscription = SocketService
        .instance
        .callEarningsCreditedStream
        .listen((event) {
          final minutesRaw = event['minutes'];
          final earnedRaw = event['creditedCoins'];
          final walletRaw = event['walletBalance'];
          if (!mounted) return;
          setState(() {
          _lastCallMinutes = minutesRaw is int
            ? minutesRaw
            : int.tryParse(minutesRaw?.toString() ?? '0') ?? 0;
          _lastCallEarnedCoins = earnedRaw is int
            ? earnedRaw
            : int.tryParse(earnedRaw?.toString() ?? '0') ?? 0;
          _lastCallChargedCoins = 0;
          _walletBalance = walletRaw is int
            ? walletRaw
            : int.tryParse(walletRaw?.toString() ?? '0') ?? _walletBalance;
          _hasLastCallSummary = true;
          });
        });

      final cachedEarned = SocketService.instance.getLastCallEarningsCredited();
      if (cachedEarned != null) {
        final minutesRaw = cachedEarned['minutes'];
        final earnedRaw = cachedEarned['creditedCoins'];
        final walletRaw = cachedEarned['walletBalance'];
        _lastCallMinutes = minutesRaw is int
          ? minutesRaw
          : int.tryParse(minutesRaw?.toString() ?? '0') ?? 0;
        _lastCallEarnedCoins = earnedRaw is int
          ? earnedRaw
          : int.tryParse(earnedRaw?.toString() ?? '0') ?? 0;
        _lastCallChargedCoins = 0;
        _walletBalance = walletRaw is int
          ? walletRaw
          : int.tryParse(walletRaw?.toString() ?? '0') ?? _walletBalance;
        _hasLastCallSummary = true;
      }

      final cachedCharged = SocketService.instance.getLastCallCoinsSettled();
      if (cachedCharged != null && !_hasLastCallSummary) {
        final minutesRaw = cachedCharged['minutes'];
        final chargedRaw = cachedCharged['chargedCoins'];
        final walletRaw = cachedCharged['walletBalance'];
        _lastCallMinutes = minutesRaw is int
          ? minutesRaw
          : int.tryParse(minutesRaw?.toString() ?? '0') ?? 0;
        _lastCallChargedCoins = chargedRaw is int
          ? chargedRaw
          : int.tryParse(chargedRaw?.toString() ?? '0') ?? 0;
        _lastCallEarnedCoins = 0;
        _walletBalance = walletRaw is int
          ? walletRaw
          : int.tryParse(walletRaw?.toString() ?? '0') ?? _walletBalance;
        _hasLastCallSummary = true;
      }

    _loadRooms();
    _loadWalletSummary();
  }

  @override
  void dispose() {
    _incomingCallSubscription?.cancel();
    _callEndedSubscription?.cancel();
    _callCoinsSettledSubscription?.cancel();
    _callEarningsCreditedSubscription?.cancel();
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

  Future<void> _loadWalletSummary() async {
    try {
      final summary = await ApiService.getWalletSummary();
      if (!mounted) return;
      setState(() {
        _walletBalance = summary['walletBalance'] ?? 0;
        _totalEarnings = summary['totalEarnings'] ?? 0;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _walletBalance = ApiService.currentUser?['walletBalance'] is int
            ? ApiService.currentUser!['walletBalance'] as int
            : int.tryParse(
                    ApiService.currentUser?['walletBalance']?.toString() ?? '0',
                  ) ??
                  0;
        _totalEarnings = ApiService.currentUser?['totalEarnings'] is int
            ? ApiService.currentUser!['totalEarnings'] as int
            : int.tryParse(
                    ApiService.currentUser?['totalEarnings']?.toString() ?? '0',
                  ) ??
                  0;
      });
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
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1E45),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.account_balance_wallet,
                    color: Colors.amberAccent,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Wallet: $_walletBalance coins',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    'Earnings: $_totalEarnings',
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            if (_hasLastCallSummary) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF161A3F),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Last call: $_lastCallMinutes min',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Charged: $_lastCallChargedCoins',
                      style: const TextStyle(
                        color: Colors.orangeAccent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Earned: $_lastCallEarnedCoins',
                      style: const TextStyle(
                        color: Colors.greenAccent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
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
