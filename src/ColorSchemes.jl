module FractalColorSchemes

using Colors
using ColorSchemes

export get_color_palette, apply_palette

"""
    get_color_palette(name::Symbol) -> Vector{RGB{Float64}}

Returns a list of colors for a given palette name.
"""
function get_color_palette(name::Symbol)
    if hasproperty(ColorSchemes, name)
        return getproperty(ColorSchemes, name).colors
    else
        return ColorSchemes.viridis.colors
    end
end

"""
    apply_palette(value::Float64, palette::Vector{RGB{Float64}}) -> RGB{Float64}

Maps a normalized iteration value (0..1) to a color from the palette.
A value of 0 (reached max_iter) is mapped to black.
"""
@inline function apply_palette(value::Float64, palette::Vector{C}) where {C<:Colorant}
    if value == 0.0
        return RGB(0.0, 0.0, 0.0)
    end
    
    n = length(palette)
    # value is (i / max_iter)
    idx = Int(clamp(floor(value * (n - 1)) + 1, 1, n))
    return palette[idx]
end

end # module
