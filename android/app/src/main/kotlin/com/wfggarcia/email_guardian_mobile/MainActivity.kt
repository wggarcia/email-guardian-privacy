package com.wfggarcia.email_guardian_mobile

import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onResume() {
        super.onResume()
        // Edge-to-edge para Android 15+ — substitui setStatusBarColor/setNavigationBarColor (deprecated)
        WindowCompat.setDecorFitsSystemWindows(window, false)
    }
}
