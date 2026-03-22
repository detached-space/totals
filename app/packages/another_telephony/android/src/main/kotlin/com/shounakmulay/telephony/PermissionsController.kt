package com.shounakmulay.telephony

import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.content.pm.PackageManager.PERMISSION_GRANTED
import android.os.Build
import androidx.annotation.RequiresApi
import androidx.core.content.ContextCompat
import com.shounakmulay.telephony.utils.Constants.PHONE_PERMISSIONS
import com.shounakmulay.telephony.utils.Constants.SERVICE_STATE_PERMISSIONS
import com.shounakmulay.telephony.utils.Constants.SMS_PERMISSIONS

class PermissionsController(private val context: Context) {

  var isRequestingPermission: Boolean = false

  fun hasRequiredPermissions(permissions: List<String>): Boolean {
      var hasPermissions = true
      for (permission in permissions) {
        hasPermissions = hasPermissions && checkPermission(permission)
      }
      return hasPermissions
  }

  private fun checkPermission(permission: String): Boolean {
    return Build.VERSION.SDK_INT < Build.VERSION_CODES.M || context.checkSelfPermission(permission) == PERMISSION_GRANTED
  }

  @RequiresApi(Build.VERSION_CODES.M)
  fun requestPermissions(activity: Activity, permissions: List<String>, requestCode: Int) {
    if (!isRequestingPermission) {
      isRequestingPermission = true
      activity.requestPermissions(permissions.toTypedArray(), requestCode)
    }
  }

  fun getSmsPermissions(): List<String> {
    val permissions = getListedPermissions()
    return permissions.filter { permission -> SMS_PERMISSIONS.contains(permission) }
  }

  fun getPhonePermissions(): List<String> {
    val permissions = getListedPermissions()
    return permissions.filter { permission -> PHONE_PERMISSIONS.contains(permission) }
  }

  fun getServiceStatePermissions(): List<String> {
    val permissions = getListedPermissions()
    return permissions.filter { permission -> SERVICE_STATE_PERMISSIONS.contains(permission) }
  }

  private fun getListedPermissions(): Array<out String> {
      context.apply {
        val info = packageManager.getPackageInfo(packageName, PackageManager.GET_PERMISSIONS)
        return info.requestedPermissions ?: arrayOf()
      }
  }
}