// Техника (M5): цвет детали × пиксельный узор (общий код — body.gdshaderinc). Пишет 1 в stencil, как
// StandardMaterial3D со STENCIL_MODE_XRAY: силуэт сквозь препятствия — следующий проход
// (BodyMaterial.xray_pass) рисуется там, где stencil не 1.
shader_type spatial;
render_mode cull_back;
stencil_mode write, compare_always, 1;

#define FACE_DECALS                     // обшивка по граням: меши размечены MeshKit.face_mapped
#include "res://src/render/shaders/body.gdshaderinc"
