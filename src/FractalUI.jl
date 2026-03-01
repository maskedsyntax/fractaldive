module FractalUI

using Makie, GLMakie, Colors, CUDA
using ..FractalEngine
using ..FractalColorSchemes
using ..Exporter

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
    
    # Render data
    data = Observable(zeros(width, height))
    
    function update_render()
        nx, ny = width, height
        
        # Determine precision
        T = high_precision[] ? BigFloat : Float64
        
        # Auto iterations: roughly proportional to zoom
        if auto_iter[]
            zoom_level = 3.0 / (xmax[] - xmin[])
            new_iter = Int(clamp(round(256 * (1.0 + 0.5 * log10(max(1.0, zoom_level)))), 1, 10000))
            if new_iter != max_iter[]
                max_iter[] = new_iter
            end
        end
        
        if use_gpu[] && CUDA.functional() && !high_precision[]
            # GPU Rendering
            # Note: T is Float64 here
            x_r = CuArray(Vector{Float64}(range(xmin[], xmax[], length=nx)))
            y_r = CuArray(Vector{Float64}(range(ymin[], ymax[], length=ny)))
            output_gpu = CUDA.zeros(Float64, nx, ny)
            
            render_fractal!(output_gpu, x_r, y_r, max_iter[]; 
                           is_julia=is_julia[], 
                           julia_c=complex(Float64(real(julia_c[])), Float64(imag(julia_c[]))))
            data[] = Array(output_gpu)
        else
            # CPU Rendering
            x_range = range(T(xmin[]), T(xmax[]), length=nx)
            y_range = range(T(ymin[]), T(ymax[]), length=ny)
            matrix = zeros(nx, ny)
            render_fractal!(matrix, x_range, y_range, max_iter[]; 
                           is_julia=is_julia[], 
                           julia_c=complex(T(real(julia_c[])), T(imag(julia_c[]))))
            data[] = matrix
        end
    end
    
    # Setup Figure
    fig = Figure(size=(1200, 800))
    ax = Axis(fig[1, 1], aspect=DataAspect(), title="Fractal Explorer")
    
    # Fractal heatmap
    hm = heatmap!(ax, 
        @lift(range($xmin, $xmax, length=width)), 
        @lift(range($ymin, $ymax, length=height)), 
        data, 
        colormap=:fire
    )
    
    # UI Controls
    ctrl_grid = fig[1, 2] = GridLayout(tellheight=false, width=250)
    
    row = 1
    ctrl_grid[row, 1:2] = Label(fig, "Max Iterations", halign=:left)
    row += 1
    sl_iter = Slider(ctrl_grid[row, 1:2], range=1:10000, startvalue=256)
    connect!(max_iter, sl_iter.value)
    row += 1
    
    ctrl_grid[row, 1] = Toggle(fig, active=false)
    ctrl_grid[row, 2] = Label(fig, "Auto Iterations", halign=:left)
    cb_auto_iter = ctrl_grid[row, 1].content
    connect!(auto_iter, cb_auto_iter.active)
    row += 1
    
    ctrl_grid[row, 1] = Toggle(fig, active=false)
    ctrl_grid[row, 2] = Label(fig, "High Precision", halign=:left)
    cb_precision = ctrl_grid[row, 1].content
    connect!(high_precision, cb_precision.active)
    row += 1

    ctrl_grid[row, 1] = Toggle(fig, active=false)
    ctrl_grid[row, 2] = Label(fig, "Use GPU", halign=:left)
    cb_gpu = ctrl_grid[row, 1].content
    connect!(use_gpu, cb_gpu.active)
    row += 1
    
    ctrl_grid[row, 1] = Toggle(fig, active=false)
    ctrl_grid[row, 2] = Label(fig, "Julia Set Mode", halign=:left)
    toggle_julia = ctrl_grid[row, 1].content
    connect!(is_julia, toggle_julia.active)
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
    menu = Menu(ctrl_grid[row, 1:2], options=palettes, default=:fire)
    on(menu.selection) do s
        palette_name[] = s
        hm.colormap = s
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
        update_render()
    end
    row += 1

    # Status Bar
    status_bar = fig[2, 1] = Label(fig, "Ready", tellwidth=false)
    onany(xmin, xmax, ymin, ymax, max_iter) do xi, xa, yi, ya, mi
        status_bar.text = "X: [$(round(xi, digits=6)), $(round(xa, digits=6))] Y: [$(round(yi, digits=6)), $(round(ya, digits=6))] Iter: $mi"
    end
    
    # Interactions: Zoom and Pan
    register_interaction!(ax, :zoom) do event::ScrollEvent, axis
        zoom_factor = event.y > 0 ? 0.8 : 1.25
        mp = Makie.mouseposition(axis.scene)
        
        new_w = (xmax[] - xmin[]) * zoom_factor
        new_h = (ymax[] - ymin[]) * zoom_factor
        
        xmin[] = mp[1] - (mp[1] - xmin[]) * zoom_factor
        xmax[] = xmin[] + new_w
        ymin[] = mp[2] - (mp[2] - ymin[]) * zoom_factor
        ymax[] = ymin[] + new_h
        
        update_render()
        return Consume(true)
    end
    
    last_mouse_pos = Ref{Point2f}((0, 0))
    is_dragging = Ref(false)
    
    register_interaction!(ax, :pan) do event::MouseEvent, axis
        if event.type == MouseEventTypes.leftbuttondown
            last_mouse_pos[] = Makie.mouseposition(axis.scene)
            is_dragging[] = true
            return Consume(true)
        elseif event.type == MouseEventTypes.leftbuttonup
            is_dragging[] = false
            return Consume(true)
        elseif event.type == MouseEventTypes.drag && is_dragging[]
            mp = Makie.mouseposition(axis.scene)
            dx = mp[1] - last_mouse_pos[][1]
            dy = mp[2] - last_mouse_pos[][2]
            
            xmin[] -= dx
            xmax[] -= dx
            ymin[] -= dy
            ymax[] -= dy
            
            update_render()
            last_mouse_pos[] = Makie.mouseposition(axis.scene)
            return Consume(true)
        end
        return Consume(false)
    end
    
    # Initial render
    update_render()
    
    # Observe changes in parameters
    onany(max_iter, is_julia, julia_c, high_precision, auto_iter, use_gpu) do _, _, _, _, _, _
        update_render()
    end
    
    on(is_julia) do val
        ax.title = val ? "Julia Explorer" : "Mandelbrot Explorer"
    end
    
    display(fig)
end

end # module
