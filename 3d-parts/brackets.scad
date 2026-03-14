// ============================================================
// LEGO AI Sorting Machine — Brackets (Print-Optimized)
// Parametric OpenSCAD Model v2
// ============================================================
//
// PRINT OPTIMIZATION STRATEGY:
// All brackets redesigned to print flat on the bed with zero
// supports. Key changes:
//
//   - Corner bracket: prints flat on one arm, gusset uses 
//     45° angle (no supports needed)
//   - Belt roller mount: bearing seat redesigned as a clamp
//     that prints flat, then folds over the bearing
//   - NEMA 17 mount: prints flat on the base plate, motor
//     plate is perpendicular but only 5mm thick (no overhang)
//   - Gate tree bracket: prints flat on shelf, arm is vertical
//     (just a tall thin wall = no overhang)
//
// Material: PETG for all brackets (strength + slight flex)
// Supports: NONE NEEDED for any bracket
// All dimensions in mm.
// ============================================================

// ── PARAMETERS ─────────────────────────────────────────────

extrusion_size = 20;
m5_hole        = 5.5;
m3_hole        = 3.4;
bracket_t      = 5;

// 608 bearing
bearing_od     = 22;
bearing_id     = 8;
bearing_width  = 7;

// NEMA 17
nema_face          = 42.3;
nema_hole_spacing  = 31;
nema_pilot_dia     = 22;
nema_screw         = 3.4;

// ── 1. CORNER BRACKET (Print-Optimized) ───────────────────
// Prints flat on Arm 1. Arm 2 extends upward.
// The gusset is now a 45° triangle — exactly the angle that
// FDM printers handle without supports.
// The outside surface of the gusset is a smooth 45° slope.

module corner_bracket_90() {
    arm_length = 40;
    arm_width  = 20;
    gusset_size = 18;  // size of the 45° triangular gusset
    
    difference() {
        union() {
            // Arm 1 (flat on bed)
            cube([arm_length, arm_width, bracket_t]);
            
            // Arm 2 (vertical — just a tall thin wall, no overhang)
            cube([bracket_t, arm_width, arm_length]);
            
            // 45° gusset — prints as a ramp, no supports needed
            // This is a solid triangle in the XZ plane
            translate([0, 0, 0])
                linear_extrude(height = arm_width)
                    // Swap to extrude in Y direction
                    polygon([]);
            
            // Actually, build gusset as a hull between two thin shapes:
            hull() {
                // Bottom of gusset (along arm 1)
                translate([bracket_t, 0, bracket_t])
                    cube([gusset_size, arm_width, 0.1]);
                // Top of gusset (along arm 2)
                translate([bracket_t, 0, bracket_t])
                    cube([0.1, arm_width, gusset_size]);
            }
        }
        
        // M5 hole in Arm 1
        translate([arm_length * 0.6, arm_width/2, -1])
            cylinder(h = bracket_t + 2, d = m5_hole, $fn = 32);
        
        // M5 hole in Arm 2 (horizontal)
        translate([-1, arm_width/2, arm_length * 0.6])
            rotate([0, 90, 0])
                cylinder(h = bracket_t + 2, d = m5_hole, $fn = 32);
    }
}

// ── 2. BELT ROLLER MOUNT (Print-Optimized) ────────────────
// Completely redesigned as a two-piece clamp:
//   - BASE prints flat: has two uprights with a U-channel
//     at the top (open upward = no overhang)
//   - CAP prints flat: a small bridge piece that bolts across
//     the top of the U-channel to capture the bearing
//
// The bearing drops into the U-channel, then the cap bolts on.
// Everything prints flat, no supports.

module belt_roller_base() {
    base_w = 44;
    base_d = 25;
    pillar_h = 30;
    u_channel_width = bearing_od + 1;  // bearing OD + tolerance
    pillar_spacing = u_channel_width + 2 * 4;  // pillars on each side
    
    difference() {
        union() {
            // Base plate
            cube([base_w, base_d, bracket_t]);
            
            // Left pillar (simple tall wall = no overhang)
            translate([base_w/2 - pillar_spacing/2 - 4, base_d/2 - bracket_t, bracket_t])
                cube([4, bracket_t * 2, pillar_h]);
            
            // Right pillar
            translate([base_w/2 + pillar_spacing/2, base_d/2 - bracket_t, bracket_t])
                cube([4, bracket_t * 2, pillar_h]);
        }
        
        // M5 mounting holes in base
        translate([base_w * 0.25, base_d/2, -1])
            cylinder(h = bracket_t + 2, d = m5_hole, $fn = 32);
        translate([base_w * 0.75, base_d/2, -1])
            cylinder(h = bracket_t + 2, d = m5_hole, $fn = 32);
        
        // Axle hole through both pillars
        translate([-1, base_d/2, bracket_t + pillar_h - bearing_od/2 - 2])
            rotate([0, 90, 0])
                cylinder(h = base_w + 2, d = bearing_id + 0.5, $fn = 32);
        
        // M3 holes in pillar tops for cap bolts
        for (side = [-1, 1]) {
            translate([base_w/2 + side * (pillar_spacing/2 + 2), 
                       base_d/2, 
                       bracket_t + pillar_h - 1])
                cylinder(h = 2, d = m3_hole, $fn = 32);
        }
    }
}

module belt_roller_cap() {
    // Small bridge piece that bolts across the pillar tops
    // Prints flat — it's just a small rectangle with holes
    cap_w = bearing_od + 16;
    cap_d = bracket_t * 2;
    cap_h = 4;
    
    difference() {
        cube([cap_w, cap_d, cap_h]);
        
        // Bearing clearance arc (just a shallow groove so it sits flush)
        translate([cap_w/2, cap_d/2, -1])
            cylinder(h = cap_h + 2, d = bearing_od + 1, $fn = 64);
        
        // Axle hole
        translate([cap_w/2, cap_d/2, -1])
            cylinder(h = cap_h + 2, d = bearing_id + 0.5, $fn = 32);
        
        // M3 bolt holes (match pillar tops)
        for (side = [-1, 1]) {
            translate([cap_w/2 + side * (bearing_od/2 + 6), cap_d/2, -1])
                cylinder(h = cap_h + 2, d = m3_hole, $fn = 32);
        }
    }
}

// ── 3. NEMA 17 MOTOR MOUNT (Print-Optimized) ──────────────
// Prints flat on the base plate.
// The motor face plate is vertical — but it's only 5mm thick
// and solid, so it's just a thin tall wall (no overhang).
// Gussets use 45° angles — no supports needed.

module nema17_mount() {
    plate_w = nema_face + 10;
    plate_h = nema_face + 10;
    base_depth = 30;
    gusset_size = 20;
    
    difference() {
        union() {
            // Base plate (on bed)
            cube([plate_w, base_depth, bracket_t]);
            
            // Motor face plate (vertical thin wall = no overhang)
            cube([plate_w, bracket_t, plate_h]);
            
            // 45° gussets on both sides (print as ramps, no supports)
            for (x = [4, plate_w - 4 - bracket_t]) {
                translate([x, bracket_t, bracket_t])
                    hull() {
                        cube([bracket_t, 0.1, gusset_size]);  // top
                        cube([bracket_t, gusset_size, 0.1]);  // bottom
                    }
            }
        }
        
        // NEMA 17 center pilot hole
        translate([plate_w/2, -1, plate_h/2])
            rotate([-90, 0, 0])
                cylinder(h = bracket_t + 2, d = nema_pilot_dia + 1, $fn = 64);
        
        // NEMA 17 mounting holes (4× M3)
        for (dx = [-1, 1], dz = [-1, 1]) {
            translate([plate_w/2 + dx * nema_hole_spacing/2,
                       -1,
                       plate_h/2 + dz * nema_hole_spacing/2])
                rotate([-90, 0, 0])
                    cylinder(h = bracket_t + 2, d = nema_screw, $fn = 32);
        }
        
        // M5 base mounting holes
        translate([plate_w * 0.25, base_depth * 0.6, -1])
            cylinder(h = bracket_t + 2, d = m5_hole, $fn = 32);
        translate([plate_w * 0.75, base_depth * 0.6, -1])
            cylinder(h = bracket_t + 2, d = m5_hole, $fn = 32);
    }
}

// ── 4. GATE TREE BRACKET (Print-Optimized) ────────────────
// Prints flat on the shelf surface.
// The vertical arm is just a thin wall = no overhang.
// The gusset is 45° = no supports.

module gate_tree_bracket() {
    shelf_w = 35;
    shelf_d = 45;
    arm_h   = 40;
    gusset_size = 15;
    
    difference() {
        union() {
            // Shelf (flat on bed)
            cube([shelf_w, shelf_d, bracket_t]);
            
            // Vertical arm (thin wall, no overhang)
            cube([shelf_w, bracket_t, arm_h]);
            
            // 45° gusset
            translate([0, bracket_t, bracket_t])
                hull() {
                    cube([shelf_w, 0.1, gusset_size]);
                    cube([shelf_w, gusset_size, 0.1]);
                }
        }
        
        // M5 holes in vertical arm (for extrusion T-nuts)
        translate([shelf_w/2, -1, arm_h * 0.4])
            rotate([-90, 0, 0])
                cylinder(h = bracket_t + 2, d = m5_hole, $fn = 32);
        translate([shelf_w/2, -1, arm_h * 0.75])
            rotate([-90, 0, 0])
                cylinder(h = bracket_t + 2, d = m5_hole, $fn = 32);
        
        // M3 holes in shelf (for bolting gate modules)
        translate([shelf_w * 0.3, shelf_d * 0.5, -1])
            cylinder(h = bracket_t + 2, d = m3_hole, $fn = 32);
        translate([shelf_w * 0.7, shelf_d * 0.5, -1])
            cylinder(h = bracket_t + 2, d = m3_hole, $fn = 32);
    }
}

// ── 5. DIAGONAL BRACE BRACKET (Print-Optimized) ────────────
// Connects two 2020 extrusion pieces at 45° for frame diagonal bracing.
// Prints flat on the larger vertical flange with no supports needed.
//
// Two mounting flanges:
//   - Vertical flange: mounts flat to a vertical upright (2 x M5 holes)
//   - Angled flange: mounts to diagonal extrusion at 45° (2 x M5 holes)
// Triangular gusset connects flanges for rigidity.

module diagonal_brace_bracket() {
    flange_w = 40;      // width of mounting flange (fits 2020 extrusion)
    flange_t = bracket_t;
    hole_spacing = 20;  // T-slot pitch
    hole_offset = 10;   // center hole position along length
    gusset_h = 35;      // height of gusset for structural support
    gusset_t = bracket_t;

    difference() {
        union() {
            // Vertical flange (prints flat on bed)
            cube([flange_w, flange_w, flange_t]);

            // Angled flange at 45°
            // This flange is rotated 45° around the edge where it meets vertical flange
            translate([0, flange_w, 0])
                rotate([45, 0, 0])
                    cube([flange_w, flange_w, flange_t]);

            // Triangular gusset for rigidity
            // Connects the two flanges at the edge with smooth 45° surfaces (no supports)
            hull() {
                // Along the edge of vertical flange
                translate([0, 0, flange_t])
                    cube([flange_w, gusset_t, 0.1]);
                // Peak of the gusset, aligned with the 45° direction
                translate([0, flange_w, flange_t + gusset_h * sin(45)])
                    cube([flange_w, 0.1, 0.1]);
            }
        }

        // M5 holes in vertical flange (for T-nuts on vertical upright)
        // Two holes spaced at T-slot pitch (20mm)
        translate([flange_w/2 - hole_spacing/2, hole_offset, -1])
            cylinder(h = flange_t + 2, d = m5_hole, $fn = 32);
        translate([flange_w/2 + hole_spacing/2, hole_offset, -1])
            cylinder(h = flange_t + 2, d = m5_hole, $fn = 32);

        // M5 holes in angled flange (for T-nuts on diagonal extrusion)
        // Transform hole positions to angled flange coordinate space
        translate([flange_w/2 - hole_spacing/2, flange_w, flange_t])
            rotate([45, 0, 0])
                translate([0, 0, hole_offset - flange_t])
                    cylinder(h = flange_t + 2, d = m5_hole, $fn = 32);
        translate([flange_w/2 + hole_spacing/2, flange_w, flange_t])
            rotate([45, 0, 0])
                translate([0, 0, hole_offset - flange_t])
                    cylinder(h = flange_t + 2, d = m5_hole, $fn = 32);
    }
}

// ── RENDER ──────────────────────────────────────────────────

// All brackets shown in print orientation (flat on bed)
corner_bracket_90();

translate([55, 0, 0]) belt_roller_base();
translate([55, 35, 0]) belt_roller_cap();

translate([115, 0, 0]) nema17_mount();

translate([0, 55, 0]) gate_tree_bracket();

translate([115, 55, 0]) diagonal_brace_bracket();

// ============================================================
// EXPORT & PRINT INSTRUCTIONS:
//
// 1. corner_bracket_90()   → corner_bracket.stl
//    Qty: 16 | Supports: NONE | Time: ~12 min each
//    Orientation: Arm 1 flat on bed
//
// 2. belt_roller_base()    → roller_base.stl
//    Qty: 4  | Supports: NONE | Time: ~18 min each
//    Orientation: Base plate on bed
//
// 3. belt_roller_cap()     → roller_cap.stl  
//    Qty: 4  | Supports: NONE | Time: ~5 min each
//    Orientation: Flat face on bed
//
// 4. nema17_mount()        → motor_mount.stl
//    Qty: 1  | Supports: NONE | Time: ~25 min
//    Orientation: Base plate on bed
//
// 5. gate_tree_bracket()   → tree_bracket.stl
//    Qty: 12 | Supports: NONE | Time: ~15 min each
//    Orientation: Shelf on bed
//
// 6. diagonal_brace_bracket() → diagonal_brace.stl
//    Qty: 2  | Supports: NONE | Time: ~20 min each
//    Orientation: Vertical flange flat on bed, angled flange at 45°
//    Purpose: Back frame diagonal bracing (corner-to-corner)
//    Notes: 45° angle is exact; gusset prints as smooth ramp
//
// ALL BRACKETS: PETG, 0.2mm, 30% infill, 3 walls, NO SUPPORTS
// ============================================================
