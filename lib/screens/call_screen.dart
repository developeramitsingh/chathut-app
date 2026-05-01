// ignore_for_file: avoid_print

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
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

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  bool _isConnecting = true;
  bool _offerSent = false;
  bool _remoteDescSet = false;
  bool _remoteAnswerSet = false;
  final List<RTCIceCandidate> _pendingCandidates = [];

  @override
  void initState() {
    super.initState();
    _listenSignaling();
    _initWebRtc();
  }

  void _listenSignaling() {
    _callEndedSub = SocketService.instance.callEndedStream.listen((_) {
      if (mounted) Navigator.of(context).pop();
    });

    _callFailedSub = SocketService.instance.callFailedStream.listen((reason) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(reason), backgroundColor: Colors.redAccent),
      );
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
  }

  Future<void> _initWebRtc() async {
    print(
      '[CallScreen] init isCaller=${widget.isCaller} partner=${widget.partnerId}',
    );
    await _remoteRenderer.initialize();

    try {
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': false,
      });
    } catch (e) {
      print('[CallScreen] getUserMedia error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Microphone access denied: $e'),
            backgroundColor: Colors.redAccent,
          ),
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
        setState(() => _isConnecting = false);
      }
    };

    pc.onIceConnectionState = (state) {
      print('[CallScreen] iceState=$state');
      if (!mounted) return;
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        setState(() => _isConnecting = false);
      }
    };

    pc.onTrack = (event) {
      print('[CallScreen] onTrack streams=${event.streams.length}');
      if (event.streams.isNotEmpty) {
        _remoteRenderer.srcObject = event.streams[0];
        _remoteRenderer.muted = false;
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
    _callEndedSub?.cancel();
    _callFailedSub?.cancel();
    _callAcceptedSub?.cancel();
    _offerSub?.cancel();
    _answerSub?.cancel();
    _candidateSub?.cancel();
    _localStream?.dispose();
    _remoteRenderer.srcObject = null;
    _remoteRenderer.dispose();
    _pc?.close();
    super.dispose();
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
