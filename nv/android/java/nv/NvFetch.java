package nv;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;

// Image bytes for Odin: downloads on a thread of their own (Android forbids the network on the UI
// thread, and bionic can't host core:thread), delivered back on the UI thread; and the APK's
// assets. `req` is a ^Fetch.
public final class NvFetch {
    private static final Handler main = new Handler(Looper.getMainLooper());

    static void start(long req, String url) {
        new Thread(() -> {
            byte[] data = download(url);
            main.post(() -> nativeOnFetch(req, data));
        }, "nv-fetch").start();
    }

    static byte[] readAsset(Context context, String name) {
        try (InputStream in = context.getAssets().open(name)) {
            return readAll(in);
        } catch (IOException e) {
            return null;
        }
    }

    private static byte[] download(String url) {
        HttpURLConnection c = null;
        try {
            c = (HttpURLConnection) new URL(url).openConnection();
            c.setInstanceFollowRedirects(true);
            if (c.getResponseCode() / 100 != 2) return null;
            try (InputStream in = c.getInputStream()) {
                return readAll(in);
            }
        } catch (Exception e) { // any failure still reaches nativeOnFetch, which frees the request
            return null;
        } finally {
            if (c != null) c.disconnect();
        }
    }

    private static byte[] readAll(InputStream in) throws IOException {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        byte[] buf = new byte[16 * 1024];
        for (int n; (n = in.read(buf)) > 0; ) out.write(buf, 0, n);
        return out.toByteArray();
    }

    private static native void nativeOnFetch(long req, byte[] data);
}
