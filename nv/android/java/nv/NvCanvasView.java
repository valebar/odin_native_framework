package nv;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.Path;
import android.view.InputDevice;
import android.view.MotionEvent;
import android.view.ScaleGestureDetector;
import android.view.View;

// Custom-drawn view; onDraw, touches, two fingers' pinch and the mouse wheel go to Odin. `handle`
// is a ^Canvas_Handle.
public final class NvCanvasView extends View {
    private final long handle;
    private final ScaleGestureDetector pinch;
    private float span0, spanY0; // the pinch's spans when it began

    public NvCanvasView(Context context, long handle) {
        super(context);
        this.handle = handle;
        pinch = new ScaleGestureDetector(context, new ScaleGestureDetector.SimpleOnScaleGestureListener() {
            @Override public boolean onScaleBegin(ScaleGestureDetector d) {
                span0 = d.getCurrentSpan();
                spanY0 = d.getCurrentSpanY();
                nativeOnScale(NvCanvasView.this.handle, 0, 1, 1, d.getFocusX(), d.getFocusY());
                return true;
            }
            @Override public boolean onScale(ScaleGestureDetector d) {
                nativeOnScale(NvCanvasView.this.handle, 1, span0 > 0 ? d.getCurrentSpan() / span0 : 1,
                        spanY0 > 0 ? d.getCurrentSpanY() / spanY0 : 1, d.getFocusX(), d.getFocusY());
                return true;
            }
            @Override public void onScaleEnd(ScaleGestureDetector d) {
                nativeOnScale(NvCanvasView.this.handle, 2, span0 > 0 ? d.getCurrentSpan() / span0 : 1,
                        spanY0 > 0 ? d.getCurrentSpanY() / spanY0 : 1, d.getFocusX(), d.getFocusY());
            }
        });
        pinch.setQuickScaleEnabled(false); // a double tap stays the app's
    }

    @Override protected void onDraw(Canvas c) { nativeOnDraw(handle, c, getWidth(), getHeight()); }

    @Override
    public boolean onTouchEvent(MotionEvent e) {
        pinch.onTouchEvent(e);
        nativeOnTouch(handle, e.getActionMasked(), e.getX(), e.getY(), e.getMetaState());
        return true;
    }

    // A mouse's wheel; Odin returns false when the canvas has no on_scroll.
    @Override
    public boolean onGenericMotionEvent(MotionEvent e) {
        if (e.isFromSource(InputDevice.SOURCE_CLASS_POINTER) && e.getActionMasked() == MotionEvent.ACTION_SCROLL
                && nativeOnScroll(handle, e.getAxisValue(MotionEvent.AXIS_HSCROLL), e.getAxisValue(MotionEvent.AXIS_VSCROLL),
                        e.getX(), e.getY(), e.getMetaState())) {
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

    // The closed polygon through the first n floats of pts, filled with paint (non-zero winding).
    static void fillPolygon(Canvas c, float[] pts, int n, Paint paint) {
        Path p = polyline;
        p.rewind();
        p.moveTo(pts[0], pts[1]);
        for (int i = 2; i + 1 < n; i += 2) p.lineTo(pts[i], pts[i + 1]);
        p.close();
        c.drawPath(p, paint);
    }

    private static native void nativeOnDraw(long handle, Canvas c, int width, int height);
    private static native void nativeOnTouch(long handle, int action, float x, float y, int meta);
    private static native boolean nativeOnScroll(long handle, float h, float v, float x, float y, int meta);
    private static native void nativeOnScale(long handle, int phase, float scale, float vscale, float fx, float fy);
}
