package com.auth0.guardian.sample;

import android.util.Log;

import androidx.annotation.NonNull;

import com.google.firebase.messaging.FirebaseMessagingService;
import com.google.firebase.messaging.RemoteMessage;

import java.util.Map;

public class GuardianMessagingService extends FirebaseMessagingService {

    private static final String TAG = "GuardianFCM";

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
    }

    @Override
    public void onNewToken(@NonNull String token) {
        super.onNewToken(token);
        Log.d(TAG, "FCM Token refreshed: " + token);
    }
}
