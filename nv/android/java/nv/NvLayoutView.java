package nv;

import android.content.Context;
import android.view.ViewTreeObserver;
import android.widget.FrameLayout;

// FrameLayout that reports its size to Odin (`handle` is a ^Layout_Handle) before a frame at that
// size is drawn: a new size cancels the draw (onPreDraw returns false), so the traversal Odin's
// answer asks for runs first. Reporting from onLayout would request a layout during layout.
public final class NvLayoutView extends FrameLayout implements ViewTreeObserver.OnPreDrawListener {
    private final long handle;
    private ViewTreeObserver observer;
    private int reportedWidth = -1, reportedHeight = -1;

    public NvLayoutView(Context context, long handle) {
        super(context);
        this.handle = handle;
    }

    @Override
    protected void onAttachedToWindow() {
        super.onAttachedToWindow();
        observer = getViewTreeObserver();
        observer.addOnPreDrawListener(this);
    }

    @Override
    protected void onDetachedFromWindow() {
        if (observer != null && observer.isAlive()) observer.removeOnPreDrawListener(this);
        observer = null;
        super.onDetachedFromWindow();
    }

    @Override
    public boolean onPreDraw() {
        int w = getWidth(), h = getHeight();
        if (w == reportedWidth && h == reportedHeight) return true;
        reportedWidth = w;
        reportedHeight = h;
        if (w <= 0 || h <= 0) return true;
        nativeOnLayout(handle, w, h);
        return false;
    }

    private static native void nativeOnLayout(long handle, int width, int height);
}
