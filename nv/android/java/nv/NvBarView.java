package nv;

import android.content.Context;
import android.view.View;
import android.view.ViewGroup;
import android.widget.FrameLayout;

// The ActionBar's custom view: the page's leading view (nv.page_set_bar_leading) at its natural
// width, centred vertically, then the title (NvTitleView) over the rest.
public final class NvBarView extends ViewGroup {
    private final FrameLayout leading;
    private final NvTitleView title;

    public NvBarView(Context context) {
        super(context);
        leading = new FrameLayout(context);
        title = new NvTitleView(context);
        addView(leading);
        addView(title);
    }

    public FrameLayout getLeading() { return leading; }

    public NvTitleView getTitle() { return title; }

    @Override
    protected void onMeasure(int widthSpec, int heightSpec) {
        int w = MeasureSpec.getSize(widthSpec), h = MeasureSpec.getSize(heightSpec);
        leading.measure(MeasureSpec.makeMeasureSpec(w, MeasureSpec.AT_MOST), MeasureSpec.makeMeasureSpec(h, MeasureSpec.AT_MOST));
        int lw = leadingWidth();
        title.measure(MeasureSpec.makeMeasureSpec(Math.max(0, w - lw), MeasureSpec.EXACTLY), MeasureSpec.makeMeasureSpec(h, MeasureSpec.EXACTLY));
        setMeasuredDimension(w, h);
    }

    @Override
    protected void onLayout(boolean changed, int l, int t, int r, int b) {
        int w = r - l, h = b - t, lw = leadingWidth(), lh = Math.min(leading.getMeasuredHeight(), h);
        leading.layout(0, (h - lh) / 2, lw, (h - lh) / 2 + lh);
        title.layout(lw, 0, w, h);
        title.invalidate(); // its centring depends on where it starts
    }

    private int leadingWidth() {
        return leading.getChildCount() == 0 ? 0 : leading.getMeasuredWidth();
    }
}
