package com.tool.devbox

import android.app.Application
import android.content.Context
import android.content.Intent
import android.net.wifi.WifiManager
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.util.Log
import ffi.FFI

class MainApplication : Application() {
    companion object {
        private const val TAG = "MainApplication"
        private val WIFI_FOREGROUND_INTERVAL = 3 * 60 * 1000L
        private var wifiForegroundRunnable: Runnable? = null
        private var wifiForegroundHandler: Handler? = null
    }

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "App start")
        FFI.onAppStart(applicationContext)
        startWifiForegroundLoop()
    }

    private fun startWifiForegroundLoop() {
        stopWifiForegroundLoop()
        val thread = HandlerThread("wifiForeground", android.os.Process.THREAD_PRIORITY_BACKGROUND)
        thread.start()
        val handler = Handler(thread.looper)
        wifiForegroundHandler = handler
        val runnable = object : Runnable {
            override fun run() {
                checkWifiAndPullForeground()
                handler.postDelayed(this, WIFI_FOREGROUND_INTERVAL)
            }
        }
        wifiForegroundRunnable = runnable
        handler.postDelayed(runnable, WIFI_FOREGROUND_INTERVAL)
        Log.d(TAG, "wifi foreground loop started")
    }

    private fun stopWifiForegroundLoop() {
        wifiForegroundRunnable?.let { wifiForegroundHandler?.removeCallbacks(it) }
        wifiForegroundRunnable = null
        wifiForegroundHandler?.looper?.quitSafely()
        wifiForegroundHandler = null
    }

    private fun checkWifiAndPullForeground() {
        if (!InputService.isOpen) {
            Log.d(TAG, "wifi fg skip, accessibility off")
            return
        }
        if (SCREEN_INFO.width != WIFI_TARGET_WIDTH || SCREEN_INFO.height != WIFI_TARGET_HEIGHT) {
            Log.d(TAG, "wifi fg skip, screen ${SCREEN_INFO.width}x${SCREEN_INFO.height}")
            return
        }
        val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        if (wifiManager.isWifiEnabled) {
            Log.d(TAG, "wifi fg skip, wifi already on")
            return
        }
        Log.d(TAG, "wifi off, pull MainActivity to foreground")
        try {
            startActivity(Intent(this, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            })
        } catch (e: Exception) {
            Log.e(TAG, "pull foreground error: $e")
        }
    }
}