shader_type canvas_item;

// Vignette tepi + grain animasi halus. Dipakai overlay board.

uniform vec4 vignette_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float strength : hint_range(0.0, 1.0) = 0.65;
uniform float grain : hint_range(0.0, 0.2) = 0.08;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV - vec2(0.5);
	float d = length(uv * vec2(1.2, 1.0));
	float v = smoothstep(0.35, 0.85, d) * strength;
	float g = (hash(FRAGCOORD.xy + vec2(TIME * 61.0, TIME * 47.0)) - 0.5) * grain;
	COLOR = vec4(vignette_color.rgb, clamp(v + g, 0.0, 1.0));
}
