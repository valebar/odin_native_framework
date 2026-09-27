package nv;

import android.content.Context;
import android.widget.FrameLayout;

// FrameLayout whose natural size can be fixed from Odin (px, 0 = from the child). A fixed axis is
// forced on the child too, and a parent that decides the size itself (an EXACTLY spec: the cross
// axis of a LinearLayout, or a weighted child) still wins, like Flutter's Expanded.
public final class NvContainerView extends FrameLayout {
    private int naturalWidth, naturalHeight;

    public NvContainerView(Context context) { super(context); }

    void setNaturalSize(int width, int height) {
        naturalWidth = width;
        naturalHeight = height;
        requestLayout();
    }

    @Override
    protected void onMeasure(int widthSpec, int heightSpec) {
        if (naturalWidth > 0) widthSpec = MeasureSpec.makeMeasureSpec(resolveSize(naturalWidth, widthSpec), MeasureSpec.EXACTLY);
        if (naturalHeight > 0) heightSpec = MeasureSpec.makeMeasureSpec(resolveSize(naturalHeight, heightSpec), MeasureSpec.EXACTLY);
        super.onMeasure(widthSpec, heightSpec);
    }
}
