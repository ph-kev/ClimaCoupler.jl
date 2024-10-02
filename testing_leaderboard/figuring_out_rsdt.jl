import ClimaAnalysis
import ClimaUtilities.ClimaArtifacts: @clima_artifact
import GeoMakie
import CairoMakie

include("leaderboard_plotting_utils.jl")

@info "Error against observations"

# TODO: Make this an array of tuples or something so that we know what correspond to what
# Short names for loading simulation data
short_names_no_pr = [
    "rsdt",
    "rsut",
    "rlut",
    "rsutcs",
    "rlutcs",
    "rsds",
    "rsus",
    "rlds",
    "rlus",
    "rsdscs",
    "rsuscs",
    "rldscs",
]

# Short names for loading observational data
obs_var_short_names_no_pr = [
    "solar_mon",
    "toa_sw_all_mon",
    "toa_lw_all_mon",
    "toa_sw_clr_t_mon",
    "toa_lw_clr_t_mon",
    "sfc_sw_down_all_mon",
    "sfc_sw_up_all_mon",
    "sfc_lw_down_all_mon",
    "sfc_lw_up_all_mon",
    "sfc_sw_down_clr_t_mon",
    "sfc_sw_up_clr_t_mon",
    "sfc_lw_down_clr_t_mon",
]

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
leaderboard_base_path = "testing_leaderboard/saved_leaderboard_analysis/"

# Path to simulation data
diagnostics_folder_path = "testing_leaderboard/leaderboard_data/output_active"

# Dict for loading in simulation data
sim_var_dict = Dict{String,Any}(
    "pr" =>
        () -> begin
            sim_var = get(ClimaAnalysis.SimDir(diagnostics_folder_path), short_name="pr")
            sim_var = ClimaAnalysis.convert_units(
                sim_var,
                "mm/day",
                conversion_function=x -> x .* Float32(-86400),
            )
            return sim_var
        end,
)

# Loop to load the rest of the simulation data
for short_name in short_names_no_pr
    sim_var_dict[short_name] =
        () -> begin
            sim_var = get(
                ClimaAnalysis.SimDir(diagnostics_folder_path),
                short_name=short_name,
            )
            return sim_var
        end
end

# Dict for loading observational data
obs_var_dict = Dict{String,Any}(
    "pr" =>
        () -> begin
            obs_var = ClimaAnalysis.OutputVar(
                joinpath(
                    @clima_artifact("precipitation_obs"),
                    "gpcp.precip.mon.mean.197901-202305.nc",
                ),
                "precip",
            )
            return obs_var
        end,
)

# Load in the rest of the observational data
for (sim_name, obs_name) in zip(short_names_no_pr, obs_var_short_names_no_pr)
    obs_var_dict[sim_name] =
        () -> begin
            obs_var = ClimaAnalysis.OutputVar(
                joinpath(
                    @clima_artifact("radiation_obs"),
                    "CERES_EBAF_Ed4.2_Subset_200003-201910.nc",
                ),
                obs_name,
            )
            # Convert from W m-2 to W m^-2
            obs_var = ClimaAnalysis.set_units(obs_var, "W m^-2")
            return obs_var
        end
end

sim_obs_comparsion_dict = Dict()
seasons = ["ANN", "MAM", "JJA", "SON", "DJF"]

# short_name_t = "rsdt"

# short_names = ["rsdt", "pr", "rsut", "rlut", "rsds", "rsus", "rlds", "rlus", "rsutcs", "rlutcs", "rsdscs", "rsuscs", "rldscs"]
short_names = ["rsdt"]
name2diff = Dict{Any, Any}()
short_name_t = "rsdt"
# for short_name_t in short_names
#     println(short_name_t)
# No extra day
# Simulation data
sim_var = sim_var_dict[short_name_t]()

# Observational data
obs_var_no_extra_day = obs_var_dict[short_name_t]()
obs_var_no_extra_day = dates_to_times_no_extra_day(obs_var_no_extra_day, sim_var.attributes["start_date"])

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

# Use window to get rid of spinup months
sim_var = ClimaAnalysis.window(
    sim_var,
    "time";
    left=diagnostics_times[begin],
    right=diagnostics_times[end],
)

obs_var_no_extra_day = ClimaAnalysis.reordered_as(obs_var_no_extra_day, sim_var) # TODO: Remove this later, only for debugging
obs_var_no_extra_day = ClimaAnalysis.resampled_as(obs_var_no_extra_day, sim_var)

obs_var_no_extra_day_seasons = ClimaAnalysis.split_by_season(obs_var_no_extra_day)
sim_var_seasons = ClimaAnalysis.split_by_season(sim_var)

































# No extra day
# Simulation data
sim_var = sim_var_dict[short_name_t]()

# Observational data
obs_var_extra_day = obs_var_dict[short_name_t]()
obs_var_extra_day = dates_to_times(obs_var_extra_day, sim_var.attributes["start_date"])

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

# Use window to get rid of spinup months
sim_var = ClimaAnalysis.window(
    sim_var,
    "time";
    left=diagnostics_times[begin],
    right=diagnostics_times[end],
)

obs_var_extra_day = ClimaAnalysis.reordered_as(obs_var_extra_day, sim_var) # TODO: Remove this later, only for debugging
obs_var_extra_day = ClimaAnalysis.resampled_as(obs_var_extra_day, sim_var)

obs_var_extra_day_seasons = ClimaAnalysis.split_by_season(obs_var_extra_day)
sim_var_seasons = ClimaAnalysis.split_by_season(sim_var)

# obs_var_no_extra_day = obs_var_no_extra_day |> average_time
# obs_var_extra_day = obs_var_extra_day |> average_time

# obs_var_no_extra_day = ClimaAnalysis.slice(obs_var_no_extra_day, time = 0.0)
# obs_var_extra_day = ClimaAnalysis.slice(obs_var_extra_day, time = 0.0)

# fig = CairoMakie.Figure()

# ClimaAnalysis.Visualize.plot_bias_on_globe!(fig, obs_var_no_extra_day, obs_var_extra_day)
# display(fig)

obs_var_no_extra_day1 = ClimaAnalysis.slice(obs_var_no_extra_day, time = 0.0)
obs_var_no_extra_day2 = ClimaAnalysis.slice(obs_var_no_extra_day, time = 2.099f7)

fig = CairoMakie.Figure()

ClimaAnalysis.Visualize.plot_bias_on_globe!(fig, obs_var_no_extra_day1, obs_var_no_extra_day2)
display(fig)



# abs_diff = abs.(obs_var_no_extra_day.data - obs_var_extra_day.data)
# avg_abs_diff_per_entry_arr = sum(abs_diff, dims = (2, 3)) ./ (180 * 90) # divide to normalize to get average abs diff per entry

# sorted_arr = dropdims(avg_abs_diff_per_entry_arr, dims = (2,3)) |> sort |> reverse
# sorted_arr[1:5] |> println

# name2diff[short_name] = sorted_arr[1:5]

# end
