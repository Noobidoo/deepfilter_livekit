import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:deepfilter_livekit/deepfilter_livekit.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;

void main() => runApp(const _App());

class _App extends StatelessWidget {
  const _App();
  @override
  Widget build(BuildContext context) =>
      const MaterialApp(title: 'Voice Chat Test', home: _Chat());
}

class _Chat extends StatefulWidget {
  const _Chat();
  @override
  State<_Chat> createState() => _ChatState();
}

class _ChatState extends State<_Chat> {
  final _urlCtl = TextEditingController(text: 'ws://127.0.0.1:7880');
  final _roomCtl = TextEditingController(text: 'test-room');
  final _idCtl = TextEditingController(text: 'alice');
  final _keyCtl = TextEditingController(text: 'devkey');
  final _secCtl = TextEditingController(text: 'secret');

  lk.Room? _room;
  DeepFilterProcessor? _processor;
  String _remote = '';
  String _err = '';
  bool _muted = false;
  bool _nsOn = true;

  @override void dispose() {
    _disconnect();
    for (final c in [_urlCtl, _roomCtl, _idCtl, _keyCtl, _secCtl]) c.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() { _err = ''; _remote = ''; });
    try {
      final token = JWT({
        'iss': _keyCtl.text,
        'sub': _idCtl.text,
        'video': {
          'roomJoin': true,
          'room': _roomCtl.text,
          'canPublish': true,
          'canSubscribe': true,
        },
        'name': _idCtl.text,
      }).sign(SecretKey(_secCtl.text), expiresIn: const Duration(hours: 1));

      _room = lk.Room(roomOptions: const lk.RoomOptions());
      final listener = _room!.createListener();
      listener.on<lk.TrackSubscribedEvent>((ev) {
        if (ev.track is lk.RemoteAudioTrack) {
          (ev.track as lk.RemoteAudioTrack).start();
          setState(() => _remote = ev.participant.identity);
        }
      });
      listener.on<lk.TrackUnsubscribedEvent>((_) {
        setState(() => _remote = '');
      });

      await _room!.connect(_urlCtl.text, token);

      // Enumerate to get the real default mic deviceId.
      // Workaround for flutter-webrtc#2071 where mic may not open without explicit deviceId.
      String? micId;
      try {
        final devices = await rtc.navigator.mediaDevices.enumerateDevices();
        micId = devices.firstWhere((d) => d.kind == 'audioinput').deviceId;
      } catch (_) {}

      _processor = DeepFilterProcessor(enabled: _nsOn);
      final track = await lk.LocalAudioTrack.create(
        lk.AudioCaptureOptions(
          deviceId: micId,
          processor: _processor,
        ),
      );
      await _room!.localParticipant!.publishAudioTrack(track);

      setState(() => _err = '');
    } catch (e) {
      setState(() => _err = '$e');
    }
  }

  Future<void> _disconnect() async {
    await _room?.disconnect();
    _room?.dispose();
    _room = null;
    _processor = null;
    setState(() => _remote = '');
  }

  void _toggleMic() {
    _room?.localParticipant?.setMicrophoneEnabled(_muted);
    setState(() => _muted = !_muted);
  }

  void _toggleNs() {
    _nsOn = !_nsOn;
    _processor?.setEnabled(_nsOn);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ok = DeepFilterProcessor.isRealLibrary;
    final connected = _room?.connectionState == lk.ConnectionState.connected;
    return Scaffold(
      appBar: AppBar(title: const Text('Voice Chat Test')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        ..._fields(),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: connected ? _disconnect : _connect,
          child: Text(connected ? 'Disconnect' : 'Connect'),
        ),
        const SizedBox(height: 12),
        if (connected) ...[
          Row(children: [
            Icon(ok ? Icons.check_circle : Icons.error,
                color: ok ? Colors.green : Colors.red),
            const SizedBox(width: 6),
            Text(ok ? 'Real Library' : 'STUB (no noise reduction)',
                style: TextStyle(fontWeight: FontWeight.bold,
                    color: ok ? Colors.green : Colors.red)),
            const Spacer(),
            Text('NS: ${_nsOn ? "ON" : "OFF"}',
                style: TextStyle(fontWeight: FontWeight.bold,
                    color: _nsOn ? Colors.green : Colors.grey)),
          ]),
          const SizedBox(height: 4),
          Builder(builder: (_) {
            final apm = DeepFilterProcessor.isApmAttached;
            return Row(children: [
              Icon(apm ? Icons.graphic_eq : Icons.mic_off,
                  size: 16,
                  color: apm ? Colors.green : Colors.orange),
              const SizedBox(width: 4),
              Text(apm ? 'APM hook active' : 'APM hook not attached',
                  style: TextStyle(
                      fontSize: 12,
                      color: apm ? Colors.green : Colors.orange)),
            ]);
          }),
          const SizedBox(height: 8),
          Text('Room: ${_room!.name ?? "-"}'),
          Text('Remote: ${_remote.isEmpty ? "none" : _remote}'),
          Text('Status: ${_room!.connectionState.name}'),
          const SizedBox(height: 12),
          Row(children: [
            ElevatedButton(
                onPressed: _toggleMic,
                child: Text(_muted ? 'Unmute' : 'Mute')),
            const SizedBox(width: 12),
            ElevatedButton(
                onPressed: _toggleNs,
                style: ElevatedButton.styleFrom(
                    backgroundColor: _nsOn ? Colors.green : Colors.grey),
                child: Text('NS ${_nsOn ? "ON" : "OFF"}')),
          ]),
        ],
        if (_err.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(_err, style: const TextStyle(color: Colors.red)),
          ),
      ]),
    );
  }

  List<Widget> _fields() => [
    _field(_urlCtl, 'Server URL'),
    _field(_roomCtl, 'Room'),
    _field(_idCtl, 'Identity'),
    _field(_keyCtl, 'API Key'),
    _field(_secCtl, 'API Secret', obscure: true),
  ];

  Widget _field(TextEditingController c, String label, {bool obscure = false}) =>
    Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(controller: c,
        decoration: InputDecoration(
          labelText: label, border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        obscureText: obscure),
    );
}
