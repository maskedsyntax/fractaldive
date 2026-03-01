module FractalDive

include("FractalEngine.jl")
include("ColorSchemes.jl")
include("Exporter.jl")
include("FractalUI.jl")

using .FractalUI

export main

"""
    main()

Entry point for the FractalDive application.
"""
function main()
    println("Starting FractalDive...")
    run_app()
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end

end # module
