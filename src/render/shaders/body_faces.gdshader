// Челноки и капсула десанта (M5): цвет детали × пиксельный узор (общий код — body.gdshaderinc), обшивка
// по граням, как у машин, но без stencil — силуэт машины сквозь них виден.
shader_type spatial;
render_mode cull_back;

#define FACE_DETAILS                    // обшивка по граням: меши размечены MeshKit.face_mapped
#include "res://src/render/shaders/body.gdshaderinc"
