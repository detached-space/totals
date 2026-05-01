package detached.totals

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.shounakmulay.telephony.sms.IncomingSmsHandler
import com.shounakmulay.telephony.sms.IncomingSmsReceiver

class SafeIncomingSmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent == null) return

        try {
            if (!canDelegateToTelephonyReceiver(context)) {
                Log.w(TAG, "Dropping background SMS because Telephony callbacks are not registered")
                return
            }

            IncomingSmsReceiver().onReceive(context, intent)
        } catch (throwable: Throwable) {
            disableTelephonyBackgroundProcessing(context)
            Log.e(TAG, "Telephony SMS receiver failed; background SMS was dropped", throwable)
        }
    }

    private fun canDelegateToTelephonyReceiver(context: Context): Boolean {
        val preferences = context.getSharedPreferences(
            TELEPHONY_SHARED_PREFERENCES,
            Context.MODE_PRIVATE
        )

        if (preferences.getBoolean(TELEPHONY_BACKGROUND_DISABLED, false)) {
            return true
        }

        if (IncomingSmsReceiver.foregroundSmsChannel != null && isAppForeground(context)) {
            return true
        }

        val setupHandle = preferences.getLong(TELEPHONY_BACKGROUND_SETUP_HANDLE, 0L)
        val messageHandle = preferences.getLong(TELEPHONY_BACKGROUND_MESSAGE_HANDLE, 0L)
        return setupHandle > 0L && messageHandle > 0L
    }

    private fun isAppForeground(context: Context): Boolean {
        return try {
            IncomingSmsHandler.isApplicationForeground(context)
        } catch (_: Throwable) {
            false
        }
    }

    private fun disableTelephonyBackgroundProcessing(context: Context) {
        context.getSharedPreferences(TELEPHONY_SHARED_PREFERENCES, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(TELEPHONY_BACKGROUND_DISABLED, true)
            .apply()
    }

    private companion object {
        private const val TAG = "TotalsSmsReceiver"
        private const val TELEPHONY_SHARED_PREFERENCES =
            "com.shounakmulay.android_telephony_plugin"
        private const val TELEPHONY_BACKGROUND_SETUP_HANDLE = "background_setup_handle"
        private const val TELEPHONY_BACKGROUND_MESSAGE_HANDLE = "background_message_handle"
        private const val TELEPHONY_BACKGROUND_DISABLED = "disable_background"
    }
}
