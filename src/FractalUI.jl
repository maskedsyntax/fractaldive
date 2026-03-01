module FractalUI

using Makie, GLMakie, Colors
using ..FractalEngine
using ..FractalColorSchemes
using ..Exporter

export run_app

function run_app()
    # Initial state
    width, height = 800, 600
    max_iter = Observable(256)
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
        x_range = range(xmin[], xmax[], length=nx)
        y_range = range(ymin[], ymax[], length=ny)
        
        # Calculate in-place
        matrix = zeros(nx, ny)
        render_fractal!(matrix, x_range, y_range, max_iter[]; is_julia=is_julia[], julia_c=julia_c[])
        data[] = matrix
    end
    
    # Setup plot
    fig = Figure(size=(1000, 800))
    ax = Axis(fig[1, 1], aspect=DataAspect(), title="Mandelbrot Explorer")
    
    # Fractal heatmap
    # Use custom coloring via applying palette manually or using Makie's colormap
    # To have it interactive, it is easier to use Makie's colormap
    hm = heatmap!(ax, 
        @lift(range(xmin[], xmax[], length=width)), 
        @lift(range(ymin[], ymax[], length=height)), 
        data, 
        colormap=:fire
    )
    
    # UI Controls
    ctrl_grid = fig[1, 2] = GridLayout(tellheight=false, width=200)
    
    # Iteration slider
    ctrl_grid[1, 1] = Label(fig, "Max Iterations")
    sl_iter = Slider(fig[1, 2][2, 1], range=1:1000, startvalue=256)
    connect!(max_iter, sl_iter.value)
    
    # Set type toggle
    ctrl_grid[3, 1] = Label(fig, "Mode")
    toggle_julia = Toggle(fig[1, 2][4, 1], active=false)
    connect!(is_julia, toggle_julia.active)
    
    # Julia parameters (only if Julia mode is on)
    ctrl_grid[5, 1] = Label(fig, "Julia Re(c)")
    sl_julia_re = Slider(fig[1, 2][6, 1], range=-2.0:0.01:2.0, startvalue=-0.8)
    ctrl_grid[7, 1] = Label(fig, "Julia Im(c)")
    sl_julia_im = Slider(fig[1, 2][8, 1], range=-2.0:0.01:2.0, startvalue=0.156)
    
    onany(sl_julia_re.value, sl_julia_im.value) do re, im
        julia_c[] = complex(re, im)
    end
    
    # Color palette
    ctrl_grid[9, 1] = Label(fig, "Palette")
    palettes = [:fire, :ice, :rainbow, :magma, :viridis]
    menu = Menu(fig[1, 2][10, 1], options=palettes, default=:fire)
    on(menu.selection) do s
        palette_name[] = s
        hm.colormap = s
    end
    
    # Export button
    btn_export = Button(fig[1, 2][11, 1], label="Export PNG")
    on(btn_export.clicks) do _
        filename = "fractal_$(round(time())).png"
        export_to_png(filename, data[], palette_name[])
        println("Exported to $filename")
    end
    
    # Reset view button
    btn_reset = Button(fig[1, 2][12, 1], label="Reset View")
    on(btn_reset.clicks) do _
        xmin[] = -2.0; xmax[] = 1.0; ymin[] = -1.5; ymax[] = 1.5
        update_render()
    end

    # Status Bar
    status_bar = fig[2, 1] = Label(fig, "Ready", tellwidth=false)
    onany(xmin, xmax, ymin, ymax, max_iter) do xi, xa, yi, ya, mi
        status_bar.text = "X: [$(round(xi, digits=4)), $(round(xa, digits=4))] Y: [$(round(yi, digits=4)), $(round(ya, digits=4))] Iter: $mi"
    end
    
    # Interactions: Zoom and Pan
    # Makie has built-in zoom and pan for Axis, but we need to re-render on changes.
    # We can listen to ax.limits.
    on(ax.finallimits) do limits
        # Only update if the limits actually changed significantly to avoid infinite loop
        # But here we will manually handle zoom/pan for better control
    end
    
    # Custom interaction: scroll to zoom at mouse position
    register_interaction!(ax, :zoom) do event::ScrollEvent, axis
        # Zoom factor
        zoom_factor = event.y > 0 ? 0.8 : 1.25
        
        # Get mouse position in data coordinates
        mp = Makie.mouseposition(axis.scene)
        
        # New range
        new_w = (xmax[] - xmin[]) * zoom_factor
        new_h = (ymax[] - ymin[]) * zoom_factor
        
        # Center zoom on mouse position
        # new_min = mp - (mp - old_min) * zoom_factor
        xmin[] = mp[1] - (mp[1] - xmin[]) * zoom_factor
        xmax[] = xmin[] + new_w
        ymin[] = mp[2] - (mp[2] - ymin[]) * zoom_factor
        ymax[] = ymin[] + new_h
        
        update_render()
        return Consume(true)
    end
    
    # Custom interaction: drag to pan
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
            
            # Need to update last_mouse_pos because the plane moved
            # Wait, if we move the plane, the mouseposition in data coordinates also changes.
            # So we should update it.
            # Actually, simpler to just re-render and keep dragging.
            update_render()
            last_mouse_pos[] = Makie.mouseposition(axis.scene)
            return Consume(true)
        end
        return Consume(false)
    end
    
    # Initial render
    update_render()
    
    # Observe changes in parameters
    onany(max_iter, is_julia, julia_c) do _, _, _
        update_render()
    end
    
    # Title update
    on(is_julia) do val
        ax.title = val ? "Julia Explorer" : "Mandelbrot Explorer"
    end
    
    display(fig)
end

end # module
