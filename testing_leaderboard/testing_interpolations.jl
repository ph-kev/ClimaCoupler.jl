using Interpolations

xs = 1:0.2:5 |> collect
ys = 1:0.2:5 |> collect
data = ones(length(xs), length(ys))
dims_tuple = (xs, ys)
interp_linear = extrapolate(interpolate(dims_tuple, data, Gridded(Linear())), (Throw(), Periodic()))

x = interp_linear(1.07, 9.03)

bounds(interp_linear)