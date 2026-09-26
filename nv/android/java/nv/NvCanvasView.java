package nv;

import android.content.Context;
import android.graphics.Canvas;
import android.view.MotionEvent;
import android.view.View;

// Custom-drawn view; onDraw and touches go to Odin. `handle` is a ^Canvas_Handle.
public final class NvCanvasView extends View {
    private final long handle;

    public NvCanvasView(Context context, long handle) {
        super(context);
        this.handle = handle;
    }

    @Override protected void onDraw(Canvas c) { nativeOnDraw(handle, c, getWidth(), getHeight()); }

    @Override
    public boolean onTouchEvent(MotionEvent e) {
        nativeOnTouch(handle, e.getActionMasked(), e.getX(), e.getY());
        return true;
    }

    private static native void nativeOnDraw(long handle, Canvas c, int width, int height);
    private static native void nativeOnTouch(long handle, int action, float x, float y);
}
