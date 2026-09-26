package nv;

import android.view.View;

// Forwards Button clicks to Odin; `handle` is a ^Button_Handle.
public final class NvClickListener implements View.OnClickListener {
    private final long handle;

    public NvClickListener(long handle) { this.handle = handle; }

    @Override public void onClick(View v) { nativeOnClick(handle); }

    private static native void nativeOnClick(long handle);
}
