struct VertexInput {
    @location(0) pos: vec3f,
    @location(1) col: vec4f,
}

struct VertexOutput {
    @builtin(position) pos: vec4f,
    @location(0) col: vec4f, 
}

struct Uniform {
    mvp: mat4x4f,
}

@group(0) @binding(0) var<uniform> uniforms: Uniform;

@vertex
fn vs_main(input: VertexInput) -> VertexOutput {
    var out: VertexOutput;

    out.pos = uniforms.mvp * vec4(input.pos, 1.0);
    out.col = input.col;

    return out;
}


@fragment
fn fs_main(input: VertexOutput) -> @location(0) vec4f {
    return input.col;
}