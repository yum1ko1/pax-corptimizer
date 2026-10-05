// Pax Corptimizer — the time-skip screen: stars streaking outward and a clock hand.
// Drawn entirely on the GPU: the CPU spends nothing on it while the world is being computed.
shader_type canvas_item;

uniform vec4 tint : source_color = vec4(0.45, 0.75, 1.0, 1.0);
uniform vec4 hand_color : source_color = vec4(1.0, 0.85, 0.5, 1.0);
uniform float speed = 1.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 res = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 uv = (FRAGCOORD.xy - 0.5 * res) / res.y;
	float t = TIME * speed;
	float r = length(uv);
	float a = atan(uv.y, uv.x);
	float turn = a / 6.28318 + 0.5;
	vec3 col = vec3(0.008, 0.012, 0.026) + vec3(0.02, 0.03, 0.06) * clamp(1.0 - r, 0.0, 1.0);

	// Three layers of rays: each ray carries a star that runs outward and speeds up — time flying by.
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		float n = 90.0 + 55.0 * fi;
		float sector = floor(turn * n);
		float h = hash(vec2(sector, fi * 13.0 + 1.0));
		float z = fract(h * 7.0 + t * (0.22 + 0.15 * fi) * (0.6 + h));
		float d = z * z * 1.7;
		float len = 0.015 + 0.3 * z * z;
		float along = smoothstep(d - len, d, r) * (1.0 - smoothstep(d, d + 0.004, r));
		float across = smoothstep(0.12, 0.0, abs(fract(turn * n) - 0.5));
		col += tint.rgb * along * across * (0.35 + 0.65 * h) * z * 1.6;
	}

	// The clock: a ring and a hand going round.
	col += tint.rgb * smoothstep(0.006, 0.0, abs(r - 0.16)) * 0.8;
	float hand_a = mod(t * 2.2, 6.28318) - 3.14159;
	float da = abs(atan(sin(a - hand_a), cos(a - hand_a)));
	col += hand_color.rgb * smoothstep(0.035, 0.0, da) * step(r, 0.15) * smoothstep(0.0, 0.025, r) * 0.9;
	col += tint.rgb * 0.18 / (1.0 + 80.0 * r * r);

	COLOR = vec4(col, 1.0);
}
