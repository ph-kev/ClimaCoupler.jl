using ClimaAnalysis
import ClimaUtilities.ClimaArtifacts: @clima_artifact
using NCDatasets


ds = NCDataset(
    joinpath(@clima_artifact("precipitation_obs"), "gpcp.precip.mon.mean.197901-202305.nc"),
)
