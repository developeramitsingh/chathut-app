// ignore_for_file: avoid_print

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';

/// Maximum seconds a co-speaker can hold the seat before auto-rotation.
const int _kSeatSeconds = 60; // 1 minute

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
  MediaStream? _localStream;
  final Map<String, RTCPeerConnection> _peerConnections = {};
  final Map<String, RTCVideoRenderer> _remoteRenderers = {};
  final Set<String> _connectingPeerIds = <String>{};
  final Set<String> _connectedPeerIds = <String>{};
  final Map<String, bool> _offerSentByPeer = {};
  final Map<String, bool> _remoteDescSetByPeer = {};
  final Map<String, bool> _remoteAnswerSetByPeer = {};
  final Map<String, List<RTCIceCandidate>> _pendingCandidatesByPeer = {};
  bool _audioConnected = false;
  bool _audioConnecting = false;
  Timer? _autoConnectRetryTimer;

  // ── Seat timer (co-speaker) ───────────────────────────────────────────────
  Timer? _seatTimer;
  int _seatSecondsLeft = _kSeatSeconds;
  String? _timedOtherSpeakerId;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _room = widget.room;
    _subscribeSocket();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshRoom());
  }

  @override
  void dispose() {
    _seatTimer?.cancel();
    _autoConnectRetryTimer?.cancel();
    _roomUpdateSub?.cancel();
    _incomingCallSub?.cancel();
    _callAcceptedSub?.cancel();
    _offerSub?.cancel();
    _answerSub?.cancel();
    _candidateSub?.cancel();
    _callEndedSub?.cancel();
    final id = _roomId;
    if (id != null) SocketService.instance.unsubscribeRoom(id);
    _teardownAudio(notify: false, updateUi: false);
    super.dispose();
  }

  // ── Getters ───────────────────────────────────────────────────────────────

  String? get _roomId => _room['_id']?.toString() ?? _room['id']?.toString();
  Map<String, dynamic>? get _me => ApiService.currentUser;
  String? get _myId => _me?['_id']?.toString() ?? _me?['id']?.toString();

  bool get _isHost => _myId != null && _myId == _room['hostId']?.toString();
  bool get _isFemaleSpeaker =>
      _myId != null && _myId == _room['femaleSpeakerId']?.toString();
  bool get _isNormalSpeaker =>
      _myId != null && _myId == _room['otherSpeakerId']?.toString();
  bool get _canBroadcastAudio =>
      _isHost || _isFemaleSpeaker || _isNormalSpeaker;
  bool get _isRoomActiveParticipant =>
      _canBroadcastAudio || _isQueued || _isListenerParticipant;

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

  List<Map<String, dynamic>> get _joinRequests =>
      List<Map<String, dynamic>>.from(
        _room['joinRequests'] as List<dynamic>? ?? [],
      );

  List<Map<String, dynamic>> get _participants =>
      List<Map<String, dynamic>>.from(
        _room['participants'] as List<dynamic>? ?? [],
      );

  bool get _isQueued {
    if (_me == null || _room['queue'] == null) return false;
    final q = List<dynamic>.from(_room['queue'] as List);
    return q.any((e) {
      final m = e as Map<String, dynamic>;
      return m['userId']?.toString() == _myId || m['userName'] == _me!['name'];
    });
  }

  bool get _hasPendingRequest {
    if (_myId == null) return false;
    return _joinRequests.any((entry) => entry['userId']?.toString() == _myId);
  }

  bool get _isListenerParticipant {
    if (_myId == null) return false;
    return _participants.any(
      (entry) =>
          entry['userId']?.toString() == _myId &&
          entry['role']?.toString() == 'listener',
    );
  }

  int get _queuePosition {
    if (_me == null || _room['queue'] == null) return -1;
    final q = List<dynamic>.from(_room['queue'] as List);
    for (var i = 0; i < q.length; i++) {
      final m = q[i] as Map<String, dynamic>;
      if (m['userId']?.toString() == _myId || m['userName'] == _me!['name'])
        return i + 1;
    }
    return -1;
  }

  // ── Socket ────────────────────────────────────────────────────────────────

  void _subscribeSocket() {
    final id = _roomId;
    if (id == null || id.isEmpty) return;
    SocketService.instance.subscribeRoom(id);
    _roomUpdateSub = SocketService.instance.roomUpdateStream.listen(
      _onRoomUpdated,
    );
    _incomingCallSub = SocketService.instance.incomingCallStream.listen(
      _onIncomingCall,
    );
    _callAcceptedSub = SocketService.instance.callAcceptedStream.listen(
      _onCallAccepted,
    );
    _offerSub = SocketService.instance.offerStream.listen(_onOffer);
    _answerSub = SocketService.instance.answerStream.listen(_onAnswer);
    _candidateSub = SocketService.instance.candidateStream.listen(_onCandidate);
    _callEndedSub = SocketService.instance.callEndedStream.listen(
      (_) => _onCallEnded(),
    );
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
      _syncLocalAudioTrackState();
      _syncRoomAudioMesh();
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
      _syncLocalAudioTrackState();
      _syncRoomAudioMesh();
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
          prevOtherSpeakerId != null &&
          prevOtherSpeakerId.isNotEmpty) {
        unawaited(_closePeerConnection(prevOtherSpeakerId, notify: false));
      }
    }
  }

  void _startSeatTimer() {
    _seatTimer?.cancel();
    if (mounted) setState(() => _seatSecondsLeft = _kSeatSeconds);
    _seatTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _seatSecondsLeft--);
      if (_seatSecondsLeft <= 0) {
        t.cancel();
        _rotateSeat();
      }
    });
  }

  Future<void> _rotateSeat() async {
    await _leaveRoom();
  }

  // ── Room join / leave ─────────────────────────────────────────────────────

  Future<void> _joinRoom(String role) async {
    final id = _roomId;
    if (id == null) return;
    setState(() {
      _isLoading = true;
      _message = null;
    });
    try {
      await ApiService.requestJoinRoom(roomId: id, role: role);
      await _refreshRoom();
      if (mounted) {
        final msg = role == 'femaleSpeaker'
            ? 'Partner speaker request sent to host'
            : role == 'coSpeaker' || role == 'normalSpeaker'
            ? 'Speaker request sent to host'
            : 'Listener request sent to host';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
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
    setState(() {
      _isLoading = true;
      _message = null;
    });
    _teardownAudio(notify: false);
    try {
      await ApiService.leaveRoom(roomId: id);
      await _refreshRoom();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Left room')));
      }
    } catch (e) {
      if (mounted) setState(() => _message = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _approveJoinRequest(String userId) async {
    final id = _roomId;
    if (id == null) return;
    setState(() {
      _isLoading = true;
      _message = null;
    });
    try {
      await ApiService.approveJoinRequest(roomId: id, userId: userId);
      await _refreshRoom();
    } catch (e) {
      if (mounted) {
        setState(() => _message = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _rejectJoinRequest(String userId) async {
    final id = _roomId;
    if (id == null) return;
    setState(() {
      _isLoading = true;
      _message = null;
    });
    try {
      await ApiService.rejectJoinRequest(roomId: id, userId: userId);
      await _refreshRoom();
    } catch (e) {
      if (mounted) {
        setState(() => _message = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _removeParticipant(String userId, String userName) async {
    final id = _roomId;
    if (id == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove participant'),
        content: Text('Remove $userName from this room?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() {
      _isLoading = true;
      _message = null;
    });
    try {
      await ApiService.removeRoomParticipant(roomId: id, userId: userId);
      await _refreshRoom();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$userName removed')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _message = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _deleteRoom() async {
    final id = _roomId;
    if (id == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete room'),
        content: const Text(
          'This will permanently delete this room. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() {
      _isLoading = true;
      _message = null;
    });
    try {
      await ApiService.deleteRoom(roomId: id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Room deleted')));
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _message = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'femaleSpeaker':
        return 'Partner';
      case 'coSpeaker':
      case 'normalSpeaker':
        return 'Joiner';
      case 'queue':
        return 'Queued';
      case 'listener':
      default:
        return 'Listener';
    }
  }

  // ── WebRTC: room mesh ─────────────────────────────────────────────────────

  Set<String> _activeRoomUserIds() {
    final ids = <String>{};
    void add(String? value) {
      if (value != null && value.isNotEmpty) ids.add(value);
    }

    add(_room['hostId']?.toString());
    add(_room['femaleSpeakerId']?.toString());
    add(_room['otherSpeakerId']?.toString());

    for (final entry in _participants) {
      add(entry['userId']?.toString());
    }
    final queue = List<Map<String, dynamic>>.from(
      _room['queue'] as List<dynamic>? ?? [],
    );
    for (final entry in queue) {
      add(entry['userId']?.toString());
    }
    return ids;
  }

  Set<String> _currentTalkerIds() {
    final ids = <String>{};
    final hostId = _room['hostId']?.toString();
    final partnerId = _room['femaleSpeakerId']?.toString();
    final joinerId = _room['otherSpeakerId']?.toString();
    if (hostId != null && hostId.isNotEmpty) ids.add(hostId);
    if (partnerId != null && partnerId.isNotEmpty) ids.add(partnerId);
    if (joinerId != null && joinerId.isNotEmpty) ids.add(joinerId);
    return ids;
  }

  bool _shouldInitiateToPeer(String peerId) {
    final me = _myId;
    if (me == null) return false;
    if (!_canBroadcastAudio) {
      return true;
    }
    final talkers = _currentTalkerIds();
    if (talkers.contains(peerId)) {
      return me.compareTo(peerId) < 0;
    }
    return false;
  }

  Set<String> _desiredPeerIds() {
    final me = _myId;
    if (me == null || !_isRoomActiveParticipant) return <String>{};

    final talkers = _currentTalkerIds();
    final desired = <String>{};
    if (_canBroadcastAudio) {
      desired.addAll(talkers.where((id) => id != me));
    } else {
      desired.addAll(talkers.where((id) => id != me));
    }
    return desired;
  }

  void _syncLocalAudioTrackState() {
    final shouldEnableMic = _canBroadcastAudio;
    if (_localStream == null) return;
    for (final track in _localStream!.getAudioTracks()) {
      track.enabled = shouldEnableMic;
    }
  }

  void _updateAudioFlags() {
    if (!mounted) return;
    setState(() {
      _audioConnected = _connectedPeerIds.isNotEmpty;
      _audioConnecting = _connectingPeerIds.isNotEmpty;
    });
  }

  void _syncRoomAudioMesh() {
    if (!SocketService.instance.isConnected) {
      _autoConnectRetryTimer?.cancel();
      _autoConnectRetryTimer = Timer(
        const Duration(seconds: 2),
        _syncRoomAudioMesh,
      );
      return;
    }

    final desired = _desiredPeerIds();

    for (final peerId in List<String>.from(_peerConnections.keys)) {
      if (!desired.contains(peerId)) {
        _closePeerConnection(peerId, notify: false);
      }
    }

    for (final peerId in desired) {
      if (_shouldInitiateToPeer(peerId)) {
        unawaited(_initiatePeerConnection(peerId));
      }
    }

    _updateAudioFlags();
  }

  Future<void> _ensureLocalStream() async {
    if (_localStream != null) {
      _syncLocalAudioTrackState();
      return;
    }
    try {
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': false,
      });
      _syncLocalAudioTrackState();
    } catch (e) {
      throw Exception('Microphone access denied or unavailable: $e');
    }
  }

  Future<RTCPeerConnection> _createPeerConnectionFor(String peerId) async {
    if (_peerConnections[peerId] != null) {
      return _peerConnections[peerId]!;
    }

    await _ensureLocalStream();

    final config = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
      ],
      'sdpSemantics': 'unified-plan',
    };

    final pc = await createPeerConnection(config);
    for (final track in _localStream!.getTracks()) {
      await pc.addTrack(track, _localStream!);
    }

    final renderer = RTCVideoRenderer();
    await renderer.initialize();
    _remoteRenderers[peerId] = renderer;

    pc.onIceCandidate = (candidate) {
      if (candidate.candidate == null || candidate.candidate!.isEmpty) return;
      SocketService.instance.sendCandidate(peerId, {
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    };

    pc.onTrack = (event) {
      final stream = event.streams.isNotEmpty ? event.streams[0] : null;
      if (stream != null) {
        final peerRenderer = _remoteRenderers[peerId];
        if (peerRenderer != null) {
          peerRenderer.srcObject = stream;
          peerRenderer.muted = false;
        }
      }
      _connectedPeerIds.add(peerId);
      _connectingPeerIds.remove(peerId);
      _updateAudioFlags();
    };

    pc.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _connectedPeerIds.add(peerId);
        _connectingPeerIds.remove(peerId);
        _updateAudioFlags();
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        _closePeerConnection(peerId, notify: false);
      }
    };

    _peerConnections[peerId] = pc;
    _offerSentByPeer[peerId] = false;
    _remoteDescSetByPeer[peerId] = false;
    _remoteAnswerSetByPeer[peerId] = false;
    _pendingCandidatesByPeer[peerId] = <RTCIceCandidate>[];
    return pc;
  }

  Future<void> _initiatePeerConnection(String peerId) async {
    if (_peerConnections.containsKey(peerId) ||
        _connectingPeerIds.contains(peerId)) {
      return;
    }

    _connectingPeerIds.add(peerId);
    _updateAudioFlags();

    try {
      await _createPeerConnectionFor(peerId);
      SocketService.instance.callPartner(peerId, source: 'room');

      final cachedAccepted = SocketService.instance.getLastCallAccepted(peerId);
      if (cachedAccepted != null) {
        await _sendOfferToPeer(peerId);
        SocketService.instance.clearLastCallAccepted();
      }

      final cachedAnswer = SocketService.instance.getLastAnswer(peerId);
      if (cachedAnswer != null) {
        await _handleAnswerForPeer(peerId, cachedAnswer);
        SocketService.instance.clearLastAnswer(peerId);
      }
    } catch (e) {
      _closePeerConnection(peerId, notify: false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Audio setup error: $e')));
      }
    }
  }

  // ── WebRTC: signaling ─────────────────────────────────────────────────────

  void _onIncomingCall(Map<String, dynamic> event) async {
    final callerId = event['callerId']?.toString();
    if (callerId == null || callerId.isEmpty) return;
    if (!_isRoomActiveParticipant) return;

    final activeRoomUsers = _activeRoomUserIds();
    if (!activeRoomUsers.contains(callerId)) {
      await _refreshRoom();
      if (!_activeRoomUserIds().contains(callerId)) {
        return;
      }
    }

    try {
      await _createPeerConnectionFor(callerId);
      SocketService.instance.acceptCall(callerId, source: 'room');
      final cachedOffer = SocketService.instance.getLastOffer(callerId);
      if (cachedOffer != null) {
        final handled = await _handleOfferFromPeer(callerId, cachedOffer);
        if (handled) {
          SocketService.instance.clearLastOffer(callerId);
        }
      }
      _connectingPeerIds.add(callerId);
      _updateAudioFlags();
    } catch (_) {}
  }

  void _onCallAccepted(Map<String, dynamic> event) async {
    final acceptedBy = event['partnerId']?.toString();
    if (acceptedBy == null || acceptedBy.isEmpty) return;
    if (!_peerConnections.containsKey(acceptedBy)) return;
    await _sendOfferToPeer(acceptedBy);
    SocketService.instance.clearLastCallAccepted();
  }

  void _onOffer(Map<String, dynamic> data) async {
    final fromId = data['from']?.toString();
    if (fromId == null || fromId.isEmpty) return;
    if (!_activeRoomUserIds().contains(fromId)) return;
    await _createPeerConnectionFor(fromId);
    final handled = await _handleOfferFromPeer(fromId, data);
    if (handled) {
      SocketService.instance.clearLastOffer(fromId);
    }
  }

  void _onAnswer(Map<String, dynamic> data) async {
    final fromId = data['from']?.toString();
    if (fromId == null || fromId.isEmpty) return;
    await _handleAnswerForPeer(fromId, data);
  }

  void _onCandidate(Map<String, dynamic> data) async {
    final fromId = data['from']?.toString();
    if (fromId == null || fromId.isEmpty) return;
    await _handleCandidateForPeer(fromId, data);
  }

  void _onCallEnded() {
    _teardownAudio(notify: false);
  }

  Future<bool> _sendOfferToPeer(String peerId) async {
    final pc = _peerConnections[peerId];
    if (pc == null) return false;
    if (_offerSentByPeer[peerId] == true) return false;

    _offerSentByPeer[peerId] = true;
    final offer = await pc.createOffer({'offerToReceiveAudio': true});
    await pc.setLocalDescription(offer);
    SocketService.instance.sendOffer(peerId, offer.toMap());
    _connectingPeerIds.add(peerId);
    _updateAudioFlags();
    return true;
  }

  Future<bool> _handleOfferFromPeer(
    String peerId,
    Map<String, dynamic> data,
  ) async {
    final pc = _peerConnections[peerId];
    if (pc == null) return false;
    final offerMap = data['offer'] as Map<String, dynamic>?;
    if (offerMap == null) return false;

    await pc.setRemoteDescription(
      RTCSessionDescription(
        offerMap['sdp'] as String,
        offerMap['type'] as String,
      ),
    );
    _remoteDescSetByPeer[peerId] = true;
    await _flushPendingCandidatesForPeer(peerId);

    final answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    SocketService.instance.sendAnswer(peerId, answer.toMap());

    _connectingPeerIds.add(peerId);
    _updateAudioFlags();
    return true;
  }

  Future<void> _handleAnswerForPeer(
    String peerId,
    Map<String, dynamic> data,
  ) async {
    final pc = _peerConnections[peerId];
    if (pc == null) return;
    final answerMap = data['answer'] as Map<String, dynamic>?;
    if (answerMap == null) return;

    await pc.setRemoteDescription(
      RTCSessionDescription(
        answerMap['sdp'] as String,
        answerMap['type'] as String,
      ),
    );
    _remoteAnswerSetByPeer[peerId] = true;
    _remoteDescSetByPeer[peerId] = true;
    await _flushPendingCandidatesForPeer(peerId);

    _connectingPeerIds.add(peerId);
    _updateAudioFlags();
  }

  Future<void> _handleCandidateForPeer(
    String peerId,
    Map<String, dynamic> data,
  ) async {
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
    final pc = _peerConnections[peerId];
    if (pc == null || _remoteDescSetByPeer[peerId] != true) {
      final pending = _pendingCandidatesByPeer.putIfAbsent(
        peerId,
        () => <RTCIceCandidate>[],
      );
      pending.add(candidate);
      return;
    }

    await pc.addCandidate(candidate);
  }

  Future<void> _flushPendingCandidatesForPeer(String peerId) async {
    final pc = _peerConnections[peerId];
    final pending = _pendingCandidatesByPeer[peerId];
    if (pc == null || pending == null || pending.isEmpty) return;
    for (final candidate in List<RTCIceCandidate>.from(pending)) {
      await pc.addCandidate(candidate);
    }
    pending.clear();
  }

  Future<void> _closePeerConnection(
    String peerId, {
    required bool notify,
  }) async {
    if (notify) {
      SocketService.instance.endCall(peerId);
    }

    final renderer = _remoteRenderers.remove(peerId);
    if (renderer != null) {
      renderer.srcObject = null;
      await renderer.dispose();
    }

    final pc = _peerConnections.remove(peerId);
    await pc?.close();

    _connectingPeerIds.remove(peerId);
    _connectedPeerIds.remove(peerId);
    _offerSentByPeer.remove(peerId);
    _remoteDescSetByPeer.remove(peerId);
    _remoteAnswerSetByPeer.remove(peerId);
    _pendingCandidatesByPeer.remove(peerId);

    SocketService.instance.clearLastOffer(peerId);
    SocketService.instance.clearLastAnswer(peerId);
    _updateAudioFlags();
  }

  void _teardownAudio({required bool notify, bool updateUi = true}) {
    _autoConnectRetryTimer?.cancel();
    _autoConnectRetryTimer = null;

    final peerIds = List<String>.from(_peerConnections.keys);
    for (final peerId in peerIds) {
      unawaited(_closePeerConnection(peerId, notify: notify));
    }

    _localStream?.dispose();
    _localStream = null;

    _connectingPeerIds.clear();
    _connectedPeerIds.clear();
    _offerSentByPeer.clear();
    _remoteDescSetByPeer.clear();
    _remoteAnswerSetByPeer.clear();
    _pendingCandidatesByPeer.clear();

    if (updateUi && mounted) {
      setState(() {
        _audioConnected = false;
        _audioConnecting = false;
      });
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final roomName = _room['name'] as String? ?? 'Live Room';
    final hostName = _room['hostName'] as String? ?? 'Host';
    final femaleSpeakerName = _room['femaleSpeaker'] as String?;
    final otherSpeakerName = _room['otherSpeaker'] as String?;
    final queue = List<Map<String, dynamic>>.from(
      _room['queue'] as List<dynamic>? ?? [],
    );
    final joinRequests = _joinRequests;
    final participantMap = <String, Map<String, dynamic>>{};

    void addManagedParticipant(String? userId, String? userName, String role) {
      if (userId == null ||
          userId.isEmpty ||
          userId == _room['hostId']?.toString()) {
        return;
      }
      participantMap[userId] = {
        'userId': userId,
        'userName': userName ?? 'User',
        'role': role,
      };
    }

    for (final entry in _participants) {
      addManagedParticipant(
        entry['userId']?.toString(),
        entry['userName']?.toString(),
        entry['role']?.toString() ?? 'listener',
      );
    }

    addManagedParticipant(
      _room['femaleSpeakerId']?.toString(),
      _room['femaleSpeaker']?.toString(),
      'femaleSpeaker',
    );
    addManagedParticipant(
      _room['otherSpeakerId']?.toString(),
      _room['otherSpeaker']?.toString(),
      'coSpeaker',
    );

    for (final queuedUser in queue) {
      addManagedParticipant(
        queuedUser['userId']?.toString(),
        queuedUser['userName']?.toString(),
        'queue',
      );
    }

    final managedParticipants = participantMap.values.toList();

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
              child: Text(
                roomName,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (_audioConnected)
              _LiveBadge(
                label: 'LIVE',
                color: const Color(0xFF3AA047),
                icon: Icons.graphic_eq,
              )
            else if (_audioConnecting)
              _LiveBadge(
                label: 'Connecting…',
                color: const Color(0xFF9C4FFF),
                icon: Icons.hourglass_top,
              ),
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
              audioStatus: _isHost ? audioStatus : null,
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
                      audioStatus: femaleSpeakerName != null
                          ? audioStatus
                          : null,
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
                      audioStatus: otherSpeakerName != null
                          ? audioStatus
                          : null,
                    ),
                  ),
                ],
              ),
            ),

            // Hidden WebRTC audio renderers (one per connected remote peer)
            ..._remoteRenderers.values.map(
              (renderer) =>
                  SizedBox(width: 1, height: 1, child: RTCVideoView(renderer)),
            ),

            // ── CO-SPEAKER seat timer ──────────────────────────────────────
            if (_isNormalSpeaker) ...[
              const SizedBox(height: 16),
              _SeatTimerBar(
                secondsLeft: _seatSecondsLeft,
                total: _kSeatSeconds,
              ),
            ],

            const SizedBox(height: 20),

            if (_isHost) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Join requests (${joinRequests.length})',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              if (joinRequests.isEmpty)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF151A3C),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Center(
                    child: Text(
                      'No pending requests',
                      style: TextStyle(color: Colors.white54),
                    ),
                  ),
                )
              else
                ...joinRequests.map((entry) {
                  final userId = entry['userId']?.toString() ?? '';
                  final userName = entry['userName']?.toString() ?? 'User';
                  final role = _roleLabel(
                    entry['role']?.toString() ?? 'listener',
                  );
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF151A3C),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF2A2F57)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '$userName • $role',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        IconButton(
                          onPressed: userId.isEmpty
                              ? null
                              : () => _rejectJoinRequest(userId),
                          icon: const Icon(
                            Icons.close,
                            color: Colors.redAccent,
                          ),
                        ),
                        IconButton(
                          onPressed: userId.isEmpty
                              ? null
                              : () => _approveJoinRequest(userId),
                          icon: const Icon(
                            Icons.check,
                            color: Color(0xFF3AA047),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Participants (${managedParticipants.length})',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              if (managedParticipants.isEmpty)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF151A3C),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Center(
                    child: Text(
                      'No participants to manage',
                      style: TextStyle(color: Colors.white54),
                    ),
                  ),
                )
              else
                ...managedParticipants.map((entry) {
                  final userId = entry['userId']?.toString() ?? '';
                  final userName = entry['userName']?.toString() ?? 'User';
                  final role = _roleLabel(
                    entry['role']?.toString() ?? 'listener',
                  );
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF151A3C),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF2A2F57)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '$userName • $role',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        IconButton(
                          onPressed: userId.isEmpty
                              ? null
                              : () => _removeParticipant(userId, userName),
                          icon: const Icon(
                            Icons.person_remove,
                            color: Colors.redAccent,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              const SizedBox(height: 20),
            ],

            // ── QUEUE ──────────────────────────────────────────────────────
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Waiting queue (${queue.length})',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
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
                  child: Text(
                    'No one waiting',
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
              )
            else
              ...queue.asMap().entries.map((entry) {
                final idx = entry.key;
                final e = entry.value;
                final name = e['userName']?.toString() ?? '?';
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF151A3C),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF2A2F57)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: const Color(0xFF3A2F6E),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '${idx + 1}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          name,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      Text(
                        '~${idx + 1} min',
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 12,
                        ),
                      ),
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
              child: const Text(
                'Refresh',
                style: TextStyle(color: Colors.white38),
              ),
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
        // Partner speaker join
        if (!_hasFemaleSpeaker &&
            _isPartner &&
            !_isHost &&
            !_isFemaleSpeaker &&
            !_hasPendingRequest) ...[
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed: () => _joinRoom('femaleSpeaker'),
            icon: const Icon(Icons.female),
            label: const Text('Request Partner Speaker Seat'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF5AA2),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],

        // Co-speaker / queue
        if (_isNormalUser &&
            !_isHost &&
            !_isNormalSpeaker &&
            !_isQueued &&
            !_hasPendingRequest) ...[
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed: () => _joinRoom('coSpeaker'),
            icon: Icon(_hasNormalSpeaker ? Icons.queue : Icons.mic),
            label: Text(
              _hasNormalSpeaker
                  ? 'Request Queue Position'
                  : 'Request Speaker Seat',
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8E44AD),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],

        if (_hasPendingRequest) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1A40),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF5E4FFF)),
            ),
            child: const Row(
              children: [
                Icon(Icons.hourglass_top, color: Color(0xFF9C4FFF)),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Join request pending host approval',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              ],
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
                    'Queue position #$_queuePosition  (~$_queuePosition min wait)',
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
        if (_isFemaleSpeaker ||
            _isNormalSpeaker ||
            _isQueued ||
            _isListenerParticipant ||
            _hasPendingRequest) ...[
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _leaveRoom,
            icon: const Icon(Icons.exit_to_app),
            label: Text(
              _hasPendingRequest ? 'Cancel Join Request' : 'Leave Room / Queue',
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFB03060),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],

        if (_isHost) ...[
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _deleteRoom,
            icon: const Icon(Icons.delete_forever),
            label: const Text('Delete Room'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
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
  const _LiveBadge({
    required this.label,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 13),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
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
        border: Border.all(
          color: isMe ? accent : const Color(0xFF2A2F57),
          width: isMe ? 2 : 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            alignment: Alignment.bottomRight,
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: isEmpty
                    ? const Color(0xFF2A2F57)
                    : accent.withOpacity(0.25),
                child: Icon(
                  icon,
                  color: isEmpty ? Colors.white24 : accent,
                  size: 28,
                ),
              ),
              if (audioStatus == _AudioStatus.live)
                Container(
                  width: 16,
                  height: 16,
                  decoration: const BoxDecoration(
                    color: Color(0xFF3AA047),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.graphic_eq,
                    size: 10,
                    color: Colors.white,
                  ),
                )
              else if (audioStatus == _AudioStatus.connecting)
                Container(
                  width: 16,
                  height: 16,
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    color: Color(0xFF9C4FFF),
                    shape: BoxShape.circle,
                  ),
                  child: const CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: accent,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
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
        border: Border.all(
          color: urgent ? Colors.redAccent : const Color(0xFF5E4FFF),
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.timer,
                    color: urgent ? Colors.redAccent : const Color(0xFF5E4FFF),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Your seat time',
                    style: TextStyle(
                      color: urgent ? Colors.redAccent : Colors.white70,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
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
