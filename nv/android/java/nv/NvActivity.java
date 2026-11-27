package nv;

// Generic embedder: loads the Odin library and hands the Activity to it. Loading runs the runtime
// and the app's main when libapp.so has a DT_INIT, else nativeOnCreate does; either way
// nativeOnCreate builds the root page (nv/app_android.odin). The Back key and the ActionBar's up
// arrow go to nativeOnBack, which pops a pushed page; on the root page it returns false and the
// default handling runs: it finishes the Activity, or moves the task to the back when the launcher
// started it. On a root page with a drawer the up arrow is a menu button: nativeOnMenu toggles the
// drawer. The options menu holds the page's actions: nativeOnCreateMenu fills it and
// nativeOnAction gets the selected item's id.
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
    public boolean onCreateOptionsMenu(android.view.Menu menu) {
        nativeOnCreateMenu(menu);
        return true;
    }

    @Override
    public boolean onOptionsItemSelected(android.view.MenuItem item) {
        if (item.getItemId() == android.R.id.home && (nativeOnMenu() || nativeOnBack())) return true;
        if (nativeOnAction(item.getItemId())) return true;
        return super.onOptionsItemSelected(item);
    }

    @Override
    protected void onActivityResult(int request, int result, android.content.Intent data) {
        if (!NvFiles.onResult(this, request, result, data)) super.onActivityResult(request, result, data);
    }

    private static native void nativeOnCreate(android.app.Activity activity);
    private static native boolean nativeOnBack();
    private static native boolean nativeOnMenu();
    private static native void nativeOnCreateMenu(android.view.Menu menu);
    private static native boolean nativeOnAction(int id);
}
