import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import 'call_screen.dart';
import 'login_screen.dart';

class PartnerHomeScreen extends StatefulWidget {
  const PartnerHomeScreen({super.key});

  @override
  State<PartnerHomeScreen> createState() => _PartnerHomeScreenState();
}

class _PartnerHomeScreenState extends State<PartnerHomeScreen> {
  StreamSubscription<Map<String, dynamic>>? _incomingCallSubscription;
  StreamSubscription<Map<String, dynamic>>? _callAcceptedSubscription;
  StreamSubscription<void>? _callEndedSubscription;
  bool _isOnCall = false;
  String? _incomingCallerName;
  String? _incomingCallerId;

  @override
  void initState() {
    super.initState();
    _incomingCallSubscription = SocketService.instance.incomingCallStream.listen((data) {
      if (_isOnCall) return;
      setState(() {
        _incomingCallerName = data['callerName'] as String? ?? 'Caller';
        _incomingCallerId = data['callerId'] as String?;
      });
    });

    _callAcceptedSubscription = SocketService.instance.callAcceptedStream.listen((data) {
      if (_isOnCall) return;
      final partnerId = data['callerId'] as String? ?? '';
      final partnerName = data['callerName'] as String? ?? 'Caller';
      if (!mounted) return;
      _openCallScreen(partnerId: partnerId, partnerName: partnerName, isCaller: false);
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
  }

  @override
  void dispose() {
    _incomingCallSubscription?.cancel();
    _callAcceptedSubscription?.cancel();
    _callEndedSubscription?.cancel();
    super.dispose();
  }

  Future<void> _acceptCall() async {
    if (_incomingCallerId == null) return;
    SocketService.instance.acceptCall(_incomingCallerId!);
    _openCallScreen(partnerId: _incomingCallerId!, partnerName: _incomingCallerName ?? 'Caller', isCaller: false);
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

  Future<void> _logout() async {
    SocketService.instance.disconnect();
    ApiService.logout();
    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginScreen()));
  }

  void _openCallScreen({required String partnerId, required String partnerName, required bool isCaller}) {
    if (!mounted) return;
    setState(() {
      _isOnCall = true;
    });
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CallScreen(partnerId: partnerId, partnerName: partnerName, isCaller: isCaller),
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
          IconButton(
            onPressed: _logout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Welcome, ${user?['name'] ?? 'Partner'}', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            const Text('You are now available to accept incoming calls from users.', style: TextStyle(color: Colors.white70, fontSize: 16)),
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
                    const Text('Incoming call', style: TextStyle(color: Colors.white70, fontSize: 16)),
                    const SizedBox(height: 12),
                    Text(_incomingCallerName ?? 'Caller', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _acceptCall,
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF5AA2), padding: const EdgeInsets.symmetric(vertical: 16)),
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
                            child: const Text('Reject', style: TextStyle(color: Color(0xFFFF5AA2))),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            if (_incomingCallerName == null)
              const Text('Waiting for user calls…', style: TextStyle(color: Colors.white54, fontSize: 16)),
          ],
        ),
      ),
    );
  }
}
