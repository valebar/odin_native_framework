package nv;

import android.content.Context;
import android.graphics.Canvas;
import android.view.InputDevice;
import android.view.MotionEvent;
import android.view.View;

// Custom-drawn view; onDraw, touches and the mouse wheel go to Odin. `handle` is a ^Canvas_Handle.
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

    // A mouse's wheel; Odin returns false when the canvas has no on_scroll.
    @Override
    public boolean onGenericMotionEvent(MotionEvent e) {
        if (e.isFromSource(InputDevice.SOURCE_CLASS_POINTER) && e.getActionMasked() == MotionEvent.ACTION_SCROLL
                && nativeOnScroll(handle, e.getAxisValue(MotionEvent.AXIS_HSCROLL), e.getAxisValue(MotionEvent.AXIS_VSCROLL))) {
            return true;
        }
        return super.onGenericMotionEvent(e);
    }

    private static native void nativeOnDraw(long handle, Canvas c, int width, int height);
    private static native void nativeOnTouch(long handle, int action, float x, float y);
    private static native boolean nativeOnScroll(long handle, float h, float v);
}
