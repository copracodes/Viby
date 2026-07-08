package com.copra.viby

import android.os.Bundle
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import com.ryanheise.audioservice.AudioServiceActivity

// audio_service requires the host Activity to extend AudioServiceActivity (not
// the stock FlutterActivity) so the background audio handler and the UI share a
// single cached FlutterEngine. Without this, AudioService.init() throws
// "The Activity class declared in your AndroidManifest.xml is wrong...".
class MainActivity : AudioServiceActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // Install the Android 12+ system splash (backported by core-splashscreen)
        // before super.onCreate so the splash theme hands off to NormalTheme.
        installSplashScreen()
        super.onCreate(savedInstanceState)
    }
}
