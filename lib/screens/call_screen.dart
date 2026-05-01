// ignore_for_file: avoid_print

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';

class CallScreen extends StatefulWidget {
  final String partnerId;
  final String partnerName;
  final bool isCaller;

  const CallScreen({
    super.key,
    required this.partnerId,
    required this.partnerName,
    required this.isCaller,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  StreamSubscription<void>? _callEndedSub;
  StreamSubscription<String>? _callFailedSub;
  StreamSubscription<Map<String, dynamic>>? _callAcceptedSub;
  StreamSubscription<Map<String, dynamic>>? _offerSub;
  StreamSubscription<Map<String, dynamic>>? _answerSub;
  StreamSubscription<Map<String, dynamic>>? _candidateSub;
  StreamSubscription<Map<String, dynamic>>? _callCoinsSettledSub;
  StreamSubscription<Map<String, dynamic>>? _callEarningsCreditedSub;
  StreamSubscription<Map<String, dynamic>>? _lowCoinsWarningSub;

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  bool _isConnecting = true;
  bool _offerSent = false;
  bool _remoteDescSet = false;
  bool _remoteAnswerSet = false;
  bool _micMuted = false;
  bool _speakerMuted = false;
  int _walletBalance = 0;
  int _elapsedSeconds = 0;
  int _settledMinutes = 0;
  int _chargedCoins = 0;
  int _earnedCoins = 0;
  bool _showEarnedStats = false;
  Timer? _callTimer;
  final List<RTCIceCandidate> _pendingCandidates = [];

  Future<void> _showPopup({required String title, required String message}) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF151A42),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          message,
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF5AA2),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _listenSignaling();
    _initWebRtc();
  }

  void _listenSignaling() {
    final role = ApiService.currentUser?['role']?.toString().toLowerCase();
    final gender = ApiService.currentUser?['gender']?.toString().toLowerCase();
    _showEarnedStats = role == 'partner' && gender == 'female';

    _callEndedSub = SocketService.instance.callEndedStream.listen((_) {
      if (mounted) Navigator.of(context).pop();
    });

    _callFailedSub = SocketService.instance.callFailedStream.listen((
      reason,
    ) async {
      if (!mounted) return;
      await _showPopup(title: 'Call Alert', message: reason);
      if (mounted) Navigator.of(context).pop();
    });

    _callAcceptedSub = SocketService.instance.callAcceptedStream.listen((
      data,
    ) async {
      if (!widget.isCaller) return;
      final acceptedId = data['partnerId']?.toString();
      if (acceptedId != widget.partnerId) return;
      print('[CallScreen] callAccepted -> creating offer');
      final sent = await _sendOffer();
      if (sent) {
        SocketService.instance.clearLastCallAccepted();
      }
    });

    _offerSub = SocketService.instance.offerStream.listen((data) async {
      final fromId = data['from']?.toString();
      if (widget.isCaller || fromId != widget.partnerId) return;
      print(
        '[CallScreen] offer received from $fromId, pc ready: ${_pc != null}',
      );
      final handled = await _handleOffer(data);
      if (handled) {
        SocketService.instance.clearLastOffer(widget.partnerId);
      }
    });

    _answerSub = SocketService.instance.answerStream.listen((data) async {
      if (!widget.isCaller) return;
      print('[CallScreen] answer received');
      await _handleAnswer(data);
    });

    _candidateSub = SocketService.instance.candidateStream.listen((data) async {
      final fromId = data['from']?.toString();
      if (fromId != null && fromId != widget.partnerId) return;
      await _handleCandidate(data);
    });

    _callCoinsSettledSub = SocketService.instance.callCoinsSettledStream.listen((
      event,
    ) {
      final walletRaw = event['walletBalance'];
      final chargedRaw = event['chargedCoins'];
      final minutesRaw = event['minutes'];
      final wallet = walletRaw is int
          ? walletRaw
          : int.tryParse(walletRaw?.toString() ?? '0') ?? _walletBalance;
      final charged = chargedRaw is int
          ? chargedRaw
          : int.tryParse(chargedRaw?.toString() ?? '0') ?? 0;
      final minutes = minutesRaw is int
          ? minutesRaw
          : int.tryParse(minutesRaw?.toString() ?? '0') ?? 0;
      if (!mounted) return;
      setState(() {
        _walletBalance = wallet;
        _chargedCoins = charged;
        _settledMinutes = minutes;
      });
    });

    _lowCoinsWarningSub = SocketService.instance.lowCoinsWarningStream.listen((
      event,
    ) {
      final message = event['message']?.toString() ??
          'Coins are insufficient to continue the call. Please add coins.';
      final graceRaw = event['graceSeconds'];
      final graceSeconds = graceRaw is int
          ? graceRaw
          : int.tryParse(graceRaw?.toString() ?? '0') ?? 10;
      _showPopup(
        title: 'Low Coins Warning',
        message: '$message\n\nThis call will end in $graceSeconds seconds.',
      );
    });

    _callEarningsCreditedSub = SocketService.instance.callEarningsCreditedStream
        .listen((event) {
          if (!_showEarnedStats) return;
          final walletRaw = event['walletBalance'];
          final creditedRaw = event['creditedCoins'];
          final minutesRaw = event['minutes'];
          final wallet = walletRaw is int
              ? walletRaw
              : int.tryParse(walletRaw?.toString() ?? '0') ?? _walletBalance;
          final credited = creditedRaw is int
              ? creditedRaw
              : int.tryParse(creditedRaw?.toString() ?? '0') ?? 0;
          final minutes = minutesRaw is int
              ? minutesRaw
              : int.tryParse(minutesRaw?.toString() ?? '0') ?? 0;
          if (!mounted) return;
          setState(() {
            _walletBalance = wallet;
            _earnedCoins = credited;
            _settledMinutes = minutes;
          });
        });
  }

  Future<void> _initWebRtc() async {
    print(
      '[CallScreen] init isCaller=${widget.isCaller} partner=${widget.partnerId}',
    );
    await _remoteRenderer.initialize();
    await _loadWalletBalance();

    try {
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': false,
      });
    } catch (e) {
      print('[CallScreen] getUserMedia error: $e');
      if (mounted) {
        _showPopup(
          title: 'Microphone Access',
          message: 'Microphone access denied: $e',
        );
        Navigator.of(context).pop();
      }
      return;
    }
    _pc = await _buildPeerConnection();

    // Drain cached events that arrived before _pc was ready
    if (widget.isCaller) {
      final accepted = SocketService.instance.getLastCallAccepted(
        widget.partnerId,
      );
      if (accepted != null && !_offerSent) {
        print('[CallScreen] drain cached callAccepted');
        final sent = await _sendOffer();
        if (sent) {
          SocketService.instance.clearLastCallAccepted();
        }
      }

      final cachedAnswer = SocketService.instance.getLastAnswer(
        widget.partnerId,
      );
      if (cachedAnswer != null && !_remoteAnswerSet) {
        print('[CallScreen] drain cached answer');
        await _handleAnswer(cachedAnswer);
        SocketService.instance.clearLastAnswer(widget.partnerId);
      }
    } else {
      final cachedOffer = SocketService.instance.getLastOffer(widget.partnerId);
      if (cachedOffer != null) {
        print('[CallScreen] drain cached offer');
        final handled = await _handleOffer(cachedOffer);
        if (handled) {
          SocketService.instance.clearLastOffer(widget.partnerId);
        }
      }
    }
  }

  Future<RTCPeerConnection> _buildPeerConnection() async {
    final config = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
      ],
      'sdpSemantics': 'unified-plan',
    };

    final pc = await createPeerConnection(config);

    pc.onIceCandidate = (candidate) {
      if (candidate.candidate == null || candidate.candidate!.isEmpty) return;
      SocketService.instance.sendCandidate(widget.partnerId, {
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    };

    pc.onConnectionState = (state) {
      print('[CallScreen] connectionState=$state');
      if (!mounted) return;
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _startCallTimer();
        setState(() => _isConnecting = false);
      }
    };

    pc.onIceConnectionState = (state) {
      print('[CallScreen] iceState=$state');
      if (!mounted) return;
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        _startCallTimer();
        setState(() => _isConnecting = false);
      }
    };

    pc.onTrack = (event) {
      print('[CallScreen] onTrack streams=${event.streams.length}');
      if (event.streams.isNotEmpty) {
        _remoteRenderer.srcObject = event.streams[0];
        _remoteRenderer.muted = _speakerMuted;
        _startCallTimer();
        if (mounted) setState(() => _isConnecting = false);
      }
    };

    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        await pc.addTrack(track, _localStream!);
      }
    }

    return pc;
  }

  Future<bool> _sendOffer() async {
    if (_offerSent || _pc == null) return false;
    _offerSent = true;
    print('[CallScreen] _sendOffer');
    final offer = await _pc!.createOffer({'offerToReceiveAudio': true});
    await _pc!.setLocalDescription(offer);
    SocketService.instance.sendOffer(widget.partnerId, offer.toMap());
    return true;
  }

  Future<bool> _handleOffer(Map<String, dynamic> data) async {
    if (_pc == null) return false;
    final offerMap = data['offer'] as Map<String, dynamic>?;
    if (offerMap == null) return false;

    await _pc!.setRemoteDescription(
      RTCSessionDescription(
        offerMap['sdp'] as String,
        offerMap['type'] as String,
      ),
    );
    _remoteDescSet = true;
    await _flushPendingCandidates();

    final answer = await _pc!.createAnswer();
    await _pc!.setLocalDescription(answer);
    final fromId = data['from']?.toString() ?? widget.partnerId;
    SocketService.instance.sendAnswer(fromId, answer.toMap());
    if (mounted) setState(() => _isConnecting = false);
    return true;
  }

  Future<void> _handleAnswer(Map<String, dynamic> data) async {
    if (_pc == null) return;
    final fromId = data['from']?.toString();
    if (fromId != null && fromId != widget.partnerId) return;
    final answerMap = data['answer'] as Map<String, dynamic>?;
    if (answerMap == null) return;

    await _pc!.setRemoteDescription(
      RTCSessionDescription(
        answerMap['sdp'] as String,
        answerMap['type'] as String,
      ),
    );
    _remoteAnswerSet = true;
    _remoteDescSet = true;
    await _flushPendingCandidates();
    if (mounted) setState(() => _isConnecting = false);
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
    print(
      '[CallScreen] flushing ${_pendingCandidates.length} buffered candidates',
    );
    for (final c in List<RTCIceCandidate>.from(_pendingCandidates)) {
      await _pc!.addCandidate(c);
    }
    _pendingCandidates.clear();
  }

  @override
  void dispose() {
    _callTimer?.cancel();
    _callEndedSub?.cancel();
    _callFailedSub?.cancel();
    _callAcceptedSub?.cancel();
    _offerSub?.cancel();
    _answerSub?.cancel();
    _candidateSub?.cancel();
    _callCoinsSettledSub?.cancel();
    _callEarningsCreditedSub?.cancel();
    _lowCoinsWarningSub?.cancel();
    _localStream?.dispose();
    _remoteRenderer.srcObject = null;
    _remoteRenderer.dispose();
    _pc?.close();
    super.dispose();
  }

  Future<void> _loadWalletBalance() async {
    try {
      final balance = await ApiService.getWalletBalance();
      if (!mounted) return;
      setState(() {
        _walletBalance = balance;
      });
    } catch (_) {
      final fallback = ApiService.currentUser?['walletBalance'];
      final parsed = fallback is int
          ? fallback
          : int.tryParse(fallback?.toString() ?? '0') ?? 0;
      if (!mounted) return;
      setState(() {
        _walletBalance = parsed;
      });
    }
  }

  void _startCallTimer() {
    if (_callTimer != null) return;
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _elapsedSeconds++;
      });
    });
  }

  String get _formattedDuration {
    final minutes = (_elapsedSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_elapsedSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _toggleMicMute() {
    final stream = _localStream;
    if (stream == null) return;
    final nextMuted = !_micMuted;
    for (final track in stream.getAudioTracks()) {
      track.enabled = !nextMuted;
    }
    if (!mounted) return;
    setState(() {
      _micMuted = nextMuted;
    });
  }

  void _toggleSpeakerMute() {
    final nextMuted = !_speakerMuted;
    _remoteRenderer.muted = nextMuted;
    if (!mounted) return;
    setState(() {
      _speakerMuted = nextMuted;
    });
  }

  void _endCall() {
    SocketService.instance.endCall(widget.partnerId);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1030),
      appBar: AppBar(
        backgroundColor: const Color(0xFF10133D),
        title: const Text('Live Audio', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isConnecting
                    ? const Color(0xFF2B1E67)
                    : const Color(0xFF1E4620),
                border: Border.all(
                  color: _isConnecting
                      ? const Color(0xFFFF5AA2)
                      : const Color(0xFF3AA047),
                  width: 3,
                ),
              ),
              child: Icon(
                Icons.mic,
                size: 50,
                color: _isConnecting
                    ? const Color(0xFFFF5AA2)
                    : const Color(0xFF3AA047),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              widget.partnerName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF161A45),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Duration: $_formattedDuration',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'Wallet: $_walletBalance',
                    style: const TextStyle(
                      color: Colors.amberAccent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF14183F),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Billed: $_settledMinutes min',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'Charged: $_chargedCoins',
                    style: const TextStyle(
                      color: Colors.orangeAccent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (_showEarnedStats)
                    Text(
                      'Earned: $_earnedCoins',
                      style: const TextStyle(
                        color: Color(0xFF5CE38E),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _isConnecting
                  ? const Column(
                      key: ValueKey('connecting'),
                      children: [
                        SizedBox(height: 8),
                        CircularProgressIndicator(color: Color(0xFFFF5AA2)),
                        SizedBox(height: 12),
                        Text(
                          'Connecting audio\u2026',
                          style: TextStyle(color: Colors.white70, fontSize: 15),
                        ),
                      ],
                    )
                  : const Column(
                      key: ValueKey('live'),
                      children: [
                        SizedBox(height: 8),
                        Icon(
                          Icons.graphic_eq,
                          color: Color(0xFF3AA047),
                          size: 32,
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Audio live',
                          style: TextStyle(
                            color: Color(0xFF3AA047),
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
            ),
            SizedBox(width: 1, height: 1, child: RTCVideoView(_remoteRenderer)),
            const SizedBox(height: 40),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: _toggleMicMute,
                  icon: Icon(_micMuted ? Icons.mic_off : Icons.mic),
                  label: Text(_micMuted ? 'Unmute Mic' : 'Mute Mic'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF5E4FFF),
                    padding: const EdgeInsets.symmetric(
                      vertical: 14,
                      horizontal: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _toggleSpeakerMute,
                  icon: Icon(
                    _speakerMuted ? Icons.volume_off : Icons.volume_up,
                  ),
                  label: Text(_speakerMuted ? 'Unmute Spk' : 'Mute Spk'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3A3F7A),
                    padding: const EdgeInsets.symmetric(
                      vertical: 14,
                      horizontal: 18,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _endCall,
              icon: const Icon(Icons.call_end),
              label: const Text('End Call', style: TextStyle(fontSize: 16)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                padding: const EdgeInsets.symmetric(
                  vertical: 16,
                  horizontal: 40,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
