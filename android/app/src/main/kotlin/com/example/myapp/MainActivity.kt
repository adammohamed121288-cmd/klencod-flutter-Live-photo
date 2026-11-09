package com.example.myapp


import android.Manifest
import android.app.Activity
import android.content.ContentValues
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.view.View
import androidx.camera.core.Camera
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.video.FileOutputOptions
import androidx.camera.video.Quality
import androidx.camera.video.QualitySelector
import androidx.camera.video.Recorder
import androidx.camera.video.VideoCapture
import androidx.camera.video.VideoRecordEvent
import androidx.camera.view.PreviewView
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.charset.Charset
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {

    private var cameraView: MotionCameraView? = null

    override fun configureFlutterEngine(
        flutterEngine: FlutterEngine
    ) {
        super.configureFlutterEngine(flutterEngine)

        flutterEngine.platformViewsController.registry
            .registerViewFactory(
                "live_photo/camera_preview",
                CameraViewFactory(this) {
                    cameraView = it
                }
            )

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "live_photo/camera"
        ).setMethodCallHandler { call, result ->

            val cam = cameraView

            if (cam == null) {
                result.error(
                    "CAMERA_NOT_READY",
                    "الكاميرا غير جاهزة",
                    null
                )
                return@setMethodCallHandler
            }

            when (call.method) {

                "captureMotionPhoto" -> {
                    cam.captureMotionPhoto(
                        call.argument<Boolean>("enabled") ?: true,
                        result
                    )
                }

                "setFlash" -> {
                    cam.setFlash(
                        call.argument<Boolean>("enabled") ?: false
                    )
                    result.success(null)
                }

                "switchCamera" -> {
                    cam.switchCamera()
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(
            requestCode,
            permissions,
            grantResults
        )

        if (requestCode == 701 &&
            grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        ) {
            cameraView?.startCamera()
        }
    }
}

private class CameraViewFactory(
    private val activity: MainActivity,
    private val onCreated: (MotionCameraView) -> Unit
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    override fun create(
        context: android.content.Context,
        viewId: Int,
        args: Any?
    ): PlatformView {
        return MotionCameraView(
            context,
            activity
        ).also(onCreated)
    }
}

private class MotionCameraView(
    private val context: android.content.Context,
    private val activity: Activity
) : PlatformView {

    private val preview = PreviewView(context)

    private val handler = Handler(Looper.getMainLooper())

    private val executor: ExecutorService =
        Executors.newSingleThreadExecutor()

    private var provider: ProcessCameraProvider? = null
    private var imageCapture: ImageCapture? = null
    private var videoCapture: VideoCapture<Recorder>? = null
    private var camera: Camera? = null

    private var front = false
    private var flash = false
    private var busy = false

    init {
        preview.scaleType =
            PreviewView.ScaleType.FILL_CENTER

        startCamera()
    }

    override fun getView(): View = preview

    fun startCamera() {

        if (
            ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.CAMERA
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            ActivityCompat.requestPermissions(
                activity,
                arrayOf(Manifest.permission.CAMERA),
                701
            )
            return
        }

        val future =
            ProcessCameraProvider.getInstance(context)

        future.addListener({

            try {
                provider = future.get()
                bindCamera()
            } catch (e: Exception) {
                android.util.Log.e(
                    "MotionPhoto",
                    "Camera error",
                    e
                )
            }

        }, ContextCompat.getMainExecutor(context))
    }

    private fun bindCamera() {

        val p = provider ?: return

        val previewUseCase = Preview.Builder()
            .build()
            .also {
                it.setSurfaceProvider(preview.surfaceProvider)
            }

        imageCapture = ImageCapture.Builder()
            .setCaptureMode(
                ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY
            )
            .build()

        val recorder = Recorder.Builder()
            .setQualitySelector(
                QualitySelector.from(Quality.SD)
            )
            .build()

        videoCapture = VideoCapture.withOutput(recorder)

        val selector =
            if (front)
                CameraSelector.DEFAULT_FRONT_CAMERA
            else
                CameraSelector.DEFAULT_BACK_CAMERA

        try {

            p.unbindAll()

            camera = p.bindToLifecycle(
                activity as LifecycleOwner,
                selector,
                previewUseCase,
                imageCapture,
                videoCapture
            )

            camera?.cameraControl?.enableTorch(
                flash && !front
            )

        } catch (e: Exception) {

            android.util.Log.e(
                "MotionPhoto",
                "Binding failed",
                e
            )
        }
    }

    fun setFlash(enabled: Boolean) {

        flash = enabled

        try {
            camera?.cameraControl?.enableTorch(
                enabled && !front
            )
        } catch (_: Exception) {}
    }

    fun switchCamera() {

        front = !front
        flash = false

        bindCamera()
    }

    fun captureMotionPhoto(
        enabled: Boolean,
        result: MethodChannel.Result
    ) {

        if (busy) {
            result.error(
                "BUSY",
                "انتظر انتهاء التصوير",
                null
            )
            return
        }

        val capture = imageCapture
        val video = videoCapture

        if (capture == null || video == null) {
            result.error(
                "NOT_READY",
                "الكاميرا لم تجهز بعد",
                null
            )
            return
        }

        busy = true

        val stamp = System.currentTimeMillis()

        val stillFile = File(
            context.cacheDir,
            "still_$stamp.jpg"
        )

        if (!enabled) {

            val options =
                ImageCapture.OutputFileOptions.Builder(
                    stillFile
                ).build()

            capture.takePicture(
                options,
                executor,
                object : ImageCapture.OnImageSavedCallback {

                    override fun onImageSaved(
                        output: ImageCapture.OutputFileResults
                    ) {
                        try {

                            val uri = saveImage(
                                stillFile.readBytes(),
                                stamp
                            )

                            stillFile.delete()

                            handler.post {
                                busy = false
                                result.success(
                                    "تم حفظ الصورة: $uri"
                                )
                            }

                        } catch (e: Exception) {

                            handler.post {
                                busy = false
                                result.error(
                                    "SAVE_ERROR",
                                    e.message,
                                    null
                                )
                            }
                        }
                    }

                    override fun onError(
                        exception: ImageCaptureException
                    ) {
                        handler.post {
                            busy = false
                            result.error(
                                "PHOTO_ERROR",
                                exception.message,
                                null
                            )
                        }
                    }
                }
            )

            return
        }

        val videoFile = File(
            context.cacheDir,
            "motion_$stamp.mp4"
        )

        val videoOptions =
            FileOutputOptions.Builder(videoFile).build()

        val recording = video.output
            .prepareRecording(context, videoOptions)
            .start(
                ContextCompat.getMainExecutor(context)
            ) { event ->

                if (event is VideoRecordEvent.Finalize) {

                    if (event.hasError()) {

                        stillFile.delete()
                        videoFile.delete()

                        busy = false

                        result.error(
                            "VIDEO_ERROR",
                            "فشل تسجيل الحركة",
                            null
                        )

                    } else {

                        executor.execute {

                            try {

                                val photoBytes =
                                    stillFile.readBytes()

                                val videoBytes =
                                    videoFile.readBytes()

                                val motionBytes =
                                    MotionPhotoMuxer.create(
                                        photoBytes,
                                        videoBytes
                                    )

                                val uri = saveImage(
                                    motionBytes,
                                    stamp
                                )

                                stillFile.delete()
                                videoFile.delete()

                                handler.post {

                                    busy = false

                                    result.success(
                                        "تم حفظ Motion Photo كصورة واحدة"
                                    )
                                }

                            } catch (e: Exception) {

                                handler.post {

                                    busy = false

                                    result.error(
                                        "MERGE_ERROR",
                                        e.message,
                                        null
                                    )
                                }
                            }
                        }
                    }
                }
            }

        // تسجيل جزء قبل التصوير
        handler.postDelayed({

            val options =
                ImageCapture.OutputFileOptions.Builder(
                    stillFile
                ).build()

            capture.takePicture(
                options,
                executor,
                object : ImageCapture.OnImageSavedCallback {

                    override fun onImageSaved(
                        output: ImageCapture.OutputFileResults
                    ) {
                        // تسجيل جزء بعد التصوير
                        handler.postDelayed(
                            { recording.stop() },
                            1400
                        )
                    }

                    override fun onError(
                        exception: ImageCaptureException
                    ) {
                        recording.stop()

                        handler.post {
                            busy = false
                            result.error(
                                "PHOTO_ERROR",
                                exception.message,
                                null
                            )
                        }
                    }
                }
            )

        }, 1400)
    }

    private fun saveImage(
        bytes: ByteArray,
        stamp: Long
    ): android.net.Uri {

        val filename =
            "IMG_${SimpleDateFormat(
                "yyyyMMdd_HHmmss",
                Locale.US
            ).format(Date(stamp))}MP.jpg"

        val values = android.content.ContentValues().apply {

            put(
                MediaStore.Images.Media.DISPLAY_NAME,
                filename
            )

            put(
                MediaStore.Images.Media.MIME_TYPE,
                "image/jpeg"
            )

            if (Build.VERSION.SDK_INT >= 29) {

                put(
                    MediaStore.Images.Media.RELATIVE_PATH,
                    "Pictures/Live Photo Camera"
                )

                put(
                    MediaStore.Images.Media.IS_PENDING,
                    1
                )
            }
        }

        val uri = context.contentResolver.insert(
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
            values
        ) ?: throw Exception("تعذر إنشاء الصورة")

        context.contentResolver.openOutputStream(uri)?.use {
            it.write(bytes)
        } ?: throw Exception("تعذرت كتابة الصورة")

        if (Build.VERSION.SDK_INT >= 29) {

            val done = android.content.ContentValues().apply {
                put(
                    MediaStore.Images.Media.IS_PENDING,
                    0
                )
            }

            context.contentResolver.update(
                uri,
                done,
                null,
                null
            )
        }

        return uri
    }

    override fun dispose() {

        try {
            provider?.unbindAll()
        } catch (_: Exception) {}

        executor.shutdown()
    }
}

private object MotionPhotoMuxer {

    private val header =
        "http://ns.adobe.com/xap/1.0/\u0000"
            .toByteArray(Charset.forName("UTF-8"))

    fun create(
        jpeg: ByteArray,
        mp4: ByteArray
    ): ByteArray {

        require(
            jpeg.size > 4 &&
            jpeg[0] == 0xFF.toByte() &&
            jpeg[1] == 0xD8.toByte()
        ) {
            "ملف JPEG غير صالح"
        }

        require(mp4.size > 8) {
            "ملف MP4 غير صالح"
        }

        val xml = """
            <?xpacket begin="﻿" id="W5M0MpCehiHzreSzNTczkc9d"?>
            <x:xmpmeta xmlns:x="adobe:ns:meta/">
            <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description rdf:about=""
              xmlns:Camera="http://ns.google.com/photos/1.0/camera/"
              xmlns:Container="http://ns.google.com/photos/1.0/container/"
              xmlns:Item="http://ns.google.com/photos/1.0/container/item/"
              Camera:MotionPhoto="1"
              Camera:MotionPhotoVersion="1"
              Camera:MotionPhotoPresentationTimestampUs="-1">
            <Container:Directory>
            <rdf:Seq>
            <rdf:li rdf:parseType="Resource">
            <Container:Item Item:Mime="image/jpeg"
             Item:Semantic="Primary" Item:Length="0"/>
            </rdf:li>
            <rdf:li rdf:parseType="Resource">
            <Container:Item Item:Mime="video/mp4"
             Item:Semantic="MotionPhoto"
             Item:Length="${mp4.size}"/>
            </rdf:li>
            </rdf:Seq>
            </Container:Directory>
            </rdf:Description>
            </rdf:RDF>
            </x:xmpmeta>
            <?xpacket end="w"?>
        """.trimIndent().toByteArray(
            Charset.forName("UTF-8")
        )

        val payload = header + xml

        val length = payload.size + 2

        require(length <= 65535) {
            "XMP أكبر من الحجم المسموح"
        }

        val app1 = ByteArrayOutputStream().apply {

            write(0xFF)
            write(0xE1)

            write((length shr 8) and 0xFF)
            write(length and 0xFF)

            write(payload)
        }.toByteArray()

        return ByteArrayOutputStream().apply {

            // JPEG SOI
            write(jpeg, 0, 2)

            // XMP APP1
            write(app1)

            // بقية JPEG
            write(jpeg, 2, jpeg.size - 2)

            // فيديو الحركة داخل نفس الملف
            write(mp4)

        }.toByteArray()
    }
}
