package nv;

import android.view.View;
import android.view.ViewGroup;
import android.widget.AdapterView;
import android.widget.BaseAdapter;

// Forwards ListView adapter + click callbacks to Odin; `handle` is a ^List_Handle.
public final class NvListAdapter extends BaseAdapter implements AdapterView.OnItemClickListener {
    private final long handle;

    public NvListAdapter(long handle) { this.handle = handle; }

    @Override public int getCount() { return nativeCount(handle); }
    @Override public Object getItem(int position) { return null; }
    @Override public long getItemId(int position) { return position; }

    @Override
    public View getView(int position, View convertView, ViewGroup parent) {
        return nativeGetView(handle, position, convertView, parent);
    }

    @Override
    public void onItemClick(AdapterView<?> parent, View view, int position, long id) {
        nativeOnSelect(handle, position);
    }

    private static native int nativeCount(long handle);
    private static native View nativeGetView(long handle, int position, View convertView, ViewGroup parent);
    private static native void nativeOnSelect(long handle, int position);
}
