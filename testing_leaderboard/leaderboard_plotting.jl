using Dates

@info "Error against observations"
# include("user_io/leaderboard.jl")
include("../experiments/ClimaEarth/user_io/leaderboard.jl")
ClimaAnalysis = Leaderboard.ClimaAnalysis

compare_vars_biases_plot_extrema = Dict(
    "pr" => (-5.0, 5.0),
    "rsdt" => (-2.0, 2.0),
    "rsut" => (-50.0, 50.0),
    "rlut" => (-50.0, 50.0),
    "rsutcs" => (-20.0, 20.0),
    "rlutcs" => (-20.0, 20.0),
    "rsds" => (-50.0, 50.0),
    "rsus" => (-10.0, 10.0),
    "rlds" => (-50.0, 50.0),
    "rlus" => (-50.0, 50.0),
    "rsdscs" => (-10.0, 10.0),
    "rsuscs" => (-10.0, 10.0),
    "rldscs" => (-20.0, 20.0),
)

# diagnostics_folder_path = atmos_sim.integrator.p.output_dir
# leaderboard_base_path = dir_paths.artifacts
diagnostics_folder_path = "testing_leaderboard/leaderboard_data/output_active"
leaderboard_base_path = "testing_leaderboard/saved_leaderboard/"

compare_vars_biases_groups = [
    ["pr", "rsdt", "rsut", "rlut"],
    ["rsds", "rsus", "rlds", "rlus"],
    ["rsutcs", "rlutcs", "rsdscs", "rsuscs", "rldscs"],
]

function compute_biases(compare_vars_biases, dates)
    if isempty(dates)
        return map(x -> 0.0, compare_vars_biases)
    else
        return Leaderboard.compute_biases(
            diagnostics_folder_path,
            compare_vars_biases,
            dates,
            cmap_extrema = compare_vars_biases_plot_extrema,
        )
    end
end

function plot_biases(dates, biases, output_name)
    isempty(dates) && return nothing

    output_path = joinpath(leaderboard_base_path, "bias_$(output_name).png")
    Leaderboard.plot_biases(biases; output_path)
end

first_var = get(
    ClimaAnalysis.SimDir(diagnostics_folder_path),
    short_name = first(first(compare_vars_biases_groups)),
)

diagnostics_times = ClimaAnalysis.times(first_var)
# Remove the first `spinup_months` months from the leaderboard
spinup_months = 6
# The monthly average output is at the end of the month, so this is safe
spinup_cutoff = spinup_months * 31 * 86400.0
if diagnostics_times[end] > spinup_cutoff
    filter!(x -> x > spinup_cutoff, diagnostics_times)
end

output_dates =
    Dates.DateTime(first_var.attributes["start_date"]) .+ Dates.Second.(diagnostics_times)
@info "Working with dates:"
@info output_dates
## collect all days between cs.dates.date0 and cs.dates.date
MAM, JJA, SON, DJF = Leaderboard.split_by_season(output_dates)

# for compare_vars_biases in compare_vars_biases_groups
#     ann_biases = compute_biases(compare_vars_biases, output_dates)
#     plot_biases(output_dates, ann_biases, first(compare_vars_biases) * "_total")

#     MAM_biases = compute_biases(compare_vars_biases, MAM)
#     plot_biases(MAM, MAM_biases, first(compare_vars_biases) * "_MAM")
#     JJA_biases = compute_biases(compare_vars_biases, JJA)
#     plot_biases(JJA, JJA_biases, first(compare_vars_biases) * "_JJA")
#     SON_biases = compute_biases(compare_vars_biases, SON)
#     plot_biases(SON, SON_biases, first(compare_vars_biases) * "_SON")
#     DJF_biases = compute_biases(compare_vars_biases, DJF)
#     plot_biases(DJF, DJF_biases, first(compare_vars_biases) * "_DJF")
# end

# compare_vars_rmses = ["pr", "rsut", "rlut"]

# ann_biases = compute_biases(compare_vars_rmses, output_dates)
# MAM_biases = compute_biases(compare_vars_rmses, MAM)
# JJA_biases = compute_biases(compare_vars_rmses, JJA)
# SON_biases = compute_biases(compare_vars_rmses, SON)
# DJF_biases = compute_biases(compare_vars_rmses, DJF)

# rmses = map(
#     (index) -> Leaderboard.RMSEs(;
#         model_name="CliMA",
#         ANN=ann_biases[index],
#         DJF=DJF_biases[index],
#         MAM=MAM_biases[index],
#         JJA=JJA_biases[index],
#         SON=SON_biases[index],
#     ),
#     1:length(compare_vars_rmses),
# )

# Leaderboard.plot_leaderboard(rmses; output_path=joinpath(leaderboard_base_path, "bias_leaderboard.png"))

ann_biases = compute_biases(["pr"], output_dates)

nothing
