"""
    Checkpointer

This module contains template functions for checkpointing the model states and restarting the simulations from the Coupler.
"""
module Checkpointer

using ClimaCore: Fields, InputOutput
using ClimaCoupler: Interfacer
using Dates
using ClimaCoupler.TimeManager: AbstractFrequency, Monthly, EveryTimestep, trigger_callback
using ClimaComms
export get_model_state_vector, checkpoint_model_state, restart_model_state!

"""
    get_model_state_vector(sim::Interfacer.ComponentModelSimulation)

Returns the model state of a simulation as a `ClimaCore.FieldVector`.
This is a template function that should be implemented for each component model.
"""
get_model_state_vector(sim::Interfacer.ComponentModelSimulation) = nothing

"""
    checkpoint_model_state(sim::Interfacer.ComponentModelSimulation, comms_ctx::ClimaComms.AbstractCommsContext, t::Int; output_dir = "output")

Checkpoints the model state of a simulation to a HDF5 file at a given time, t (in seconds).
"""
function checkpoint_model_state(
    sim::Interfacer.ComponentModelSimulation,
    comms_ctx::ClimaComms.AbstractCommsContext,
    t::Int;
    output_dir = "output",
)
    Y = get_model_state_vector(sim)
    day = floor(Int, t / (60 * 60 * 24))
    sec = floor(Int, t % (60 * 60 * 24))
    @info "Saving checkpoint " * Interfacer.name(sim) * " model state to HDF5 on day $day second $sec"
    mkpath(joinpath(output_dir, "checkpoint"))
    output_file = joinpath(output_dir, "checkpoint", "checkpoint_" * Interfacer.name(sim) * "_$t.hdf5")
    hdfwriter = InputOutput.HDF5Writer(output_file, comms_ctx)
    InputOutput.HDF5.write_attribute(hdfwriter.file, "time", t)
    InputOutput.write!(hdfwriter, Y, "model_state")
    Base.close(hdfwriter)
    return nothing

end

"""
    restart_model_state!(sim::Interfacer.ComponentModelSimulation, t::Int; input_dir = "input")

Sets the model state of a simulation from a HDF5 file from a given time, t (in seconds).
"""
function restart_model_state!(sim::Interfacer.ComponentModelSimulation, t::Int; input_dir = "input")
    Y = get_model_state_vector(sim)
    day = floor(Int, t / (60 * 60 * 24))
    sec = floor(Int, t % (60 * 60 * 24))
    input_file = joinpath(input_dir, "checkpoint", "checkpoint_" * Interfacer.name(sim) * "_$t.hdf5")

    @info "Setting " Interfacer.name(sim) " state to checkpoint: $input_file, corresponding to day $day second $sec"

    # open file and read
    hdfreader = InputOutput.HDF5Reader(input_file)
    Y_new = InputOutput.read_field(hdfreader, "model_state")
    Base.close(hdfreader)

    # set new state
    Y .= Y_new
end

end # module