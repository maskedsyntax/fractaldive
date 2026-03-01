using Test
include("../src/FractalEngine.jl")
using .FractalEngine

@testset "FractalEngine Tests" begin
    # Mandelbrot set (0,0) should be inside
    @test mandelbrot_pixel(0.0 + 0.0im, 100) == 0.0
    
    # Mandelbrot set (2,2) should be outside
    @test mandelbrot_pixel(2.0 + 2.0im, 100) > 0.0
    
    # Julia set test
    @test julia_pixel(0.0 + 0.0im, 0.0 + 0.0im, 100) == 0.0
end
