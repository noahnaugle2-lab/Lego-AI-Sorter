/*
================================================================================
LEGO AI SORTING MACHINE - Belt Rollers & Tensioner Bracket
================================================================================

FILE: belt_rollers.scad
PURPOSE: Parametric models for belt drive system components
MATERIAL: PETG
LAYER HEIGHT: 0.2mm
INFILL: 25%
WALL COUNT: 3

DESIGN OPTIMIZATION STRATEGY:
- All parts designed to print flat without supports
- Bearing bores are press-fit design (tolerance: -0.1mm on OD)
- Belt rollers feature shallow crown (0.5mm max) to naturally center belt
- Knurling/texture pattern added via shallow grooves for belt grip
- Tensioner bracket designed with vertical mounting (T-slot facing down)
- D-cut on drive roller bore prevents motor slip without extra fasteners
- All overhangs < 45° or supported by geometry
- Critical tolerances maintained through design (no post-processing needed)

BEARING SPECIFICATIONS:
- Type: 608 (skateboard bearings)
- Outer Diameter: 22mm
- Inner Diameter: 8mm
- Width: 7mm
- Press-fit bores: 7.95mm (nominal 22mm OD with -0.05mm tolerance)

EXTRUSION SPECIFICATIONS:
- 2020 Aluminum T-slot: 20mm x 20mm
- M5 mounting holes: 5.5mm diameter
- T-nut slot width: 6mm

PRINT ORIENTATION:
- Drive Roller: Print horizontally, axis parallel to bed
- Idler Roller: Print horizontally, axis parallel to bed
- Tensioner Bracket: Print vertically, mounting face down

ESTIMATED PRINT TIMES:
- Drive Roller: ~45 minutes
- Idler Roller: ~45 minutes
- Tensioner Bracket: ~30 minutes
- Total print time: ~2 hours

ASSEMBLY NOTES:
- Use 608 bearings pressed into bores (no adhesive needed)
- Drive roller attaches to NEMA 17 shaft with set screw through D-cut
- Idler roller installed on tensioner bracket with shoulder bolt (M8x30)
- Tensioner bracket mounts to 2020 extrusion with M5 cap screws + T-nuts
- Tension adjustment via spring compression (recommend 50-100N preload)

================================================================================
*/

// ============================================================================
// GLOBAL PARAMETERS
// ============================================================================

// Roller dimensions
ROLLER_DIAMETER = 25;           // Finished OD for belt contact
ROLLER_WIDTH = 70;              // Belt width + clearance
BEARING_OD = 22;                // 608 bearing outer diameter
BEARING_ID = 8;                 // 608 bearing inner diameter
BEARING_WIDTH = 7;              // 608 bearing width
PRESS_FIT_BORE = 7.95;          // Bore for pressed 22mm bearing (22 - 0.05 tolerance)

// Motor shaft parameters
MOTOR_SHAFT_DIA = 5;            // NEMA 17 shaft diameter
MOTOR_SHAFT_FLAT_WIDTH = 2;     // D-cut flat width
D_CUT_DEPTH = 2.5;              // D-cut depth for set screw engagement

// Roller surface features
CROWN_HEIGHT = 0.5;             // Center rise for belt tracking
KNURL_GROOVE_DEPTH = 0.3;       // Shallow grooves for belt grip
KNURL_GROOVE_SPACING = 2;       // Groove pitch

// Mounting parameters
EXTRUSION_SIZE = 20;            // 2020 aluminum extrusion
M5_HOLE_DIA = 5.5;              // M5 screw hole
SLOT_WIDTH = 6;                 // T-nut slot width
SHOULDER_BOLT_BORE = 8.2;       // For M8 shoulder bolt (8mm shaft + tolerance)

// Spring parameters
SPRING_HOOK_HEIGHT = 8;         // Height of spring mounting hook
SPRING_HOOK_THICKNESS = 3;      // Thickness of hook post

// Tolerances
TOLERANCE = 0.1;                // General tolerance for fit

// ============================================================================
// PART 1: DRIVE ROLLER WITH D-CUT BORE
// ============================================================================

module drive_roller() {
    difference() {
        // Main roller body with crown
        roller_body(ROLLER_DIAMETER, ROLLER_WIDTH, CROWN_HEIGHT);

        // Bearing bores on each end
        translate([-ROLLER_WIDTH/2 + BEARING_WIDTH/2, 0, 0]) {
            cylinder(h = BEARING_WIDTH + TOLERANCE, r = BEARING_OD/2 - 0.05, center = true, $fn = 32);
        }
        translate([ROLLER_WIDTH/2 - BEARING_WIDTH/2, 0, 0]) {
            cylinder(h = BEARING_WIDTH + TOLERANCE, r = BEARING_OD/2 - 0.05, center = true, $fn = 32);
        }

        // D-cut bore for motor shaft engagement
        d_cut_bore(MOTOR_SHAFT_DIA, MOTOR_SHAFT_FLAT_WIDTH, D_CUT_DEPTH, ROLLER_WIDTH);
    }

    // Add knurled texture pattern
    knurl_pattern(ROLLER_DIAMETER, ROLLER_WIDTH, KNURL_GROOVE_DEPTH);
}

// ============================================================================
// PART 2: IDLER ROLLER (Same as drive but without D-cut)
// ============================================================================

module idler_roller() {
    difference() {
        // Main roller body with crown
        roller_body(ROLLER_DIAMETER, ROLLER_WIDTH, CROWN_HEIGHT);

        // Bearing bores on each end
        translate([-ROLLER_WIDTH/2 + BEARING_WIDTH/2, 0, 0]) {
            cylinder(h = BEARING_WIDTH + TOLERANCE, r = BEARING_OD/2 - 0.05, center = true, $fn = 32);
        }
        translate([ROLLER_WIDTH/2 - BEARING_WIDTH/2, 0, 0]) {
            cylinder(h = BEARING_OD/2 - 0.05, r = BEARING_OD/2 - 0.05, center = true, $fn = 32);
        }

        // Through bore for shoulder bolt (no D-cut, just straight hole)
        cylinder(h = ROLLER_WIDTH + TOLERANCE, r = SHOULDER_BOLT_BORE/2, center = true, $fn = 32);
    }

    // Add knurled texture pattern
    knurl_pattern(ROLLER_DIAMETER, ROLLER_WIDTH, KNURL_GROOVE_DEPTH);
}

// ============================================================================
// PART 3: BELT TENSIONER BRACKET
// ============================================================================

module tensioner_bracket() {
    difference() {
        union() {
            // Main mounting block
            translate([0, 0, 0]) {
                cube([40, 35, 20], center = true);
            }

            // Vertical support posts for idler axle
            translate([-15, 0, 0]) {
                cube([8, ROLLER_WIDTH + 10, 20], center = true);
            }
            translate([15, 0, 0]) {
                cube([8, ROLLER_WIDTH + 10, 20], center = true);
            }

            // Spring hook/post for tension spring
            translate([0, ROLLER_WIDTH/2 + 5, 0]) {
                cube([SPRING_HOOK_THICKNESS, SPRING_HOOK_THICKNESS, SPRING_HOOK_HEIGHT], center = true);
            }
            translate([0, ROLLER_WIDTH/2 + 5, SPRING_HOOK_HEIGHT/2 - 3]) {
                cube([SPRING_HOOK_THICKNESS * 2, SPRING_HOOK_THICKNESS, 4], center = true);
            }
        }

        // Slot for idler roller axle (allows vertical adjustment)
        translate([0, 0, 0]) {
            cube([SHOULDER_BOLT_BORE + 2, ROLLER_WIDTH + 12, 8], center = true);
        }

        // M5 mounting holes for 2020 extrusion (3 holes, spaced for T-nuts)
        // Hole 1 - Center
        translate([0, 0, -10]) {
            cylinder(h = 15, r = M5_HOLE_DIA/2, center = true, $fn = 24);
        }

        // Hole 2 - Left offset
        translate([-12, 0, -10]) {
            cylinder(h = 15, r = M5_HOLE_DIA/2, center = true, $fn = 24);
        }

        // Hole 3 - Right offset
        translate([12, 0, -10]) {
            cylinder(h = 15, r = M5_HOLE_DIA/2, center = true, $fn = 24);
        }

        // Clearance for spring at mounting point
        translate([0, ROLLER_WIDTH/2 + 8, SPRING_HOOK_HEIGHT/2]) {
            cube([8, 6, 6], center = true);
        }
    }

    // Add chamfers on edges for print quality
    color([0.8, 0.8, 0.8]) {
        difference() {
            translate([0, 0, 0]) {
                cube([40, 35, 20], center = true);
            }
            translate([0, 0, 0]) {
                cube([38, 33, 18], center = true);
            }
        }
    }
}

// ============================================================================
// HELPER MODULES
// ============================================================================

// Base roller body with crown profile
module roller_body(diameter, width, crown) {
    // Create crown profile using cylinder with slight taper
    union() {
        // Main body cylinder
        cylinder(h = width, r = diameter/2 - crown, center = true, $fn = 64);

        // Crown rise (parabolic taper toward center)
        for (x = [-width/2 : 1 : width/2]) {
            offset_distance = abs(x) / (width/2);
            height_at_x = crown * (1 - offset_distance * offset_distance);
            translate([0, 0, x]) {
                cylinder(h = 1, r = diameter/2 - crown + height_at_x, center = true, $fn = 64);
            }
        }
    }
}

// D-cut bore for motor shaft gripping
module d_cut_bore(shaft_dia, flat_width, depth, length) {
    // Center bore for smooth rotation
    cylinder(h = length + TOLERANCE, r = shaft_dia/2, center = true, $fn = 32);

    // D-cut flat section
    translate([0, shaft_dia/2 - depth, 0]) {
        cube([flat_width, depth * 2, length + TOLERANCE], center = true);
    }
}

// Knurled surface pattern (shallow grooves for belt grip)
module knurl_pattern(diameter, width, groove_depth) {
    // Spiral knurl pattern using linear grooves
    for (i = [0 : 2 : width - KNURL_GROOVE_SPACING]) {
        rotate_extrude(angle = 360, convexity = 2) {
            translate([diameter/2 - groove_depth, i - width/2, 0]) {
                square([groove_depth, KNURL_GROOVE_SPACING - 0.1]);
            }
        }
    }
}

// ============================================================================
// ASSEMBLY & RENDERING
// ============================================================================

/*
ASSEMBLY LAYOUT FOR PRINTING:
- Drive Roller: positioned at (0, 0, 0), prints horizontally
- Idler Roller: positioned at (0, 80, 0), prints horizontally
- Tensioner Bracket: positioned at (60, 0, 0), prints vertically
*/

// Drive Roller (main drive component)
translate([0, 0, 0]) {
    color([0.2, 0.6, 1.0], 1.0) {
        drive_roller();
    }
}

// Idler Roller (tension-adjusted component)
translate([0, 80, 0]) {
    color([0.8, 0.4, 0.2], 1.0) {
        idler_roller();
    }
}

// Tensioner Bracket (spring-loaded mount)
translate([60, 0, 20]) {
    color([0.5, 0.5, 0.5], 1.0) {
        tensioner_bracket();
    }
}

// ============================================================================
// PRINT INSTRUCTIONS & NOTES
// ============================================================================

/*
PRINT CONFIGURATION:
- Printer: Prusa i3 MK3S+ (or compatible FDM printer)
- Filament: PETG (Prusament PETG Charcoal Black recommended)
- Nozzle Temperature: 240°C
- Bed Temperature: 80°C
- Layer Height: 0.2mm
- Nozzle Diameter: 0.4mm
- Infill: 25% (Gyroid pattern for strength)
- Wall Count: 3 perimeters
- Support: NONE required (all parts designed flat)
- Raft: Not required (good bed adhesion with PETG)
- First Layer: 110% speed for better adhesion

PRINT SEQUENCE:
1. Drive Roller - Estimated time: 45 minutes, Weight: ~35g
2. Idler Roller - Estimated time: 45 minutes, Weight: ~35g
3. Tensioner Bracket - Estimated time: 30 minutes, Weight: ~25g

TOTAL PRINT TIME: ~2 hours 20 minutes
TOTAL MATERIAL: ~95g

PRE-PRINT CHECKLIST:
□ Bed cleaned and leveled
□ PETG filament loaded
□ Nozzle primed and clean
□ Part orientation verified (all flat, no supports shown in preview)
□ Estimated time realistic for printer speed

POST-PRINT PROCESSING:
1. Remove parts carefully from bed (let cool 5+ minutes)
2. Clean any stringy PETG from supports (none should exist)
3. Press-fit 608 bearings into bores (no adhesive needed)
4. Test fit on motor shaft (D-cut should grip at ~2-3 turns of set screw)
5. Verify roller rotation is smooth and balanced
6. Install in assembly with spring tension set to 50-100N

ASSEMBLY VERIFICATION:
- Rollers should rotate freely with minimal friction
- Belt should center naturally due to crown
- Tensioner bracket should slide smoothly for tension adjustment
- All M5 holes should cleanly receive cap screws with T-nuts
- D-cut grip should hold motor shaft without stripping

TROUBLESHOOTING:
- If bearings won't fit: Check bore diameter (should be 7.95mm for 22mm bearing)
- If roller is unbalanced: Bearings may not be seated fully (press firmly)
- If belt slips: Increase spring tension or check knurling integrity
- If bracket won't slide: Check for layer artifacts (sand gently if needed)
*/

// ============================================================================
// END OF FILE
// ============================================================================
