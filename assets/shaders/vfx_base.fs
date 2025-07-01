#version 330

in vec2 fragTexCoord;
out vec4 finalColor;

uniform sampler2D texture0;
uniform int u_tex_height;
uniform int u_tex_width;


uniform float u_camera_rotation;
uniform float u_camera_offset_x;
uniform float u_camera_offset_y;

uniform float u_camera_screen_offset_x;
uniform float u_camera_screen_offset_y;

uniform float u_time;

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);

    // Smooth interpolation
    vec2 u = f * f * (3.0 - 2.0 * f);

    float a = hash(i + vec2(0.0, 0.0));
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));

    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void main() {
    vec2 uv = vec2(fragTexCoord.x, 1 - fragTexCoord.y);
    vec4 color = texture(texture0, uv);

	vec2 screen_center = vec2(u_camera_screen_offset_x, u_camera_screen_offset_y);
	vec2 world_position = (uv * vec2(u_tex_width, u_tex_height)) - vec2(-u_camera_offset_x, u_camera_offset_y);

	float angle = -u_camera_rotation;
	float cos_a = cos(angle);
	float sin_a = sin(angle);

	world_position = world_position - screen_center;
	vec2 rotated = vec2(
			cos_a * world_position.x - sin_a * world_position.y,
			sin_a * world_position.x + cos_a * world_position.y
			);
	rotated = rotated + screen_center;

	vec2 rotated_camera_offset = vec2(
			cos_a * u_camera_offset_x - sin_a * -u_camera_offset_y,
			sin_a * u_camera_offset_x + cos_a * -u_camera_offset_y
			);

	// camera representation of world position, with respect to rotation
	vec2 rotated_world_position = rotated - rotated_camera_offset - vec2(-u_camera_offset_x, u_camera_offset_y);

	vec2 offset = vec2(u_time, u_time * 0.5);
	float n = noise((rotated_world_position / 30) + offset);
	float intensity = 0.15;
	float strength = mix(1.0 - intensity, 1.0 + intensity, n);

    finalColor = color * strength;
}
