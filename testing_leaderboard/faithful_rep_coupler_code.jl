using ClimaAnalysis
import ClimaUtilities.ClimaArtifacts: @clima_artifact
using Dates
using OrderedCollections: OrderedDict
import GeoMakie
import CairoMakie
using Infiltrator
include("leaderboard_plotting_utils.jl")

@info "Error against observations"

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

# Path to saved leaderboards
leaderboard_base_path = "testing_leaderboard/saved_leaderboard/"

# Path to simulation data
diagnostics_folder_path = "testing_leaderboard/leaderboard_data/output_active"

# Dicts for loading simulational and observational data
sim_var_dict = Dict(
    "pr" => get(ClimaAnalysis.SimDir(diagnostics_folder_path), short_name = "pr"),
    "rsdt" => get(ClimaAnalysis.SimDir(diagnostics_folder_path), short_name = "rsdt"),
    # "rsut" => get(ClimaAnalysis.SimDir(diagnostics_folder_path), short_name = "rsut"),
    # "rlut" => get(ClimaAnalysis.SimDir(diagnostics_folder_path), short_name = "rlut"),
    # "rsutcs" => get(ClimaAnalysis.SimDir(diagnostics_folder_path), short_name = "rsutcs"),
    # "rlutcs" => get(ClimaAnalysis.SimDir(diagnostics_folder_path), short_name = "rlutcs"),
    # "rsds" => get(ClimaAnalysis.SimDir(diagnostics_folder_path), short_name = "rsds"),
    # "rsus" => get(ClimaAnalysis.SimDir(diagnostics_folder_path), short_name = "rsus"),
    # "rlds" => get(ClimaAnalysis.SimDir(diagnostics_folder_path), short_name = "rlds"),
    # "rlus" => get(ClimaAnalysis.SimDir(diagnostics_folder_path), short_name = "rlus"),
    # "rsdscs" => get(ClimaAnalysis.SimDir(diagnostics_folder_path), short_name = "rsdscs"),
    # "rsuscs" => get(ClimaAnalysis.SimDir(diagnostics_folder_path), short_name = "rsuscs"),
    # "rldscs" => get(ClimaAnalysis.SimDir(diagnostics_folder_path), short_name = "rldscs"),
)
obs_var_dict = Dict(
    "pr" => ClimaAnalysis.read_var(
        joinpath(
            @clima_artifact("precipitation_obs"),
            "gpcp.precip.mon.mean.197901-202305.nc",
        ),
        short_name = "precip",
    ),
    "rsdt" => ClimaAnalysis.read_var(
        joinpath(
            @clima_artifact("radiation_obs"),
            "CERES_EBAF_Ed4.2_Subset_200003-201910.nc",
        ),
        short_name = "solar_mon",
    ),
)

arr = ["pr"]

for short_name in arr
    # Observational data
    sim_var = sim_var_dict[short_name]

    # TODO: Error when showing/printing this variable (probably because of dates in time
    # dimension which interpolation does not like)
    # Simulation data
    obs_var = obs_var_dict[short_name]

    # Get rid of startup times
    # Make a copy since the function return the OutputVar's time array and not a copy of it
    diagnostics_times = ClimaAnalysis.times(sim_var) |> copy
    # Remove the first `spinup_months` months from the leaderboard
    spinup_months = 6
    # The monthly average output is at the end of the month, so this is safe
    spinup_cutoff = spinup_months * 31 * 86400.0
    if diagnostics_times[end] > spinup_cutoff
        filter!(x -> x > spinup_cutoff, diagnostics_times)
    end

    sim_var = ClimaAnalysis.window(
        sim_var,
        "time";
        left = diagnostics_times[begin],
        right = diagnostics_times[end],
    )

    # Convert units so they match (-1 kg/m/s2 -> 1 mm/day) for pr
    if short_name == "pr"
        sim_var = Var.convert_units(
            sim_var,
            "mm/day",
            conversion_function = x -> x .* Float32(-86400),
        )
    end

    obs_var = dates_to_times(obs_var, sim_var.attributes["start_date"])
    obs_var = reorder_as(obs_var, sim_var)

    obs_var = ClimaAnalysis.window(
        obs_var,
        "time";
        left = diagnostics_times[begin],
        right = diagnostics_times[end], # janky way of being able to resample...
    )

    # THIS IS THE CULPRIT (I NEED TO RESAMPLE ONLY OVER LON AND LAT AND NOT OVER TIME)
    # @infiltrate
    obs_var = resampled_as_ignore_time(obs_var, sim_var)
    # @infiltrate

    # Take time average
    obs_var = obs_var |> ClimaAnalysis.average_time
    sim_var = sim_var |> ClimaAnalysis.average_time

    # Fix up dim_attributes so they are the same (otherwise we get an error from ClimaAnalysis.arecompatible)
    obs_var.dim_attributes["lon"] = sim_var.dim_attributes["lon"]
    obs_var.dim_attributes["lat"] = sim_var.dim_attributes["lat"]


    bias_pr_var = ClimaAnalysis.bias(sim_var, obs_var)

    fig = CairoMakie.Figure()
    ClimaAnalysis.Visualize.plot_bias_on_globe!(
        fig,
        sim_var,
        obs_var,
        cmap_extrema = compare_vars_biases_plot_extrema[short_name],
    )
    CairoMakie.save("testing_leaderboard/saved_leaderboard_analysis/bias_pr_total.png", fig)
end
