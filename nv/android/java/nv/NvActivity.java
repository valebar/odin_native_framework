package nv;

// Generic embedder: loads the Odin library and hands the Activity to it.
public final class NvActivity extends android.app.Activity {
    static { System.loadLibrary("app"); }

    @Override
    protected void onCreate(android.os.Bundle state) {
        super.onCreate(state);
        nativeOnCreate(this);
    }

    private static native void nativeOnCreate(android.app.Activity activity);
}
