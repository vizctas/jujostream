package com.limelight.jujostream

import android.app.Notification
import android.app.NotificationManager
import android.os.Build
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

class JujoNotificationListenerService : NotificationListenerService() {
    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return
        val notification = sbn.notification ?: return
        val extras = notification.extras
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty()
        val text = (
            extras.getCharSequence(Notification.EXTRA_BIG_TEXT)
                ?: extras.getCharSequence(Notification.EXTRA_TEXT)
            )?.toString().orEmpty()
        val subText = extras.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString().orEmpty()
        val body = if (text.isNotBlank()) text else subText
        val appLabel = runCatching {
            val appInfo = packageManager.getApplicationInfo(sbn.packageName, 0)
            packageManager.getApplicationLabel(appInfo).toString()
        }.getOrDefault(sbn.packageName)
        val isOngoing = notification.flags and Notification.FLAG_ONGOING_EVENT != 0
        val isSilent = isSilentNotification(sbn)
        val isGroupSummary = notification.flags and Notification.FLAG_GROUP_SUMMARY != 0

        NotificationMirrorBridge.emit(
            mapOf(
                "type" to "posted",
                "id" to sbn.key,
                "sourceDeviceId" to "",
                "sourceDeviceName" to Build.MODEL.orEmpty(),
                "packageName" to sbn.packageName,
                "appLabel" to appLabel,
                "title" to title,
                "body" to body,
                "postedAt" to sbn.postTime,
                "isOngoing" to isOngoing,
                "isSilent" to isSilent,
                "isGroupSummary" to isGroupSummary
            )
        )
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        if (sbn == null) return
        NotificationMirrorBridge.emit(
            mapOf(
                "type" to "removed",
                "id" to sbn.key,
                "packageName" to sbn.packageName
            )
        )
    }

    private fun isSilentNotification(sbn: StatusBarNotification): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        val ranking = Ranking()
        if (!currentRanking.getRanking(sbn.key, ranking)) return false
        return ranking.importance <= NotificationManager.IMPORTANCE_LOW
    }
}
