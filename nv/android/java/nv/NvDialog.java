package nv;

import android.content.Context;
import android.content.res.ColorStateList;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.EditText;
import android.widget.TextView;

// A light dialog's body on its white card: the views were made with the Activity's theme, which
// may be dark. Text in the theme's colour (what a fresh view of the same kind has; a colour nv set
// differs) turns dark and hints grey; untinted fields get a grey underline, untinted buttons a
// light grey shape.
public final class NvDialog {
    private static final int TEXT = 0xDE000000, HINT = 0x61000000, LINE = 0x8A000000, BUTTON = 0xFFE0E0E0;

    static void lighten(View root) {
        Context c = root.getContext();
        lighten(root, new TextView(c), new EditText(c), new Button(c));
    }

    private static void lighten(View v, TextView text, EditText edit, Button button) {
        if (v instanceof TextView) {
            TextView t = (TextView) v;
            TextView probe = v instanceof EditText ? edit : v instanceof Button ? button : text;
            if (t.getCurrentTextColor() == probe.getCurrentTextColor()) t.setTextColor(TEXT);
            if (v instanceof EditText) t.setHintTextColor(HINT); // nv never sets a hint colour
            if (v.getBackgroundTintList() == null) {
                if (v instanceof EditText) v.setBackgroundTintList(ColorStateList.valueOf(LINE));
                else if (v instanceof Button) v.setBackgroundTintList(ColorStateList.valueOf(BUTTON));
            }
        }
        if (v instanceof ViewGroup) {
            ViewGroup g = (ViewGroup) v;
            for (int i = 0; i < g.getChildCount(); i++) lighten(g.getChildAt(i), text, edit, button);
        }
    }
}
