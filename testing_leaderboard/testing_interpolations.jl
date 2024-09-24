xs = 1:0.2:5
A = Vector{Union{Float64,Missing}}(log.(xs))
interp_linear = linear_interpolation(xs, A)

interp_linear(1.07)
