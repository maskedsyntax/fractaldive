module Exporter

using Images, FileIO, Colors
using ..FractalColorSchemes

export export_to_png

"""
    export_to_png(filename::String, data::AbstractMatrix{Float64}, palette_name::Symbol)

Saves the fractal data matrix as a PNG image with the specified color palette.
"""
function export_to_png(filename::String, data::AbstractMatrix{Float64}, palette_name::Symbol)
    palette = get_color_palette(palette_name)
    nx, ny = size(data)
    
    # Transpose and apply color mapping
    # Note: data[i, j] corresponds to (x, y). 
    # Images are normally (y, x) or we can just map it correctly.
    # We want top-left to be the first pixel in the image.
    img = Matrix{RGB{Float16}}(undef, ny, nx)
    
    for j in 1:ny
        for i in 1:nx
            # j=1 is top, j=ny is bottom in some coordinate systems
            # In our data, j=1 is min_y, j=ny is max_y.
            # PNG image coordinates: (row, col) where (1, 1) is top-left.
            # So row=1 is max_y, row=ny is min_y.
            img[ny - j + 1, i] = apply_palette(data[i, j], palette)
        end
    end
    
    save(filename, img)
end

end # module
