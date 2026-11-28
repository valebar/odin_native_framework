#+build windows
#+private
package nv

// Direct2D and DirectWrite as far as the canvas uses them (canvas_windows.odin). Hand-written, as
// Odin's vendor has Direct3D but not these: every vtable lists each method in the SDK's order
// (d2d1.h, d2d1_1.h, dwrite*.h, 10.0.26100; MSVC reverses overloads declared together, and none
// of those is called), the unused ones as rawptr. Structs a method takes by value are small float
// pairs (D2D1_POINT_2F), passed as the C ABI does.

import win "core:sys/windows"

foreign import d2d1 "system:d2d1.lib"
foreign import dwrite "system:dwrite.lib"

D2D1_COLOR_F       :: struct { r, g, b, a: f32 }
D2D1_POINT_2F      :: struct { x, y: f32 }
D2D1_SIZE_F        :: struct { width, height: f32 }
D2D1_SIZE_U        :: struct { width, height: u32 }
D2D1_RECT_F        :: struct { left, top, right, bottom: f32 }
D2D1_RECT_U        :: struct { left, top, right, bottom: u32 }
D2D1_ELLIPSE       :: struct { point: D2D1_POINT_2F, radius_x, radius_y: f32 }
D2D1_MATRIX_3X2_F  :: struct { m11, m12, m21, m22, dx, dy: f32 }
D2D1_ARC_SEGMENT   :: struct { point: D2D1_POINT_2F, size: D2D1_SIZE_F, rotation: f32, sweep: u32, arc_size: u32 }
D2D1_PIXEL_FORMAT  :: struct { format: u32, alpha_mode: u32 }
D2D1_BITMAP_PROPERTIES :: struct { pixel_format: D2D1_PIXEL_FORMAT, dpi_x, dpi_y: f32 }
D2D1_RENDER_TARGET_PROPERTIES :: struct {
	type:         u32,
	pixel_format: D2D1_PIXEL_FORMAT,
	dpi_x, dpi_y: f32,
	usage:        u32,
	min_level:    u32,
}
D2D1_STROKE_STYLE_PROPERTIES :: struct {
	start_cap, end_cap, dash_cap, line_join: u32,
	miter_limit: f32,
	dash_style:  u32,
	dash_offset: f32,
}

DXGI_FORMAT_UNKNOWN        :: 0
DXGI_FORMAT_B8G8R8A8_UNORM :: 87
D2D1_ALPHA_MODE_PREMULTIPLIED :: 1
D2D1_ALPHA_MODE_IGNORE        :: 3
D2D1_CAP_STYLE_FLAT  :: 0
D2D1_CAP_STYLE_ROUND :: 2
D2D1_LINE_JOIN_MITER :: 0
D2D1_LINE_JOIN_ROUND :: 2
D2D1_FIGURE_BEGIN_FILLED :: 0
D2D1_FIGURE_BEGIN_HOLLOW :: 1
D2D1_FIGURE_END_OPEN     :: 0
D2D1_FIGURE_END_CLOSED   :: 1
D2D1_FILL_MODE_WINDING   :: 1
D2D1_SWEEP_DIRECTION_COUNTER_CLOCKWISE :: 0
D2D1_SWEEP_DIRECTION_CLOCKWISE         :: 1
D2D1_ARC_SIZE_SMALL :: 0
D2D1_ARC_SIZE_LARGE :: 1
D2D1_ANTIALIAS_MODE_PER_PRIMITIVE :: 0
D2D1_ANTIALIAS_MODE_ALIASED       :: 1
D2D1_BITMAP_INTERPOLATION_MODE_LINEAR      :: 1
D2D1_INTERPOLATION_MODE_HIGH_QUALITY_CUBIC :: 5
D2D1_DRAW_TEXT_OPTIONS_NONE :: 0
D2DERR_RECREATE_TARGET :: win.HRESULT(-2003238900) // 0x8899000C

DWRITE_FACTORY_TYPE_SHARED     :: 0
DWRITE_FONT_STYLE_NORMAL       :: 0
DWRITE_FONT_STYLE_ITALIC       :: 2
DWRITE_FONT_STRETCH_NORMAL     :: 5
DWRITE_MEASURING_MODE_NATURAL  :: 0
DWRITE_WORD_WRAPPING_NO_WRAP   :: 1
DWRITE_LINE_SPACING_METHOD_UNIFORM :: 1

DWRITE_TEXT_METRICS :: struct {
	left, top, width, width_including_trailing_whitespace, height: f32,
	layout_width, layout_height: f32,
	max_bidi_reordering_depth, line_count: u32,
}

DWRITE_FONT_METRICS :: struct {
	design_units_per_em:     u16,
	ascent:                  u16,
	descent:                 u16,
	line_gap:                i16,
	cap_height:              u16,
	x_height:                u16,
	underline_position:      i16,
	underline_thickness:     u16,
	strikethrough_position:  i16,
	strikethrough_thickness: u16,
}

IID_ID2D1Factory       := win.GUID{0x06152247, 0x6f50, 0x465a, {0x92, 0x45, 0x11, 0x8b, 0xfd, 0x3b, 0x60, 0x07}}
IID_ID2D1DeviceContext := win.GUID{0xe8f7fe7a, 0x191c, 0x466d, {0xad, 0x95, 0x97, 0x56, 0x78, 0xbd, 0xa9, 0x98}}
IID_IDWriteFactory     := win.GUID{0xb859ee5a, 0xd838, 0x4b5b, {0xa2, 0xe8, 0x1a, 0xdc, 0x7d, 0x93, 0xdb, 0x48}}
IID_IDWriteFactory5    := win.GUID{0x958db99a, 0xbe2a, 0x4f09, {0xaf, 0x7d, 0x65, 0x18, 0x98, 0x03, 0xd1, 0xd3}}

@(default_calling_convention="system")
foreign d2d1 {
	D2D1CreateFactory :: proc(type: u32, riid: ^win.GUID, options: rawptr, factory: ^rawptr) -> win.HRESULT ---
}

@(default_calling_convention="system")
foreign dwrite {
	DWriteCreateFactory :: proc(type: u32, iid: ^win.GUID, factory: ^rawptr) -> win.HRESULT ---
}

// The IUnknown release every interface has.
com_release :: proc "contextless" (p: rawptr) {
	if p != nil do (^win.IUnknown)(p)->Release()
}

// ---- Direct2D ----

ID2D1Factory :: struct #raw_union {
	#subtype iunknown: win.IUnknown,
	using vt: ^ID2D1Factory_VTable,
}
ID2D1Factory_VTable :: struct {
	using iunknown_vtable: win.IUnknown_VTable,
	ReloadSystemMetrics, GetDesktopDpi, CreateRectangleGeometry, CreateRoundedRectangleGeometry,
	CreateEllipseGeometry, CreateGeometryGroup, CreateTransformedGeometry: rawptr,
	CreatePathGeometry: proc "system" (this: ^ID2D1Factory, geometry: ^^ID2D1PathGeometry) -> win.HRESULT,
	CreateStrokeStyle: proc "system" (this: ^ID2D1Factory, props: ^D2D1_STROKE_STYLE_PROPERTIES, dashes: [^]f32, count: u32, style: ^^ID2D1StrokeStyle) -> win.HRESULT,
	CreateDrawingStateBlock, CreateWicBitmapRenderTarget: rawptr,
	CreateHwndRenderTarget: rawptr,
	CreateDxgiSurfaceRenderTarget: rawptr,
	CreateDCRenderTarget: proc "system" (this: ^ID2D1Factory, props: ^D2D1_RENDER_TARGET_PROPERTIES, target: ^^ID2D1DCRenderTarget) -> win.HRESULT,
}

ID2D1Resource :: struct #raw_union {
	#subtype iunknown: win.IUnknown,
	using vt: ^ID2D1Resource_VTable,
}
ID2D1Resource_VTable :: struct {
	using iunknown_vtable: win.IUnknown_VTable,
	GetFactory: rawptr,
}

ID2D1RenderTarget :: struct #raw_union {
	#subtype resource: ID2D1Resource,
	using vt: ^ID2D1RenderTarget_VTable,
}
ID2D1RenderTarget_VTable :: struct {
	using resource_vtable: ID2D1Resource_VTable,
	CreateBitmap: proc "system" (this: ^ID2D1RenderTarget, size: D2D1_SIZE_U, src: rawptr, pitch: u32, props: ^D2D1_BITMAP_PROPERTIES, bitmap: ^^ID2D1Bitmap) -> win.HRESULT,
	CreateBitmapFromWicBitmap, CreateSharedBitmap, CreateBitmapBrush: rawptr,
	CreateSolidColorBrush: proc "system" (this: ^ID2D1RenderTarget, color: ^D2D1_COLOR_F, props: rawptr, brush: ^^ID2D1SolidColorBrush) -> win.HRESULT,
	CreateGradientStopCollection, CreateLinearGradientBrush, CreateRadialGradientBrush,
	CreateCompatibleRenderTarget, CreateLayer, CreateMesh: rawptr,
	DrawLine: proc "system" (this: ^ID2D1RenderTarget, p0, p1: D2D1_POINT_2F, brush: ^ID2D1Brush, width: f32, style: ^ID2D1StrokeStyle),
	DrawRectangle: proc "system" (this: ^ID2D1RenderTarget, rect: ^D2D1_RECT_F, brush: ^ID2D1Brush, width: f32, style: ^ID2D1StrokeStyle),
	FillRectangle: proc "system" (this: ^ID2D1RenderTarget, rect: ^D2D1_RECT_F, brush: ^ID2D1Brush),
	DrawRoundedRectangle, FillRoundedRectangle: rawptr,
	DrawEllipse: proc "system" (this: ^ID2D1RenderTarget, ellipse: ^D2D1_ELLIPSE, brush: ^ID2D1Brush, width: f32, style: ^ID2D1StrokeStyle),
	FillEllipse: proc "system" (this: ^ID2D1RenderTarget, ellipse: ^D2D1_ELLIPSE, brush: ^ID2D1Brush),
	DrawGeometry: proc "system" (this: ^ID2D1RenderTarget, geometry: ^ID2D1Geometry, brush: ^ID2D1Brush, width: f32, style: ^ID2D1StrokeStyle),
	FillGeometry: proc "system" (this: ^ID2D1RenderTarget, geometry: ^ID2D1Geometry, brush: ^ID2D1Brush, opacity_brush: ^ID2D1Brush),
	FillMesh, FillOpacityMask: rawptr,
	DrawBitmap: proc "system" (this: ^ID2D1RenderTarget, bitmap: ^ID2D1Bitmap, dest: ^D2D1_RECT_F, opacity: f32, interpolation: u32, src: ^D2D1_RECT_F),
	DrawText: proc "system" (this: ^ID2D1RenderTarget, text: [^]u16, length: u32, format: ^IDWriteTextFormat, rect: ^D2D1_RECT_F, brush: ^ID2D1Brush, options: u32, measuring: u32),
	DrawTextLayout, DrawGlyphRun: rawptr,
	SetTransform: proc "system" (this: ^ID2D1RenderTarget, m: ^D2D1_MATRIX_3X2_F),
	GetTransform: proc "system" (this: ^ID2D1RenderTarget, m: ^D2D1_MATRIX_3X2_F),
	SetAntialiasMode, GetAntialiasMode, SetTextAntialiasMode, GetTextAntialiasMode,
	SetTextRenderingParams, GetTextRenderingParams, SetTags, GetTags, PushLayer, PopLayer, Flush,
	SaveDrawingState, RestoreDrawingState: rawptr,
	PushAxisAlignedClip: proc "system" (this: ^ID2D1RenderTarget, rect: ^D2D1_RECT_F, mode: u32),
	PopAxisAlignedClip: proc "system" (this: ^ID2D1RenderTarget),
	Clear: proc "system" (this: ^ID2D1RenderTarget, color: ^D2D1_COLOR_F),
	BeginDraw: proc "system" (this: ^ID2D1RenderTarget),
	EndDraw: proc "system" (this: ^ID2D1RenderTarget, tag1, tag2: ^u64) -> win.HRESULT,
	GetPixelFormat: rawptr,
	SetDpi: proc "system" (this: ^ID2D1RenderTarget, dpi_x, dpi_y: f32),
	GetDpi, GetSize, GetPixelSize, GetMaximumBitmapSize, IsSupported: rawptr,
}

ID2D1DCRenderTarget :: struct #raw_union {
	#subtype render_target: ID2D1RenderTarget,
	using vt: ^ID2D1DCRenderTarget_VTable,
}
ID2D1DCRenderTarget_VTable :: struct {
	using render_target_vtable: ID2D1RenderTarget_VTable,
	BindDC: proc "system" (this: ^ID2D1DCRenderTarget, dc: win.HDC, rect: ^win.RECT) -> win.HRESULT,
}

// ID2D1DeviceContext (Windows 8+), queried from a render target for its DrawBitmap's cubic filter.
ID2D1DeviceContext :: struct #raw_union {
	#subtype render_target: ID2D1RenderTarget,
	using vt: ^ID2D1DeviceContext_VTable,
}
ID2D1DeviceContext_VTable :: struct {
	using render_target_vtable: ID2D1RenderTarget_VTable,
	CreateBitmap1, CreateBitmapFromWicBitmap1, CreateColorContext, CreateColorContextFromFilename,
	CreateColorContextFromWicColorContext, CreateBitmapFromDxgiSurface, CreateEffect,
	CreateGradientStopCollection1, CreateImageBrush, CreateBitmapBrush1, CreateCommandList,
	IsDxgiFormatSupported, IsBufferPrecisionSupported, GetImageLocalBounds, GetImageWorldBounds,
	GetGlyphRunWorldBounds, GetDevice, SetTarget, GetTarget, SetRenderingControls,
	GetRenderingControls, SetPrimitiveBlend, GetPrimitiveBlend, SetUnitMode, GetUnitMode,
	DrawGlyphRun1, DrawImage, DrawGdiMetafile: rawptr,
	DrawBitmap1: proc "system" (this: ^ID2D1DeviceContext, bitmap: ^ID2D1Bitmap, dest: ^D2D1_RECT_F, opacity: f32, interpolation: u32, src: ^D2D1_RECT_F, perspective: rawptr),
	PushLayer1, InvalidateEffectInputRectangle, GetEffectInvalidRectangleCount,
	GetEffectInvalidRectangles, GetEffectRequiredInputRectangles, FillOpacityMask1: rawptr,
}

ID2D1Brush :: struct #raw_union {
	#subtype resource: ID2D1Resource,
	using vt: ^ID2D1Brush_VTable,
}
ID2D1Brush_VTable :: struct {
	using resource_vtable: ID2D1Resource_VTable,
	SetOpacity, SetTransform, GetOpacity, GetTransform: rawptr,
}

ID2D1SolidColorBrush :: struct #raw_union {
	#subtype brush: ID2D1Brush,
	using vt: ^ID2D1SolidColorBrush_VTable,
}
ID2D1SolidColorBrush_VTable :: struct {
	using brush_vtable: ID2D1Brush_VTable,
	SetColor: proc "system" (this: ^ID2D1SolidColorBrush, color: ^D2D1_COLOR_F),
	GetColor: rawptr,
}

ID2D1StrokeStyle :: struct #raw_union {
	#subtype resource: ID2D1Resource,
	using vt: ^ID2D1Resource_VTable,
}

ID2D1Geometry :: struct #raw_union {
	#subtype resource: ID2D1Resource,
	using vt: ^ID2D1Geometry_VTable,
}
ID2D1Geometry_VTable :: struct {
	using resource_vtable: ID2D1Resource_VTable,
	GetBounds, GetWidenedBounds, StrokeContainsPoint, FillContainsPoint, CompareWithGeometry,
	Simplify, Tessellate, CombineWithGeometry, Outline, ComputeArea, ComputeLength,
	ComputePointAtLength, Widen: rawptr,
}

ID2D1PathGeometry :: struct #raw_union {
	#subtype geometry: ID2D1Geometry,
	using vt: ^ID2D1PathGeometry_VTable,
}
ID2D1PathGeometry_VTable :: struct {
	using geometry_vtable: ID2D1Geometry_VTable,
	Open: proc "system" (this: ^ID2D1PathGeometry, sink: ^^ID2D1GeometrySink) -> win.HRESULT,
	Stream, GetSegmentCount, GetFigureCount: rawptr,
}

ID2D1GeometrySink :: struct #raw_union {
	#subtype iunknown: win.IUnknown,
	using vt: ^ID2D1GeometrySink_VTable,
}
ID2D1GeometrySink_VTable :: struct {
	using iunknown_vtable: win.IUnknown_VTable,
	// ID2D1SimplifiedGeometrySink
	SetFillMode: proc "system" (this: ^ID2D1GeometrySink, mode: u32),
	SetSegmentFlags: rawptr,
	BeginFigure: proc "system" (this: ^ID2D1GeometrySink, start: D2D1_POINT_2F, begin: u32),
	AddLines: proc "system" (this: ^ID2D1GeometrySink, points: [^]D2D1_POINT_2F, count: u32),
	AddBeziers: rawptr,
	EndFigure: proc "system" (this: ^ID2D1GeometrySink, end: u32),
	Close: proc "system" (this: ^ID2D1GeometrySink) -> win.HRESULT,
	// ID2D1GeometrySink
	AddLine, AddBezier, AddQuadraticBezier, AddQuadraticBeziers: rawptr,
	AddArc: proc "system" (this: ^ID2D1GeometrySink, arc: ^D2D1_ARC_SEGMENT),
}

ID2D1Bitmap :: struct #raw_union {
	#subtype resource: ID2D1Resource,
	using vt: ^ID2D1Bitmap_VTable,
}
ID2D1Bitmap_VTable :: struct {
	using resource_vtable: ID2D1Resource_VTable, // ID2D1Image adds nothing
	GetSize, GetPixelSize, GetPixelFormat, GetDpi, CopyFromBitmap, CopyFromRenderTarget: rawptr,
	CopyFromMemory: proc "system" (this: ^ID2D1Bitmap, dst: ^D2D1_RECT_U, src: rawptr, pitch: u32) -> win.HRESULT,
}

// ---- DirectWrite ----

IDWriteFactory5 :: struct #raw_union {
	#subtype iunknown: win.IUnknown,
	using vt: ^IDWriteFactory5_VTable,
}
// IDWriteFactory through IDWriteFactory5 (Windows 10 1703+); a plain IDWriteFactory uses the first part.
IDWriteFactory5_VTable :: struct {
	using iunknown_vtable: win.IUnknown_VTable,
	GetSystemFontCollection: proc "system" (this: ^IDWriteFactory5, collection: ^^IDWriteFontCollection, check_updates: win.BOOL) -> win.HRESULT,
	CreateCustomFontCollection, RegisterFontCollectionLoader, UnregisterFontCollectionLoader,
	CreateFontFileReference, CreateCustomFontFileReference, CreateFontFace, CreateRenderingParams,
	CreateMonitorRenderingParams, CreateCustomRenderingParams: rawptr,
	RegisterFontFileLoader: proc "system" (this: ^IDWriteFactory5, loader: ^IDWriteInMemoryFontFileLoader) -> win.HRESULT,
	UnregisterFontFileLoader: rawptr,
	CreateTextFormat: proc "system" (this: ^IDWriteFactory5, family: win.wstring, collection: ^IDWriteFontCollection, weight, style, stretch: u32, size: f32, locale: win.wstring, format: ^^IDWriteTextFormat) -> win.HRESULT,
	CreateTypography, GetGdiInterop: rawptr,
	CreateTextLayout: proc "system" (this: ^IDWriteFactory5, text: [^]u16, length: u32, format: ^IDWriteTextFormat, max_width, max_height: f32, layout: ^^IDWriteTextLayout) -> win.HRESULT,
	CreateGdiCompatibleTextLayout, CreateEllipsisTrimmingSign, CreateTextAnalyzer,
	CreateNumberSubstitution, CreateGlyphRunAnalysis: rawptr,
	// IDWriteFactory1
	GetEudcFontCollection, CreateCustomRenderingParams1: rawptr,
	// IDWriteFactory2
	GetSystemFontFallback, CreateFontFallbackBuilder, TranslateColorGlyphRun,
	CreateCustomRenderingParams2, CreateGlyphRunAnalysis2: rawptr,
	// IDWriteFactory3
	CreateGlyphRunAnalysis3, CreateCustomRenderingParams3, CreateFontFaceReference_b,
	CreateFontFaceReference_a, GetSystemFontSet, CreateFontSetBuilder: rawptr,
	CreateFontCollectionFromFontSet: proc "system" (this: ^IDWriteFactory5, set: ^IDWriteFontSet, collection: ^^IDWriteFontCollection) -> win.HRESULT,
	GetSystemFontCollection3, GetFontDownloadQueue: rawptr,
	// IDWriteFactory4
	TranslateColorGlyphRun4, ComputeGlyphOrigins_b, ComputeGlyphOrigins_a: rawptr,
	// IDWriteFactory5
	CreateFontSetBuilder1: proc "system" (this: ^IDWriteFactory5, builder: ^^IDWriteFontSetBuilder1) -> win.HRESULT,
	CreateInMemoryFontFileLoader: proc "system" (this: ^IDWriteFactory5, loader: ^^IDWriteInMemoryFontFileLoader) -> win.HRESULT,
	CreateHttpFontFileLoader, AnalyzeContainerType, UnpackFontFile: rawptr,
}

IDWriteTextFormat :: struct #raw_union {
	#subtype iunknown: win.IUnknown,
	using vt: ^IDWriteTextFormat_VTable,
}
IDWriteTextFormat_VTable :: struct {
	using iunknown_vtable: win.IUnknown_VTable,
	SetTextAlignment, SetParagraphAlignment: rawptr,
	SetWordWrapping: proc "system" (this: ^IDWriteTextFormat, wrapping: u32) -> win.HRESULT,
	SetReadingDirection, SetFlowDirection, SetIncrementalTabStop, SetTrimming: rawptr,
	SetLineSpacing: proc "system" (this: ^IDWriteTextFormat, method: u32, spacing, baseline: f32) -> win.HRESULT,
	GetTextAlignment, GetParagraphAlignment, GetWordWrapping, GetReadingDirection,
	GetFlowDirection, GetIncrementalTabStop, GetTrimming, GetLineSpacing, GetFontCollection,
	GetFontFamilyNameLength, GetFontFamilyName, GetFontWeight, GetFontStyle, GetFontStretch,
	GetFontSize, GetLocaleNameLength, GetLocaleName: rawptr,
}

IDWriteTextLayout :: struct #raw_union {
	#subtype text_format: IDWriteTextFormat,
	using vt: ^IDWriteTextLayout_VTable,
}
IDWriteTextLayout_VTable :: struct {
	using text_format_vtable: IDWriteTextFormat_VTable,
	SetMaxWidth, SetMaxHeight, SetFontCollection, SetFontFamilyName, SetFontWeight, SetFontStyle,
	SetFontStretch, SetFontSize, SetUnderline, SetStrikethrough, SetDrawingEffect, SetInlineObject,
	SetTypography, SetLocaleName, GetMaxWidth, GetMaxHeight, GetFontCollection1,
	GetFontFamilyNameLength1, GetFontFamilyName1, GetFontWeight1, GetFontStyle1, GetFontStretch1,
	GetFontSize1, GetUnderline, GetStrikethrough, GetDrawingEffect, GetInlineObject, GetTypography,
	GetLocaleNameLength1, GetLocaleName1, Draw, GetLineMetrics: rawptr,
	GetMetrics: proc "system" (this: ^IDWriteTextLayout, metrics: ^DWRITE_TEXT_METRICS) -> win.HRESULT,
	GetOverhangMetrics, GetClusterMetrics, DetermineMinWidth, HitTestPoint, HitTestTextPosition,
	HitTestTextRange: rawptr,
}

IDWriteFontCollection :: struct #raw_union {
	#subtype iunknown: win.IUnknown,
	using vt: ^IDWriteFontCollection_VTable,
}
IDWriteFontCollection_VTable :: struct {
	using iunknown_vtable: win.IUnknown_VTable,
	GetFontFamilyCount: proc "system" (this: ^IDWriteFontCollection) -> u32,
	GetFontFamily: proc "system" (this: ^IDWriteFontCollection, index: u32, family: ^^IDWriteFontFamily) -> win.HRESULT,
	FindFamilyName: proc "system" (this: ^IDWriteFontCollection, name: win.wstring, index: ^u32, exists: ^win.BOOL) -> win.HRESULT,
	GetFontFromFontFace: rawptr,
}

IDWriteFontFamily :: struct #raw_union {
	#subtype iunknown: win.IUnknown,
	using vt: ^IDWriteFontFamily_VTable,
}
IDWriteFontFamily_VTable :: struct {
	using iunknown_vtable: win.IUnknown_VTable,
	GetFontCollection, GetFontCount, GetFont: rawptr, // IDWriteFontList
	GetFamilyNames: proc "system" (this: ^IDWriteFontFamily, names: ^^IDWriteLocalizedStrings) -> win.HRESULT,
	GetFirstMatchingFont: proc "system" (this: ^IDWriteFontFamily, weight, stretch, style: u32, font: ^^IDWriteFont) -> win.HRESULT,
	GetMatchingFonts: rawptr,
}

IDWriteFont :: struct #raw_union {
	#subtype iunknown: win.IUnknown,
	using vt: ^IDWriteFont_VTable,
}
IDWriteFont_VTable :: struct {
	using iunknown_vtable: win.IUnknown_VTable,
	GetFontFamily, GetWeight, GetStretch, GetStyle, IsSymbolFont, GetFaceNames,
	GetInformationalStrings, GetSimulations: rawptr,
	GetMetrics: proc "system" (this: ^IDWriteFont, metrics: ^DWRITE_FONT_METRICS),
	HasCharacter, CreateFontFace: rawptr,
}

IDWriteLocalizedStrings :: struct #raw_union {
	#subtype iunknown: win.IUnknown,
	using vt: ^IDWriteLocalizedStrings_VTable,
}
IDWriteLocalizedStrings_VTable :: struct {
	using iunknown_vtable: win.IUnknown_VTable,
	GetCount, FindLocaleName, GetLocaleNameLength, GetLocaleName: rawptr,
	GetStringLength: proc "system" (this: ^IDWriteLocalizedStrings, index: u32, length: ^u32) -> win.HRESULT,
	GetString: proc "system" (this: ^IDWriteLocalizedStrings, index: u32, buf: [^]u16, size: u32) -> win.HRESULT,
}

IDWriteInMemoryFontFileLoader :: struct #raw_union {
	#subtype iunknown: win.IUnknown,
	using vt: ^IDWriteInMemoryFontFileLoader_VTable,
}
IDWriteInMemoryFontFileLoader_VTable :: struct {
	using iunknown_vtable: win.IUnknown_VTable,
	CreateStreamFromKey: rawptr, // IDWriteFontFileLoader
	CreateInMemoryFontFileReference: proc "system" (this: ^IDWriteInMemoryFontFileLoader, factory: ^IDWriteFactory5, data: rawptr, size: u32, owner: ^win.IUnknown, file: ^^IDWriteFontFile) -> win.HRESULT,
	GetFileCount: rawptr,
}

IDWriteFontSetBuilder1 :: struct #raw_union {
	#subtype iunknown: win.IUnknown,
	using vt: ^IDWriteFontSetBuilder1_VTable,
}
IDWriteFontSetBuilder1_VTable :: struct {
	using iunknown_vtable: win.IUnknown_VTable,
	AddFontFaceReference_b, AddFontFaceReference_a, AddFontSet: rawptr,
	CreateFontSet: proc "system" (this: ^IDWriteFontSetBuilder1, set: ^^IDWriteFontSet) -> win.HRESULT,
	AddFontFile: proc "system" (this: ^IDWriteFontSetBuilder1, file: ^IDWriteFontFile) -> win.HRESULT,
}

IDWriteFontSet  :: struct { using iunknown: win.IUnknown }
IDWriteFontFile :: struct { using iunknown: win.IUnknown }
