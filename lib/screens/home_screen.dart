import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import 'audio_room_screen.dart';
import 'call_screen.dart';
import 'chat_room_screen.dart';
import 'gaming_room_screen.dart';
import 'login_screen.dart';
import 'gifting_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  List<Map<String, dynamic>> _liveUsers = [];
  bool _isLoadingLiveUsers = true;
  String? _liveUsersError;
  bool _isCallingPartner = false;

  static const List<String> _titles = <String>['Live Connect', 'Gaming', 'Chat', 'Gifts'];

  StreamSubscription<List<Map<String, dynamic>>>? _liveUsersSubscription;
  StreamSubscription<Map<String, dynamic>>? _callAcceptedSubscription;
  StreamSubscription<String>? _callFailedSubscription;

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
    if (index == 0) {
      _loadLiveUsers();
    }
  }

  Widget _activePage() {
    switch (_selectedIndex) {
      case 0:
        return const AudioRoomScreen(nested: true);
      case 1:
        return const GamingRoomScreen(nested: true);
      case 2:
        return const ChatRoomScreen(nested: true);
      case 3:
        return const GiftingScreen(nested: true);
      default:
        return const AudioRoomScreen(nested: true);
    }
  }

  @override
  void initState() {
    super.initState();
    _liveUsersSubscription = SocketService.instance.liveUsersStream.listen((users) {
      if (!mounted) return;
      setState(() {
        _liveUsers = users;
        _isLoadingLiveUsers = false;
        _liveUsersError = null;
      });
    });

    _callAcceptedSubscription = SocketService.instance.callAcceptedStream.listen((data) {
      // Only open CallScreen if HomeScreen is the active route (not when inside a room)
      if (_isCallingPartner || !mounted) return;
      final route = ModalRoute.of(context);
      if (route == null || !route.isCurrent) return;
      _isCallingPartner = true;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CallScreen(
            partnerId: data['partnerId'] as String? ?? '',
            partnerName: data['partnerName'] as String? ?? 'Partner',
            isCaller: true,
          ),
        ),
      ).then((_) {
        _isCallingPartner = false;
      });
    });

    _callFailedSubscription = SocketService.instance.callFailedStream.listen((reason) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(reason), backgroundColor: Colors.redAccent));
      _isCallingPartner = false;
    });

    _loadLiveUsers();
  }

  @override
  void dispose() {
    _liveUsersSubscription?.cancel();
    _callAcceptedSubscription?.cancel();
    _callFailedSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadLiveUsers() async {
    setState(() {
      _isLoadingLiveUsers = true;
      _liveUsersError = null;
    });

    if (SocketService.instance.isConnected) {
      SocketService.instance.requestLiveUsers();
      return;
    }

    try {
      final liveUsers = await ApiService.getLiveUsers();
      if (!mounted) return;
      setState(() {
        _liveUsers = liveUsers.map((user) => Map<String, dynamic>.from(user as Map<String, dynamic>)).toList();
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _liveUsersError = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingLiveUsers = false;
        });
      }
    }
  }

  void _callPartner(Map<String, dynamic> user) {
    if (!SocketService.instance.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Not connected to live service.')));
      return;
    }

    final partnerId = user['id']?.toString();
    final name = user['name']?.toString() ?? 'Partner';
    if (partnerId == null || partnerId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Unable to call partner')));
      return;
    }

    SocketService.instance.callPartner(partnerId);
    setState(() {
      _isCallingPartner = true;
    });

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CallScreen(partnerId: partnerId, partnerName: name, isCaller: true),
      ),
    ).then((_) {
      if (mounted) {
        setState(() {
          _isCallingPartner = false;
        });
      }
    });
  }

  Future<void> _logout() async {
    SocketService.instance.disconnect();
    ApiService.logout();
    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          _titles[_selectedIndex],
          style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            onPressed: _logout,
            icon: const Icon(Icons.logout, color: Colors.white),
            tooltip: 'Logout',
          ),
          Container(
            margin: const EdgeInsets.only(right: 16),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFFFF5AA2), Color(0xFF8E44AD)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(color: const Color.fromRGBO(0, 0, 0, 0.25), blurRadius: 18, offset: const Offset(0, 6)),
              ],
            ),
            child: const CircleAvatar(
              radius: 24,
              backgroundColor: Colors.transparent,
              child: Icon(Icons.person, color: Colors.white),
            ),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF090C24), Color(0xFF120531), Color(0xFF0A0418)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 160),
            child: Column(
              children: [
                if (_selectedIndex == 0) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 18),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: const Color(0xFF12173A),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: Colors.white10),
                        boxShadow: [
                          BoxShadow(color: const Color.fromRGBO(0, 0, 0, 0.28), blurRadius: 24, offset: const Offset(0, 16)),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Good evening', style: TextStyle(color: Colors.white70, fontSize: 16)),
                          const SizedBox(height: 6),
                          const Text('Welcome back to FRND', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 20),
                          Row(
                            children: const [
                              _QuickAction(icon: Icons.mic, label: 'Live'),
                              SizedBox(width: 12),
                              _QuickAction(icon: Icons.gamepad, label: 'Play'),
                              SizedBox(width: 12),
                              _QuickAction(icon: Icons.card_giftcard, label: 'Gifts'),
                            ],
                          ),
                          const SizedBox(height: 22),
                          Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF0E1131),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: Colors.white10),
                            ),
                            child: Row(
                              children: [
                                const Padding(
                                  padding: EdgeInsets.all(16.0),
                                  child: Icon(Icons.search, color: Colors.white54),
                                ),
                                Expanded(
                                  child: TextField(
                                    decoration: const InputDecoration(
                                      hintText: 'Search friends, rooms, gifts',
                                      hintStyle: TextStyle(color: Colors.white38),
                                      border: InputBorder.none,
                                    ),
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ),
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 16.0),
                                  child: Icon(Icons.tune, color: Colors.white54),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: const [
                        Text('Friend circles', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        Text('See all', style: TextStyle(color: Color(0xFFFF5AA2), fontSize: 14)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 140,
                    child: _isLoadingLiveUsers
                        ? const Center(child: CircularProgressIndicator())
                        : _liveUsersError != null
                            ? Center(child: Text(_liveUsersError!, style: const TextStyle(color: Colors.redAccent)))
                            : _liveUsers.isNotEmpty
                                ? ListView(
                                    scrollDirection: Axis.horizontal,
                                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                                    children: _liveUsers.map((user) {
                                      return GestureDetector(
                                        onTap: () => _callPartner(user),
                                        child: _FriendCard(
                                          name: user['name'] as String,
                                          status: 'Live',
                                          color: const Color(0xFF56CCF2),
                                          isOnline: user['isOnline'] == true,
                                        ),
                                      );
                                    }).toList(),
                                  )
                                : const Center(
                                    child: Text(
                                      'No live partners available right now.',
                                      style: TextStyle(color: Colors.white54),
                                    ),
                                  ),
                  ),
                  const SizedBox(height: 18),
                ],
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 24.0),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D1029),
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: _activePage(),
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: const Color(0xFF0D1030),
        selectedItemColor: const Color(0xFFFF5AA2),
        unselectedItemColor: Colors.white70,
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.mic), label: 'Live'),
          BottomNavigationBarItem(icon: Icon(Icons.videogame_asset), label: 'Gaming'),
          BottomNavigationBarItem(icon: Icon(Icons.chat), label: 'Chat'),
          BottomNavigationBarItem(icon: Icon(Icons.card_giftcard), label: 'Gifts'),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  const _QuickAction({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF141B45),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: const Color(0xFFFF5AA2), size: 24),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _FriendCard extends StatelessWidget {
  final String name;
  final String status;
  final Color color;
  final bool isOnline;

  const _FriendCard({required this.name, required this.status, required this.color, this.isOnline = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 140,
      margin: const EdgeInsets.only(right: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF141A3F),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: [color.withAlpha(242), color.withAlpha(115)]),
            ),
            child: Center(
              child: Text(name[0], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
            ),
          ),
          const SizedBox(height: 8),
          Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13), overflow: TextOverflow.ellipsis, maxLines: 1),
          const SizedBox(height: 6),
          Row(
            children: [
              if (isOnline)
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                  ),
                ),
              if (isOnline) const SizedBox(width: 6),
              Text(status, style: TextStyle(color: isOnline ? Colors.green.shade200 : Colors.white54, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }
}
