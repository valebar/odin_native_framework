package nv;

import android.content.Context;
import android.graphics.Canvas;
import android.text.Layout;
import android.text.TextUtils;
import android.view.Gravity;
import android.view.View;
import android.widget.TextView;

// The ActionBar's title, in NvBarView after the page's leading view (the width between the up /
// menu button and the actions). Centred over the whole bar like the centred title of a Flutter
// AppBar, and moved aside only as far as the sides need.
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
        if (layout != null && getParent() instanceof View && ((View) getParent()).getParent() instanceof View) {
            View holder = (View) getParent(), bar = (View) holder.getParent();
            float left = holder.getLeft() + getLeft(); // this view's left edge in the bar
            float slack = Math.max(0, (getWidth() - layout.getLineWidth(0)) / 2);
            float want = bar.getWidth() / 2f - left - getWidth() / 2f;
            dx = Math.max(-slack, Math.min(slack, want));
        }
        canvas.save();
        canvas.translate(dx, 0);
        super.onDraw(canvas);
        canvas.restore();
    }
}
