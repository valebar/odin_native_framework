package nv;

import android.app.Activity;
import android.content.Intent;
import android.database.Cursor;
import android.net.Uri;
import android.os.Handler;
import android.os.Looper;
import android.provider.OpenableColumns;
import android.webkit.MimeTypeMap;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.io.OutputStream;

// File dialogs for Odin (nv.file_open / file_save): the system's document picker through
// ACTION_OPEN_DOCUMENT / ACTION_CREATE_DOCUMENT; NvActivity hands the result here. The file is read
// or written on a thread of its own and the answer delivered on the UI thread. `req` is a
// ^File_Request; it is kept in a static field, so an Activity recreated meanwhile still answers it.
public final class NvFiles {
    private static final int REQ_OPEN = 0x6E01, REQ_SAVE = 0x6E02;
    private static final Handler main = new Handler(Looper.getMainLooper());
    private static long pending;
    private static byte[] saveData;

    // `extensions`: comma-separated, "" for any file.
    static void open(Activity a, long req, String extensions) {
        Intent i = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        i.addCategory(Intent.CATEGORY_OPENABLE);
        i.setType("*/*");
        String[] mimes = mimeTypes(extensions);
        if (mimes != null) i.putExtra(Intent.EXTRA_MIME_TYPES, mimes);
        start(a, req, i, REQ_OPEN);
    }

    static void save(Activity a, long req, String name, String extension, byte[] data) {
        Intent i = new Intent(Intent.ACTION_CREATE_DOCUMENT);
        i.addCategory(Intent.CATEGORY_OPENABLE);
        String mime = extension == null ? null : MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension);
        i.setType(mime != null ? mime : "application/octet-stream");
        i.putExtra(Intent.EXTRA_TITLE, name);
        saveData = data;
        start(a, req, i, REQ_SAVE);
    }

    private static void start(Activity a, long req, Intent i, int code) {
        pending = req;
        try {
            a.startActivityForResult(i, code);
        } catch (Exception e) { // no document provider
            pending = 0;
            saveData = null;
            main.post(() -> nativeOnDone(req, 2, null, null));
        }
    }

    // A filter by MIME type only when every extension has one: an unknown one shows every file.
    private static String[] mimeTypes(String extensions) {
        if (extensions == null || extensions.isEmpty()) return null;
        String[] list = extensions.split(","), out = new String[list.length];
        for (int k = 0; k < list.length; k++) {
            out[k] = MimeTypeMap.getSingleton().getMimeTypeFromExtension(list[k]);
            if (out[k] == null) return null;
        }
        return out;
    }

    // From NvActivity.onActivityResult; false for a request that isn't ours.
    static boolean onResult(Activity a, int code, int result, Intent data) {
        if (code != REQ_OPEN && code != REQ_SAVE) return false;
        long req = pending;
        byte[] bytes = saveData;
        pending = 0;
        saveData = null;
        if (req == 0) return true;
        Uri uri = data != null ? data.getData() : null;
        if (result != Activity.RESULT_OK || uri == null) {
            nativeOnDone(req, 1, null, null);
            return true;
        }
        android.content.ContentResolver cr = a.getContentResolver();
        new Thread(() -> {
            String name = displayName(cr, uri);
            byte[] read = null;
            boolean ok = false;
            try {
                if (code == REQ_OPEN) {
                    try (InputStream in = cr.openInputStream(uri)) {
                        ByteArrayOutputStream out = new ByteArrayOutputStream();
                        byte[] buf = new byte[16 * 1024];
                        for (int n; (n = in.read(buf)) > 0; ) out.write(buf, 0, n);
                        read = out.toByteArray();
                    }
                } else {
                    try (OutputStream out = cr.openOutputStream(uri, "wt")) {
                        out.write(bytes);
                    }
                }
                ok = true;
            } catch (Exception e) {
                ok = false;
            }
            int status = ok ? 0 : 2;
            byte[] answer = read;
            main.post(() -> nativeOnDone(req, status, name, answer));
        }, "nv-files").start();
        return true;
    }

    private static String displayName(android.content.ContentResolver cr, Uri uri) {
        try (Cursor c = cr.query(uri, new String[]{OpenableColumns.DISPLAY_NAME}, null, null, null)) {
            if (c != null && c.moveToFirst()) return c.getString(0);
        } catch (Exception e) {
            // the last path segment below
        }
        return uri.getLastPathSegment();
    }

    // status: 0 ok, 1 cancelled, 2 failed (nv.File_Status).
    private static native void nativeOnDone(long req, int status, String name, byte[] data);
}
