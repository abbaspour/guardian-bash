package com.auth0.guardian.sample;

import android.app.PendingIntent;
import android.content.Intent;
import android.util.Log;

import androidx.annotation.NonNull;
import androidx.core.app.NotificationCompat;
import androidx.core.app.NotificationManagerCompat;

import com.google.firebase.messaging.FirebaseMessagingService;
import com.google.firebase.messaging.RemoteMessage;

import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.Locale;
import java.util.Map;

public class GuardianMessagingService extends FirebaseMessagingService {

    private static final String TAG = "GuardianFCM";
    public static final String ACTION_PUSH_RECEIVED = "com.auth0.guardian.PUSH_RECEIVED";
    public static final String CHANNEL_ID = "guardian_push";

    public static final ArrayList<String> notificationLog = new ArrayList<>();

    @Override
    public void onMessageReceived(@NonNull RemoteMessage remoteMessage) {
        super.onMessageReceived(remoteMessage);

        Log.d(TAG, "=== GUARDIAN PUSH NOTIFICATION ===");
        Log.d(TAG, "From: " + remoteMessage.getFrom());

        Map<String, String> data = remoteMessage.getData();
        if (!data.isEmpty()) {
            // Log specific Guardian fields
            if (data.containsKey("c")) {
                Log.d(TAG, "challenge: " + data.get("c"));
            }
            if (data.containsKey("txtkn")) {
                Log.d(TAG, "txtkn: " + data.get("txtkn"));
            }

            // Log full data payload
            Log.d(TAG, "Full data: " + data.toString());
        }

        // Log notification payload if present
        RemoteMessage.Notification notification = remoteMessage.getNotification();
        if (notification != null) {
            Log.d(TAG, "Notification title: " + notification.getTitle());
            Log.d(TAG, "Notification body: " + notification.getBody());
        }

        Log.d(TAG, "==================================");

        // Build a single-line log entry and prepend it to the in-memory log
        String timestamp = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault()).format(new Date());
        String challenge = data.getOrDefault("c", "—");
        String txtkn = data.getOrDefault("txtkn", "—");
        String entry = "[" + timestamp + "]  challenge=" + challenge + "  txtkn=" + txtkn;
        notificationLog.add(0, entry);

        // Post system status-bar notification so it appears when the app is backgrounded
        String title = (notification != null && notification.getTitle() != null)
                ? notification.getTitle() : "Guardian MFA Request";
        String body = (notification != null && notification.getBody() != null)
                ? notification.getBody() : "challenge=" + challenge;

        Intent tapIntent = new Intent(this, MainActivity.class);
        tapIntent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK);
        PendingIntent pendingIntent = PendingIntent.getActivity(
                this, 0, tapIntent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
        );

        NotificationCompat.Builder builder = new NotificationCompat.Builder(this, CHANNEL_ID)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle(title)
                .setContentText(body)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setContentIntent(pendingIntent)
                .setAutoCancel(true);

        NotificationManagerCompat.from(this).notify((int) System.currentTimeMillis(), builder.build());

        // Notify MainActivity (if visible) that a new push arrived
        Intent intent = new Intent(ACTION_PUSH_RECEIVED);
        intent.setPackage(getPackageName());
        sendBroadcast(intent);
    }

    @Override
    public void onNewToken(@NonNull String token) {
        super.onNewToken(token);
        Log.d(TAG, "FCM Token refreshed: " + token);
    }
}
