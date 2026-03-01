module FractalEngine

using Base.Threads

export mandelbrot_pixel, julia_pixel, render_fractal!

"""
    mandelbrot_pixel(c::Complex, max_iter::Int) -> Float64

Calculates the iteration count for a point in the Mandelbrot set.
Returns a normalized value between 0 and 1, or 0 if it reached max_iter.
Uses the smooth coloring algorithm.
"""
@inline function mandelbrot_pixel(c::Complex{T}, max_iter::Int) where {T<:Real}
    z = complex(zero(T), zero(T))
    for i in 1:max_iter
        z = z*z + c
        if abs2(z) > 4.0
            return Float64(i) / max_iter
        end
    end
    return 0.0
end

"""
    julia_pixel(z::Complex, c::Complex, max_iter::Int) -> Float64

Calculates the iteration count for a point in a Julia set.
"""
@inline function julia_pixel(z::Complex{T}, c::Complex{T}, max_iter::Int) where {T<:Real}
    curr_z = z
    for i in 1:max_iter
        curr_z = curr_z*curr_z + c
        if abs2(curr_z) > 4.0
            return Float64(i) / max_iter
        end
    end
    return 0.0
end

"""
    render_fractal!(output::AbstractMatrix, x_range, y_range, max_iter::Int; 
                   is_julia=false, julia_c=complex(0.0, 0.0))

Renders a fractal into the output matrix using multi-threading.
"""
function render_fractal!(
    output::AbstractMatrix{Float64}, 
    x_range::AbstractVector{T}, 
    y_range::AbstractVector{T}, 
    max_iter::Int; 
    is_julia::Bool=false, 
    julia_c::Complex{T}=complex(zero(T), zero(T))
) where {T<:Real}
    nx, ny = size(output)
    
    @threads for j in 1:ny
        for i in 1:nx
            p = complex(x_range[i], y_range[j])
            if is_julia
                @inbounds output[i, j] = julia_pixel(p, julia_c, max_iter)
            else
                @inbounds output[i, j] = mandelbrot_pixel(p, max_iter)
            end
        end
    end
end

end # module
