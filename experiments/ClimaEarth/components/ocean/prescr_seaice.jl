import SciMLBase
import ClimaCore as CC
import ClimaTimeSteppers as CTS
import Thermodynamics as TD
import ClimaCoupler: Checkpointer, FluxCalculator, Interfacer, Regridder, Utilities

include("../slab_utils.jl")

###
### Functions required by ClimaCoupler.jl for a SurfaceModelSimulation
###
"""
    PrescribedIceSimulation{P, Y, D, I}

Ice concentration is prescribed, and we solve the following energy equation:

    (h * ρ * c) d T_sfc dt = -(F_turb_energy + F_radiativead) + F_conductive

    with
    F_conductive = k_ice (T_base - T_sfc) / (h)

    The surface temperature (`T_sfc`) is the prognostic variable which is being
    modified by turbulent aerodynamic (`F_turb_energy`) and radiative (`F_turb_energy`) fluxes,
    as well as a conductive flux that depends on the temperature difference
    across the ice layer (with `T_base` being prescribed).

In the current version, the sea ice has a prescribed thickness, and we assume that it is not
sublimating. That contribution has been zeroed out in the atmos fluxes.

"""
struct PrescribedIceSimulation{P, Y, D, I} <: Interfacer.SeaIceModelSimulation
    params::P
    Y_init::Y
    domain::D
    integrator::I
end
Interfacer.name(::PrescribedIceSimulation) = "PrescribedIceSimulation"

# sea-ice parameters
Base.@kwdef struct IceSlabParameters{FT <: AbstractFloat}
    h::FT = 2               # ice thickness [m]
    ρ::FT = 900             # density of sea ice [kg / m3]
    c::FT = 2100            # specific heat of sea ice [J / kg / K]
    T_base::FT = 271.2      # temperature of sea water at the ice base
    z0m::FT = 1e-4          # roughness length for momentum [m]
    z0b::FT = 1e-4          # roughness length for tracers [m]
    T_freeze::FT = 271.2    # freezing temperature of sea water [K]
    k_ice::FT = 2           # thermal conductivity of sea ice [W / m / K] (less in HM71)
    α::FT = 0.8             # albedo of sea ice [0, 1]
end

Interfacer.name(::IceSlabParameters) = "IceSlabParameters"

# init simulation
function slab_ice_space_init(::Type{FT}, space, p) where {FT}
    Y = CC.Fields.FieldVector(T_sfc = ones(space) .* p.T_freeze)
    return Y
end

"""
    ice_init(::Type{FT}; tspan, dt, saveat, space, ice_fraction, stepper = CTS.RK4()) where {FT}

Initializes the `DiffEq` problem, and creates a Simulation-type object containing the necessary information for `Interfacer.step!` in the coupling loop.
"""
function ice_init(::Type{FT}; tspan, saveat, dt, space, area_fraction, thermo_params, stepper = CTS.RK4()) where {FT}

    params = IceSlabParameters{FT}()

    Y = slab_ice_space_init(FT, space, params)
    additional_cache = (;
        F_turb_energy = CC.Fields.zeros(space),
        F_radiative = CC.Fields.zeros(space),
        q_sfc = CC.Fields.zeros(space),
        ρ_sfc = CC.Fields.zeros(space),
        area_fraction = area_fraction,
        dt = dt,
        thermo_params = thermo_params,
        # add dss_buffer to cache to avoid runtime dss allocation
        dss_buffer = CC.Spaces.create_dss_buffer(CC.Fields.zeros(space)),
    )

    ode_algo = CTS.ExplicitAlgorithm(stepper)
    ode_function = CTS.ClimaODEFunction(T_exp! = ice_rhs!, dss! = weighted_dss_slab!)

    problem = SciMLBase.ODEProblem(ode_function, Y, Float64.(tspan), (; additional_cache..., params = params))
    integrator = SciMLBase.init(problem, ode_algo, dt = Float64(dt), saveat = Float64(saveat), adaptive = false)

    sim = PrescribedIceSimulation(params, Y, space, integrator)

    # DSS state to ensure we have continuous fields
    dss_state!(sim)
    return sim
end

# extensions required by Interfacer
Interfacer.get_field(sim::PrescribedIceSimulation, ::Val{:air_density}) = sim.integrator.p.ρ_sfc
Interfacer.get_field(sim::PrescribedIceSimulation, ::Val{:area_fraction}) = sim.integrator.p.area_fraction
Interfacer.get_field(sim::PrescribedIceSimulation, ::Val{:beta}) = convert(eltype(sim.integrator.u), 1.0)
Interfacer.get_field(sim::PrescribedIceSimulation, ::Val{:roughness_buoyancy}) = sim.integrator.p.params.z0b
Interfacer.get_field(sim::PrescribedIceSimulation, ::Val{:roughness_momentum}) = sim.integrator.p.params.z0m
Interfacer.get_field(sim::PrescribedIceSimulation, ::Union{Val{:surface_direct_albedo}, Val{:surface_diffuse_albedo}}) =
    sim.integrator.p.params.α
Interfacer.get_field(sim::PrescribedIceSimulation, ::Val{:surface_humidity}) = sim.integrator.p.q_sfc
Interfacer.get_field(sim::PrescribedIceSimulation, ::Val{:surface_temperature}) = sim.integrator.u.T_sfc
Interfacer.get_field(sim::PrescribedIceSimulation, ::Val{:water}) = nothing

"""
    Interfacer.get_field(sim::PrescribedIceSimulation, ::Val{:energy})

Extension of Interfacer.get_field to get the energy of the ocean.
It multiplies the the slab temperature by the heat capacity, density, and depth.
"""
Interfacer.get_field(sim::PrescribedIceSimulation, ::Val{:energy}) =
    sim.integrator.p.params.ρ .* sim.integrator.p.params.c .* sim.integrator.u.T_sfc .* sim.integrator.p.params.h

function Interfacer.update_field!(sim::PrescribedIceSimulation, ::Val{:air_density}, field)
    parent(sim.integrator.p.ρ_sfc) .= parent(field)
end
function Interfacer.update_field!(sim::PrescribedIceSimulation, ::Val{:area_fraction}, field::CC.Fields.Field)
    sim.integrator.p.area_fraction .= field
end
function Interfacer.update_field!(sim::PrescribedIceSimulation, ::Val{:radiative_energy_flux_sfc}, field)
    parent(sim.integrator.p.F_radiative) .= parent(field)
end
function Interfacer.update_field!(sim::PrescribedIceSimulation, ::Val{:turbulent_energy_flux}, field)
    parent(sim.integrator.p.F_turb_energy) .= parent(field)
end

# extensions required by FieldExchanger
Interfacer.step!(sim::PrescribedIceSimulation, t) = Interfacer.step!(sim.integrator, t - sim.integrator.t, true)
Interfacer.reinit!(sim::PrescribedIceSimulation) = Interfacer.reinit!(sim.integrator)

# extensions required by FluxCalculator (partitioned fluxes)
function FluxCalculator.update_turbulent_fluxes!(sim::PrescribedIceSimulation, fields::NamedTuple)
    (; F_turb_energy) = fields
    @. sim.integrator.p.F_turb_energy = F_turb_energy
end

"""
    Checkpointer.get_model_prog_state(sim::PrescribedIceSimulation)

Extension of Checkpointer.get_model_prog_state to get the model state.
"""
function Checkpointer.get_model_prog_state(sim::PrescribedIceSimulation)
    return sim.integrator.u
end

###
### Sea ice model-specific functions (not explicitly required by ClimaCoupler.jl)
###
# setting that SIC < 0.5 is counted as ocean if binary remapping.
get_ice_fraction(h_ice::FT, mono::Bool, threshold = 0.5) where {FT} =
    mono ? h_ice : Regridder.binary_mask(h_ice, threshold)

"""
    ice_rhs!(du, u, p, _)

Rhs method in the form as required by `ClimeTimeSteppers`, with the tendency vector `du`,
the state vector `u` and the parameter vector, `p`, as input arguments.

This sea-ice energy formulation follows [Holloway and Manabe 1971](https://journals.ametsoc.org/view/journals/mwre/99/5/1520-0493_1971_099_0335_socbag_2_3_co_2.xml?tab_body=pdf),
where sea-ice concentrations and thicknes are prescribed, and the model solves for temperature (curbed at the freezing point).
"""
function ice_rhs!(du, u, p, _)
    dY = du
    Y = u
    FT = eltype(dY)

    params = p.params
    F_turb_energy = p.F_turb_energy
    F_radiative = p.F_radiative
    area_fraction = p.area_fraction
    T_freeze = params.T_freeze

    F_conductive = @. params.k_ice / (params.h) * (params.T_base - Y.T_sfc) # fluxes are defined to be positive when upward
    rhs = @. (-F_turb_energy - F_radiative + F_conductive) / (params.h * params.ρ * params.c)

    # do not count tendencies that lead to temperatures above freezing, and mask out no-ice areas
    area_mask = Regridder.binary_mask.(area_fraction)
    threshold = zero(FT)
    unphysical = @. Regridder.binary_mask.(T_freeze - (Y.T_sfc + FT(rhs) * FT(p.dt)), threshold) .* area_mask
    parent(dY.T_sfc) .= parent(rhs .* unphysical)

    @. p.q_sfc = TD.q_vap_saturation_generic.(p.thermo_params, Y.T_sfc, p.ρ_sfc, TD.Ice())
end

"""
    dss_state!(sim::PrescribedIceSimulation)

Perform DSS on the state of a component simulation, intended to be used
before the initial step of a run. This method acts on prescribed ice simulations.
"""
function dss_state!(sim::PrescribedIceSimulation)
    Y = sim.integrator.u
    p = sim.integrator.p
    for key in propertynames(Y)
        field = getproperty(Y, key)
        buffer = get_dss_buffer(axes(field), p)
        CC.Spaces.weighted_dss!(field, buffer)
    end
end
