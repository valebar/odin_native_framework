package nv;

import android.text.Editable;
import android.text.TextWatcher;
import android.view.KeyEvent;
import android.widget.TextView;

// Forwards EditText edits and the keyboard's action key to Odin; `handle` is a ^Input_Handle.
public final class NvInputListener implements TextWatcher, TextView.OnEditorActionListener {
    private final long handle;

    public NvInputListener(long handle) { this.handle = handle; }

    @Override public void beforeTextChanged(CharSequence s, int start, int count, int after) {}
    @Override public void onTextChanged(CharSequence s, int start, int before, int count) {}
    @Override public void afterTextChanged(Editable s) { nativeOnChange(handle); }

    // The soft keyboard's action key comes without an event; a hardware Enter comes as key down
    // and key up, so only the down counts. Returning false keeps the default (Done hides the keyboard).
    @Override
    public boolean onEditorAction(TextView v, int actionId, KeyEvent event) {
        if (event == null || event.getAction() == KeyEvent.ACTION_DOWN) nativeOnSubmit(handle);
        return false;
    }

    private static native void nativeOnChange(long handle);
    private static native void nativeOnSubmit(long handle);
}
