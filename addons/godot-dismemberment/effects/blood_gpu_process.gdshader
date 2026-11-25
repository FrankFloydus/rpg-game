shader_type particles;
render_mode disable_force, disable_velocity;

/** Runtime texture identifying particles retired by contact. The effect supplies it automatically. */
uniform sampler2D contact_particle_mask : filter_nearest, repeat_disable;
/** Runtime texture of source velocities for particles that inherit continuous motion. */
uniform sampler2D inherited_motion : filter_nearest, repeat_disable;
/** Runtime texture of previous source velocities for ordered simulation steps. */
uniform sampler2D inherited_motion_history : filter_nearest, repeat_disable;
/** Basis that converts world acceleration to emitter-local coordinates for attached particles. */
uniform mat3 source_gravity_world_to_local = mat3(1.0);
/** Last completed physics frame for host-timed particles. The effect publishes this value. */
uniform int source_host_epoch = -1;
/** Recent physics step durations for host-timed particles. The effect fills this array. */
uniform float source_host_deltas [16];

const int SOURCE_HOST_FLAG = 32;
const int SOURCE_HOST_WRAP = 65536;
const int SOURCE_HOST_HISTORY = 16;

bool advance_host_particle(inout vec3 velocity, inout vec3 position, inout float age,
		inout float next_epoch, vec4 force, float lifetime) {
	if (source_host_epoch < 0) {
		return true;
	}
	int epoch = int(next_epoch);
	int pending = (source_host_epoch - epoch + SOURCE_HOST_WRAP + 1) % SOURCE_HOST_WRAP;
	if (pending == 0 || pending >= SOURCE_HOST_WRAP / 2) {
		return true;
	}
	// Old step durations are unavailable after a long render stall.
	if (pending > SOURCE_HOST_HISTORY) {
		return false;
	}
	age = max(age, 0.0);
	for (int i = 0; i < pending; i++) {
		float dt = source_host_deltas[(epoch + i) % SOURCE_HOST_HISTORY];
		age += dt;
		if (dt <= 0.0 || age >= lifetime) {
			return false;
		}
		velocity = (velocity + force.xyz * dt) / (1.0 + max(force.w, 0.0) * dt);
		position += velocity * dt;
	}
	next_epoch = float((epoch + pending) % SOURCE_HOST_WRAP);
	return true;
}

void start() {
	if (RESTART_CUSTOM) {
		ACTIVE = false;
	} else {
		// The draw shader gets orientation and dimensions via transform and
		// custom fields. Keep the forces separately for the simulation.
		USERDATA1 = vec4(TRANSFORM[2].xyz, COLOR.g);
		USERDATA2 = vec4(TRANSFORM[1].xyz, CUSTOM.y);
		CUSTOM.y = (int(TRANSFORM[0].z) & SOURCE_HOST_FLAG) != 0 ? -1.0 : -TRANSFORM[0].x;
		TRANSFORM[0].x = 1.0;
		TRANSFORM[2].xyz = vec3(length(VELOCITY), -1.0, -1.0);
	}
}

void process() {
	int id = int(COLOR.r);
	bool hit = false;
	if (id > 0) {
		int slot = id % 65536;
		hit = texelFetch(contact_particle_mask, ivec2(slot % 256, slot / 256), 0).r == float(id);
	}

	int flags = int(TRANSFORM[0].z);
	if ((flags & SOURCE_HOST_FLAG) != 0) {
		// A particle may hit before the renderer consumes its launch packet.
		if (hit) {
			ACTIVE = false;
		} else {
			ACTIVE = advance_host_particle(VELOCITY, TRANSFORM[3].xyz, CUSTOM.y, USERDATA2.w, USERDATA1, CUSTOM.w);
			if (ACTIVE && CUSTOM.y >= 0.0) {
				float speed = length(VELOCITY);
				TRANSFORM[1].xyz = TRANSFORM[0].y == 1.0 && speed > 0.00001 ? VELOCITY / speed : USERDATA2.xyz;
				TRANSFORM[2].x = speed;
			}
		}
	} else {
		float previous_age = CUSTOM.y;
		vec3 impulse = vec3(0.0);
		int motion_token = int(USERDATA2.w);
		bool step_ready = true;
		if (motion_token < 0) {
			// The negative token carries the fixed source phase, slot and generation.
			int address = -motion_token;
			int slot = address % 64;
			int generation = (address / 64) % 64;
			int phase = address / 4096;
			vec4 header = texelFetch(inherited_motion_history, ivec2(slot, 16), 0);
			int backlog = (int(header.x) - phase + 4096) % 4096;
			int time_since_stop = (phase - int(header.y) + 4096) % 4096;
			bool stopped = int(header.w) != generation || (header.z > 0.5 && time_since_stop < 2048);
			step_ready = stopped || backlog < 2048;
			if (step_ready) {
				if (!stopped && backlog < 16) {
					vec4 record = texelFetch(inherited_motion_history, ivec2(slot, phase % 16), 0);
					if (int(record.w) == phase) {
						impulse = record.xyz;
					}
				}
				USERDATA2.w = -float(address % 4096 + ((phase + 1) % 4096) * 4096);
			}
		}
		if (step_ready) {
			CUSTOM.y += DELTA;
		}
		if (CUSTOM.y >= CUSTOM.w || hit) {
			ACTIVE = false;
		} else if (step_ready && CUSTOM.y >= 0.0) {
			float dt = CUSTOM.y - max(previous_age, 0.0);
			if (motion_token > 0) {
				int width = textureSize(inherited_motion, 0).x;
				impulse = texelFetch(inherited_motion, ivec2(motion_token % width, motion_token / width), 0).xyz * (60.0 * DELTA);
			}
			vec3 acceleration = USERDATA1.xyz;
			if ((flags & 16) != 0) {
				acceleration = source_gravity_world_to_local * acceleration;
			}
			VELOCITY = (VELOCITY + impulse + acceleration * dt) / (1.0 + max(USERDATA1.w, 0.0) * dt);
			// Niagara's spawned-particle contact handler writes position after the
			// interpolated spawn solve, keeping its half-step age and velocity.
			bool contact_birth = previous_age < 0.0 && (flags & 8) != 0;
			if (!contact_birth) {
				TRANSFORM[3].xyz += VELOCITY * dt;
			}
			float speed = length(VELOCITY);
			TRANSFORM[1].xyz = TRANSFORM[0].y == 1.0 && speed > 0.00001 ? VELOCITY / speed : USERDATA2.xyz;
			TRANSFORM[2].x = speed;
		}
	}
}
