struct VertexInput {
    @builtin(instance_index) index: u32,
    @location(0) pos: vec3f,
    @location(1) uv: vec2f,
    @location(2) norm: vec3f,
}

struct VertexOutput {
    @builtin(position) pos: vec4f,
    @location(0) uv: vec2f, 
    @location(1) norm: vec3f, 
}

struct Uniform {
    mvp: mat4x4f,
}

@group(0) @binding(0) var<uniform> uniforms: array<Uniform,4>;

@vertex
fn vs_main(input: VertexInput) -> VertexOutput {
    var out: VertexOutput;

    out.pos = uniforms[input.index].mvp * vec4(input.pos, 1.0);
    out.uv = input.uv;
    out.norm = input.norm;

    return out;
}


@fragment
fn fs_main(input: VertexOutput) -> @location(0) vec4f {
    return vec4f(input.norm, 1.0);
}