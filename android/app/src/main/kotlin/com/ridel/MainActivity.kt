package com.ridel

import android.content.Intent // 🚀 NAYA ADD KIYA: Doosri screen kholne ke liye
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    // 🚀 THE BRIDGE: Same naam jo Flutter me diya tha
    private val CHANNEL = "com.ridel/ola_nav"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // 🎧 Flutter se aane wale orders ko sunna
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            
            if (call.method == "startOlaNavigation") {
                // 1. Flutter se coordinates nikalna
                val originLat = call.argument<Double>("originLat") ?: 0.0
                val originLng = call.argument<Double>("originLng") ?: 0.0
                val destLat = call.argument<Double>("destLat") ?: 0.0
                val destLng = call.argument<Double>("destLng") ?: 0.0
                
                println("🚀 Android: Order Received! Navigating from ($originLat, $originLng) to ($destLat, $destLng)")
                
                // 🔥 THE MAGIC: Native Ola Screen ko start karna
                val intent = Intent(this@MainActivity, OlaNavigationActivity::class.java)
                intent.putExtra("originLat", originLat)
                intent.putExtra("originLng", originLng)
                intent.putExtra("destLat", destLat)
                intent.putExtra("destLng", destLng)
                startActivity(intent)

                result.success("Native 3D Map Opened!")
            } else {
                result.notImplemented()
            }
        }
    }
}