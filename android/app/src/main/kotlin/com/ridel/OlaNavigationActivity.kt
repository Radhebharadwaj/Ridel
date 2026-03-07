package com.ridel

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import com.ola.maps.navigation.v5.navigation.OlaMapView
import com.ola.maps.navigation.v5.navigation.listeners.MapStatusCallback
import com.ola.maps.navigation.v5.navigation.OlaMapsConfig

class OlaNavigationActivity : AppCompatActivity(), MapStatusCallback {
    
    private var olaMapView: OlaMapView? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_ola_navigation)

        olaMapView = findViewById(R.id.olaMapView)
        olaMapView?.onCreate(savedInstanceState)

        // 🚀 Initialize SDK
        olaMapView?.initialize(
            mapStatusCallback = this,
            olaMapsConfig = OlaMapsConfig.Builder(applicationContext)
                .setMapBaseUrl("https://api.olamaps.io")
                .setApiKey("LXLK4nwQMwacpTZhol7QHc3RPet3tUOkb76reivs") 
                .setProjectId("RidelNav")
                .build()
        )
    }

    override fun onMapReady() {
        println("✅ OLA 3D MAP IS READY!")
        
        // 1. Get Coordinates from Flutter (MainActivity)
        val oLat = intent.getDoubleExtra("originLat", 0.0)
        val oLng = intent.getDoubleExtra("originLng", 0.0)
        val dLat = intent.getDoubleExtra("destLat", 0.0)
        val dLng = intent.getDoubleExtra("destLng", 0.0)

        // (Agle step me hum yahan Turn-by-Turn start karne ka route fetch karenge)
    }

    // Lifecycle methods (Map ko crash hone se bachane ke liye)
    override fun onStart() { super.onStart(); olaMapView?.onStart() }
    override fun onResume() { super.onResume(); olaMapView?.onResume() }
    override fun onPause() { super.onPause(); olaMapView?.onPause() }
    override fun onStop() { super.onStop(); olaMapView?.onStop() }
    override fun onDestroy() { super.onDestroy(); olaMapView?.onDestroy() }
}