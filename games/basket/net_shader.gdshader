shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform vec3 ball_pos = vec3(0.0, -100.0, 0.0);
uniform float ball_radius = 0.35;
uniform float hoop_y = 1.24;

varying vec3 world_pos;

void vertex() {
	vec3 w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_pos = w_pos;
	
	if (w_pos.y < hoop_y) {
		float dist = distance(w_pos, ball_pos);
		if (dist < ball_radius) {
			vec3 dir = normalize(w_pos - ball_pos);
			dir.y = 0.0; 
			
			float push = (ball_radius - dist) * 0.8;
			
			vec3 new_w_pos = w_pos + dir * push;
			VERTEX = (inverse(MODEL_MATRIX) * vec4(new_w_pos, 1.0)).xyz;
		}
	}
}

void fragment() {
	vec4 tex_color = texture(albedo_tex, UV);
	ALBEDO = tex_color.rgb;
	ALPHA = tex_color.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
