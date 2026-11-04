import 'dart:typed_data';
import 'dart:js_interop';
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

class IdentityVideo extends StatefulWidget {
  const IdentityVideo({super.key, required this.bytes});
  final Uint8List bytes;
  @override
  State<IdentityVideo> createState() => _IdentityVideoState();
}

class _IdentityVideoState extends State<IdentityVideo> {
  late final String _url;
  web.HTMLVideoElement? _video;
  @override
  void initState() {
    super.initState();
    _url = web.URL.createObjectURL(web.Blob(
        [widget.bytes.toJS].toJS,
        web.BlobPropertyBag(
            type: widget.bytes.first == 0x1a ? 'video/webm' : 'video/mp4')));
  }

  @override
  void dispose() {
    _video?.pause(); _video?.removeAttribute('src'); _video?.load();
    web.URL.revokeObjectURL(_url);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HtmlElementView.fromTagName(
      tagName: 'video',
      onElementCreated: (element) {
        final video = element as web.HTMLVideoElement;
          _video=video;
        video.src = _url;
        video.controls = true;
        video.setAttribute('playsinline', '');
        video.style.width = '100%';
        video.style.height = '100%';
        video.style.objectFit = 'contain';
      });
}
