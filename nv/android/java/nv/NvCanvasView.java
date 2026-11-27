package nv;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.Path;
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

    private static final Path polyline = new Path(); // the UI thread's, reused

    // One stroked path through the first n floats of pts (x0, y0, x1, y1, ..), with round joins;
    // the paint's join is put back, since rects keep theirs.
    static void strokePolyline(Canvas c, float[] pts, int n, Paint paint) {
        Path p = polyline;
        p.rewind();
        p.moveTo(pts[0], pts[1]);
        for (int i = 2; i + 1 < n; i += 2) p.lineTo(pts[i], pts[i + 1]);
        Paint.Join join = paint.getStrokeJoin();
        paint.setStrokeJoin(Paint.Join.ROUND);
        c.drawPath(p, paint);
        paint.setStrokeJoin(join);
    }

    private static native void nativeOnDraw(long handle, Canvas c, int width, int height);
    private static native void nativeOnTouch(long handle, int action, float x, float y);
    private static native boolean nativeOnScroll(long handle, float h, float v);
}
