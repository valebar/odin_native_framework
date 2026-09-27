package nv;

// Generic embedder: loads the Odin library and hands the Activity to it. The Back key and the
// ActionBar's up arrow go to nativeOnBack, which pops a pushed page; on the root page it returns
// false and the Activity finishes as usual.
public final class NvActivity extends android.app.Activity {
    static { System.loadLibrary("app"); }

    @Override
    protected void onCreate(android.os.Bundle state) {
        super.onCreate(state);
        nativeOnCreate(this);
    }

    @Override
    public void onBackPressed() {
        if (!nativeOnBack()) super.onBackPressed();
    }

    @Override
    public boolean onOptionsItemSelected(android.view.MenuItem item) {
        if (item.getItemId() == android.R.id.home && nativeOnBack()) return true;
        return super.onOptionsItemSelected(item);
    }

    private static native void nativeOnCreate(android.app.Activity activity);
    private static native boolean nativeOnBack();
}
