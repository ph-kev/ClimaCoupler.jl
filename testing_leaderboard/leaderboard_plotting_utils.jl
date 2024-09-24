using ClimaAnalysis
using Dates
using OrderedCollections: OrderedDict

# Convert dates to time for pr_obs_var
# for converting dates to float (with a start date added in attributes)
function dates_to_times(
    var::OutputVar,
    new_start_date::String;
    shift_to_end_of_month = true,
)
    ClimaAnalysis.has_time(var) || error("Time is not a dimension of var")
    time_arr = times(var)
    first(time_arr) isa Dates.AbstractDateTime ||
        error("The elements of time array is not type DateTime")

    # Shift days to end of the month if true
    if shift_to_end_of_month
        time_arr = Dates.DateTime.(Dates.lastdayofmonth.(times(var)))
    end

    # Convert dates to float with reference to start date (first elt of time arr)
    start_date = time_arr[begin]
    time_arr = map(date -> ClimaAnalysis.Utils.date_to_time(start_date, date), time_arr)

    # Shift everything with reference to the new start date
    new_start_date_formatted = DateTime(new_start_date)
    dt = ClimaAnalysis.Utils.period_to_seconds_float(new_start_date_formatted - start_date)
    time_arr .= time_arr .- dt

    ret_dims = deepcopy(var.dims)
    ret_dims[time_name(var)] = time_arr
    ret_attribs = deepcopy(var.attributes)
    ret_attribs["start_date"] = new_start_date # add start_date as an attribute
    ret_dim_attribs = deepcopy(var.dim_attributes)
    ret_dim_attribs[ClimaAnalysis.time_name(var)]["units"] = "s" # add units
    ret_data = copy(var.data)
    return OutputVar(ret_attribs, ret_dims, ret_dim_attribs, ret_data)
end

function reorder_as(obs_var::OutputVar, dest_var::OutputVar)
    conventional_dim_name_obs = conventional_dim_name.(keys(obs_var.dims))
    conventional_dim_name_dest = conventional_dim_name.(keys(dest_var.dims))
    # Check if the dimensions are the same (order does not matter)
    Set(conventional_dim_name_obs) == Set(conventional_dim_name_dest) || error(
        "Dimensions are not the same between obs ($conventional_dim_name_obs) and dest ($conventional_dim_name_dest)",
    )

    # Find permutation indices to reorder dims
    reorder_indices = indexin(conventional_dim_name_dest, conventional_dim_name_obs)

    reorder_dict(dict, indices) = OrderedDict(collect(dict)[indices])

    # Reorder dims, dim_attribs, and data
    ret_dims = deepcopy(obs_var.dims)
    ret_dims = reorder_dict(ret_dims, reorder_indices)
    ret_attribs = deepcopy(obs_var.attributes)
    ret_dim_attribs = deepcopy(obs_var.dim_attributes)
    ret_dim_attribs = reorder_dict(ret_dim_attribs, reorder_indices)
    ret_data = copy(obs_var.data)
    ret_data = permutedims(ret_data, reorder_indices)
    return OutputVar(ret_attribs, ret_dims, ret_dim_attribs, ret_data)
end

# TODO: probably a more generic way of doing this?
function shift_lon(var::OutputVar)
    # Assume lon is between [0, 360] so we shift to get lon between [-180, 180]
    new_lon = var.dims["lon"] .- 180.0
    ret_dims = deepcopy(var.dims)
    ret_dims[ClimaAnalysis.longitude_name(var)] = new_lon
    ret_attribs = deepcopy(var.attributes)
    ret_dim_attribs = deepcopy(var.dim_attributes)
    ret_data = copy(var.data)
    return OutputVar(ret_attribs, ret_dims, ret_dim_attribs, ret_data)
end
