
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LivePhotoApp());
}

const cameraChannel = MethodChannel('live_photo/camera');

class LivePhotoApp extends StatelessWidget {
  const LivePhotoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'LIVE PHOTO CAMERA',
      theme: ThemeData.dark(useMaterial3: true),
      home: const CameraScreen(),
    );
  }
}

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  bool liveOn = true;
  bool flashOn = false;
  bool busy = false;

  Future<void> callCamera(
    String method, [
    Map<String, dynamic>? args,
  ]) async {
    try {
      await cameraChannel.invokeMethod(method, args);
    } on PlatformException catch (e) {
      showMessage(e.message ?? 'حدث خطأ في الكاميرا');
    }
  }

  void showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            textAlign: TextAlign.center,
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> takePhoto() async {
    if (busy) return;

    setState(() => busy = true);

    try {
      final result = await cameraChannel.invokeMethod<String>(
        'captureMotionPhoto',
        {'enabled': liveOn},
      );

      showMessage(result ?? 'تم حفظ الصورة بنجاح');
    } on PlatformException catch (e) {
      showMessage(e.message ?? 'فشل التصوير');
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> toggleFlash() async {
    final next = !flashOn;

    await callCamera(
      'setFlash',
      {'enabled': next},
    );

    if (mounted) {
      setState(() => flashOn = next);
    }
  }

  Future<void> switchCamera() async {
    await callCamera('switchCamera');

    if (mounted) {
      setState(() => flashOn = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 65,
              child: Row(
                mainAxisAlignment:
                    MainAxisAlignment.spaceAround,
                children: [
                  IconButton(
                    onPressed: toggleFlash,
                    icon: Icon(
                      flashOn
                          ? Icons.flash_on
                          : Icons.flash_off,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),

                  GestureDetector(
                    onTap: () {
                      setState(() => liveOn = !liveOn);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 17,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF292929),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.motion_photos_on,
                            color: liveOn
                                ? Colors.yellow
                                : Colors.white54,
                            size: 19,
                          ),
                          const SizedBox(width: 7),
                          Text(
                            liveOn ? 'LIVE' : 'LIVE OFF',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  IconButton(
                    onPressed: () {
                      showMessage(
                        'ميزة التعريض قيد التطوير',
                      );
                    },
                    icon: const Icon(
                      Icons.exposure,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 7,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      const AndroidView(
                        viewType: 'live_photo/camera_preview',
                        creationParams: {},
                        creationParamsCodec:
                            StandardMessageCodec(),
                      ),

                      if (busy)
                        Container(
                          color: Colors.black38,
                          child: const Center(
                            child: CircularProgressIndicator(
                              color: Colors.white,
                            ),
                          ),
                        ),

                      Positioned(
                        bottom: 20,
                        left: 0,
                        right: 0,
                        child: Text(
                          liveOn ? 'LIVE PHOTO' : 'PHOTO',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 3,
                            shadows: [
                              Shadow(
                                blurRadius: 8,
                                color: Colors.black,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 18),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Text(
                  'VIDEO',
                  style: TextStyle(color: Colors.white54),
                ),
                SizedBox(width: 30),
                Text(
                  'PHOTO',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(width: 30),
                Text(
                  'PORTRAIT',
                  style: TextStyle(color: Colors.white54),
                ),
              ],
            ),

            const SizedBox(height: 22),

            Padding(
              padding: const EdgeInsets.fromLTRB(
                30, 0, 30, 25,
              ),
              child: Row(
                mainAxisAlignment:
                    MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFF252525),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: IconButton(
                      onPressed: () {
                        showMessage(
                          'افتح Google Photos أو المعرض لمشاهدة صورك',
                        );
                      },
                      icon: const Icon(
                        Icons.photo_library,
                        color: Colors.white,
                      ),
                    ),
                  ),

                  GestureDetector(
                    onTap: takePhoto,
                    child: Container(
                      width: 83,
                      height: 83,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white,
                          width: 5,
                        ),
                      ),
                      child: Center(
                        child: Container(
                          width: 65,
                          height: 65,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),

                  GestureDetector(
                    onTap: switchCamera,
                    child: Container(
                      width: 49,
                      height: 49,
                      decoration: const BoxDecoration(
                        color: Color(0xFF252525),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.cameraswitch,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
