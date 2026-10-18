package org.love2d.android;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

/**
 * The Pokéwalker's background check (WalkerNotifications.check), fired by the
 * inexact half-hourly alarm, and re-armed after a reboot when a walk is being
 * watched.
 */
public class WalkerAlarmReceiver extends BroadcastReceiver {
    static final String ACTION_CHECK = "org.love2d.android.POKEWALKER_CHECK";

    @Override
    public void onReceive(Context context, Intent intent) {
        final Context ctx = context.getApplicationContext();
        String action = intent != null ? intent.getAction() : null;
        if (Intent.ACTION_BOOT_COMPLETED.equals(action)) {
            if (ctx.getSharedPreferences(WalkerNotifications.PREFS, Context.MODE_PRIVATE)
                    .getString(WalkerNotifications.PREF_WATCH, null) != null) {
                WalkerNotifications.schedule(ctx);
            }
            return;
        }
        final PendingResult pending = goAsync();
        WalkerNotifications.check(ctx, new Runnable() {
            @Override
            public void run() {
                pending.finish();
            }
        });
    }
}
