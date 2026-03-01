module FractalEngine

using Base.Threads
using CUDA

export mandelbrot_pixel, julia_pixel, render_fractal!, render_fractal_gpu!

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
        if abs2(z) > 16.0  # Large escape radius for smoother colors
            return (i + 1.0 - 0.5 * log2(log(abs2(z)))) / max_iter
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
        if abs2(curr_z) > 16.0
            return (i + 1.0 - 0.5 * log2(log(abs2(curr_z)))) / max_iter
        end
    end
    return 0.0
end

# Kernel for GPU
function fractal_kernel(output, x_range, y_range, max_iter, is_julia, julia_c)
    i = (blockIdx().x - 1) * blockDim().x + threadIdx().x
    j = (blockIdx().y - 1) * blockDim().y + threadIdx().y
    
    nx, ny = size(output)
    if i <= nx && j <= ny
        p = complex(x_range[i], y_range[j])
        if is_julia
            output[i, j] = julia_pixel(p, julia_c, max_iter)
        else
            output[i, j] = mandelbrot_pixel(p, max_iter)
        end
    end
    return nothing
end

"""
    render_fractal_gpu!(output::CuMatrix, x_range, y_range, max_iter::Int; 
                       is_julia=false, julia_c=complex(0.0, 0.0))
"""
function render_fractal_gpu!(
    output::CuMatrix{Float64}, 
    x_range::CuVector{T}, 
    y_range::CuVector{T}, 
    max_iter::Int; 
    is_julia::Bool=false, 
    julia_c::Complex{T}=complex(zero(T), zero(T))
) where {T<:Real}
    nx, ny = size(output)
    threads = (16, 16)
    blocks = (ceil(Int, nx/threads[1]), ceil(Int, ny/threads[2]))
    
    @cuda threads=threads blocks=blocks fractal_kernel(
        output, x_range, y_range, max_iter, is_julia, julia_c
    )
end

"""
    render_fractal!(output::AbstractMatrix, x_range, y_range, max_iter::Int; 
                   is_julia=false, julia_c=complex(0.0, 0.0), stop_signal=nothing)

Renders a fractal into the output matrix using multi-threading or GPU.
"""
function render_fractal!(
    output::AbstractMatrix{Float64}, 
    x_range::AbstractVector{T}, 
    y_range::AbstractVector{T}, 
    max_iter::Int; 
    is_julia::Bool=false, 
    julia_c::Complex{T}=complex(zero(T), zero(T)),
    stop_signal=nothing
) where {T<:Real}
    # Check for GPU
    if output isa CuArray && x_range isa CuArray && y_range isa CuArray
        render_fractal_gpu!(output, x_r, y_r, max_iter; is_julia=is_julia, julia_c=julia_c)
        return
    end

    nx, ny = size(output)
    @threads for j in 1:ny
        # Check stop signal periodically
        if stop_signal !== nothing && stop_signal[]
            break
        end
        
        @inbounds for i in 1:nx
            p = complex(x_range[i], y_range[j])
            if is_julia
                output[i, j] = julia_pixel(p, julia_c, max_iter)
            else
                output[i, j] = mandelbrot_pixel(p, max_iter)
            end
        end
        # Yield more frequently to allow UI events to process
        yield()
    end
end

end # module
