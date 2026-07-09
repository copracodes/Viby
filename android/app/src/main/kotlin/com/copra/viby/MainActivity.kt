package com.copra.viby

import android.database.ContentObserver
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel

// audio_service requires the host Activity to extend AudioServiceActivity (not
// the stock FlutterActivity) so the background audio handler and the UI share a
// single cached FlutterEngine. Without this, AudioService.init() throws
// "The Activity class declared in your AndroidManifest.xml is wrong...".
class MainActivity : AudioServiceActivity() {
    private var mediaObserver: ContentObserver? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // Install the Android 12+ system splash (backported by core-splashscreen)
        // before super.onCreate so the splash theme hands off to NormalTheme.
        installSplashScreen()
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Bridge MediaStore audio changes to Dart. on_audio_query is pull-only —
        // it has no change notifications — so we register a ContentObserver on the
        // audio content URI and forward each onChange tick over an EventChannel.
        // The Dart side debounces and runs a cheap incremental rescan, so newly
        // downloaded / synced music appears within seconds with no user action.
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, MEDIA_OBSERVER_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    val observer = object : ContentObserver(Handler(Looper.getMainLooper())) {
                        override fun onChange(selfChange: Boolean) = onChange(selfChange, null)
                        override fun onChange(selfChange: Boolean, uri: Uri?) {
                            events?.success(null)
                        }
                    }
                    mediaObserver = observer
                    contentResolver.registerContentObserver(
                        MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                        true,
                        observer,
                    )
                }

                override fun onCancel(arguments: Any?) {
                    mediaObserver?.let { contentResolver.unregisterContentObserver(it) }
                    mediaObserver = null
                }
            })
    }

    override fun onDestroy() {
        mediaObserver?.let { contentResolver.unregisterContentObserver(it) }
        mediaObserver = null
        super.onDestroy()
    }

    companion object {
        private const val MEDIA_OBSERVER_CHANNEL = "com.copra.viby/media_observer"
    }
}
