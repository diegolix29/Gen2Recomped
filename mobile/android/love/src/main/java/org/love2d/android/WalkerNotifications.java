package org.love2d.android;

import android.app.AlarmManager;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.hardware.Sensor;
import android.hardware.SensorEvent;
import android.hardware.SensorEventListener;
import android.hardware.SensorManager;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.util.Log;

import androidx.core.app.NotificationCompat;
import androidx.core.app.NotificationManagerCompat;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.File;
import java.io.FileInputStream;

/**
 * Pokéwalker notifications (src/pokewalker/WalkerNotify.lua through
 * love.system.walkerNotify -> GameActivity.walkerNotify).
 *
 *   post   a notification now (events while the app is open)
 *   watch  the walk's step milestones, checked every ~30 minutes by
 *          WalkerAlarmReceiver while the app is closed: the hardware step
 *          counter is read against the step bridge's own anchor
 *          (pokewalker_steps / anchor, never moved here), plus any steps
 *          already staged in steps_pending.json, and every milestone the walk
 *          has passed since the watch was written is notified once
 *   stop   no more background checks
 *
 * Nothing here credits steps: the walker still counts them itself when the
 * app next opens (the step bridge stays the only writer of the anchor).
 */
public final class WalkerNotifications {
    static final String CHANNEL = "pokewalker";
    static final String PREFS = "pokewalker_watch";
    static final String PREF_WATCH = "watch";
    static final String PREF_DONE = "done";
    static final long INTERVAL = AlarmManager.INTERVAL_HALF_HOUR;
    private static int nextId = 4100;

    private WalkerNotifications() {}

    static void ensureChannel(Context ctx) {
        if (Build.VERSION.SDK_INT < 26) return;
        NotificationManager nm = (NotificationManager) ctx.getSystemService(Context.NOTIFICATION_SERVICE);
        if (nm == null || nm.getNotificationChannel(CHANNEL) != null) return;
        NotificationChannel ch = new NotificationChannel(CHANNEL, "Pokéwalker",
            NotificationManager.IMPORTANCE_DEFAULT);
        ch.setDescription("Steps, finds and wild Pokémon on your walk");
        nm.createNotificationChannel(ch);
    }

    static void post(Context ctx, String title, String text) {
        try {
            ensureChannel(ctx);
            Intent open = ctx.getPackageManager().getLaunchIntentForPackage(ctx.getPackageName());
            PendingIntent tap = null;
            if (open != null) {
                open.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP);
                tap = PendingIntent.getActivity(ctx, 0, open,
                    PendingIntent.FLAG_UPDATE_CURRENT | (Build.VERSION.SDK_INT >= 23 ? PendingIntent.FLAG_IMMUTABLE : 0));
            }
            NotificationCompat.Builder b = new NotificationCompat.Builder(ctx, CHANNEL)
                .setSmallIcon(ctx.getApplicationInfo().icon)
                .setContentTitle(title)
                .setContentText(text)
                .setStyle(new NotificationCompat.BigTextStyle().bigText(text))
                .setAutoCancel(true)
                .setPriority(NotificationCompat.PRIORITY_DEFAULT);
            if (tap != null) b.setContentIntent(tap);
            NotificationManagerCompat.from(ctx).notify(nextId++, b.build());
        } catch (SecurityException e) {
            Log.d("Pokewalker", "notifications not permitted: " + e);
        } catch (Exception e) {
            Log.d("Pokewalker", "could not notify: " + e);
        }
    }

    private static PendingIntent alarmIntent(Context ctx) {
        Intent i = new Intent(ctx, WalkerAlarmReceiver.class);
        i.setAction(WalkerAlarmReceiver.ACTION_CHECK);
        return PendingIntent.getBroadcast(ctx, 0, i,
            PendingIntent.FLAG_UPDATE_CURRENT | (Build.VERSION.SDK_INT >= 23 ? PendingIntent.FLAG_IMMUTABLE : 0));
    }

    static void schedule(Context ctx) {
        AlarmManager am = (AlarmManager) ctx.getSystemService(Context.ALARM_SERVICE);
        if (am == null) return;
        am.setInexactRepeating(AlarmManager.ELAPSED_REALTIME_WAKEUP,
            SystemClock.elapsedRealtime() + INTERVAL, INTERVAL, alarmIntent(ctx));
    }

    static void cancel(Context ctx) {
        AlarmManager am = (AlarmManager) ctx.getSystemService(Context.ALARM_SERVICE);
        if (am != null) am.cancel(alarmIntent(ctx));
    }

    /** One command from Lua; see the class comment. */
    static boolean command(Context ctx, String json) {
        try {
            JSONObject cmd = new JSONObject(json);
            SharedPreferences prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
            if (cmd.has("post")) {
                JSONObject p = cmd.getJSONObject("post");
                post(ctx, p.optString("title", "Pokéwalker"), p.optString("text", ""));
            }
            if (cmd.has("watch")) {
                JSONObject w = cmd.getJSONObject("watch");
                // a new watch starts its own "already notified" list
                String old = prefs.getString(PREF_WATCH, null);
                String oldId = old != null ? new JSONObject(old).optString("id", "") : "";
                SharedPreferences.Editor e = prefs.edit().putString(PREF_WATCH, w.toString());
                if (!w.optString("id", "").equals(oldId)) e.remove(PREF_DONE);
                e.apply();
                schedule(ctx);
            }
            if (cmd.optBoolean("stop", false)) {
                prefs.edit().remove(PREF_WATCH).remove(PREF_DONE).apply();
                cancel(ctx);
            }
            return true;
        } catch (Exception e) {
            Log.d("Pokewalker", "bad walkerNotify command: " + e);
            return false;
        }
    }

    private static long pendingSteps(String path) {
        if (path == null || path.length() == 0) return 0;
        File f = new File(path);
        if (!f.isFile()) return 0;
        try {
            byte[] raw = new byte[(int) Math.min(f.length(), 4096)];
            FileInputStream in = new FileInputStream(f);
            int n = in.read(raw);
            in.close();
            if (n <= 0) return 0;
            return Math.max(0, new JSONObject(new String(raw, 0, n, "UTF-8")).optLong("steps", 0));
        } catch (Exception e) {
            return 0;
        }
    }

    /** The background check: read the counter, notify what was passed. */
    static void check(final Context ctx, final Runnable done) {
        final SharedPreferences prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        final String watchJson = prefs.getString(PREF_WATCH, null);
        if (watchJson == null) { done.run(); return; }
        final SensorManager manager = (SensorManager) ctx.getSystemService(Context.SENSOR_SERVICE);
        Sensor counter = manager != null ? manager.getDefaultSensor(Sensor.TYPE_STEP_COUNTER) : null;
        if (counter == null) { done.run(); return; }
        final Handler handler = new Handler(Looper.getMainLooper());
        final boolean[] finished = { false };
        final SensorEventListener listener = new SensorEventListener() {
            @Override
            public void onSensorChanged(SensorEvent event) {
                if (finished[0] || event.values.length == 0) return;
                finished[0] = true;
                manager.unregisterListener(this);
                try {
                    evaluate(ctx, prefs, new JSONObject(watchJson), (long) event.values[0]);
                } catch (Exception e) {
                    Log.d("Pokewalker", "watch check failed: " + e);
                }
                done.run();
            }
            @Override
            public void onAccuracyChanged(Sensor sensor, int accuracy) {}
        };
        try {
            if (!manager.registerListener(listener, counter, SensorManager.SENSOR_DELAY_NORMAL)) {
                done.run();
                return;
            }
        } catch (SecurityException e) {
            done.run();
            return;
        }
        handler.postDelayed(new Runnable() {
            @Override
            public void run() {
                if (finished[0]) return;
                finished[0] = true;
                manager.unregisterListener(listener);
                done.run();
            }
        }, 8000);
    }

    private static void evaluate(Context ctx, SharedPreferences prefs, JSONObject watch, long counterNow)
            throws Exception {
        SharedPreferences steps = ctx.getSharedPreferences("pokewalker_steps", Context.MODE_PRIVATE);
        long anchor = steps.getLong("anchor", -1);
        if (anchor < 0 || counterNow < anchor) return;   // a reboot: wait for the app
        // steps walked since the watch was written: the counter past the
        // anchor the walker last read, plus what is staged and not yet read
        long since = (counterNow - anchor) + pendingSteps(watch.optString("pendingFile", null))
            - watch.optLong("baseline", 0);
        if (since <= 0) return;
        JSONArray marks = watch.optJSONArray("milestones");
        if (marks == null) return;
        JSONArray done = new JSONArray(prefs.getString(PREF_DONE, "[]"));
        boolean changed = false;
        for (int i = 0; i < marks.length(); i++) {
            JSONObject m = marks.getJSONObject(i);
            long at = m.optLong("at", Long.MAX_VALUE);
            boolean already = false;
            for (int k = 0; k < done.length(); k++) if (done.getInt(k) == i) { already = true; break; }
            if (!already && since >= at) {
                post(ctx, m.optString("title", "Pokéwalker"), m.optString("text", ""));
                done.put(i);
                changed = true;
            }
        }
        if (changed) prefs.edit().putString(PREF_DONE, done.toString()).apply();
    }
}
