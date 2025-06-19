#version 330

in vec2 fragTexCoord;
out vec4 finalColor;

uniform sampler2D texture0;
uniform int u_tex_height;
uniform int u_tex_width;

uniform float u_camera_rotation;
uniform float u_camera_offset_x;
uniform float u_camera_offset_y;

uniform float u_time;

const int STACK_HEIGHT = 16; // number of vertical samples

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
		}
    }

    finalColor = color;
}

