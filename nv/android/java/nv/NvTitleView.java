package nv;

import android.content.Context;
import android.graphics.Canvas;
import android.text.Layout;
import android.text.TextUtils;
import android.view.Gravity;
import android.view.View;
import android.widget.TextView;

// The ActionBar's title, as its custom view (the width between the up / menu button and the
// actions). Centred over the bar from its own left edge to 16 dp before the bar's end, like the
// centred title of a Flutter AppBar, and moved left only as far as the actions need.
public final class NvTitleView extends TextView {
    public NvTitleView(Context context) {
        super(context);
        setTextAppearance(android.R.style.TextAppearance_Material_Widget_ActionBar_Title); // the bar's own title look
        setSingleLine(true);
        setEllipsize(TextUtils.TruncateAt.END);
        setGravity(Gravity.CENTER);
    }

    @Override
    protected void onDraw(Canvas canvas) {
        Layout layout = getLayout();
        float dx = 0;
        if (layout != null && getParent() instanceof View) {
            View bar = (View) getParent();
            float end = bar.getWidth() - 16 * getResources().getDisplayMetrics().density;
            float slack = Math.max(0, (getWidth() - layout.getLineWidth(0)) / 2);
            float want = (end - getLeft()) / 2 - getWidth() / 2f;
            dx = Math.max(-slack, Math.min(slack, want));
        }
        canvas.save();
        canvas.translate(dx, 0);
        super.onDraw(canvas);
        canvas.restore();
    }
}
