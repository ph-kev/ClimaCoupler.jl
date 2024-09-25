import ClimaAnalysis
import ClimaUtilities.ClimaArtifacts: @clima_artifact
using Dates
using OrderedCollections: OrderedDict
import GeoMakie
import CairoMakie

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
    "rsdt" =>
        () -> begin
            return get(ClimaAnalysis.SimDir(diagnostics_folder_path), short_name = "rsdt")
        end,
    "rsut" =>
        () -> begin
            return get(ClimaAnalysis.SimDir(diagnostics_folder_path), short_name = "rsut")
        end,
    "rlut" =>
        () -> begin
            return get(ClimaAnalysis.SimDir(diagnostics_folder_path), short_name = "rlut")
        end,
    "rsutcs" =>
        () -> begin
            return get(ClimaAnalysis.SimDir(diagnostics_folder_path), short_name = "rsutcs")
        end,
    "rlutcs" =>
        () -> begin
            return get(ClimaAnalysis.SimDir(diagnostics_folder_path), short_name = "rlutcs")
        end,
    "rsds" =>
        () -> begin
            return get(ClimaAnalysis.SimDir(diagnostics_folder_path), short_name = "rsds")
        end,
    "rsus" =>
        () -> begin
            return get(ClimaAnalysis.SimDir(diagnostics_folder_path), short_name = "rsus")
        end,
    "rlds" =>
        () -> begin
            return get(ClimaAnalysis.SimDir(diagnostics_folder_path), short_name = "rlds")
        end,
    "rlus" =>
        () -> begin
            return get(ClimaAnalysis.SimDir(diagnostics_folder_path), short_name = "rlus")
        end,
    "rsdscs" =>
        () -> begin
            return get(ClimaAnalysis.SimDir(diagnostics_folder_path), short_name = "rsdscs")
        end,
    "rsuscs" =>
        () -> begin
            return get(ClimaAnalysis.SimDir(diagnostics_folder_path), short_name = "rsuscs")
        end,
    "rldscs" =>
        () -> begin
            return get(ClimaAnalysis.SimDir(diagnostics_folder_path), short_name = "rldscs")
        end,
)
obs_var_dict = Dict(
    "pr" =>
        () -> begin
            obs_var = ClimaAnalysis.read_var(
                joinpath(
                    @clima_artifact("precipitation_obs"),
                    "gpcp.precip.mon.mean.197901-202305.nc",
                ),
                short_name = "precip",
            )
            return obs_var
        end,
    "rsdt" =>
        () -> begin
            obs_var = ClimaAnalysis.read_var(
                joinpath(
                    @clima_artifact("radiation_obs"),
                    "CERES_EBAF_Ed4.2_Subset_200003-201910.nc",
                ),
                short_name = "solar_mon",
            )
            # Convert from W m-2 to W m^-2
            # TODO: This should change to be a helper function so that we don't need to copy and paste this everywhere
            obs_var = ClimaAnalysis.convert_units(
                obs_var,
                "W m^-2",
                conversion_function = x -> x,
            )
            return obs_var
        end,
    "rsut" =>
        () -> begin
            obs_var = ClimaAnalysis.read_var(
                joinpath(
                    @clima_artifact("radiation_obs"),
                    "CERES_EBAF_Ed4.2_Subset_200003-201910.nc",
                ),
                short_name = "toa_sw_all_mon",
            )
            obs_var = ClimaAnalysis.convert_units(
                obs_var,
                "W m^-2",
                conversion_function = x -> x,
            )
            return obs_var
        end,
    "rlut" =>
        () -> begin
            obs_var = ClimaAnalysis.read_var(
                joinpath(
                    @clima_artifact("radiation_obs"),
                    "CERES_EBAF_Ed4.2_Subset_200003-201910.nc",
                ),
                short_name = "toa_lw_all_mon",
            )
            obs_var = ClimaAnalysis.convert_units(
                obs_var,
                "W m^-2",
                conversion_function = x -> x,
            )
            return obs_var
        end,
    "rsutcs" =>
        () -> begin
            obs_var = ClimaAnalysis.read_var(
                joinpath(
                    @clima_artifact("radiation_obs"),
                    "CERES_EBAF_Ed4.2_Subset_200003-201910.nc",
                ),
                short_name = "toa_sw_clr_t_mon",
            )
            obs_var = ClimaAnalysis.convert_units(
                obs_var,
                "W m^-2",
                conversion_function = x -> x,
            )
            return obs_var
        end,
    "rlutcs" =>
        () -> begin
            obs_var = ClimaAnalysis.read_var(
                joinpath(
                    @clima_artifact("radiation_obs"),
                    "CERES_EBAF_Ed4.2_Subset_200003-201910.nc",
                ),
                short_name = "toa_lw_clr_t_mon",
            )
            obs_var = ClimaAnalysis.convert_units(
                obs_var,
                "W m^-2",
                conversion_function = x -> x,
            )
            return obs_var
        end,
    "rsds" =>
        () -> begin
            obs_var = ClimaAnalysis.read_var(
                joinpath(
                    @clima_artifact("radiation_obs"),
                    "CERES_EBAF_Ed4.2_Subset_200003-201910.nc",
                ),
                short_name = "sfc_sw_down_all_mon",
            )
            obs_var = ClimaAnalysis.convert_units(
                obs_var,
                "W m^-2",
                conversion_function = x -> x,
            )
            return obs_var
        end,
    "rsus" =>
        () -> begin
            obs_var = ClimaAnalysis.read_var(
                joinpath(
                    @clima_artifact("radiation_obs"),
                    "CERES_EBAF_Ed4.2_Subset_200003-201910.nc",
                ),
                short_name = "sfc_sw_up_all_mon",
            )
            obs_var = ClimaAnalysis.convert_units(
                obs_var,
                "W m^-2",
                conversion_function = x -> x,
            )
            return obs_var
        end,
    "rlds" =>
        () -> begin
            obs_var = ClimaAnalysis.read_var(
                joinpath(
                    @clima_artifact("radiation_obs"),
                    "CERES_EBAF_Ed4.2_Subset_200003-201910.nc",
                ),
                short_name = "sfc_lw_down_all_mon",
            )
            obs_var = ClimaAnalysis.convert_units(
                obs_var,
                "W m^-2",
                conversion_function = x -> x,
            )
            return obs_var
        end,
    "rlus" =>
        () -> begin
            obs_var = ClimaAnalysis.read_var(
                joinpath(
                    @clima_artifact("radiation_obs"),
                    "CERES_EBAF_Ed4.2_Subset_200003-201910.nc",
                ),
                short_name = "sfc_lw_up_all_mon",
            )
            obs_var = ClimaAnalysis.convert_units(
                obs_var,
                "W m^-2",
                conversion_function = x -> x,
            )
            return obs_var
        end,
    "rsdscs" =>
        () -> begin
            obs_var = ClimaAnalysis.read_var(
                joinpath(
                    @clima_artifact("radiation_obs"),
                    "CERES_EBAF_Ed4.2_Subset_200003-201910.nc",
                ),
                short_name = "sfc_sw_down_clr_t_mon",
            )
            obs_var = ClimaAnalysis.convert_units(
                obs_var,
                "W m^-2",
                conversion_function = x -> x,
            )
            return obs_var
        end,
    "rsuscs" =>
        () -> begin
            obs_var = ClimaAnalysis.read_var(
                joinpath(
                    @clima_artifact("radiation_obs"),
                    "CERES_EBAF_Ed4.2_Subset_200003-201910.nc",
                ),
                short_name = "sfc_sw_up_clr_t_mon",
            )
            obs_var = ClimaAnalysis.convert_units(
                obs_var,
                "W m^-2",
                conversion_function = x -> x,
            )
            return obs_var
        end,
    "rldscs" =>
        () -> begin
            obs_var = ClimaAnalysis.read_var(
                joinpath(
                    @clima_artifact("radiation_obs"),
                    "CERES_EBAF_Ed4.2_Subset_200003-201910.nc",
                ),
                short_name = "sfc_lw_down_clr_t_mon",
            )
            obs_var = ClimaAnalysis.convert_units(
                obs_var,
                "W m^-2",
                conversion_function = x -> x,
            )
            return obs_var
        end,
)

arr = ["pr"]
# keys(sim_var_dict)

for short_name in arr
    println(short_name)
    # Observational data

    sim_var = sim_var_dict[short_name]()

    # TODO: Error when showing/printing this variable (probably because of dates in time
    # dimension which interpolation does not like)
    # Simulation data
    obs_var = obs_var_dict[short_name]()
    obs_var = dates_to_times(obs_var, sim_var.attributes["start_date"])

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

    obs_var = reorder_as(obs_var, sim_var)

    ### JANKY WAY OF DOING THIS
    # obs_var = ClimaAnalysis.window(
    #     obs_var,
    #     "time";
    #     left = diagnostics_times[begin],
    #     right = diagnostics_times[end],
    # )
    # obs_var = resampled_as_ignore_time(obs_var, sim_var)
    ### JANKY WAY OF DOING THIS
    # Cleaner way would be using only the line below (however, this change the results)
    obs_var = resampled_as(obs_var, sim_var)

    # TODO: Add split by season here and make a for loop?

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
    CairoMakie.save("testing_leaderboard/saved_leaderboard_analysis/bias_" * short_name * "_total.png", fig)
end
