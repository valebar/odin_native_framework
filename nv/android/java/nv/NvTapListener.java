package nv;

import android.view.View;

// Forwards clicks on the scaffold's pieces to Odin (scaffold_android.odin): `kind` says what
// `handle` is: 0 = a scrim (^Overlay_Handle), 1 = a FAB (^Fab_Handle), 2 + i = tab i of a tab bar
// (^Tabbar_Handle).
public final class NvTapListener implements View.OnClickListener {
    private final long handle;
    private final int kind;

    public NvTapListener(long handle, int kind) {
        this.handle = handle;
        this.kind = kind;
    }

    @Override public void onClick(View v) { nativeOnTap(handle, kind); }

    private static native void nativeOnTap(long handle, int kind);
}
