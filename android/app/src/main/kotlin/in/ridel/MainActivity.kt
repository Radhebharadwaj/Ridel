package `in`.ridel

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "in.ridel/ola_nav"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            // ... (Tera Ola Navigation wala code waise hi rahega)
            if (call.method == "startOlaNavigation") {
                val originLat = call.argument<Double>("originLat") ?: 0.0
                val originLng = call.argument<Double>("originLng") ?: 0.0
                val destLat = call.argument<Double>("destLat") ?: 0.0
                val destLng = call.argument<Double>("destLng") ?: 0.0
                
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