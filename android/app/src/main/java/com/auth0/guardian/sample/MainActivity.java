package com.auth0.guardian.sample;

import android.Manifest;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.content.BroadcastReceiver;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.Bundle;
import android.util.Log;
import android.widget.Button;
import android.widget.TextView;
import android.widget.Toast;

import androidx.activity.result.ActivityResultLauncher;
import androidx.activity.result.contract.ActivityResultContracts;
import androidx.appcompat.app.AppCompatActivity;
import androidx.core.content.ContextCompat;

import com.google.firebase.messaging.FirebaseMessaging;

import java.util.List;

public class MainActivity extends AppCompatActivity {

    private static final String TAG = "GuardianFCM";
    private TextView tokenTextView;
    private TextView latestNotificationTextView;
    private TextView notificationLogTextView;
    private BroadcastReceiver pushReceiver;

    private final ActivityResultLauncher<String> requestPermissionLauncher =
            registerForActivityResult(new ActivityResultContracts.RequestPermission(), isGranted -> {
                if (isGranted) {
                    Log.d(TAG, "Notification permission granted");
                } else {
                    Log.w(TAG, "Notification permission denied");
                }
            });

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel channel = new NotificationChannel(
                    GuardianMessagingService.CHANNEL_ID,
                    "Guardian Push Notifications",
                    NotificationManager.IMPORTANCE_HIGH
            );
            channel.setDescription("Auth0 Guardian MFA push notifications");
            NotificationManager nm = getSystemService(NotificationManager.class);
            nm.createNotificationChannel(channel);
        }

        tokenTextView = findViewById(R.id.tokenTextView);
        latestNotificationTextView = findViewById(R.id.latestNotificationTextView);
        notificationLogTextView = findViewById(R.id.notificationLogTextView);
        Button copyButton = findViewById(R.id.copyButton);

        pushReceiver = new BroadcastReceiver() {
            @Override
            public void onReceive(Context context, Intent intent) {
                refreshNotificationUI();
            }
        };

        requestNotificationPermission();
        fetchFcmToken();

        copyButton.setOnClickListener(v -> copyTokenToClipboard());
    }

    @Override
    protected void onResume() {
        super.onResume();
        IntentFilter filter = new IntentFilter(GuardianMessagingService.ACTION_PUSH_RECEIVED);
        ContextCompat.registerReceiver(this, pushReceiver, filter, ContextCompat.RECEIVER_NOT_EXPORTED);
        refreshNotificationUI();
    }

    @Override
    protected void onPause() {
        super.onPause();
        unregisterReceiver(pushReceiver);
    }

    private void refreshNotificationUI() {
        List<String> log = GuardianMessagingService.notificationLog;
        if (!log.isEmpty()) {
            // Extract the timestamp portion from the first (newest) entry: "[yyyy-MM-dd HH:mm:ss]"
            String newest = log.get(0);
            String timestamp = newest.startsWith("[") ? newest.substring(1, newest.indexOf(']')) : newest;
            latestNotificationTextView.setText(timestamp);
            notificationLogTextView.setText(android.text.TextUtils.join("\n", log));
        }
    }

    private void requestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS)
                    != PackageManager.PERMISSION_GRANTED) {
                requestPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS);
            }
        }
    }

    private void fetchFcmToken() {
        FirebaseMessaging.getInstance().getToken()
                .addOnCompleteListener(task -> {
                    if (!task.isSuccessful()) {
                        Log.w(TAG, "Failed to get FCM token", task.getException());
                        tokenTextView.setText("Failed to get token");
                        return;
                    }

                    String token = task.getResult();
                    Log.d(TAG, "FCM Token: " + token);
                    tokenTextView.setText(token);
                });
    }

    private void copyTokenToClipboard() {
        String token = tokenTextView.getText().toString();
        if (token.isEmpty() || token.equals("Loading...") || token.equals("Failed to get token")) {
            Toast.makeText(this, "No token to copy", Toast.LENGTH_SHORT).show();
            return;
        }

        ClipboardManager clipboard = (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
        ClipData clip = ClipData.newPlainText("FCM Token", token);
        clipboard.setPrimaryClip(clip);
        Toast.makeText(this, "Token copied to clipboard", Toast.LENGTH_SHORT).show();
    }
}
