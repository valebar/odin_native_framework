package nv;

import android.os.Handler;
import android.os.Looper;

// One-shot timers on the UI thread for Odin; `timer` is a ^Timer, which nativeOnTimer frees.
public final class NvTimer {
    private static final Handler main = new Handler(Looper.getMainLooper());

    static void start(long timer, long ms) {
        main.postDelayed(() -> nativeOnTimer(timer), ms);
    }

    private static native void nativeOnTimer(long timer);
}
