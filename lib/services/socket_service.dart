// ignore_for_file: avoid_print

import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as socket_io_client;
import 'api_service.dart';

class SocketService {
  SocketService._internal();

  static final SocketService instance = SocketService._internal();

  socket_io_client.Socket? _socket;
  final _liveUsersController = StreamController<List<Map<String, dynamic>>>.broadcast();
  final _incomingCallController = StreamController<Map<String, dynamic>>.broadcast();
  final _callAcceptedController = StreamController<Map<String, dynamic>>.broadcast();
  final _callEndedController = StreamController<void>.broadcast();
  final _callFailedController = StreamController<String>.broadcast();
  final _offerController = StreamController<Map<String, dynamic>>.broadcast();
  final _answerController = StreamController<Map<String, dynamic>>.broadcast();
  final _candidateController = StreamController<Map<String, dynamic>>.broadcast();
  final _roomUpdateController = StreamController<Map<String, dynamic>>.broadcast();

  Stream<List<Map<String, dynamic>>> get liveUsersStream => _liveUsersController.stream;
  Stream<Map<String, dynamic>> get incomingCallStream => _incomingCallController.stream;
  Stream<Map<String, dynamic>> get callAcceptedStream => _callAcceptedController.stream;
  Stream<void> get callEndedStream => _callEndedController.stream;
  Stream<String> get callFailedStream => _callFailedController.stream;
  Stream<Map<String, dynamic>> get offerStream => _offerController.stream;
  Stream<Map<String, dynamic>> get answerStream => _answerController.stream;
  Stream<Map<String, dynamic>> get candidateStream => _candidateController.stream;
  Stream<Map<String, dynamic>> get roomUpdateStream => _roomUpdateController.stream;

  bool get isConnected => _socket?.connected == true;

  Map<String, dynamic>? _cachedCallAccepted;
  final Map<String, Map<String, dynamic>> _cachedOffers = {};
  final Map<String, Map<String, dynamic>> _cachedAnswers = {};
  String? _subscribedRoomId;

  Map<String, dynamic>? getLastCallAccepted(String partnerId) {
    if (_cachedCallAccepted != null && _cachedCallAccepted!['partnerId'] == partnerId) {
      return _cachedCallAccepted;
    }
    return null;
  }

  Map<String, dynamic>? getLastOffer(String fromId) => _cachedOffers[fromId];
  Map<String, dynamic>? getLastAnswer(String fromId) => _cachedAnswers[fromId];

  void clearLastCallAccepted() {
    _cachedCallAccepted = null;
  }

  void clearLastOffer(String fromId) {
    _cachedOffers.remove(fromId);
  }

  void clearLastAnswer(String fromId) {
    _cachedAnswers.remove(fromId);
  }

  void connect(String token) {
    if (_socket != null) {
      return;
    }

    _socket = socket_io_client.io(
      ApiService.baseUrl,
      <String, dynamic>{
        'transports': ['websocket'],
        'autoConnect': false,
        'auth': {'token': token},
        'withCredentials': true,
      },
    );

    _socket!.on('connect', (_) {
      requestLiveUsers();
      if (_subscribedRoomId != null) {
        _socket!.emit('subscribeRoom', {'roomId': _subscribedRoomId});
      }
    });

    _socket!.on('liveUsers', (data) {
      final users = _toUserList(data);
      _liveUsersController.add(users);
    });

    _socket!.on('incomingCall', (data) {
      if (data is Map) {
        final event = Map<String, dynamic>.from(data.cast<String, dynamic>());
        print('[SocketService] incomingCall: $event');
        _incomingCallController.add(event);
      }
    });

    _socket!.on('callAccepted', (data) {
      if (data is Map) {
        final event = Map<String, dynamic>.from(data.cast<String, dynamic>());
        print('[SocketService] callAccepted: $event');
        _cachedCallAccepted = event;
        _callAcceptedController.add(event);
      }
    });

    _socket!.on('offer', (data) {
      if (data is Map) {
        final event = Map<String, dynamic>.from(data.cast<String, dynamic>());
        print('[SocketService] offer received: $event');
        final fromId = event['from']?.toString();
        if (fromId != null) {
          _cachedOffers[fromId] = event;
        }
        _offerController.add(event);
      }
    });

    _socket!.on('answer', (data) {
      if (data is Map) {
        final event = Map<String, dynamic>.from(data.cast<String, dynamic>());
        final fromId = event['from']?.toString();
        if (fromId != null) {
          _cachedAnswers[fromId] = event;
        }
        _answerController.add(event);
      }
    });

    _socket!.on('candidate', (data) {
      if (data is Map) {
        final event = Map<String, dynamic>.from(data.cast<String, dynamic>());
        print('[SocketService] candidate received: $event');
        _candidateController.add(event);
      }
    });

    _socket!.on('roomUpdated', (data) {
      if (data is Map) {
        final event = Map<String, dynamic>.from(data.cast<String, dynamic>());
        print('[SocketService] roomUpdated: $event');
        _roomUpdateController.add(event);
      }
    });

    _socket!.on('callEnded', (_) {
      _callEndedController.add(null);
    });

    _socket!.on('callFailed', (data) {
      final reason = data is Map && data['reason'] is String ? data['reason'] as String : 'Call failed';
      _callFailedController.add(reason);
    });

    _socket!.on('disconnect', (_) {
      _liveUsersController.add([]);
    });

    _socket!.on('connect_error', (_) {
      _liveUsersController.add([]);
    });

    _socket!.connect();
  }

  void disconnect() {
    if (_subscribedRoomId != null) {
      unsubscribeRoom(_subscribedRoomId!);
    }
    _socket?.disconnect();
    _socket = null;
    _subscribedRoomId = null;
  }

  void subscribeRoom(String roomId) {
    _subscribedRoomId = roomId;
    if (isConnected) {
      _socket!.emit('subscribeRoom', {'roomId': roomId});
    }
  }

  void unsubscribeRoom(String roomId) {
    if (isConnected) {
      _socket!.emit('unsubscribeRoom', {'roomId': roomId});
    }
    if (_subscribedRoomId == roomId) {
      _subscribedRoomId = null;
    }
  }

  void requestLiveUsers() {
    if (isConnected) {
      _socket!.emit('getLiveUsers');
    }
  }

  void callPartner(String partnerId) {
    print('[SocketService] emit callPartner -> $partnerId');
    _socket?.emit('callPartner', {'targetId': partnerId});
  }

  void acceptCall(String callerId) {
    print('[SocketService] emit acceptCall -> $callerId');
    _socket?.emit('acceptCall', {'callerId': callerId});
  }

  void rejectCall(String callerId) {
    _socket?.emit('rejectCall', {'callerId': callerId});
  }

  void endCall(String targetId) {
    _socket?.emit('endCall', {'targetId': targetId});
  }

  void sendOffer(String targetId, Map<String, dynamic> offer) {
    print('[SocketService] emit webrtcOffer -> target:$targetId offerType:${offer['type']}');
    _socket?.emit('webrtcOffer', {'targetId': targetId, 'offer': offer});
  }

  void sendAnswer(String targetId, Map<String, dynamic> answer) {
    print('[SocketService] emit webrtcAnswer -> target:$targetId answerType:${answer['type']}');
    _socket?.emit('webrtcAnswer', {'targetId': targetId, 'answer': answer});
  }

  void sendCandidate(String targetId, Map<String, dynamic> candidate) {
    print('[SocketService] emit webrtcCandidate -> target:$targetId candidate:${candidate['candidate']}');
    _socket?.emit('webrtcCandidate', {'targetId': targetId, 'candidate': candidate});
  }

  void sendAudioChunk(String targetId, dynamic payload) {
    _socket?.emit('audioChunk', {'to': targetId, 'data': payload});
  }

  List<Map<String, dynamic>> _toUserList(dynamic data) {
    if (data is List) {
      return data.map<Map<String, dynamic>>((user) {
        if (user is Map<String, dynamic>) {
          return Map<String, dynamic>.from(user);
        }
        if (user is Map) {
          return Map<String, dynamic>.from(user.cast<String, dynamic>());
        }
        return <String, dynamic>{};
      }).toList();
    }
    return [];
  }

  void dispose() {
    _liveUsersController.close();
    _incomingCallController.close();
    _callAcceptedController.close();
    _callEndedController.close();
    _callFailedController.close();
    _offerController.close();
    _answerController.close();
    _candidateController.close();
    _roomUpdateController.close();
    disconnect();
  }
}
