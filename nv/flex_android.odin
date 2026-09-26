#+build linux:android
package nv

// Android Row / Column backend: LinearLayout. A flex child gets main-axis size 0 plus
// layout_weight = flex, which is exactly Flutter's Expanded; the cross axis is MATCH_PARENT.
// Spacing becomes a leading margin (top or left) on every child after the first.

import "core:strings"

@(private) LAYOUT_MATCH_PARENT :: -1
@(private) LAYOUT_WRAP_CONTENT :: -2

@(private)
_flex_create :: proc(f: Flex) -> View {
	env := g_android.env

	ll_cls := jni_find_class(env, "android/widget/LinearLayout")
	ll := jni_new_object(env, ll_cls, "(Landroid/content/Context;)V", jv_obj(g_android.activity))
	jni_call_void(env, ll, "setOrientation", "(I)V", jv_int(int(f.axis)))

	lp_cls := jni_find_class(env, "android/widget/LinearLayout$LayoutParams")
	gap := android_dp(f.spacing)
	for c, i in f.children {
		main := c.flex > 0 ? 0 : LAYOUT_WRAP_CONTENT
		weight := c.flex > 0 ? f32(c.flex) : 0
		w, h := main, LAYOUT_MATCH_PARENT
		left, top := 0, 0
		if f.axis == .Vertical {
			w, h = LAYOUT_MATCH_PARENT, main
			if i > 0 do top = gap
		} else if i > 0 {
			left = gap
		}
		lp := jni_new_object(env, lp_cls, "(IIF)V", jv_int(w), jv_int(h), jv_float(weight))
		jni_call_void(env, lp, "setMargins", "(IIII)V", jv_int(left), jv_int(top), jv_int(0), jv_int(0))
		jni_call_void(env, ll, "addView", "(Landroid/view/View;Landroid/view/ViewGroup$LayoutParams;)V",
			jv_obj(jobject(c.view)), jv_obj(lp))
		jni_delete_local_ref(env, lp)
	}
	jni_delete_local_ref(env, lp_cls)
	jni_delete_local_ref(env, ll_cls)

	root := jni_new_global_ref(env, ll)
	jni_delete_local_ref(env, ll)
	return View(root)
}

@(private)
_label_create :: proc(text: string) -> View {
	env := g_android.env

	tv_cls := jni_find_class(env, "android/widget/TextView")
	tv := jni_new_object(env, tv_cls, "(Landroid/content/Context;)V", jv_obj(g_android.activity))
	s := jni_string(env, strings.clone_to_cstring(text, context.temp_allocator))
	jni_call_void(env, tv, "setText", "(Ljava/lang/CharSequence;)V", jv_obj(s))
	jni_call_void(env, tv, "setTextSize", "(F)V", jv_float(20)) // sp
	jni_call_void(env, tv, "setTypeface", "(Landroid/graphics/Typeface;I)V", jv_obj(nil), jv_int(1)) // Typeface.BOLD
	jni_delete_local_ref(env, s)
	jni_delete_local_ref(env, tv_cls)

	root := jni_new_global_ref(env, tv)
	jni_delete_local_ref(env, tv)
	return View(root)
}
