package `in`.ridel

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import `in`.ridel.R

// Standard Ola Maps Imports
import com.ola.maps.navigation.v5.*
import com.ola.maps.navigation.v5.navigation.*
import com.ola.maps.navigation.ui.v5.*

// 🚀 THE MAGIC IMPORT (Jo humne decompile karke nikala!)
import com.ola.maps.mapslibrary.models.OlaMapsConfig

class OlaNavigationActivity : AppCompatActivity(), MapStatusCallback {

    private var olaMapView: OlaMapView? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_ola_navigation)

        olaMapView = findViewById(R.id.olaMapView)
        olaMapView?.onCreate(savedInstanceState)

        // Ab compiler ko exactly pata hai OlaMapsConfig kahan se lana hai
        olaMapView?.initialize(
            this,
            OlaMapsConfig.Builder(applicationContext)
                .setMapBaseUrl("https://api.olamaps.io")
                .setApiKey("LXLK4nwQMwacpTZhol7QHc3RPet3tUOkb76reivs")
                .setProjectId("RidelNav")
                .build()
        )
    }

    override fun onMapLoadFailed(error: String?) {
        println("❌ OLA MAP LOAD FAILED: $error")
    }

    override fun onMapReady() {
        println("✅ OLA 3D MAP IS READY!")

        val oLat = intent.getDoubleExtra("originLat", 0.0)
        val oLng = intent.getDoubleExtra("originLng", 0.0)
        val dLat = intent.getDoubleExtra("destLat", 0.0)
        val dLng = intent.getDoubleExtra("destLng", 0.0)
    }

    override fun onStart() { super.onStart(); olaMapView?.onStart() }
    override fun onResume() { super.onResume(); olaMapView?.onResume() }
    override fun onPause() { super.onPause(); olaMapView?.onPause() }
    override fun onStop() { super.onStop(); olaMapView?.onStop() }
    override fun onDestroy() { super.onDestroy(); olaMapView?.onDestroy() }
}