# flame_diff.jl: provides allocation breakdown for individual backtraces for single-process unthredded runs 
# and check for fractional change in allocation compared to the last staged run

buildkite_branch = ENV["BUILDKITE_BRANCH"]
buildkite_commit = ENV["BUILDKITE_COMMIT"]
buildkite_bnumber = ENV["BUILDKITE_BUILD_NUMBER"]
buildkite_cc_dir = "/groups/esm/slurm-buildkite/climacoupler-ci/"

build_path = "/central/scratch/esm/slurm-buildkite/climacoupler-ci/$buildkite_bnumber/climacoupler-ci/perf/"
cwd = pwd()
@info "build_path is: $build_path"

import Profile
using Test
import Base: view
include("ProfileCanvasDiff.jl")
import .ProfileCanvasDiff

Profile.clear_malloc_data()
Profile.clear()

cc_dir = joinpath(dirname(@__DIR__));
include(joinpath(cc_dir, "experiments", "AMIP", "moist_mpi_earth", "cli_options.jl"));

# assuming a common driver for all tested runs
filename = joinpath(cc_dir, "experiments", "AMIP", "moist_mpi_earth", "coupler_driver_modular.jl")

# selected runs for performance analysis and their expected allocations (based on previous runs)
run_name_list = ["default_modular", "coarse_single_modular", "target_amip_n32_shortrun"]
run_name = run_name_list[parse(Int, ARGS[2])]

# number of time steps used for profiling
const n_samples = 2

# flag to split coupler init from its solve 
ENV["CI_PERF_SKIP_COUPLED_RUN"] = true

# pass in the correct arguments, overriding defaults with those specific to each run_name (in `pipeline.yaml`)
dict = parsed_args_per_job_id(; trigger = "--run_name $run_name")
parsed_args_prescribed = parsed_args_from_ARGS(ARGS)
parsed_args_target = dict[run_name]
parsed_args = merge(parsed_args_target, parsed_args_prescribed) # global scope needed to recognize this definition in the coupler driver
run_name = "perf_diff_" * run_name
parsed_args["job_id"] = run_name
parsed_args["run_name"] = run_name
parsed_args["enable_threading"] = false

@info run_name

function step_coupler!(cs, n_samples)
    cs.tspan[1] = cs.model_sims.atmos_sim.integrator.t
    cs.tspan[2] = cs.tspan[1] + n_samples * cs.Δt_cpl
    solve_coupler!(cs)
end

try # initialize the coupler
    ENV["CI_PERF_SKIP_COUPLED_RUN"] = true
    include(filename)
catch err
    if err.error !== :exit_profile_init
        rethrow(err.error)
    end
end

#####
##### Profiling
#####
"""
    iterate_children(flame_tree, ct = 0, dict = Dict{String, Float64}())

Iterate over all children of a stack tree and save their names ("\$func.\$file.\$line") and 
corresponding count values in a Dict. 
"""
function iterate_children(flame_tree, ct = 0, dict = Dict{String, Float64}())
    ct += 1
    line = flame_tree.line
    file = flame_tree.file
    func = flame_tree.func
    push!(dict, "$func.$file.$line" => flame_tree.count)

    if isempty(flame_tree.children)
        nothing
    else
        for sf in flame_tree.children
            iterate_children(sf, ct, dict)
        end
    end
    return dict
end

# obtain the stacktree from the last saved file in `buildkite_cc_dir`
ref_file = joinpath(buildkite_cc_dir, "$run_name.jld2")
tracked_list = isfile(ref_file) ? load(ref_file) : Dict{String, Float64}()

# compile coupling loop first
step_coupler!(cs, n_samples)
Profile.clear_malloc_data()
Profile.clear()

# profile the coupling loop
prof = Profile.@profile begin
    step_coupler!(cs, n_samples)
end

# produce flamegraph with colors highlighting the allocation differences relative to the last saved run
# profile_data 
if haskey(ENV, "BUILDKITE_COMMIT") || haskey(ENV, "BUILDKITE_BRANCH")
    output_dir = "perf/output/$run_name"
    mkpath(output_dir)
    ProfileCanvasDiff.html_file(joinpath(output_dir, "flame_diff.html"), build_path = build_path)
end

# save (and reset) the stack tree if this is running on the `staging` branch
profile_data = ProfileCanvasDiff.view(Profile.fetch(), tracked_list = tracked_list);
flame_tree = profile_data.data["all"]
my_dict = iterate_children(flame_tree)
@info "This branch is: $buildkite_branch, commit $buildkite_commit"
if buildkite_branch == "staging"
    isfile(ref_file) ?
    mv(ref_file, joinpath(buildkite_cc_dir, "flame_diff_ref_file.$run_name.$buildkite_commit.jld2")) : nothing
    save(ref_file, my_dict) # reset ref_file upon staging
end