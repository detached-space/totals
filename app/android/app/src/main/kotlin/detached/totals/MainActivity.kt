package detached.totals

import android.content.Intent
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    companion object {
        const val CHANNEL_NAME = "detached.totals/widget_launch"
        const val EXTRA_LAUNCH_TARGET = "widget_launch_target"
        const val TARGET_BUDGET = "budget"
    }

    private var widgetLaunchChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        widgetLaunchChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_NAME
        )

        widgetLaunchChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "consumeLaunchTarget" -> {
                    result.success(consumeLaunchTarget(intent))
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)

        val target = consumeLaunchTarget(intent) ?: return
        widgetLaunchChannel?.invokeMethod("launchTarget", target)
    }

    private fun consumeLaunchTarget(sourceIntent: Intent?): String? {
        val target = sourceIntent?.getStringExtra(EXTRA_LAUNCH_TARGET)
        if (target != null) {
            sourceIntent.removeExtra(EXTRA_LAUNCH_TARGET)
        }
        return target
    }
}
