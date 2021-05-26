#!/usr/bin/env julia --project
include("utilities/boilerplate.jl")
using CouplerMachine

########
# Set up parameters and initial conditions
########
include("parameters_initialconditions.jl")

FT = Float64

########
# Set up domain
########

# A: low atmos level (troposphere)
domainA = SphericalShell(
    radius = FT(1), 
    height = FT(0.2),
)
# B: high atmos level (stratosphere)
domainB = SphericalShell(
    radius = domainA.radius + domainA.height,
    height = domainA.height,
)

gridA = DiscretizedDomain(
    domainA;
    elements = (vertical = 1, horizontal = 8),
    polynomial_order = (vertical = 0, horizontal = 3),
    overintegration_order = (vertical = 1, horizontal = 1),
)

gridB = DiscretizedDomain(
    domainB;
    elements = (vertical = 1, horizontal = 8),
    polynomial_order = (vertical = 0, horizontal = 3),
    overintegration_order = (vertical = 1, horizontal = 1),
)

########
# Set up model physics
######## 

physics = Physics(
    orientation = SphericalOrientation(),
    advection   = NonLinearAdvection(),
    coriolis    = DeepShellCoriolis{Float64}(Ω = parameters.Ω),
    gravity     = Buoyancy{Float64}(α = parameters.α, g = 0.0),
    eos         = BarotropicFluid{Float64}(ρₒ = parameters.ρₒ, cₛ = parameters.cₛ),
)

########
# Set up boundary conditions
########

bcsA = (
    bottom = (ρu = Impenetrable(FreeSlip()), ρθ = Insulating()),
    top =    (ρu = Impenetrable(FreeSlip()), ρθ = CoupledSecondaryBoundary()),
)
bcsB = (
    bottom = (ρu = Impenetrable(FreeSlip()), ρθ = CoupledPrimaryBoundary()),
    top =    (ρu = Impenetrable(FreeSlip()), ρθ = Insulating()),
)

########
# Set up model
########

modelA = ModelSetup(
    physics = physics,
    boundary_conditions = bcsA,
    initial_conditions = (ρ = ρ₀ᶜᵃʳᵗ, ρu = ρu⃗₀ᶜᵃʳᵗ, ρθ = ρθ₀ᶜᵃʳᵗ),
    numerics = (flux = RoeNumericalFlux(),flux_second_order = PenaltyNumFluxDiffusive()),
    parameters = parameters,
)

modelB = ModelSetup(
    physics = physics,
    boundary_conditions = bcsB,
    initial_conditions = (ρ = ρ₀ᶜᵃʳᵗ, ρu = ρu⃗₀ᶜᵃʳᵗ, ρθ = ρθ₀ᶜᵃʳᵗ),
    numerics = (flux = RoeNumericalFlux(),flux_second_order = PenaltyNumFluxDiffusive()),
    parameters = parameters,
)

########
# Set up time steppers (could be done automatically in simulation)
########
Δt  = min_node_distance(gridA.numerical) / parameters.cₛ * 0.25
start_time = 0
end_time = Δt*10#30 * 24 * 3600
method = SSPRK22Heuns
callbacks = (
  Info(),
  CFL(),
  VTKState(
    iteration = Int(floor(6*3600/Δt)), 
    filepath = "./out/"),
)

########
# Set up simulation
########
nstepsA = 1
nstepsB = 1

epss = sqrt(eps(FT))
boundary_mask( param_set, xc, yc, zc ) = @. abs(( xc^2 + yc^2 + zc^2 )^0.5 - domainB.radius) < epss
    
simA = CplSimulation(
    modelA;
    grid = gridA,
    timestepper = (method = method, timestep = Δt / nstepsA),
    time        = (start = start_time, finish = end_time),
    nsteps      = nstepsA,
    boundary_z = boundary_mask,
    callbacks   = callbacks,
)
simB = CplSimulation(
    modelA;
    grid = gridB,
    timestepper = (method = method, timestep = Δt / nstepsB),
    time        = (start = start_time, finish = end_time),
    nsteps      = nstepsB,
    boundary_z = boundary_mask,
    callbacks   = callbacks,
)

## Create a Coupler State object for holding imort/export fields.
coupler = CplState()
register_cpl_field!(coupler, :EnergyA, deepcopy(simA.state.ρθ[simA.boundary]), simA.grid, DateTime(0), u"J") # value on top of domainA for calculating upward flux into domainB
register_cpl_field!(coupler, :EnergyFluxB, deepcopy(simB.state.F_ρθ_accum[simB.boundary]), simB.grid, DateTime(0), u"J") # downward flux

compA = (pre_step = preA, component_model = simA, post_step = postA)
compB = (pre_step = preB, component_model = simB, post_step = postB)
component_list = (domainA = compA, domainB = compB)


cpl_solver = CplSolver(
    component_list = component_list,
    coupler = coupler,
    coupling_dt = Δt,
    t0 = FT(start_time),
)

########
# Run the simulation
########
numberofsteps = Int( round((end_time - start_time) / Δt))
evolve!(cpl_solver, numberofsteps)

nothing