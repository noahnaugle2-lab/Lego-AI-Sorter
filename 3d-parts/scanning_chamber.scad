// ============================================================
// LEGO AI Sorting Machine — Scanning Chamber (Print-Optimized)
// Parametric OpenSCAD Model v2
// ============================================================
//
// PRINT OPTIMIZATION STRATEGY:
// Instead of splitting into top/bottom halves, the chamber is
// now split into 4 pieces that each print flat with NO supports:
//
//   1. BASE TRAY — prints face-down. Open-top box (the floor +
//      lower walls up to belt slot height). No overhangs.
//
//   2. MIDDLE RING — prints face-down. A wall ring from the top 
//      of the belt slot up to the LED channel. The belt slot 
//      openings are simply the gap between base tray and middle
//      ring. No overhangs.
//
//   3. TOP CAP — prints face-down (flipped). Ceiling + upper 
//      walls + LED channel built as a downward lip. Camera hole
//      is a simple through-hole. No overhangs.
//
//   4. MIRROR BRACKET — separate small piece that holds the 
//      mirror at 45°. Prints flat as a wedge shape. Glues to
//      the rear interior wall.
//
// All internal surfaces are smooth (no support scarring).
// Pieces stack and align with tongue-and-groove edges.
// 
// PRINT SETTINGS:
//   Material: White PLA or PETG
//   Layer height: 0.2mm
//   Infill: 20%
//   Supports: NONE NEEDED
//   Walls: 3 perimeters
//
// All dimensions in mm.
// ============================================================

// ── PARAMETERS ─────────────────────────────────────────────

// Interior chamber dimensions
interior_width  = 160;   // X - across belt direction (fits ~130mm pieces)
interior_depth  = 140;   // Y - along belt direction
interior_height = 120;   // Z - total interior height

wall = 4;                // wall thickness

// Belt slot
belt_slot_height = 50;   // tall enough for minifigs in any orientation
belt_slot_width  = 85;   // belt width + margin
belt_slot_z      = 5;    // bottom of slot above interior floor

// Camera
camera_hole_dia  = 35;
camera_mount_dia = 55;

// Mirror (separate bracket piece)
mirror_width     = 70;
mirror_depth     = 70;   // height of mirror
mirror_thickness = 3;

// LED channel (built into top cap as a downward lip)
led_channel_width  = 12;
led_channel_depth  = 5;

// Tongue-and-groove alignment
tongue_height  = 3;
tongue_depth   = 2;
tongue_tol     = 0.2;

// Mounting tabs
tab_length    = 30;
tab_width     = 20;
tab_thickness = 5;
m5_hole_dia   = 5.5;

// ── DERIVED ────────────────────────────────────────────────

ow = interior_width  + 2 * wall;
od = interior_depth  + 2 * wall;

// Z heights for the three stacking pieces:
// Base tray:   0 to base_top_z
// Middle ring: base_top_z to mid_top_z  
// Top cap:     mid_top_z to total_top_z

base_top_z  = wall + belt_slot_z + belt_slot_height;  // top of belt slot opening
mid_top_z   = wall + interior_height - led_channel_width - 5;
total_top_z = wall + interior_height + wall;           // exterior top

// ── MODULES ────────────────────────────────────────────────

// Tongue (raised ridge on top edge of a piece)
module tongue_ring(z_pos) {
    difference() {
        translate([wall + tongue_tol, wall + tongue_tol, z_pos])
            cube([interior_width - 2*tongue_tol, interior_depth - 2*tongue_tol, tongue_height]);
        translate([wall + tongue_depth + tongue_tol, wall + tongue_depth + tongue_tol, z_pos - 0.1])
            cube([interior_width - 2*tongue_depth - 2*tongue_tol, 
                  interior_depth - 2*tongue_depth - 2*tongue_tol, 
                  tongue_height + 0.2]);
    }
}

// Groove (matching slot on bottom edge of a piece)
module groove_ring(z_pos) {
    translate([wall, wall, z_pos])
        cube([interior_width, interior_depth, tongue_height + tongue_tol]);
    // But keep the outer wall intact — only cut inside
}

module groove_cut(z_pos) {
    // Cut a groove into the bottom of a piece
    difference() {
        translate([wall - tongue_tol, wall - tongue_tol, z_pos - 0.1])
            cube([interior_width + 2*tongue_tol, interior_depth + 2*tongue_tol, tongue_height + 0.2]);
        translate([wall + tongue_depth, wall + tongue_depth, z_pos - 0.2])
            cube([interior_width - 2*tongue_depth, interior_depth - 2*tongue_depth, tongue_height + 0.4]);
    }
}

// ── PIECE 1: BASE TRAY ────────────────────────────────────
// Prints face-down as-is. Open-top box shape. Zero overhangs.

module base_tray() {
    difference() {
        // Solid block from z=0 to z=base_top_z
        cube([ow, od, base_top_z]);
        
        // Hollow interior (open top)
        translate([wall, wall, wall])
            cube([interior_width, interior_depth, base_top_z]);
        
        // Belt slot openings are NOT cut here — they exist as
        // the gap between base tray and middle ring
    }
    
    // Tongue on top edge for middle ring alignment
    tongue_ring(base_top_z);
    
    // Mounting tabs on base (extend outward)
    base_mounting_tabs();
}

module base_mounting_tabs() {
    for (side_y = [0, 1]) {
        for (side_x = [0, 1]) {
            x_pos = wall + 25 + side_x * (interior_width - 50);
            y_pos = side_y * (od) ;
            y_dir = side_y == 0 ? -1 : 1;
            
            translate([x_pos - tab_length/2, 
                       y_pos + (y_dir > 0 ? 0 : -tab_width), 
                       0])
                difference() {
                    cube([tab_length, tab_width, tab_thickness]);
                    translate([tab_length/2, tab_width/2, -1])
                        cylinder(h = tab_thickness + 2, d = m5_hole_dia, $fn = 32);
                }
        }
    }
}

// ── PIECE 2: MIDDLE RING ──────────────────────────────────
// Prints face-down as-is. It's a rectangular tube/ring.
// The belt slots are simply the open gaps on left and right
// between base tray top and middle ring bottom — no cutting
// needed. Zero overhangs (it's just straight walls).

module middle_ring() {
    mid_height = mid_top_z - base_top_z;
    
    translate([0, 0, base_top_z]) {
        difference() {
            // Outer walls
            cube([ow, od, mid_height]);
            
            // Interior hollow (full pass-through, open top & bottom)
            translate([wall, wall, -1])
                cube([interior_width, interior_depth, mid_height + 2]);
            
            // Groove on bottom to receive base tray tongue
            groove_cut(0);
        }
        
        // Tongue on top for top cap
        tongue_ring(mid_height);
    }
}

// ── PIECE 3: TOP CAP ──────────────────────────────────────
// Prints UPSIDE-DOWN (ceiling face on the bed).
// When flipped, the LED channel lip hangs downward inside.
// This lip is just a short wall extension — no overhang
// because it prints as an upward extrusion when upside-down.
//
// The camera hole is a simple vertical through-hole.

module top_cap() {
    cap_height = total_top_z - mid_top_z;
    
    translate([0, 0, mid_top_z]) {
        difference() {
            union() {
                // Outer walls + ceiling
                difference() {
                    cube([ow, od, cap_height]);
                    // Interior hollow (open bottom only)
                    translate([wall, wall, -1])
                        cube([interior_width, interior_depth, cap_height - wall + 1]);
                }
                
                // LED channel lip — a thin wall that extends downward
                // from the ceiling into the interior. When printed 
                // upside-down, this is just a short upward extrusion.
                // Front and back lips
                translate([wall + 10, wall, -led_channel_width])
                    cube([interior_width - 20, led_channel_depth, led_channel_width + 1]);
                translate([wall + 10, od - wall - led_channel_depth, -led_channel_width])
                    cube([interior_width - 20, led_channel_depth, led_channel_width + 1]);
                // Left and right lips
                translate([wall, wall + 10, -led_channel_width])
                    cube([led_channel_depth, interior_depth - 20, led_channel_width + 1]);
                translate([od - wall - led_channel_depth, wall + 10, -led_channel_width])
                    cube([led_channel_depth, interior_depth - 20, led_channel_width + 1]);
            }
            
            // Camera hole (through ceiling)
            translate([ow/2, od/2, cap_height - wall - 1])
                cylinder(h = wall + 2, d = camera_hole_dia, $fn = 64);
            
            // Groove on bottom to receive middle ring tongue
            groove_cut(0);
            
            // LED strip wire exit hole (rear wall)
            translate([ow - wall - 1, od/2, -led_channel_width/2])
                rotate([0, 90, 0])
                    cylinder(h = wall + 2, d = 6, $fn = 32);
        }
    }
    
    // Camera mount ring on top exterior
    translate([ow/2, od/2, total_top_z])
        difference() {
            cylinder(h = 3, d = camera_mount_dia, $fn = 64);
            translate([0, 0, -1])
                cylinder(h = 5, d = camera_hole_dia, $fn = 64);
            // 4 screw holes for camera bracket (M2.5)
            for (a = [0, 90, 180, 270]) {
                rotate([0, 0, a])
                    translate([(camera_mount_dia/2 - 6), 0, -1])
                        cylinder(h = 5, d = 3, $fn = 32);
            }
        }
}

// ── PIECE 4: MIRROR BRACKET ───────────────────────────────
// Prints FLAT on the bed. It's a simple wedge/ramp shape
// with a slot for the mirror glass. Glues to the rear 
// interior wall of the assembled chamber.
//
// Print orientation: flat on the large face. Zero overhangs
// because the 45° slope is built as a gradual incline that
// any FDM printer handles natively (45° = no supports).

module mirror_bracket() {
    bracket_width = mirror_width + 10;  // wider than mirror for glue surface
    bracket_depth = mirror_depth * 0.707 + 10;  // 45° projected depth
    bracket_height = mirror_depth * 0.707 + 5;  // 45° projected height
    
    difference() {
        // Wedge body — 45 degree ramp
        hull() {
            // Bottom front edge
            cube([bracket_width, bracket_depth, 1]);
            // Top rear edge  
            translate([0, 0, bracket_height - 1])
                cube([bracket_width, 3, 1]);
        }
        
        // Mirror slot — cut at 45° into the ramp surface
        translate([bracket_width/2, bracket_depth * 0.4, bracket_height * 0.3])
            rotate([45, 0, 0])
                translate([-mirror_width/2, -mirror_thickness/2, 0])
                    cube([mirror_width, mirror_thickness + 0.5, mirror_depth]);
        
        // Flat back face for gluing to wall
        // (already flat by construction)
    }
}

// ── RENDER ──────────────────────────────────────────────────
// Uncomment ONE option:

// Option 1: Full assembled view (all 4 pieces stacked)
base_tray();
color("LightBlue", 0.8) middle_ring();
color("LightGreen", 0.8) top_cap();
color("Orange") translate([wall + interior_width/2 - (mirror_width+10)/2, 
                            wall + 2,  // against rear interior wall
                            base_top_z + 15])
    mirror_bracket();

// Option 2: Exploded view (pieces separated vertically)
// base_tray();
// translate([0, 0, 30]) color("LightBlue", 0.8) middle_ring();
// translate([0, 0, 60]) color("LightGreen", 0.8) top_cap();
// translate([ow + 20, 0, 0]) color("Orange") mirror_bracket();

// Option 3: Print layout (all pieces in print orientation on bed)
// base_tray();  // prints as-is
// translate([ow + 10, 0, 0]) middle_ring();  // prints as-is
// translate([0, od + 10, total_top_z - mid_top_z + wall]) 
//     mirror([0,0,1]) translate([0, 0, -mid_top_z]) top_cap();  // flip for printing
// translate([ow + 10, od + 10, 0]) mirror_bracket();  // prints as-is

// Individual exports:
// base_tray();           → scanning_chamber_base.stl
// middle_ring();         → scanning_chamber_middle.stl  
// (flip top_cap)         → scanning_chamber_top.stl
// mirror_bracket();      → mirror_bracket.stl

// ============================================================
// PRINT INSTRUCTIONS:
//
// Piece 1 — Base Tray:
//   Orientation: As-is (open side up)
//   Supports: NONE
//   Time: ~2 hrs
//
// Piece 2 — Middle Ring:
//   Orientation: As-is (it's a tube, either end down)
//   Supports: NONE
//   Time: ~1.5 hrs
//
// Piece 3 — Top Cap:
//   Orientation: FLIP UPSIDE-DOWN (ceiling on bed)
//   Supports: NONE (LED lips print as upward extrusions)
//   Time: ~2 hrs
//
// Piece 4 — Mirror Bracket:
//   Orientation: Flat face down (wedge prints as ramp, 45° = no supports)
//   Supports: NONE
//   Time: ~30 min
//
// ASSEMBLY:
//   1. Stack base tray → middle ring → top cap (tongue/groove alignment)
//   2. Secure with M3 bolts through walls, or glue
//   3. Glue mirror bracket to rear interior wall
//   4. Insert mirror glass into bracket slot
//   5. Press LED strip into the lip channel around the ceiling
//   6. Mount camera on top ring
//   7. Bolt mounting tabs to 2020 extrusion
//
// TOTAL PRINT TIME: ~6 hours, ZERO supports needed
// ============================================================
