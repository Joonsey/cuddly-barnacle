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

const int STACK_HEIGHT = 8; // number of vertical samples

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);

    // Four corners in 2D of a tile
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));

    // Cubic Hermite interpolation
    vec2 u = f * f * (3.0 - 2.0 * f);

    // Mix results
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}


bool is_black(vec4 color) {
    return color.r == 0.0 && color.g == 0.0 && color.b == 0.0;
}

void main() {
    vec2 uv = fragTexCoord;
    vec4 color = texture(texture0, uv);

    if (is_black(color)) {
		bool found = false;
		if (uv.y * u_tex_height < (u_tex_height - STACK_HEIGHT)) {
			for (int i = 1; i <= STACK_HEIGHT; i++) {
				vec2 sample_uv = uv + vec2(0.0, float(i) / float(u_tex_height));
				vec4 sample_color = texture(texture0, sample_uv);

				if (!is_black(sample_color)) {
					color = sample_color * 0.9;
					found = true;
					break;
				}
			}
		}

		if (!found) {
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

			vec2 rotated_world_position = rotated - rotated_camera_offset - vec2(-u_camera_offset_x, u_camera_offset_y);

			float n = noise(rotated_world_position * 0.05); // choose scale based on world units

			vec3 noise_color = vec3(n);
			color = vec4(noise_color, 1);
		}
    }

    finalColor = color;
}

