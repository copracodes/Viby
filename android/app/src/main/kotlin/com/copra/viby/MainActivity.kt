package com.copra.viby

import com.ryanheise.audioservice.AudioServiceActivity

// audio_service requires the host Activity to extend AudioServiceActivity (not
// the stock FlutterActivity) so the background audio handler and the UI share a
// single cached FlutterEngine. Without this, AudioService.init() throws
// "The Activity class declared in your AndroidManifest.xml is wrong...".
class MainActivity : AudioServiceActivity()
