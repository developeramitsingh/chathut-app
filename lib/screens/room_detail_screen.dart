// ignore_for_file: avoid_print

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';

/// Maximum seconds a co-speaker can hold the seat before auto-rotation.
const int _kSeatSeconds = 300; // 5 minutes

class RoomDetailScreen extends StatefulWidget {
  final Map<String, dynamic> room;

  const RoomDetailScreen({super.key, required this.room});

  @override
  State<RoomDetailScreen> createState() => _RoomDetailScreenState();
}

class _RoomDetailScreenState extends State<RoomDetailScreen> {
  // ── Room state ────────────────────────────────────────────────────────────
  late Map<String, dynamic> _room;
  bool _isLoading = false;
  String? _message;

  // ── Socket subscriptions ──────────────────────────────────────────────────
  StreamSubscription<Map<String, dynamic>>? _roomUpdateSub;
  StreamSubscription<Map<String, dynamic>>? _incomingCallSub;
  StreamSubscription<Map<String, dynamic>>? _callAcceptedSub;
  StreamSubscription<Map<String, dynamic>>? _offerSub;
  StreamSubscription<Map<String, dynamic>>? _answerSub;
  StreamSubscription<Map<String, dynamic>>? _candidateSub;
  StreamSubscription<void>? _callEndedSub;

  // ── WebRTC ────────────────────────────────────────────────────────────────
  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  bool _audioConnected = false;
  bool _audioConnecting = false;
  bool _isCaller = false;
  bool _offerSent = false;
  bool _remoteDescSet = false;
  String? _connectedPartnerId;
  final List<RTCIceCandidate> _pendingCandidates = [];

  // ── Seat timer (co-speaker) ───────────────────────────────────────────────
  Timer? _seatTimer;
  int _seatSecondsLeft = _kSeatSeconds;
  String? _timedOtherSpeakerId;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _room = widget.room;
    _remoteRenderer.initialize();
    _subscribeSocket();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshRoom());
  }

  @override
  void dispose() {
    _seatTimer?.cancel();
    _roomUpdateSub?.cancel();
    _incomingCallSub?.cancel();
    _callAcceptedSub?.cancel();
    _offerSub?.cancel();
    _answerSub?.cancel();
    _candidateSub?.cancel();
    _callEndedSub?.cancel();
    final id = _roomId;
    if (id != null) SocketService.instance.unsubscribeRoom(id);
    _teardownAudio(notify: false);
    _remoteRenderer.dispose();
    super.dispose();
  }

  // ── Getters ───────────────────────────────────────────────────────────────

  String? get _roomId => _room['_id']?.toString() ?? _room['id']?.toString();
  Map<String, dynamic>? get _me => ApiService.currentUser;
  String? get _myId => _me?['_id']?.toString() ?? _me?['id']?.toString();

  bool get _isHost => _myId != null && _myId == _room['hostId']?.toString();
  bool get _isFemaleSpeaker => _myId != null && _myId == _room['femaleSpeakerId']?.toString();
  bool get _isNormalSpeaker => _myId != null && _myId == _room['otherSpeakerId']?.toString();
  bool get _isSpeaker => _isHost || _isFemaleSpeaker || _isNormalSpeaker;

  bool get _hasFemaleSpeaker {
    final id = _room['femaleSpeakerId']?.toString() ?? '';
    return id.isNotEmpty;
  }

  bool get _hasNormalSpeaker {
    final id = _room['otherSpeakerId']?.toString() ?? '';
    return id.isNotEmpty;
  }

  bool get _isPartner => _me?['role'] == 'partner';
  bool get _isNormalUser => _me?['role'] == 'user';

  bool get _isQueued {
    if (_me == null || _room['queue'] == null) return false;
    final q = List<dynamic>.from(_room['queue'] as List);
    return q.any((e) {
      final m = e as Map<String, dynamic>;
      return m['userId']?.toString() == _myId || m['userName'] == _me!['name'];
    });
  }

  int get _queuePosition {
    if (_me == null || _room['queue'] == null) return -1;
    final q = List<dynamic>.from(_room['queue'] as List);
    for (var i = 0; i < q.length; i++) {
      final m = q[i] as Map<String, dynamic>;
      if (m['userId']?.toString() == _myId || m['userName'] == _me!['name']) return i + 1;
    }
    return -1;
  }

  // ── Socket ────────────────────────────────────────────────────────────────

  void _subscribeSocket() {
    final id = _roomId;
    if (id == null || id.isEmpty) return;
    SocketService.instance.subscribeRoom(id);
    _roomUpdateSub = SocketService.instance.roomUpdateStream.listen(_onRoomUpdated);
    _incomingCallSub = SocketService.instance.incomingCallStream.listen(_onIncomingCall);
    _callAcceptedSub = SocketService.instance.callAcceptedStream.listen(_onCallAccepted);
    _offerSub = SocketService.instance.offerStream.listen(_onOffer);
    _answerSub = SocketService.instance.answerStream.listen(_onAnswer);
    _candidateSub = SocketService.instance.candidateStream.listen(_onCandidate);
    _callEndedSub = SocketService.instance.callEndedStream.listen((_) => _onCallEnded());
  }

  // ── Room data ─────────────────────────────────────────────────────────────

  Future<void> _refreshRoom() async {
    final id = _roomId;
    if (id == null) return;
    try {
      final updated = await ApiService.getRoom(id);
      if (!mounted) return;
      final prev = _room['otherSpeakerId']?.toString();
      setState(() => _room = updated);
      _checkSeatRotation(prev);
      _attemptAutoConnect();
    } catch (e) {
      if (mounted) setState(() => _message = e.toString());
    }
  }

  void _onRoomUpdated(Map<String, dynamic> event) {
    final updatedId = event['_id']?.toString() ?? event['id']?.toString();
    if (updatedId != _roomId || !mounted) return;
    final prev = _room['otherSpeakerId']?.toString();
    // Defer to next frame to avoid setState-during-build assertion
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _room = event);
      _checkSeatRotation(prev);
      _attemptAutoConnect();
    });
  }

  // ── Seat timer ────────────────────────────────────────────────────────────

  void _checkSeatRotation(String? prevOtherSpeakerId) {
    final currentOtherSpeakerId = _room['otherSpeakerId']?.toString();

    if (_isNormalSpeaker) {
      if (_timedOtherSpeakerId != _myId) {
        _timedOtherSpeakerId = _myId;
        _startSeatTimer();
      }
    } else {
      if (_timedOtherSpeakerId == _myId) {
        _seatTimer?.cancel();
        _timedOtherSpeakerId = null;
        if (mounted) setState(() => _seatSecondsLeft = _kSeatSeconds);
      }
      // Co-speaker changed → end stale audio so new person can connect
      if (currentOtherSpeakerId != null &&
          currentOtherSpeakerId.isNotEmpty &&
          currentOtherSpeakerId != prevOtherSpeakerId &&
          _connectedPartnerId == prevOtherSpeakerId) {
        _teardownAudio(notify: true);
      }
    }
  }

  void _startSeatTimer() {
    _seatTimer?.cancel();
    if (mounted) setState(() => _seatSecondsLeft = _kSeatSeconds);
    _seatTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _seatSecondsLeft--);
      if (_seatSecondsLeft <= 0) {
        t.cancel();
        _rotateSeat();
      }
    });
  }

  Future<void> _rotateSeat() async {
    if (_connectedPartnerId != null) SocketService.instance.endCall(_connectedPartnerId!);
    await _leaveRoom();
  }

  // ── Room join / leave ─────────────────────────────────────────────────────

  Future<void> _joinRoom(String role) async {
    final id = _roomId;
    if (id == null) return;
    setState(() { _isLoading = true; _message = null; });
    try {
      await ApiService.joinRoom(roomId: id, role: role);
      await _refreshRoom();
      if (mounted) {
        final msg = role == 'femaleSpeaker'
            ? 'Joined as partner speaker'
            : role == 'coSpeaker' || role == 'normalSpeaker'
                ? (_hasNormalSpeaker ? 'Added to queue' : 'Joined as co-speaker')
                : 'Joined as listener';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (mounted) setState(() => _message = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _leaveRoom() async {
    final id = _roomId;
    if (id == null) return;
    setState(() { _isLoading = true; _message = null; });
    _teardownAudio(notify: true);
    try {
      await ApiService.leaveRoom(roomId: id);
      await _refreshRoom();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Left room')));
      }
    } catch (e) {
      if (mounted) setState(() => _message = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── WebRTC: auto-connect ──────────────────────────────────────────────────

  /// Rule: co-speaker (joiner) always initiates → calls female speaker.
  /// Female speaker waits for incoming. Host stays as observer.
  void _attemptAutoConnect() {
    if (_audioConnected || _audioConnecting) return;
    if (_isNormalSpeaker && _hasFemaleSpeaker) {
      _initiateCall(
        targetId: _room['femaleSpeakerId']!.toString(),
        targetName: _room['femaleSpeaker'] as String? ?? 'Partner',
      );
    }
  }

  Future<void> _initiateCall({required String targetId, required String targetName}) async {
    if (_audioConnected || _audioConnecting) return;
    if (!SocketService.instance.isConnected) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Not connected to live service.')),
        );
      }
      return;
    }
    print('[LiveRoom] initiating call → $targetId');
    if (!mounted) return;
    setState(() { _audioConnecting = true; _isCaller = true; _connectedPartnerId = targetId; });
    await _setupPeerConnection();
    if (!mounted) return;
    SocketService.instance.callPartner(targetId);
    // Drain cached callAccepted
    final cached = SocketService.instance.getLastCallAccepted(targetId);
    if (cached != null && !_offerSent) {
      SocketService.instance.clearLastCallAccepted();
      await _sendOffer();
    }
  }

  // ── WebRTC: signaling ─────────────────────────────────────────────────────

  void _onIncomingCall(Map<String, dynamic> event) async {
    final callerId = event['callerId']?.toString();
    final callerName = event['callerName']?.toString() ?? 'Caller';
    if (callerId == null || _audioConnected || _audioConnecting) return;
    // Only female speaker auto-accepts (co-speaker is the one calling)
    if (!_isFemaleSpeaker && !_isHost) return;
    print('[LiveRoom] auto-accepting from $callerId ($callerName)');
    if (!mounted) return;
    setState(() { _audioConnecting = true; _isCaller = false; _connectedPartnerId = callerId; });
    SocketService.instance.acceptCall(callerId);
    await _setupPeerConnection();
    if (!mounted) return;
    // Drain cached offer
    final cached = SocketService.instance.getLastOffer(callerId);
    if (cached != null) {
      SocketService.instance.clearLastOffer(callerId);
      await _handleOffer(cached);
    }
  }

  void _onCallAccepted(Map<String, dynamic> event) async {
    if (!_isCaller) return;
    final acceptedBy = event['partnerId']?.toString();
    if (acceptedBy != _connectedPartnerId) return;
    print('[LiveRoom] callAccepted by $acceptedBy');
    SocketService.instance.clearLastCallAccepted();
    if (!mounted) return;
    await _sendOffer();
  }

  void _onOffer(Map<String, dynamic> data) async {
    final fromId = data['from']?.toString();
    if (_isCaller || fromId != _connectedPartnerId) return;
    print('[LiveRoom] offer from $fromId');
    await _handleOffer(data);
    SocketService.instance.clearLastOffer(fromId ?? '');
  }

  void _onAnswer(Map<String, dynamic> data) async {
    if (!_isCaller) return;
    await _handleAnswer(data);
  }

  void _onCandidate(Map<String, dynamic> data) async {
    await _handleCandidate(data);
  }

  void _onCallEnded() {
    print('[LiveRoom] callEnded');
    _teardownAudio(notify: false);
  }

  // ── WebRTC: peer connection ───────────────────────────────────────────────

  Future<void> _setupPeerConnection() async {
    if (_pc != null) return;
    final config = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
      ],
      'sdpSemantics': 'unified-plan',
    };
    _localStream = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': false});
    _pc = await createPeerConnection(config);
    for (final track in _localStream!.getTracks()) {
      await _pc!.addTrack(track, _localStream!);
    }
    _pc!.onIceCandidate = (c) {
      if (c.candidate == null || c.candidate!.isEmpty || _connectedPartnerId == null) return;
      SocketService.instance.sendCandidate(_connectedPartnerId!, {
        'candidate': c.candidate,
        'sdpMid': c.sdpMid,
        'sdpMLineIndex': c.sdpMLineIndex,
      });
    };
    _pc!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _remoteRenderer.srcObject = event.streams[0];
        if (mounted) setState(() { _audioConnected = true; _audioConnecting = false; });
      }
    };
    _pc!.onConnectionState = (state) {
      if (!mounted) return;
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        setState(() { _audioConnected = true; _audioConnecting = false; });
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        _teardownAudio(notify: false);
      }
    };
    _pc!.onIceConnectionState = (state) {
      if (!mounted) return;
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        setState(() { _audioConnected = true; _audioConnecting = false; });
      }
    };
  }

  Future<void> _sendOffer() async {
    if (_offerSent || _pc == null) return;
    _offerSent = true;
    final offer = await _pc!.createOffer({'offerToReceiveAudio': true});
    await _pc!.setLocalDescription(offer);
    SocketService.instance.sendOffer(_connectedPartnerId!, offer.toMap());
  }

  Future<void> _handleOffer(Map<String, dynamic> data) async {
    if (_pc == null) return;
    final offerMap = data['offer'] as Map<String, dynamic>?;
    if (offerMap == null) return;
    await _pc!.setRemoteDescription(
      RTCSessionDescription(offerMap['sdp'] as String, offerMap['type'] as String),
    );
    _remoteDescSet = true;
    await _flushPendingCandidates();
    final answer = await _pc!.createAnswer();
    await _pc!.setLocalDescription(answer);
    SocketService.instance.sendAnswer(data['from']?.toString() ?? _connectedPartnerId!, answer.toMap());
    if (mounted) setState(() { _audioConnected = true; _audioConnecting = false; });
  }

  Future<void> _handleAnswer(Map<String, dynamic> data) async {
    if (_pc == null) return;
    final answerMap = data['answer'] as Map<String, dynamic>?;
    if (answerMap == null) return;
    await _pc!.setRemoteDescription(
      RTCSessionDescription(answerMap['sdp'] as String, answerMap['type'] as String),
    );
    _remoteDescSet = true;
    await _flushPendingCandidates();
    if (mounted) setState(() { _audioConnected = true; _audioConnecting = false; });
  }

  Future<void> _handleCandidate(Map<String, dynamic> data) async {
    final raw = data['candidate'];
    String? candidateStr;
    String? sdpMid;
    int? sdpMLineIndex;
    if (raw is Map) {
      candidateStr = raw['candidate']?.toString();
      sdpMid = raw['sdpMid']?.toString();
      final idx = raw['sdpMLineIndex'];
      sdpMLineIndex = idx is int ? idx : int.tryParse(idx?.toString() ?? '');
    } else if (raw is String) {
      candidateStr = raw;
    }
    if (candidateStr == null || candidateStr.isEmpty) return;
    final candidate = RTCIceCandidate(candidateStr, sdpMid, sdpMLineIndex);
    if (!_remoteDescSet || _pc == null) {
      _pendingCandidates.add(candidate);
      return;
    }
    await _pc!.addCandidate(candidate);
  }

  Future<void> _flushPendingCandidates() async {
    if (_pc == null || _pendingCandidates.isEmpty) return;
    for (final c in List<RTCIceCandidate>.from(_pendingCandidates)) {
      await _pc!.addCandidate(c);
    }
    _pendingCandidates.clear();
  }

  void _teardownAudio({required bool notify}) {
    if (notify && _connectedPartnerId != null) {
      SocketService.instance.endCall(_connectedPartnerId!);
    }
    _localStream?.dispose();
    _localStream = null;
    _remoteRenderer.srcObject = null;
    _pc?.close();
    _pc = null;
    _offerSent = false;
    _remoteDescSet = false;
    _pendingCandidates.clear();
    final prev = _connectedPartnerId;
    _connectedPartnerId = null;
    if (prev != null) {
      SocketService.instance.clearLastOffer(prev);
      SocketService.instance.clearLastCallAccepted();
    }
    if (mounted) setState(() { _audioConnected = false; _audioConnecting = false; _isCaller = false; });
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final roomName = _room['name'] as String? ?? 'Live Room';
    final hostName = _room['hostName'] as String? ?? 'Host';
    final femaleSpeakerName = _room['femaleSpeaker'] as String?;
    final otherSpeakerName = _room['otherSpeaker'] as String?;
    final queue = List<Map<String, dynamic>>.from(_room['queue'] as List<dynamic>? ?? []);

    final audioStatus = _audioConnected
        ? _AudioStatus.live
        : _audioConnecting
            ? _AudioStatus.connecting
            : _AudioStatus.idle;

    return Scaffold(
      backgroundColor: const Color(0xFF0D1030),
      appBar: AppBar(
        backgroundColor: const Color(0xFF10133D),
        title: Row(
          children: [
            Expanded(
              child: Text(roomName,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
            if (_audioConnected)
              _LiveBadge(label: 'LIVE', color: const Color(0xFF3AA047), icon: Icons.graphic_eq)
            else if (_audioConnecting)
              _LiveBadge(label: 'Connecting…', color: const Color(0xFF9C4FFF), icon: Icons.hourglass_top),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [

            // ── HOST ──────────────────────────────────────────────────────
            _SpeakerTile(
              label: 'HOST',
              name: hostName,
              isMe: _isHost,
              accent: const Color(0xFFFF5AA2),
              icon: Icons.person,
              audioStatus: null, // host is observer, no audio indicator
            ),

            const SizedBox(height: 20),

            // ── PARTNER (left) │ JOINER (right) ───────────────────────────
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _SpeakerTile(
                      label: 'PARTNER',
                      name: femaleSpeakerName ?? 'Open',
                      isMe: _isFemaleSpeaker,
                      accent: const Color(0xFFFF5AA2),
                      icon: Icons.female,
                      audioStatus: femaleSpeakerName != null ? audioStatus : null,
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Arrows between them
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.sync_alt,
                          color: _audioConnected
                              ? const Color(0xFF3AA047)
                              : _audioConnecting
                                  ? const Color(0xFF9C4FFF)
                                  : Colors.white12,
                          size: 24,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _audioConnected
                              ? 'audio\nlive'
                              : _audioConnecting
                                  ? 'linking…'
                                  : 'audio',
                          style: TextStyle(
                            color: _audioConnected
                                ? const Color(0xFF3AA047)
                                : _audioConnecting
                                    ? const Color(0xFF9C4FFF)
                                    : Colors.white12,
                            fontSize: 9,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 12),
                  Expanded(
                    child: _SpeakerTile(
                      label: 'JOINER',
                      name: otherSpeakerName ?? 'Open',
                      isMe: _isNormalSpeaker,
                      accent: const Color(0xFF5E4FFF),
                      icon: Icons.mic,
                      audioStatus: otherSpeakerName != null ? audioStatus : null,
                    ),
                  ),
                ],
              ),
            ),

            // Hidden WebRTC audio renderer
            SizedBox(width: 1, height: 1, child: RTCVideoView(_remoteRenderer)),

            // ── CO-SPEAKER seat timer ──────────────────────────────────────
            if (_isNormalSpeaker) ...[
              const SizedBox(height: 16),
              _SeatTimerBar(secondsLeft: _seatSecondsLeft, total: _kSeatSeconds),
            ],

            const SizedBox(height: 20),

            // ── QUEUE ──────────────────────────────────────────────────────
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Waiting queue (${queue.length})',
                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 10),
            if (queue.isEmpty)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF151A3C),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Center(
                  child: Text('No one waiting', style: TextStyle(color: Colors.white54)),
                ),
              )
            else
              ...queue.asMap().entries.map((entry) {
                final idx = entry.key;
                final e = entry.value;
                final name = e['userName']?.toString() ?? '?';
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF151A3C),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF2A2F57)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 32, height: 32,
                        decoration: BoxDecoration(
                          color: const Color(0xFF3A2F6E),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '${idx + 1}',
                          style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Text(name, style: const TextStyle(color: Colors.white))),
                      Text('~${(idx + 1) * 5} min', style: const TextStyle(color: Colors.white38, fontSize: 12)),
                    ],
                  ),
                );
              }),

            const SizedBox(height: 20),

            // ── MESSAGES ──────────────────────────────────────────────────
            if (_message != null) ...[
              Text(_message!, style: const TextStyle(color: Colors.redAccent)),
              const SizedBox(height: 12),
            ],

            // ── ACTION BUTTONS ────────────────────────────────────────────
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else
              _buildActions(),

            const SizedBox(height: 12),
            TextButton(
              onPressed: _refreshRoom,
              child: const Text('Refresh', style: TextStyle(color: Colors.white38)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Listener join
        if (!_isSpeaker && !_isQueued)
          ElevatedButton.icon(
            onPressed: () => _joinRoom('listener'),
            icon: const Icon(Icons.headphones),
            label: const Text('Join as Listener'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF5E4FFF),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),

        // Partner speaker join
        if (!_hasFemaleSpeaker && _isPartner && !_isHost && !_isFemaleSpeaker) ...[
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed: () => _joinRoom('femaleSpeaker'),
            icon: const Icon(Icons.female),
            label: const Text('Join as Partner Speaker'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF5AA2),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],

        // Co-speaker / queue
        if (_isNormalUser && !_isHost && !_isNormalSpeaker && !_isQueued) ...[
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed: () => _joinRoom('coSpeaker'),
            icon: Icon(_hasNormalSpeaker ? Icons.queue : Icons.mic),
            label: Text(_hasNormalSpeaker ? 'Queue for Speaker Seat' : 'Take Speaker Seat'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8E44AD),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],

        // Queue info
        if (_isQueued) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1A40),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF8E44AD)),
            ),
            child: Row(
              children: [
                const Icon(Icons.schedule, color: Color(0xFF8E44AD)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Queue position #$_queuePosition  (~${_queuePosition * 5} min wait)',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
              ],
            ),
          ),
        ],

        // Female speaker status
        if (_isFemaleSpeaker) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF2B1530),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFF5AA2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.female, color: Color(0xFFFF5AA2)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _audioConnected
                        ? 'Audio live with joiner'
                        : _audioConnecting
                            ? 'Joiner is connecting…'
                            : 'You are the partner — waiting for a joiner',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
              ],
            ),
          ),
        ],

        // Leave
        if (_isFemaleSpeaker || _isNormalSpeaker || _isQueued) ...[
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _leaveRoom,
            icon: const Icon(Icons.exit_to_app),
            label: const Text('Leave Room / Queue'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFB03060),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      ],
    );
  }
}

// ── Supporting widgets ─────────────────────────────────────────────────────────

enum _AudioStatus { idle, connecting, live }

class _LiveBadge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  const _LiveBadge({required this.label, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 13),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _SpeakerTile extends StatelessWidget {
  final String label;
  final String name;
  final bool isMe;
  final Color accent;
  final IconData icon;
  final _AudioStatus? audioStatus;

  const _SpeakerTile({
    required this.label,
    required this.name,
    required this.isMe,
    required this.accent,
    required this.icon,
    this.audioStatus,
  });

  @override
  Widget build(BuildContext context) {
    final isEmpty = name == 'Open';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isMe ? const Color(0xFF1E2A50) : const Color(0xFF151A3C),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isMe ? accent : const Color(0xFF2A2F57), width: isMe ? 2 : 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            alignment: Alignment.bottomRight,
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: isEmpty ? const Color(0xFF2A2F57) : accent.withOpacity(0.25),
                child: Icon(icon, color: isEmpty ? Colors.white24 : accent, size: 28),
              ),
              if (audioStatus == _AudioStatus.live)
                Container(
                  width: 16, height: 16,
                  decoration: const BoxDecoration(color: Color(0xFF3AA047), shape: BoxShape.circle),
                  child: const Icon(Icons.graphic_eq, size: 10, color: Colors.white),
                )
              else if (audioStatus == _AudioStatus.connecting)
                Container(
                  width: 16, height: 16,
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(color: Color(0xFF9C4FFF), shape: BoxShape.circle),
                  child: const CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(color: accent, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2),
          ),
          const SizedBox(height: 2),
          Text(
            isEmpty ? 'Open' : name,
            style: TextStyle(
              color: isEmpty ? Colors.white30 : Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
          ),
          if (isMe) ...[
            const SizedBox(height: 4),
            Text('(You)', style: TextStyle(color: accent, fontSize: 11)),
          ],
        ],
      ),
    );
  }
}

class _SeatTimerBar extends StatelessWidget {
  final int secondsLeft;
  final int total;
  const _SeatTimerBar({required this.secondsLeft, required this.total});

  @override
  Widget build(BuildContext context) {
    final fraction = secondsLeft / total;
    final m = (secondsLeft ~/ 60).toString().padLeft(2, '0');
    final s = (secondsLeft % 60).toString().padLeft(2, '0');
    final urgent = secondsLeft <= 60;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: urgent ? const Color(0xFF3B1010) : const Color(0xFF151A3C),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: urgent ? Colors.redAccent : const Color(0xFF5E4FFF)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(children: [
                Icon(Icons.timer, color: urgent ? Colors.redAccent : const Color(0xFF5E4FFF), size: 18),
                const SizedBox(width: 8),
                Text('Your seat time',
                    style: TextStyle(color: urgent ? Colors.redAccent : Colors.white70, fontSize: 13)),
              ]),
              Text(
                '$m:$s',
                style: TextStyle(
                  color: urgent ? Colors.redAccent : Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 6,
              backgroundColor: const Color(0xFF2A2F57),
              valueColor: AlwaysStoppedAnimation<Color>(
                urgent ? Colors.redAccent : const Color(0xFF5E4FFF),
              ),
            ),
          ),
          if (urgent) ...[
            const SizedBox(height: 6),
            const Text(
              'Almost up! Next person in queue will join soon.',
              style: TextStyle(color: Colors.redAccent, fontSize: 11),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}
