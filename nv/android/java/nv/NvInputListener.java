package nv;

import android.content.Context;
import android.text.Editable;
import android.text.TextWatcher;
import android.view.KeyEvent;
import android.view.View;
import android.view.inputmethod.InputMethodManager;
import android.widget.EditText;
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

    // Focus, selection and the soft keyboard once the field is attached (a dialog's field is
    // focused right after it was added: post runs once it is in the window).
    static void focus(EditText et, boolean selectAll) {
        et.post(() -> {
            if (!et.isAttachedToWindow()) return; // its dialog closed first
            et.requestFocus();
            if (selectAll) et.selectAll();
            else et.setSelection(et.length());
            InputMethodManager imm = (InputMethodManager) et.getContext().getSystemService(Context.INPUT_METHOD_SERVICE);
            if (imm != null) imm.showSoftInput(et, 0);
        });
    }

    // Hides the soft keyboard and drops the focus when it is inside `v`, which is about to be removed
    // (a dialog's card): removing a focused view leaves the keyboard up and moves the focus to the
    // page's next field.
    static void blur(View v) {
        View f = v.findFocus();
        if (f == null) return;
        InputMethodManager imm = (InputMethodManager) v.getContext().getSystemService(Context.INPUT_METHOD_SERVICE);
        if (imm != null) imm.hideSoftInputFromWindow(f.getWindowToken(), 0);
        f.clearFocus();
    }

    private static native void nativeOnChange(long handle);
    private static native void nativeOnSubmit(long handle);
}
