package detached.totals

import android.app.Activity
import android.content.Intent
import android.os.Bundle

class ShortcutActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Android clears the first static-shortcut task. This activity's empty
        // task affinity keeps that clear away from the running Flutter task.
        try {
            forwardShortcut(intent)
        } finally {
            finish()
        }
    }

    private fun forwardShortcut(sourceIntent: Intent?) {
        val shortcutUri = sourceIntent?.data ?: return
        if (
            shortcutUri.scheme != MainActivity.SHORTCUT_SCHEME ||
            shortcutUri.host != MainActivity.SHORTCUT_HOST ||
            shortcutUri.pathSegments.firstOrNull().isNullOrBlank()
        ) {
            return
        }

        startActivity(
            Intent(this, MainActivity::class.java).apply {
                action = Intent.ACTION_VIEW
                data = shortcutUri
                // Bring the existing Totals task forward and deliver through
                // MainActivity.onNewIntent() without recreating Flutter.
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
        )
    }
}
