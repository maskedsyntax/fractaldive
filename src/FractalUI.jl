module FractalUI

using Makie, GLMakie, Colors, CUDA, FileIO
using ..FractalEngine
using ..FractalColorSchemes
using ..Exporter
using Base.Threads

export run_app

function run_app()
    # Initial state
    width, height = 800, 600
    max_iter = Observable(256)
    auto_iter = Observable(false)
    high_precision = Observable(false)
    use_gpu = Observable(false)
    is_julia = Observable(false)
    julia_c = Observable(complex(-0.8, 0.156))
    palette_name = Observable(:fire)
    
    # Complex plane bounds
    xmin = Observable(-2.0)
    xmax = Observable(1.0)
    ymin = Observable(-1.5)
    ymax = Observable(1.5)
    
    # UI state
    data = Observable(zeros(width, height))
    is_rendering = Observable(false)
    is_dragging_glob = Observable(false)
    
    # Render management
    render_timer = Ref{Union{Timer, Nothing}}(nothing)
    stop_signal = Ref(false)
    current_render_task = Ref{Union{Task, Nothing}}(nothing)
    
    function update_render(low_res=false)
        stop_signal[] = true
        if render_timer[] !== nothing
            close(render_timer[])
        end
        
        delay = low_res ? 0.01 : 0.1
        render_timer[] = Timer(delay) do t
            stop_signal[] = false
            is_rendering[] = true
            current_render_task[] = Threads.@spawn begin
                try
                    scale = low_res ? 4 : 1
                    nx, ny = width ÷ scale, height ÷ scale
                    T = high_precision[] ? BigFloat : Float64
                    
                    if auto_iter[]
                        zoom_level = 3.0 / (xmax[] - xmin[])
                        new_iter = Int(clamp(round(256 * (1.0 + 0.5 * log10(max(1.0, zoom_level)))), 1, 10000))
                        if new_iter != max_iter[]
                            max_iter[] = new_iter
                        end
                    end
                    
                    if use_gpu[] && CUDA.functional() && !high_precision[]
                        x_r = CuArray(Vector{Float64}(range(xmin[], xmax[], length=nx)))
                        y_r = CuArray(Vector{Float64}(range(ymin[], ymax[], length=ny)))
                        output_gpu = CUDA.zeros(Float64, nx, ny)
                        render_fractal!(output_gpu, x_r, y_r, max_iter[]; is_julia=is_julia[], julia_c=complex(Float64(real(julia_c[])), Float64(imag(julia_c[]))))
                        matrix = Array(output_gpu)
                    else
                        x_range = range(T(xmin[]), T(xmax[]), length=nx)
                        y_range = range(T(ymin[]), T(ymax[]), length=ny)
                        matrix = zeros(nx, ny)
                        render_fractal!(matrix, x_range, y_range, max_iter[]; 
                                       is_julia=is_julia[], 
                                       julia_c=complex(T(real(julia_c[])), T(imag(julia_c[]))),
                                       stop_signal=stop_signal)
                    end
                    
                    if !stop_signal[]
                        data[] = matrix
                    end
                    is_rendering[] = false
                catch e
                    @error "Render error" exception=(e, catch_backtrace())
                    is_rendering[] = false
                end
            end
        end
    end
    
    # Force GLMakie config before showing
    GLMakie.activate!(title="FractalDive Explorer", focus_on_show=true)
    
    # Setup Figure with explicit size
    fig = Figure(size=(1200, 800))
    ax = Axis(fig[1, 1], aspect=DataAspect(), title="Fractal Explorer")
    
    hm = heatmap!(ax, 
        @lift(range($xmin, $xmax, length=size($data, 1))), 
        @lift(range($ymin, $ymax, length=size($data, 2))), 
        data, 
        colormap=:fire
    )
    
    # UI Controls - Vertically centered
    ctrl_grid = fig[1, 2] = GridLayout(tellheight=false, width=250, valign=:center)
    row = 1
    
    # Add logo
    try
        logo_path = joinpath(@__DIR__, "..", "fractaldive.png")
        if isfile(logo_path)
            logo_img = FileIO.load(logo_path)
            logo_ax = Axis(ctrl_grid[row, 1:2], aspect=DataAspect())
            image!(logo_ax, logo_img)
            hidedecorations!(logo_ax)
            hidespines!(logo_ax)
            logo_ax.tellheight = true
            logo_ax.height = 120
            row += 1
        end
    catch e
        @warn "Could not load logo" exception=e
    end
    
    ctrl_grid[row, 1:2] = Label(fig, @lift($is_rendering ? "Rendering..." : "Ready"), 
                               color=@lift($is_rendering ? :red : :black), halign=:left)
    row += 1
    
    ctrl_grid[row, 1:2] = Label(fig, "Max Iterations", halign=:left)
    row += 1
    sl_iter = Slider(ctrl_grid[row, 1:2], range=1:10000, startvalue=256)
    on(sl_iter.value) do val; max_iter[] = val; end
    row += 1
    
    cb_auto_iter = Toggle(fig, active=false)
    ctrl_grid[row, 1] = cb_auto_iter
    ctrl_grid[row, 2] = Label(fig, "Auto Iterations", halign=:left)
    on(cb_auto_iter.active) do val; auto_iter[] = val; end
    row += 1
    
    cb_precision = Toggle(fig, active=false)
    ctrl_grid[row, 1] = cb_precision
    ctrl_grid[row, 2] = Label(fig, "High Precision", halign=:left)
    on(cb_precision.active) do val; high_precision[] = val; end
    row += 1

    cb_gpu = Toggle(fig, active=false)
    ctrl_grid[row, 1] = cb_gpu
    ctrl_grid[row, 2] = Label(fig, "Use GPU", halign=:left)
    on(cb_gpu.active) do val; use_gpu[] = val; end
    row += 1
    
    toggle_julia = Toggle(fig, active=false)
    ctrl_grid[row, 1] = toggle_julia
    ctrl_grid[row, 2] = Label(fig, "Julia Set Mode", halign=:left)
    on(toggle_julia.active) do val; is_julia[] = val; end
    row += 1
    
    ctrl_grid[row, 1:2] = Label(fig, "Julia Re(c)", halign=:left)
    row += 1
    sl_julia_re = Slider(ctrl_grid[row, 1:2], range=-2.0:0.01:2.0, startvalue=-0.8)
    row += 1
    
    ctrl_grid[row, 1:2] = Label(fig, "Julia Im(c)", halign=:left)
    row += 1
    sl_julia_im = Slider(ctrl_grid[row, 1:2], range=-2.0:0.01:2.0, startvalue=0.156)
    row += 1
    
    onany(sl_julia_re.value, sl_julia_im.value) do re, im
        julia_c[] = complex(re, im)
    end
    
    ctrl_grid[row, 1:2] = Label(fig, "Palette", halign=:left)
    row += 1
    palettes = [:fire, :ice, :rainbow, :magma, :viridis, :inferno, :plasma, :thermal, :haline, :solar]
    palettes_str = string.(palettes)
    menu = Menu(ctrl_grid[row, 1:2], options=palettes_str, default="fire")
    on(menu.selection) do s
        psym = Symbol(s)
        palette_name[] = psym
        hm.colormap = psym
    end
    row += 1
    
    btn_export = Button(ctrl_grid[row, 1:2], label="Export PNG")
    on(btn_export.clicks) do _
        filename = "fractal_$(round(Int, time())).png"
        export_to_png(filename, data[], palette_name[])
        println("Exported to $filename")
    end
    row += 1
    
    btn_reset = Button(ctrl_grid[row, 1:2], label="Reset View")
    on(btn_reset.clicks) do _
        xmin[] = -2.0; xmax[] = 1.0; ymin[] = -1.5; ymax[] = 1.5
        update_render(false)
    end
    row += 1

    register_interaction!(ax, :zoom) do event::ScrollEvent, axis
        zoom_factor = event.y > 0 ? 0.8 : 1.25
        mp = Makie.mouseposition(axis.scene)
        new_w = (xmax[] - xmin[]) * zoom_factor
        new_h = (ymax[] - ymin[]) * zoom_factor
        xmin[] = mp[1] - (mp[1] - xmin[]) * zoom_factor
        xmax[] = xmin[] + new_w
        ymin[] = mp[2] - (mp[2] - ymin[]) * zoom_factor
        ymax[] = ymin[] + new_h
        update_render(false)
        return Consume(true)
    end
    
    last_mouse_pos = Ref{Point2f}((0, 0))
    register_interaction!(ax, :pan) do event::MouseEvent, axis
        if event.type == Makie.MouseEventTypes.leftdown
            last_mouse_pos[] = Makie.mouseposition(axis.scene)
            is_dragging_glob[] = true
            return Consume(true)
        elseif event.type == Makie.MouseEventTypes.leftup
            is_dragging_glob[] = false
            update_render(false)
            return Consume(true)
        elseif event.type == Makie.MouseEventTypes.leftdrag && is_dragging_glob[]
            mp = Makie.mouseposition(axis.scene)
            dx = mp[1] - last_mouse_pos[][1]
            dy = mp[2] - last_mouse_pos[][2]
            xmin[] -= dx; xmax[] -= dx; ymin[] -= dy; ymax[] -= dy
            update_render(true)
            last_mouse_pos[] = Makie.mouseposition(axis.scene)
            return Consume(true)
        end
        return Consume(false)
    end
    
    onany(max_iter, is_julia, julia_c, high_precision, auto_iter, use_gpu) do _, _, _, _, _, _
        update_render(false)
    end
    
    status_bar = fig[2, 1] = Label(fig, "Ready", tellwidth=false)
    onany(xmin, xmax, ymin, ymax, max_iter) do xi, xa, yi, ya, mi
        status_bar.text = "Threads: $(Threads.nthreads()) | Zoom: $(round(3.0/(xa-xi), digits=2))x | Iter: $mi"
    end

    update_render(false)
    
    # Display and force resize
    screen = display(fig)
    if screen isa GLMakie.Screen
        # Small delay to let the OS map the window
        sleep(0.5)
        resize!(screen, 1200, 800)
    end
    
    if !isinteractive()
        while isopen(fig.scene)
            sleep(0.1)
            yield()
        end
    end
end

end # module
