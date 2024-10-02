using ClimaAnalysis
import ClimaUtilities.ClimaArtifacts: @clima_artifact
using NCDatasets

test_var = ClimaAnalysis.OutputVar(
    joinpath(@clima_artifact("radiation_obs"), "CERES_EBAF_Ed4.2_Subset_200003-201910.nc"),
    "solar_mon",
)


ds = NCDataset(
    joinpath(@clima_artifact("radiation_obs"), "CERES_EBAF_Ed4.2_Subset_200003-201910.nc"),
)
