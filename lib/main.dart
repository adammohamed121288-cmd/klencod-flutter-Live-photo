import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LivePhotoApp());
}

class LivePhotoApp extends StatelessWidget {
  const LivePhotoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Live Photo Camera',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF080B12),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4B8DFF),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const CameraHome(),
    );
  }
}

class LiveItem {
  final File photo;
  final File video;
  LiveItem(this.photo, this.video);
}

class CameraHome extends StatefulWidget {
  const CameraHome({super.key});

  @override
  State<CameraHome> createState() => _CameraHomeState();
}

class _CameraHomeState extends State<CameraHome> with WidgetsBindingObserver {
  CameraController? _camera;
  List<CameraDescription> _cameras = [];
  bool _initializing = true;
  bool _capturing = false;
  bool _liveMode = true;
  bool _savingToGallery = true;
  FlashMode _flashMode = FlashMode.off;
  String? _error;
  String _countdown = '';
  List<LiveItem> _items = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
    _loadItems();
  }

  Future<Directory> _liveDirectory() async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory('${root.path}/LivePhotoCamera');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<void> _loadItems() async {
    try {
      final dir = await _liveDirectory();
      final files = dir.listSync().whereType<File>().toList();
      final photos = files.where((f) => f.path.endsWith('.jpg')).toList()
        ..sort((a, b) => b.path.compareTo(a.path));
      final result = <LiveItem>[];
      for (final photo in photos) {
        final stem = photo.path.substring(0, photo.path.length - 4);
        final video = File('$stem.mp4');
        if (await video.exists()) result.add(LiveItem(photo, video));
      }
      if (mounted) setState(() => _items = result);
    } catch (_) {}
  }

  Future<void> _initializeCamera({CameraDescription? selected}) async {
    if (mounted) {
      setState(() {
        _initializing = true;
        _error = null;
      });
    }
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) throw Exception('لم يتم العثور على كاميرا في الجهاز');
      final camera = selected ??
          _cameras.firstWhere(
            (c) => c.lensDirection == CameraLensDirection.back,
            orElse: () => _cameras.first,
          );

      final controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      await controller.setFlashMode(_flashMode);
      final old = _camera;
      if (mounted) {
        setState(() {
          _camera = controller;
          _initializing = false;
        });
      } else {
        await controller.dispose();
      }
      await old?.dispose();
    } catch (e) {
      if (mounted) {
        setState(() {
          _initializing = false;
          _error = 'تعذر تشغيل الكاميرا: $e';
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final camera = _camera;
    if (camera == null) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      camera.dispose();
      _camera = null;
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<void> _switchCamera() async {
    if (_capturing || _cameras.length < 2) return;
    final current = _camera?.description;
    final next = _cameras.firstWhere(
      (c) => c.lensDirection != current?.lensDirection,
      orElse: () => _cameras.first,
    );
    await _initializeCamera(selected: next);
  }

  Future<void> _toggleFlash() async {
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized) return;
    final next = _flashMode == FlashMode.off ? FlashMode.torch : FlashMode.off;
    try {
      await camera.setFlashMode(next);
      if (mounted) setState(() => _flashMode = next);
    } catch (e) {
      _message('الفلاش غير متاح في هذه الكاميرا');
    }
  }

  Future<void> _captureLivePhoto() async {
    final camera = _camera;
    if (camera == null ||
        !camera.value.isInitialized ||
        _capturing ||
        camera.value.isRecordingVideo) {
      return;
    }

    setState(() {
      _capturing = true;
      _countdown = 'LIVE';
    });

    XFile? videoFile;
    XFile? photoFile;
    try {
      final dir = await _liveDirectory();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final photoPath = '${dir.path}/live_$stamp.jpg';
      final videoPath = '${dir.path}/live_$stamp.mp4';

      if (_liveMode) {
        // Record a short clip. The still photo is captured at the midpoint.
        // This requires a camera implementation that supports still capture
        // while video recording is active.
        await camera.startVideoRecording();
        await Future.delayed(const Duration(milliseconds: 1500));
        if (mounted) setState(() => _countdown = '📸');
        photoFile = await camera.takePicture();
        await Future.delayed(const Duration(milliseconds: 1500));
        videoFile = await camera.stopVideoRecording();
        await File(photoFile.path).copy(photoPath);
        await File(videoFile.path).copy(videoPath);
      } else {
        photoFile = await camera.takePicture();
        await File(photoFile.path).copy(photoPath);
      }

      if (_savingToGallery) {
        try {
          await Gal.putImage(photoPath);
          if (_liveMode) await Gal.putVideo(videoPath);
        } catch (e) {
          _message('تم الحفظ داخل التطبيق، لكن تعذر الحفظ في معرض الهاتف. تحقق من إذن الصور والفيديو.');
        }
      }

      await _loadItems();
      if (mounted) {
        _message(_liveMode
            ? 'تم حفظ Live Photo داخل التطبيق${_savingToGallery ? ' ومعرض الهاتف' : ''}'
            : 'تم حفظ الصورة');
      }
    } catch (e) {
      // If still capture during recording is unsupported, stop the recording
      // cleanly and explain the limitation rather than creating a false pair.
      try {
        if (camera.value.isRecordingVideo) {
          videoFile = await camera.stopVideoRecording();
        }
      } catch (_) {}
      if (mounted) {
        _message('لم يكتمل التصوير: $e. قد لا يدعم إصدار الكاميرا التقاط صورة أثناء تسجيل الفيديو.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _capturing = false;
          _countdown = '';
        });
      }
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating));
  }

  Future<void> _openGallery() async {
    await _loadItems();
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LiveGalleryPage(items: _items),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _camera?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
              child: Row(
                children: [
                  const Icon(Icons.camera_alt_rounded, color: Color(0xFF75A7FF), size: 27),
                  const SizedBox(width: 9),
                  const Expanded(
                    child: Text('LIVE PHOTO', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                  ),
                  IconButton(
                    tooltip: 'المعرض',
                    onPressed: _openGallery,
                    icon: const Icon(Icons.photo_library_outlined, size: 27),
                  ),
                  IconButton(
                    tooltip: 'الإعدادات',
                    onPressed: () => showModalBottomSheet(
                      context: context,
                      backgroundColor: const Color(0xFF171D2A),
                      builder: (ctx) => StatefulBuilder(
                        builder: (ctx, setSheet) => Padding(
                          padding: const EdgeInsets.all(22),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('الإعدادات', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                              SwitchListTile(
                                title: const Text('حفظ نسخة في معرض الهاتف'),
                                value: _savingToGallery,
                                onChanged: (v) {
                                  setState(() => _savingToGallery = v);
                                  setSheet(() {});
                                },
                              ),
                              const SizedBox(height: 12),
                            ],
                          ),
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.tune_rounded),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (camera != null && camera.value.isInitialized)
                        CameraPreview(camera)
                      else
                        Container(
                          color: const Color(0xFF141A25),
                          child: Center(
                            child: _initializing
                                ? const CircularProgressIndicator()
                                : Text(_error ?? 'الكاميرا غير جاهزة', textAlign: TextAlign.center),
                          ),
                        ),
                      Positioned(
                        top: 16,
                        left: 16,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(color: Colors.black.withOpacity(.55), borderRadius: BorderRadius.circular(30)),
                          child: Row(
                            children: [
                              Icon(Icons.circle, color: _liveMode ? Colors.redAccent : Colors.white54, size: 9),
                              const SizedBox(width: 6),
                              Text(_liveMode ? 'LIVE' : 'PHOTO', style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
                            ],
                          ),
                        ),
                      ),
                      if (_capturing)
                        Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                            decoration: BoxDecoration(color: Colors.black.withOpacity(.65), borderRadius: BorderRadius.circular(18)),
                            child: Text(_countdown, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      Positioned(
                        right: 14,
                        top: 12,
                        child: _roundIcon(
                          icon: _flashMode == FlashMode.off ? Icons.flash_off : Icons.flash_on,
                          onTap: _toggleFlash,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _modeButton('PHOTO', !_liveMode, () => setState(() => _liveMode = false)),
                const SizedBox(width: 16),
                _modeButton('LIVE PHOTO', _liveMode, () => setState(() => _liveMode = true)),
              ],
            ),
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 22),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: _openGallery,
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(color: Colors.white24, width: 2),
                        image: _items.isNotEmpty
                            ? DecorationImage(image: FileImage(_items.first.photo), fit: BoxFit.cover)
                            : null,
                      ),
                      child: _items.isEmpty ? const Icon(Icons.photo_library_outlined) : null,
                    ),
                  ),
                  GestureDetector(
                    onTap: _captureLivePhoto,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 78,
                      height: 78,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 5),
                      ),
                      child: Center(
                        child: Container(
                          width: _capturing ? 42 : 58,
                          height: _capturing ? 42 : 58,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _capturing ? Colors.grey : Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                  _roundIcon(icon: Icons.flip_camera_ios_rounded, onTap: _switchCamera, size: 52),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _modeButton(String text, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF285FC5) : Colors.transparent,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: selected ? Colors.white : Colors.white60)),
      ),
    );
  }

  Widget _roundIcon({required IconData icon, required VoidCallback onTap, double size = 42}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: Colors.black.withOpacity(.48), shape: BoxShape.circle, border: Border.all(color: Colors.white24)),
        child: Icon(icon, color: Colors.white, size: 23),
      ),
    );
  }
}

class LiveGalleryPage extends StatelessWidget {
  final List<LiveItem> items;
  const LiveGalleryPage({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الصور الحية')),
      body: items.isEmpty
          ? const Center(child: Text('لا توجد صور حتى الآن'))
          : GridView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: items.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: .82,
              ),
              itemBuilder: (context, index) {
                final item = items[index];
                return InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => LiveViewerPage(item: item)),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.file(item.photo, fit: BoxFit.cover),
                        Positioned(
                          top: 9,
                          left: 9,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                            decoration: BoxDecoration(color: Colors.black.withOpacity(.6), borderRadius: BorderRadius.circular(20)),
                            child: const Row(children: [Icon(Icons.motion_photos_on, size: 14), SizedBox(width: 4), Text('LIVE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold))]),
                          ),
                        ),
                        const Positioned(bottom: 9, right: 9, child: Icon(Icons.play_circle_fill, size: 30, color: Colors.white)),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class LiveViewerPage extends StatefulWidget {
  final LiveItem item;
  const LiveViewerPage({super.key, required this.item});

  @override
  State<LiveViewerPage> createState() => _LiveViewerPageState();
}

class _LiveViewerPageState extends State<LiveViewerPage> {
  VideoPlayerController? _player;
  bool _playing = false;
  bool _showVideo = false;

  @override
  void initState() {
    super.initState();
    _player = VideoPlayerController.file(widget.item.video)
      ..initialize().then((_) {
        if (mounted) setState(() {});
      });
    _player!.addListener(() {
      if (mounted) setState(() => _playing = _player!.value.isPlaying);
    });
  }

  Future<void> _playLive() async {
    final player = _player;
    if (player == null || !player.value.isInitialized) return;
    setState(() => _showVideo = true);
    await player.seekTo(Duration.zero);
    await player.play();
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = _player;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, title: const Text('LIVE PHOTO')),
      body: Center(
        child: GestureDetector(
          onTap: _playing ? () => player?.pause() : _playLive,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (_showVideo && player != null && player.value.isInitialized)
                AspectRatio(aspectRatio: player.value.aspectRatio, child: VideoPlayer(player))
              else
                Image.file(widget.item.photo, fit: BoxFit.contain),
              if (!_playing)
                Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(color: Colors.black.withOpacity(.55), shape: BoxShape.circle),
                  child: const Icon(Icons.play_arrow_rounded, size: 42, color: Colors.white),
                ),
              Positioned(
                bottom: 22,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(color: Colors.black.withOpacity(.55), borderRadius: BorderRadius.circular(20)),
                  child: const Text('اضغط لتشغيل الصورة الحية'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
