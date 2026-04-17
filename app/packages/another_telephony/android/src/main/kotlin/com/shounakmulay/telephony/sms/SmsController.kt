package com.shounakmulay.telephony.sms

import android.Manifest
import android.Manifest.permission.READ_PHONE_STATE
import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.telephony.*
import androidx.annotation.RequiresApi
import androidx.annotation.RequiresPermission
import androidx.core.content.ContextCompat
import androidx.core.content.ContextCompat.getSystemService
import com.shounakmulay.telephony.utils.Constants.ACTION_SMS_DELIVERED
import com.shounakmulay.telephony.utils.Constants.ACTION_SMS_SENT
import com.shounakmulay.telephony.utils.Constants.SMS_BODY
import com.shounakmulay.telephony.utils.Constants.SMS_DELIVERED_BROADCAST_REQUEST_CODE
import com.shounakmulay.telephony.utils.Constants.SMS_SENT_BROADCAST_REQUEST_CODE
import com.shounakmulay.telephony.utils.Constants.SMS_TO
import com.shounakmulay.telephony.utils.ContentUri
import java.lang.RuntimeException


class SmsController(private val context: Context) {

    // FETCH SMS
    fun getMessages(
        contentUri: ContentUri,
        projection: List<String>,
        selection: String?,
        selectionArgs: List<String>?,
        sortOrder: String?
    ): List<HashMap<String, String?>> {
        val messages = mutableListOf<HashMap<String, String?>>()

        val cursor = context.contentResolver.query(
            contentUri.uri,
            projection.toTypedArray(),
            selection,
            selectionArgs?.toTypedArray(),
            sortOrder
        )

        while (cursor != null && cursor.moveToNext()) {
            val dataObject = HashMap<String, String?>(projection.size)
            for (columnName in cursor.columnNames) {
                val columnIndex = cursor.getColumnIndex(columnName)
                if (columnIndex >= 0) {
                    val value = cursor.getString(columnIndex)
                    dataObject[columnName] = value
                }
            }
            messages.add(dataObject)
        }
        cursor?.close()
        return messages
    }

    // SEND SMS
    fun sendSms(destinationAddress: String, messageBody: String, listenStatus: Boolean, subId: Int) {
        val smsManager = getSmsManager(subId)
        if (listenStatus) {
            val pendingIntents = getPendingIntents()
            smsManager.sendTextMessage(
                destinationAddress,
                null,
                messageBody,
                pendingIntents.first,
                pendingIntents.second
            )
        } else {
            smsManager.sendTextMessage(destinationAddress, null, messageBody, null, null)
        }
    }

    fun sendMultipartSms(destinationAddress: String, messageBody: String, listenStatus: Boolean, subId: Int) {
        val smsManager = getSmsManager(subId)
        val messageParts = smsManager.divideMessage(messageBody)
        if (listenStatus) {
            val pendingIntents = getMultiplePendingIntents(messageParts.size)
            smsManager.sendMultipartTextMessage(
                destinationAddress,
                null,
                messageParts,
                pendingIntents.first,
                pendingIntents.second
            )
        } else {
            smsManager.sendMultipartTextMessage(destinationAddress, null, messageParts, null, null)
        }
    }

    private fun getMultiplePendingIntents(size: Int): Pair<ArrayList<PendingIntent>, ArrayList<PendingIntent>> {
        val sentPendingIntents = arrayListOf<PendingIntent>()
        val deliveredPendingIntents = arrayListOf<PendingIntent>()
        for (i in 1..size) {
            val pendingIntents = getPendingIntents()
            sentPendingIntents.add(pendingIntents.first)
            deliveredPendingIntents.add(pendingIntents.second)
        }
        return Pair(sentPendingIntents, deliveredPendingIntents)
    }

    fun sendSmsIntent(destinationAddress: String, messageBody: String) {
        val intent = Intent(Intent.ACTION_SENDTO).apply {
            data = Uri.parse(SMS_TO + destinationAddress)
            putExtra(SMS_BODY, messageBody)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        context.applicationContext.startActivity(intent)
    }

    private fun getPendingIntents(): Pair<PendingIntent, PendingIntent> {
        val sentIntent = Intent(ACTION_SMS_SENT).apply {
            `package` = context.applicationContext.packageName
            flags = Intent.FLAG_RECEIVER_REGISTERED_ONLY
        }
        val sentPendingIntent = PendingIntent.getBroadcast(
            context,
            SMS_SENT_BROADCAST_REQUEST_CODE,
            sentIntent,
            PendingIntent.FLAG_ONE_SHOT or PendingIntent.FLAG_IMMUTABLE
        )

        val deliveredIntent = Intent(ACTION_SMS_DELIVERED).apply {
            `package` = context.applicationContext.packageName
            flags = Intent.FLAG_RECEIVER_REGISTERED_ONLY
        }
        val deliveredPendingIntent = PendingIntent.getBroadcast(
            context,
            SMS_DELIVERED_BROADCAST_REQUEST_CODE,
            deliveredIntent,
            PendingIntent.FLAG_ONE_SHOT or PendingIntent.FLAG_IMMUTABLE
        )

        return Pair(sentPendingIntent, deliveredPendingIntent)
    }

    private fun getSmsManager(subId: Int): SmsManager {
        var subscriptionId = subId
        if(subId == -1){
            subscriptionId = SmsManager.getDefaultSmsSubscriptionId()
        }

        val smsManager = getSystemService(context, SmsManager::class.java)
            ?: throw RuntimeException("Flutter Telephony: Error getting SmsManager")
        if (subscriptionId != SubscriptionManager.INVALID_SUBSCRIPTION_ID) {
            return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                smsManager.createForSubscriptionId(subscriptionId)
            } else {
                SmsManager.getSmsManagerForSubscriptionId(subscriptionId)
            }
        }
        return smsManager
    }

    // PHONE
    fun openDialer(phoneNumber: String) {
        val dialerIntent = Intent(Intent.ACTION_DIAL).apply {
            data = Uri.parse("tel:$phoneNumber")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }

        context.startActivity(dialerIntent)
    }

    @RequiresPermission(allOf = [Manifest.permission.CALL_PHONE])
    fun dialPhoneNumber(phoneNumber: String) {
        val callIntent = Intent(Intent.ACTION_CALL).apply {
            data = Uri.parse("tel:$phoneNumber")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }

        if (callIntent.resolveActivity(context.packageManager) != null) {
            context.applicationContext.startActivity(callIntent)
        }
    }

    // STATUS
    fun isSmsCapable(): Boolean {
        val telephonyManager = getTelephonyManager()
        return telephonyManager.isSmsCapable
    }

    fun getCellularDataState(): Int {
        return getTelephonyManager().dataState
    }

    @RequiresPermission(Manifest.permission.READ_PHONE_STATE)
    fun getCallState(): Int {
        val telephonyManager = getTelephonyManager()
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            telephonyManager.callStateForSubscription
        } else {
            telephonyManager.callState
        }
    }

    fun getDataActivity(): Int {
        return getTelephonyManager().dataActivity
    }

    fun getNetworkOperator(): String {
        return getTelephonyManager().networkOperator
    }

    fun getNetworkOperatorName(): String {
        return getTelephonyManager().networkOperatorName
    }

    @SuppressLint("MissingPermission")
    fun getDataNetworkType(): Int {
        val telephonyManager = getTelephonyManager()
        return if (Build.VERSION.SDK_INT > Build.VERSION_CODES.Q) {
            telephonyManager.dataNetworkType
        } else {
            telephonyManager.networkType
        }
    }

    fun getPhoneType(): Int {
        return getTelephonyManager().phoneType
    }

    fun getSimOperator(): String {
        return getTelephonyManager().simOperator
    }

    fun getSimOperatorName(): String {
        return getTelephonyManager().simOperatorName
    }

    fun getSimState(): Int {
        return getTelephonyManager().simState
    }

    fun isNetworkRoaming(): Boolean {
        return getTelephonyManager().isNetworkRoaming
    }

    @RequiresApi(Build.VERSION_CODES.O)
    @RequiresPermission(allOf = [Manifest.permission.ACCESS_COARSE_LOCATION, Manifest.permission.READ_PHONE_STATE])
    fun getServiceState(): Int? {
        val serviceState = getTelephonyManager().serviceState
        return serviceState?.state
    }

    @RequiresApi(Build.VERSION_CODES.Q)
    fun getSignalStrength(): List<Int>? {
        val signalStrength = getTelephonyManager().signalStrength
        return signalStrength?.cellSignalStrengths?.map {
            return@map it.level
        }
    }

    private fun getTelephonyManager(): TelephonyManager {
        val subscriptionId = SmsManager.getDefaultSmsSubscriptionId()
        val telephonyManager =
            context.getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            telephonyManager.createForSubscriptionId(subscriptionId)
        } else {
            telephonyManager
        }
    }
}