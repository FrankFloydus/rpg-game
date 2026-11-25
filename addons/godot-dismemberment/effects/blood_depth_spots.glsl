#[compute]
#version 450
layout(local_size_x = 64) in;
layout(set = 0, binding = 0) uniform sampler2D depth_image;
layout(set = 0, binding = 1) uniform sampler2D normal_image;
layout(push_constant, std430) uniform LayerParams {
	float radius_start;
	float radius_end;
	uint count;
	uint use_normal_buffer;
	uint simulation_tick;
} layer;
struct Particle {
	vec4 position_age;
	vec4 velocity_drag;
	vec4 lifetime_size_alive_offscreen;
	vec4 acceleration_has_hit;
	vec4 sprite;
	vec4 alignment;
	vec4 axis_z;
};
layout(set = 0, binding = 2, std430) buffer State { Particle particles[]; };
layout(set = 0, binding = 3, std430) buffer Instances { float instances[]; };
layout(set = 0, binding = 4, std430) readonly buffer View {
	mat4 world_to_clip;
	mat4 clip_to_world;
	mat4 view_to_world;
	vec4 camera_dt;
	vec4 settings;
} scene;
layout(set = 0, binding = 5, std430) readonly buffer BirthEpochs { uint birth_tick[]; };

struct Query {
	vec3 position;
	vec3 velocity;
	vec3 force;
	vec3 normal;
	float remaining;
	float penetration;
	bool onscreen;
	bool alive;
	bool hit;
};

const vec3 GRAVITY = vec3(0.0, -9.8, 0.0);

Query collide(vec3 position, vec3 velocity, vec3 force, float delta, float radius, float drag,
		bool has_hit, bool first_frame, bool from_force, bool use_normal) {
	Query result = Query(position, velocity, force, vec3(0.0, 1.0, 0.0), delta, 1e14, false, true, false);
	vec4 clip = scene.world_to_clip * vec4(position, 1.0);
	vec3 ndc = clip.xyz / clip.w;
	result.onscreen = all(lessThanEqual(abs(ndc.xy), vec2(1.0)));
	if (!result.onscreen) {
		result.alive = !has_hit;
		return result;
	}
	vec2 uv = ndc.xy * 0.5 + 0.5;
	float depth = textureLod(depth_image, uv, 0.0).x;
	if (depth <= 0.0) {
		return result;
	}
	vec4 point_h = scene.clip_to_world * vec4(ndc.xy, depth, 1.0);
	vec3 point = point_h.xyz / point_h.w;
	vec3 camera_to_point = point - scene.camera_dt.xyz;
	bool occluded = dot(camera_to_point, point - position) < 0.0;
	if (occluded) {
		result.alive = false;
		return result;
	}
	vec3 encoded_normal = textureLod(normal_image, uv, 0.0).xyz;
	vec3 normal = use_normal ? normalize(mat3(scene.view_to_world) * (encoded_normal * 2.0 - 1.0)) : vec3(0.0, 1.0, 0.0);
	vec2 texel = 1.0 / vec2(textureSize(depth_image, 0));
	float depth_dx = textureLod(depth_image, uv + vec2(texel.x, 0.0), 0.0).x;
	float depth_dy = textureLod(depth_image, uv + vec2(0.0, texel.y), 0.0).x;
	vec4 px_h = scene.clip_to_world * vec4(ndc.xy + vec2(2.0 * texel.x, 0.0), depth_dx, 1.0);
	vec4 py_h = scene.clip_to_world * vec4(ndc.xy + vec2(0.0, 2.0 * texel.y), depth_dy, 1.0);
	vec3 dx = px_h.xyz / px_h.w - point;
	vec3 dy = py_h.xyz / py_h.w - point;
	vec3 geometric_normal = cross(dx, dy);
	if (dot(geometric_normal, geometric_normal) > 1e-14 && length(dx) < 0.08 && length(dy) < 0.08) {
		geometric_normal = normalize(geometric_normal);
		if (dot(geometric_normal, normal) < 0.0) {
			geometric_normal *= -1.0;
		}
		if (!use_normal || dot(geometric_normal, normal) > 0.9998) {
			normal = geometric_normal;
		}
	}
	vec3 force_step = force * delta;
	vec3 update_velocity = (velocity + force_step) / (1.0 + drag * delta);
	vec3 update_movement = update_velocity * delta;
	vec3 trace_motion = from_force ? force_step : update_movement;
	vec3 trace_direction = length(trace_motion) > 1e-7 ? normalize(trace_motion) : vec3(0.0, -1.0, 0.0);
	vec3 trace_delta = trace_motion + trace_direction * (2.0 * radius);
	float plane_distance = dot(normal, position - point);
	float ending_distance = plane_distance + dot(normal, trace_motion + trace_direction * radius);
	if (plane_distance + radius < 0.0 || ending_distance > radius || dot(normal, trace_delta) >= 0.0) {
		return result;
	}
	float before = plane_distance - radius;
	float after = before + dot(normal, update_movement);
	result.penetration = before;
	if (after > 0.0) {
		return result;
	}
	result.normal = normal;
	result.hit = true;
	if (before < 0.0) {
		result.position = position - normal * (first_frame ? before : max(0.0, before));
	} else {
		float from_end = abs(after) / max(abs(before - after), 1e-8);
		float fraction = from_end == 0.0 ? 0.0 : 1.0 - from_end;
		result.position = position + update_movement * fraction;
		result.remaining = delta * (1.0 - fraction);
	}
	float normal_speed = dot(normal, update_velocity);
	if (normal_speed < 0.0) {
		vec3 tangent = update_velocity - normal_speed * normal;
		float tangent_length = length(tangent);
		float friction = dot(-normal, update_movement - force_step * delta) < 0.001 ? -normal_speed : 0.0;
		result.velocity = tangent_length > friction ? tangent * (1.0 - friction / tangent_length) : vec3(0.0);
		result.force = vec3(0.0);
	}
	return result;
}

void main() {
	uint index = gl_GlobalInvocationID.x;
	if (index >= layer.count) {
		return;
	}
	Particle particle = particles[index];
	if (particle.lifetime_size_alive_offscreen.z == 0.0) {
		instances[index * 20 + 14] = 0.0;
		return;
	}
	if (int(layer.simulation_tick - birth_tick[index]) < 0) {
		instances[index * 20 + 14] = 0.0;
		return;
	}
	vec3 position = particle.position_age.xyz;
	float age = particle.position_age.w;
	vec3 velocity = particle.velocity_drag.xyz;
	float drag = particle.velocity_drag.w;
	float lifetime = particle.lifetime_size_alive_offscreen.x;
	float size = particle.lifetime_size_alive_offscreen.y;
	float offscreen = particle.lifetime_size_alive_offscreen.w;
	bool has_hit = particle.acceleration_has_hit.w > 0.0;
	float delta = scene.camera_dt.w;
	bool first_frame = age <= delta;
	age += delta;
	bool alive = first_frame || age < lifetime;
	if (alive) {
		float radius = max(1e-8, size * mix(layer.radius_start, layer.radius_end, clamp(age / lifetime, 0.0, 1.0)));
		vec3 gravity = particle.acceleration_has_hit.xyz;
		Query first = collide(position, velocity, gravity, delta, radius, drag, has_hit, first_frame, true, layer.use_normal_buffer > 0);
		Query second = collide(first.position, first.velocity, first.force, first.remaining, radius, drag, has_hit || first.hit, first_frame, false, layer.use_normal_buffer > 0);
		offscreen = (first.onscreen || second.onscreen) ? 0.0 : offscreen + delta;
		alive = first.alive && second.alive && offscreen < 1.0;
		if (first.hit || second.hit) {
			bool rest = (first.penetration < 0.0 && second.penetration < 0.0) ||
				-first.penetration > second.penetration || second.penetration < -0.005;
			position = second.position;
			velocity = rest ? vec3(0.0) : second.velocity / (1.0 + drag * second.remaining);
			position += velocity * second.remaining;

			has_hit = true;
		} else {
			velocity = (velocity + gravity * delta) / (1.0 + drag * delta);
			position += velocity * delta;
		}
	}
	particles[index].position_age = vec4(position, age);
	particles[index].velocity_drag.xyz = velocity;
	particles[index].lifetime_size_alive_offscreen.zw = vec2(alive ? 1.0 : 0.0, offscreen);
	particles[index].acceleration_has_hit.w = has_hit ? 1.0 : 0.0;
	uint base = index * 20;
	vec3 axis = vec3(particle.alignment.zw, particle.axis_z.x);
	float speed = length(velocity);
	if (particle.alignment.x == 1.0 && speed > 0.00001) {
		axis = velocity / speed;
	}
	instances[base] = 1.0;
	instances[base + 1] = axis.x;
	instances[base + 2] = speed;
	instances[base + 3] = position.x;
	instances[base + 4] = particle.alignment.x;
	instances[base + 5] = axis.y;
	instances[base + 6] = -1.0;
	instances[base + 7] = position.y;
	instances[base + 8] = particle.alignment.y;
	instances[base + 9] = axis.z;
	instances[base + 10] = -1.0;
	instances[base + 11] = position.z;
	instances[base + 12] = 0.0;
	instances[base + 13] = drag;
	instances[base + 14] = alive ? particle.sprite.w : 0.0;
	instances[base + 15] = particle.sprite.z;
	instances[base + 16] = particle.sprite.x;
	instances[base + 17] = age;
	instances[base + 18] = particle.sprite.y;
	instances[base + 19] = lifetime;
}








