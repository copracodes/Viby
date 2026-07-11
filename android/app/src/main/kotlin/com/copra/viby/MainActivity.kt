package com.copra.viby

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.database.ContentObserver
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.provider.MediaStore
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

// audio_service requires the host Activity to extend AudioServiceActivity (not
// the stock FlutterActivity) so the background audio handler and the UI share a
// single cached FlutterEngine. Without this, AudioService.init() throws
// "The Activity class declared in your AndroidManifest.xml is wrong...".
class MainActivity : AudioServiceActivity() {
    private var mediaObserver: ContentObserver? = null

    // The pending Flutter result awaiting the ACTION_OPEN_DOCUMENT_TREE picker.
    private var pendingPickResult: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // Install the Android 12+ system splash (backported by core-splashscreen)
        // before super.onCreate so the splash theme hands off to NormalTheme.
        installSplashScreen()
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        registerMediaObserver(flutterEngine)
        registerLyricsSaf(flutterEngine)
        registerConnectivity(flutterEngine)
    }

    // Reports whether the active network is unmetered (Wi-Fi / Ethernet), for the
    // "Wi-Fi only" online-lyrics gate. Uses ConnectivityManager directly so we
    // don't take a third-party connectivity dependency.
    private fun registerConnectivity(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CONNECTIVITY_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "isUnmetered") {
                    result.success(isUnmetered())
                } else {
                    result.notImplemented()
                }
            }
    }

    private fun isUnmetered(): Boolean {
        return try {
            val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            val caps = cm.getNetworkCapabilities(cm.activeNetwork) ?: return false
            caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED) ||
                caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ||
                caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)
        } catch (_: Exception) {
            true // fail-open (tiny payloads)
        }
    }

    // Bridge MediaStore audio changes to Dart. on_audio_query is pull-only — it
    // has no change notifications — so we register a ContentObserver on the audio
    // content URI and forward each onChange tick over an EventChannel. The Dart
    // side debounces and runs a cheap incremental rescan, so newly downloaded /
    // synced music appears within seconds with no user action.
    private fun registerMediaObserver(flutterEngine: FlutterEngine) {
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

    // Lyrics sidecar (.lrc) reads. A .lrc is a *non-media* file, so scoped storage
    // on Android 13+ blocks a bare File() read (EACCES). Instead the user grants a
    // folder once via ACTION_OPEN_DOCUMENT_TREE (persistable URI permission) and we
    // read sidecars through the Storage Access Framework — no broad storage
    // permission required.
    private fun registerLyricsSaf(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LYRICS_SAF_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickFolder" -> pickFolder(result)
                    "hasAccess" -> {
                        val tree = call.argument<String>("treeUri")
                        result.success(tree != null && hasPersistedPermission(tree))
                    }
                    "readSidecar" -> {
                        val tree = call.argument<String>("treeUri")
                        val absPath = call.argument<String>("absPath")
                        val sidecarName = call.argument<String>("sidecarName")
                        if (tree == null) {
                            result.success(null)
                        } else {
                            // Read off the main thread (small file, but never do
                            // disk I/O on the UI thread) and post the bytes back.
                            Thread {
                                val bytes = readSidecar(tree, absPath, sidecarName)
                                runOnUiThread { result.success(bytes) }
                            }.start()
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun pickFolder(result: MethodChannel.Result) {
        if (pendingPickResult != null) {
            result.error("busy", "A folder pick is already in progress", null)
            return
        }
        pendingPickResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
            )
        }
        try {
            startActivityForResult(intent, REQ_PICK_LYRICS_FOLDER)
        } catch (e: Exception) {
            pendingPickResult = null
            result.error("no_picker", e.message, null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQ_PICK_LYRICS_FOLDER) return
        val reply = pendingPickResult
        pendingPickResult = null
        val uri = data?.data
        if (resultCode == Activity.RESULT_OK && uri != null) {
            try {
                contentResolver.takePersistableUriPermission(
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION,
                )
            } catch (_: Exception) {
                // Non-fatal: without persistable permission access lasts only this
                // process, which still works for the current session.
            }
            reply?.success(uri.toString())
        } else {
            reply?.success(null) // user cancelled
        }
    }

    private fun hasPersistedPermission(treeUri: String): Boolean {
        val uri = Uri.parse(treeUri)
        return contentResolver.persistedUriPermissions.any {
            it.uri == uri && it.isReadPermission
        }
    }

    // Reads the first readable sidecar candidate under the granted [treeUri]:
    // (1) the same-directory `.lrc` (from its absolute path) and (2) a
    // `<grantedRoot>/Lyrics/<name>.lrc`. Returns the bytes or null.
    private fun readSidecar(
        treeUri: String,
        absPath: String?,
        sidecarName: String?,
    ): ByteArray? {
        val tree = Uri.parse(treeUri)
        val rootDocId = try {
            DocumentsContract.getTreeDocumentId(tree)
        } catch (e: Exception) {
            return null
        }
        val candidateDocIds = mutableListOf<String>()
        absPath?.let { pathToPrimaryDocId(it)?.let(candidateDocIds::add) }
        if (sidecarName != null) candidateDocIds.add("$rootDocId/Lyrics/$sidecarName")

        for (docId in candidateDocIds) {
            try {
                val docUri = DocumentsContract.buildDocumentUriUsingTree(tree, docId)
                contentResolver.openInputStream(docUri)?.use { return it.readBytes() }
            } catch (_: Exception) {
                // Not present or outside the granted subtree — try the next.
            }
        }
        return null
    }

    // Maps a primary-shared-storage absolute path to an externalstorage document
    // id (`primary:<relative>`). Returns null for other volumes (SD cards etc.),
    // which v1 does not resolve.
    private fun pathToPrimaryDocId(path: String): String? {
        val prefixes = listOf(
            "/storage/emulated/0/",
            "/sdcard/",
            "/storage/self/primary/",
        )
        for (p in prefixes) {
            if (path.startsWith(p)) return "primary:" + path.substring(p.length)
        }
        return null
    }

    override fun onDestroy() {
        mediaObserver?.let { contentResolver.unregisterContentObserver(it) }
        mediaObserver = null
        super.onDestroy()
    }

    companion object {
        private const val MEDIA_OBSERVER_CHANNEL = "com.copra.viby/media_observer"
        private const val LYRICS_SAF_CHANNEL = "com.copra.viby/lyrics_saf"
        private const val CONNECTIVITY_CHANNEL = "com.copra.viby/connectivity"
        private const val REQ_PICK_LYRICS_FOLDER = 0x4C7C // "LRC" pick request
    }
}
