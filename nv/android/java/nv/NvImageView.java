package nv;

import android.content.Context;
import android.widget.ImageView;

// ImageView whose natural size is set from Odin (px) rather than taken from the drawable, so an
// explicit size can be smaller than the bitmap.
public final class NvImageView extends ImageView {
    private int naturalWidth, naturalHeight;

    public NvImageView(Context context) { super(context); }

    void setNaturalSize(int width, int height) {
        naturalWidth = width;
        naturalHeight = height;
        requestLayout();
    }

    @Override
    protected void onMeasure(int widthSpec, int heightSpec) {
        setMeasuredDimension(resolveSize(naturalWidth, widthSpec), resolveSize(naturalHeight, heightSpec));
    }
}
