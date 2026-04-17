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
  StreamSubscription<void>? _callEndedSubscription;
  StreamSubscription<String>? _callFailedSubscription;
  StreamSubscription<Map<String, dynamic>>? _callAcceptedSubscription;
  StreamSubscription<Map<String, dynamic>>? _offerSubscription;
  StreamSubscription<Map<String, dynamic>>? _answerSubscription;
  StreamSubscription<Map<String, dynamic>>? _candidateSubscription;

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  bool _isConnecting = true;
  bool _offerSent = false;

  @override
  void initState() {
    super.initState();
    _callEndedSubscription = SocketService.instance.callEndedStream.listen((_) {
      if (mounted) {
        Navigator.of(context).pop();
      }
    });
    _callFailedSubscription = SocketService.instance.callFailedStream.listen((
      reason,
    ) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(reason), backgroundColor: Colors.redAccent),
        );
      }
    });
    _callAcceptedSubscription = SocketService.instance.callAcceptedStream
        .listen((data) async {
          if (!mounted) return;
          final acceptedPartnerId = data['partnerId'] as String?;
          if (widget.isCaller && acceptedPartnerId == widget.partnerId) {
            SocketService.instance.clearLastCallAccepted();
            if (_peerConnection != null && !_offerSent) {
              await _createOffer();
            }
          }
        });
    _offerSubscription = SocketService.instance.offerStream.listen(
      _handleOffer,
    );
    _answerSubscription = SocketService.instance.answerStream.listen(
      _handleAnswer,
    );
    _candidateSubscription = SocketService.instance.candidateStream.listen(
      _handleCandidate,
    );
    _initWebRtc();
  }

  Future<void> _initWebRtc() async {
    print('[CallScreen] initializing WebRTC for ${widget.partnerId} isCaller=${widget.isCaller}');
    await _remoteRenderer.initialize();
    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': false,
    });
    _peerConnection = await _createPeerConnection();

    if (widget.isCaller) {
      final accepted = SocketService.instance.getLastCallAccepted(widget.partnerId);
      if (accepted != null && !_offerSent) {
        print('[CallScreen] found cached callAccepted for ${widget.partnerId}');
        SocketService.instance.clearLastCallAccepted();
        await _createOffer();
      }
    } else {
      final offer = SocketService.instance.getLastOffer(widget.partnerId);
      if (offer != null) {
        print('[CallScreen] found cached offer from ${widget.partnerId}');
        await _handleOffer(offer);
        SocketService.instance.clearLastOffer(widget.partnerId);
      }
    }

    if (!mounted) return;
  }

  Future<RTCPeerConnection> _createPeerConnection() async {
    final config = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
    };
    final pc = await createPeerConnection(config);

    pc.onIceCandidate = (candidate) {
      SocketService.instance.sendCandidate(widget.partnerId, {
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    };

    pc.onTrack = (event) async {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
        await _remoteRenderer.srcObject?.dispose();
        _remoteRenderer.srcObject = _remoteStream;
        if (!mounted) return;
        setState(() {
          _isConnecting = false;
        });
      }
    };

    if (_localStream != null) {
      _localStream!.getTracks().forEach((track) {
        pc.addTrack(track, _localStream!);
      });
    }

    return pc;
  }

  Future<void> _handleOffer(Map<String, dynamic> data) async {
    print('[CallScreen] handleOffer: $data');
    final fromId = data['from']?.toString();
    if (widget.isCaller || fromId != widget.partnerId) return;
    final offer = data['offer'] as Map<String, dynamic>;
    final description = RTCSessionDescription(
      offer['sdp'] as String,
      offer['type'] as String,
    );
    await _peerConnection?.setRemoteDescription(description);
    if (fromId == null) {
      return;
    }
    final answer = await _peerConnection?.createAnswer();
    if (answer != null) {
      await _peerConnection?.setLocalDescription(answer);
      SocketService.instance.sendAnswer(fromId, answer.toMap());
      if (mounted) {
        setState(() {
          _isConnecting = false;
        });
      }
    }
  }

  Future<void> _handleAnswer(Map<String, dynamic> data) async {
    print('[CallScreen] handleAnswer: $data');
    if (!widget.isCaller) return;
    final answer = data['answer'] as Map<String, dynamic>;
    final description = RTCSessionDescription(
      answer['sdp'] as String,
      answer['type'] as String,
    );
    await _peerConnection?.setRemoteDescription(description);
    if (mounted) {
      setState(() {
        _isConnecting = false;
      });
    }
  }

  Future<void> _handleCandidate(Map<String, dynamic> data) async {
    print('[CallScreen] handleCandidate: $data');
    final candidateInfo = data['candidate'] as Map<String, dynamic>?;
    if (candidateInfo == null) return;
    final candidate = RTCIceCandidate(
      candidateInfo['candidate'] as String?,
      candidateInfo['sdpMid'] as String?,
      candidateInfo['sdpMLineIndex'] as int?,
    );
    await _peerConnection?.addCandidate(candidate);
  }

  Future<void> _createOffer() async {
    print('[CallScreen] creating offer for ${widget.partnerId}');
    if (_offerSent || _peerConnection == null) return;
    final offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);
    SocketService.instance.sendOffer(widget.partnerId, offer.toMap());
    setState(() {
      _offerSent = true;
    });
  }

  @override
  void dispose() {
    _callEndedSubscription?.cancel();
    _callFailedSubscription?.cancel();
    _callAcceptedSubscription?.cancel();
    _offerSubscription?.cancel();
    _answerSubscription?.cancel();
    _candidateSubscription?.cancel();
    _localStream?.dispose();
    _remoteStream?.dispose();
    _remoteRenderer.dispose();
    _peerConnection?.close();
    super.dispose();
  }

  void _endCall() {
    SocketService.instance.endCall(widget.partnerId);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Live Call')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.mic, size: 80, color: Color(0xFFFF5AA2)),
            const SizedBox(height: 24),
            Text(
              'Connected with ${widget.partnerName}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              _isConnecting
                  ? 'Connecting audio...'
                  : widget.isCaller
                  ? 'Live audio is active with ${widget.partnerName}.'
                  : 'You are on a live socket call.',
              style: const TextStyle(color: Colors.white70, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            if (_isConnecting)
              const CircularProgressIndicator(color: Color(0xFFFF5AA2)),
            if (!_isConnecting) const SizedBox(height: 20),
            if (_remoteStream != null)
              SizedBox(
                height: 1,
                width: 1,
                child: RTCVideoView(
                  _remoteRenderer,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                ),
              ),
            ElevatedButton(
              onPressed: _endCall,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                padding: const EdgeInsets.symmetric(
                  vertical: 16,
                  horizontal: 40,
                ),
              ),
              child: const Text(
                'End Call',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
