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
            sim_var = get(ClimaAnalysis.SimDir(diagnostics_folder_path), short_name = "pr")
            sim_var = ClimaAnalysis.convert_units(
                sim_var,
                "mm/day",
                conversion_function = x -> x .* Float32(-86400),
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
                short_name = short_name,
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

for short_name in keys(sim_var_dict)
    # Simulation data
    sim_var = sim_var_dict[short_name]()

    # Observational data
    obs_var = obs_var_dict[short_name]()
    obs_var = dates_to_times_no_extra_day(obs_var, sim_var.attributes["start_date"])

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
        left = diagnostics_times[begin],
        right = diagnostics_times[end],
    )

    obs_var = ClimaAnalysis.reordered_as(obs_var, sim_var) # TODO: Remove this later, only for debugging
    obs_var = ClimaAnalysis.resampled_as(obs_var, sim_var)

    obs_var_seasons = ClimaAnalysis.split_by_season(obs_var)
    sim_var_seasons = ClimaAnalysis.split_by_season(sim_var)

    # Add annual to start of seasons
    obs_var_seasons = [obs_var, obs_var_seasons...]
    sim_var_seasons = [sim_var, sim_var_seasons...]

    # Take time average
    obs_var_seasons = obs_var_seasons .|> ClimaAnalysis.average_time
    sim_var_seasons = sim_var_seasons .|> ClimaAnalysis.average_time

    # Fix up dim_attributes so they are the same (otherwise we get an error from ClimaAnalysis.arecompatible)
    # TODO: Find a better way of doing this (probably change this code in arecompatible)
    for (obs_var, sim_var) in zip(obs_var_seasons, sim_var_seasons)
        obs_var.dim_attributes["lon"] = sim_var.dim_attributes["lon"]
        obs_var.dim_attributes["lat"] = sim_var.dim_attributes["lat"]
    end
    sim_obs_comparsion_dict[short_name] = Dict(
        season => (sim_var_s, obs_var_s) for
        (season, sim_var_s, obs_var_s) in zip(seasons, sim_var_seasons, obs_var_seasons)
    )
end

compare_vars_biases_groups = [
    ["pr", "rsdt", "rsut", "rlut"],
    ["rsds", "rsus", "rlds", "rlus"],
    ["rsutcs", "rlutcs", "rsdscs", "rsuscs", "rldscs"],
]

# Plot bias plots
for season in seasons
    for compare_vars_biases in compare_vars_biases_groups
        fig = CairoMakie.Figure(; size = (600, 300 * length(compare_vars_biases)))
        for (loc, short_name) in enumerate(compare_vars_biases)
            ClimaAnalysis.Visualize.plot_bias_on_globe!(
                fig,
                sim_obs_comparsion_dict[short_name][season]...,
                cmap_extrema = compare_vars_biases_plot_extrema[short_name],
                p_loc = (loc, 1),
            )
        end
        # Do if and else statement for naming files appropriately
        if season != "ANN"
            CairoMakie.save(
                joinpath(
                    leaderboard_base_path,
                    "bias_$(first(compare_vars_biases))_$season.png",
                ),
                fig,
            )
        else
            CairoMakie.save(
                joinpath(
                    leaderboard_base_path,
                    "bias_$(first(compare_vars_biases))_total.png",
                ),
                fig,
            )
        end
    end
end

# Plot leaderboard
# Load data into RMSEVariables
rmse_var_pr = ClimaAnalysis.read_rmses(
    joinpath(@clima_artifact("cmip_model_rmse"), "pr_rmse_amip_pr_amip_5yr.csv"),
    "pr",
    units = "mm / day",
)
rmse_var_rsut = ClimaAnalysis.read_rmses(
    joinpath(@clima_artifact("cmip_model_rmse"), "rsut_rmse_amip_rsut_amip_5yr.csv"),
    "rsut",
    units = "W m^-2",
)
rmse_var_rlut = ClimaAnalysis.read_rmses(
    joinpath(@clima_artifact("cmip_model_rmse"), "rlut_rmse_amip_rlut_amip_5yr.csv"),
    "rlut",
    units = "W m^-2",
)

# Add models and units for CliMA
rmse_var_pr = ClimaAnalysis.add_model(rmse_var_pr, "CliMA")
ClimaAnalysis.add_unit!(rmse_var_pr, "CliMA", "mm / day")

rmse_var_rsut = ClimaAnalysis.add_model(rmse_var_rsut, "CliMA")
ClimaAnalysis.add_unit!(rmse_var_rsut, "CliMA", "W m^-2")

rmse_var_rlut = ClimaAnalysis.add_model(rmse_var_rlut, "CliMA")
ClimaAnalysis.add_unit!(rmse_var_rlut, "CliMA", "W m^-2")

# Add RMSE for the CliMA model and for each season
for season in seasons
    rmse_var_pr["CliMA", season] =
        ClimaAnalysis.global_rmse(sim_obs_comparsion_dict["pr"][season]...)
    rmse_var_rsut["CliMA", season] =
        ClimaAnalysis.global_rmse(sim_obs_comparsion_dict["rsut"][season]...)
    rmse_var_rlut["CliMA", season] =
        ClimaAnalysis.global_rmse(sim_obs_comparsion_dict["rlut"][season]...)
end

# Plot box plots
rmse_vars = (rmse_var_pr, rmse_var_rsut, rmse_var_rlut)
fig = CairoMakie.Figure(; size = (800, 300 * 3 + 400), fontsize = 20)
for i in eachindex(rmse_vars)
    ClimaAnalysis.Visualize.plot_boxplot!(
        fig,
        rmse_vars[i],
        ploc = (i, 1),
        best_and_worst_category_name = "ANN",
    )
end

# Plot leaderboard
ClimaAnalysis.Visualize.plot_leaderboard!(
    fig,
    rmse_vars...,
    best_category_name = "ANN",
    ploc = (4, 1),
)
CairoMakie.save(joinpath(leaderboard_base_path, "bias_leaderboard.png"), fig)
