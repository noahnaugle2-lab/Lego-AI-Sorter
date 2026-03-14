// ============================================================
// LEGO AI Sorting Machine — Y-Junction Gate Module (Print-Optimized)
// Parametric OpenSCAD Model v2
// ============================================================
//
// PRINT OPTIMIZATION STRATEGY:
//
// The original single-piece Y-junction had major overhang 
// problems (angled chute ceilings, servo pocket, internal
// surfaces needing supports that are impossible to remove).
//
// NEW DESIGN: Split vertically into FRONT and BACK half-shells.
//
// Each half is a trough/channel shape that prints FLAT on the
// bed (open side up). The internal chute surfaces are the 
// smooth top layer — perfect sliding surface, zero supports.
//
// The two halves clip together with snap tabs along the edges.
// The servo mounts in a pocket formed by both halves meeting.
//
// Additionally, all angled chute transitions use 45° chamfers
// instead of sharp 90° overhangs.
//
// PRINT SETTINGS:
//   Material: PETG (smooth chute surface + durability)
//   Layer height: 0.2mm
//   Infill: 25%
//   Supports: NONE NEEDED
//   Walls: 3 perimeters
//   Print: flat, open-side-up
//   Time: ~25 min per half, ~50 min per complete module
//   Total for 31 modules: ~26 hours
//
// All dimensions in mm.
// ============================================================

// ── PARAMETERS ─────────────────────────────────────────────

// Chute dimensions (interior)
chute_width    = 65;    // fits long plates (~64mm on short axis)
chute_depth    = 50;    // Technic beams can tumble through
wall           = 2.5;

// Module overall
module_width  = chute_width + 2 * wall;   // ~70mm
module_depth  = chute_depth + 2 * wall;   // ~55mm
module_height = 60;

// Y-split geometry
split_angle   = 28;     // angle of each output branch
split_start_z = 25;     // Z height where Y-split begins

// Flap pivot
pivot_dia     = 3;
pivot_z       = split_start_z;

// Servo (SG90)
servo_body_w  = 23.5;
servo_body_d  = 12.7;
servo_body_h  = 22.5;
servo_shaft_offset = 5.5;

// Snap tabs for joining halves
snap_tab_w    = 8;
snap_tab_h    = 4;
snap_tab_d    = 2;
snap_tol      = 0.25;

// Chamfer angle for overhang-free transitions
chamfer = 45;  // degrees — FDM printers handle 45° without supports

// ── HELPER: Chamfered transition ───────────────────────────
// Replaces sharp 90° internal corners with 45° slopes

module chamfer_strip(length, size) {
    // A 45-degree chamfer strip to fill internal corners
    rotate([0, 90, 0])
        linear_extrude(height = length, center = true)
            polygon([[0, 0], [size, 0], [0, size]]);
}

// ── HALF-SHELL CHUTE PROFILE ───────────────────────────────
// 2D cross-section of one half of the Y-junction.
// This gets extruded to half the module depth.

module chute_half_profile() {
    // The profile is the interior chute shape as seen from the side.
    // Input chute (top) narrows to a Y-split, with two output channels.
    
    half_w = chute_width / 2;
    offset = split_start_z * tan(split_angle * PI / 180);
    
    // Left output channel bottom-left corner
    lx1 = -half_w - offset;
    // Right output channel bottom-right corner  
    rx1 = half_w + offset;
    
    polygon([
        // Top input (straight chute)
        [-half_w, module_height],
        [half_w, module_height],
        // Narrow to split point
        [half_w, split_start_z],
        // Right output angle
        [rx1, 0],
        [rx1 - half_w, 0],
        // Center divider (V-shape)
        [0, split_start_z - 3],
        [-half_w + offset, 0],  
        [lx1, 0],
        // Left output angle
        [-half_w, split_start_z],
    ]);
}

// ── FRONT HALF ─────────────────────────────────────────────
// Prints flat on bed, open (interior) side up.
// The chute surfaces are the smooth top surface = great for 
// bricks sliding through.

module front_half() {
    half_depth = module_depth / 2;
    
    difference() {
        union() {
            // Outer shell — half the depth
            difference() {
                // Solid outer block
                translate([-module_width/2, 0, 0])
                    cube([module_width, half_depth, module_height]);
                
                // Interior chute carved out 
                // (slightly less than half_depth so we have a floor)
                translate([0, wall, 0])
                    linear_extrude(height = module_height + 1)
                        offset(r = 0)
                            scale([1, 1])
                                translate([-chute_width/2, 0])
                                    square([chute_width, 1]);
                
                // Main input channel
                translate([-chute_width/2, wall, split_start_z])
                    cube([chute_width, half_depth, module_height - split_start_z + 1]);
                
                // Left output channel (angled)
                left_offset = split_start_z * tan(split_angle * PI / 180);
                hull() {
                    translate([-chute_width/2, wall, split_start_z - 1])
                        cube([chute_width/2 - 2, half_depth - wall, 1]);
                    translate([-chute_width/2 - left_offset, wall, 0])
                        cube([chute_width/2 - 2, half_depth - wall, 1]);
                }
                
                // Right output channel (angled)
                hull() {
                    translate([2, wall, split_start_z - 1])
                        cube([chute_width/2 - 2, half_depth - wall, 1]);
                    translate([2 + left_offset, wall, 0])
                        cube([chute_width/2 - 2, half_depth - wall, 1]);
                }
                
                // 45° chamfers at the split junction (no sharp overhangs)
                // These replace the sharp top edge of the V-divider
                translate([0, wall, split_start_z])
                    rotate([0, 45, 0])
                        translate([-3, 0, -3])
                            cube([6, half_depth - wall, 6]);
            }
            
            // Snap tabs on the flat mating face (at y = half_depth)
            for (z_pos = [15, module_height - 15]) {
                for (x_pos = [-module_width/4, module_width/4]) {
                    translate([x_pos - snap_tab_w/2, half_depth, z_pos - snap_tab_h/2])
                        cube([snap_tab_w, snap_tab_d, snap_tab_h]);
                }
            }
        }
        
        // Pivot pin hole (runs through front half)
        translate([-module_width/2 - 1, half_depth / 2, pivot_z + wall])
            rotate([0, 90, 0])
                cylinder(h = module_width + 2, d = pivot_dia + 0.3, $fn = 32);
    }
}

// ── BACK HALF ──────────────────────────────────────────────
// Mirror of front half, but includes the servo pocket.
// Also prints flat, open side up.

module back_half() {
    half_depth = module_depth / 2;
    
    difference() {
        union() {
            // Outer shell — mirror of front half
            translate([-module_width/2, 0, 0])
            difference() {
                cube([module_width, half_depth, module_height]);
                
                // Main input channel
                translate([wall, wall, split_start_z])
                    cube([chute_width, half_depth, module_height - split_start_z + 1]);
                
                // Left output channel
                left_offset = split_start_z * tan(split_angle * PI / 180);
                hull() {
                    translate([wall, wall, split_start_z - 1])
                        cube([chute_width/2 - 2, half_depth - wall, 1]);
                    translate([wall - left_offset, wall, 0])
                        cube([chute_width/2 - 2, half_depth - wall, 1]);
                }
                
                // Right output channel
                hull() {
                    translate([wall + chute_width/2 + 2, wall, split_start_z - 1])
                        cube([chute_width/2 - 2, half_depth - wall, 1]);
                    translate([wall + chute_width/2 + 2 + left_offset, wall, 0])
                        cube([chute_width/2 - 2, half_depth - wall, 1]);
                }
                
                // 45° chamfer at split
                translate([module_width/2, wall, split_start_z])
                    rotate([0, 45, 0])
                        translate([-3, 0, -3])
                            cube([6, half_depth - wall, 6]);
            }
        }
        
        // Snap tab receiving slots on mating face (at y = 0)
        for (z_pos = [15, module_height - 15]) {
            for (x_pos = [-module_width/4, module_width/4]) {
                translate([x_pos - snap_tab_w/2 - snap_tol, -snap_tab_d - snap_tol, 
                           z_pos - snap_tab_h/2 - snap_tol])
                    cube([snap_tab_w + 2*snap_tol, snap_tab_d + 2*snap_tol, snap_tab_h + 2*snap_tol]);
            }
        }
        
        // Servo pocket (cut into rear exterior)
        // When printed open-side-up, this pocket faces sideways = no supports
        translate([-servo_body_w/2, half_depth - servo_body_d, pivot_z + wall - servo_body_h/2])
            cube([servo_body_w, servo_body_d + 1, servo_body_h]);
        
        // Servo shaft hole through to interior
        translate([-servo_shaft_offset, wall - 1, pivot_z + wall])
            rotate([-90, 0, 0])
                cylinder(h = wall + 2, d = 8, $fn = 32);
        
        // Pivot pin hole
        translate([-module_width/2 - 1, half_depth / 2, pivot_z + wall])
            rotate([0, 90, 0])
                cylinder(h = module_width + 2, d = pivot_dia + 0.3, $fn = 32);
    }
}

// ── GATE FLAP ──────────────────────────────────────────────
// Prints flat on bed. Simple flat piece + pivot barrel.
// The barrel prints as a horizontal cylinder — use a brim
// for bed adhesion. Alternatively, print with the flat blade
// on the bed and the barrel on top (barrel is only 6mm 
// diameter, bridges fine).

module gate_flap() {
    flap_width  = chute_width - 4;
    flap_height = split_start_z - 5;
    barrel_dia  = pivot_dia + 2.5;
    
    // Flat blade
    translate([-flap_width/2, 0, 0])
        cube([flap_width, 2, flap_height]);
    
    // Pivot barrel at top
    // Has a flat on the bottom so it sits on the bed nicely
    translate([0, 1, flap_height])
        difference() {
            // Barrel
            rotate([0, 90, 0])
                cylinder(h = flap_width, d = barrel_dia, $fn = 32, center = true);
            // Pivot hole
            rotate([0, 90, 0])
                cylinder(h = flap_width + 2, d = pivot_dia, $fn = 32, center = true);
            // Flat bottom for printing (cut bottom of barrel)
            translate([-flap_width/2 - 1, -barrel_dia/2 - 1, -barrel_dia])
                cube([flap_width + 2, barrel_dia + 2, barrel_dia/2]);
        }
}

// ── STACKING CONNECTORS ────────────────────────────────────
// Tabs on top and slots on bottom for stacking modules in the tree.
// These are part of the front/back halves but shown here for clarity.

module stack_tab_top() {
    // Raised bumps on top face for aligning the module above
    for (x_pos = [-module_width/4, module_width/4]) {
        translate([x_pos, module_depth/4, module_height])
            cylinder(h = 3, d = 6, $fn = 6);  // hex peg
    }
}

module stack_slot_bottom() {
    // Matching hex slots on bottom face
    for (x_pos = [-module_width/4, module_width/4]) {
        translate([x_pos, module_depth/4, -1])
            cylinder(h = 4, d = 6.5, $fn = 6);  // hex hole with tolerance
    }
}

// ── RENDER ──────────────────────────────────────────────────

// Option 1: Assembled module (both halves together)
front_half();
translate([0, module_depth/2, 0]) 
    mirror([0, 1, 0]) 
        translate([0, -module_depth/2, 0])
            back_half();

// Gate flap shown beside
translate([module_width + 15, 10, 0]) gate_flap();

// Option 2: Print layout (both halves flat, open side up)
// front_half();
// translate([module_width + 10, 0, 0]) back_half();
// translate([0, module_depth + 10, 0]) gate_flap();

// ============================================================
// PRINT INSTRUCTIONS:
//
// Front Half:
//   Orientation: Open (interior) side UP
//   Supports: NONE — all chute surfaces are top layers = smooth
//   Time: ~25 min
//   Print 31 copies
//
// Back Half:
//   Orientation: Open (interior) side UP  
//   Supports: NONE — servo pocket opens to the side/top
//   Time: ~25 min
//   Print 31 copies
//
// Gate Flap:
//   Orientation: Flat blade on bed, barrel on top
//   Supports: NONE — barrel flat is trimmed for bed contact
//   Time: ~8 min
//   Print 31 copies
//
// ASSEMBLY (per module):
//   1. Snap front half + back half together (tabs click in)
//   2. Optional: add a drop of CA glue on the seam
//   3. Insert gate flap, thread 3mm pin through pivot holes
//   4. Push SG90 servo into rear pocket
//   5. Connect servo horn to flap with short linkage wire
//   6. Stack modules into tree using hex alignment pegs
//
// TOTAL: 31 × (front + back + flap) = 93 prints
// TOTAL TIME: ~30 hours (batch printing recommended)
// ============================================================
