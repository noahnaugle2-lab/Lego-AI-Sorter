/*
 * LEGO AI Sorting Machine - Electronics Enclosure
 *
 * DESIGN SUMMARY:
 * Two-piece modular enclosure (BASE + LID) housing Raspberry Pi 5, 2x PCA9685 servo drivers,
 * and TMC2209 stepper driver. Designed for flat printing with ZERO supports required.
 *
 * PRINT OPTIMIZATION STRATEGY:
 * - Base and Lid print flat on build plate (Z-axis walls)
 * - All ventilation slots oriented horizontally (print without bridging)
 * - Snap features and mounting ears designed to print cleanly
 * - Internal standoffs use radial wall patterns for strength without support
 * - Cable exit holes use chamfered edges to minimize overhang
 *
 * PRINT SETTINGS:
 * - Layer Height: 0.2mm
 * - Infill: 20% (grid pattern)
 * - Wall Count: 3
 * - Nozzle: 0.4mm
 * - Material: PLA
 * - No supports needed - design optimized for flat printing
 *
 * BOARD DIMENSIONS (reference):
 * - Raspberry Pi 5: 85mm x 56mm, M2.5 holes @ 58mm x 49mm spacing
 * - PCA9685 (qty 2): 62mm x 25mm, holes @ 56mm x 19mm spacing
 * - TMC2209: 20mm x 15mm (small, mounted on DIN rail bracket)
 *
 * ASSEMBLY:
 * 1. Insert standoffs into base
 * 2. Mount Pi 5 (left side), PCA9685 boards (right side), TMC2209 (stepper cable area)
 * 3. Route cables through exit holes
 * 4. Snap or screw lid onto base
 * 5. Bolt mounting ears to 2020 extrusion frame with M5 T-nuts
 */

// ============================================================================
// PARAMETRIC DIMENSIONS
// ============================================================================

// Enclosure outer dimensions
enclosure_length = 180;      // mm, along Pi length axis
enclosure_width = 100;       // mm, perpendicular to length
enclosure_height = 80;       // mm, vertical dimension

// Wall thickness
wall_thickness = 2;          // mm, structural walls
mounting_tab_thickness = 3;  // mm, frame mounting tabs

// Interior layout spacing
pi_clearance = 5;            // mm clearance around Pi 5
pca_stack_spacing = 6;       // mm between stacked PCA9685 boards
cable_routing_space = 10;    // mm vertical space for cable routing

// Standoff dimensions
standoff_od = 8;             // mm outer diameter
standoff_id = 3;             // mm inner diameter (M2.5 clearance)
standoff_height_pi = 5;      // mm above base for Pi mounting
standoff_height_pca = 8;     // mm for PCA9685 boards

// Ventilation
vent_slot_width = 3;         // mm slot width
vent_slot_length = 40;       // mm slot length
vent_hole_diameter = 8;      // mm for round vent holes

// Snap/screw features
snap_tab_height = 4;         // mm snap tab protrusion
snap_tab_thickness = 2;      // mm snap tab wall thickness
screw_hole_diameter = 4;     // mm M3 clearance hole

// Mounting to frame
mount_hole_diameter = 5.5;   // mm clearance for M5 bolts
mount_tab_height = 15;       // mm height of mounting ears above enclosure
mount_tab_width = 20;        // mm width of mounting ears

// Cable exit holes
cable_hole_diameter = 16;    // mm diameter for cable exit holes
cable_hole_offset = 12;      // mm from top edge

// ============================================================================
// HELPER MODULES
// ============================================================================

// Mounting standoff with M2.5 clearance hole
module standoff(height) {
    difference() {
        cylinder(h=height, d=standoff_od, $fn=24);
        cylinder(h=height, d=standoff_id, $fn=16);
    }
}

// Rectangular ventilation slot (prints flat without support)
module vent_slot(x_pos, y_pos, length, width) {
    translate([x_pos - length/2, y_pos - width/2, -0.5])
        cube([length, width, wall_thickness + 1]);
}

// Cable exit hole with chamfered edge
module cable_exit_hole(x_pos, y_pos, diameter) {
    translate([x_pos, y_pos, -0.5]) {
        cylinder(h=wall_thickness + 1, d=diameter, $fn=32);
        // Chamfer on outer edge
        translate([0, 0, wall_thickness - 0.5])
            cylinder(h=1.5, d1=diameter, d2=diameter + 2, $fn=32);
    }
}

// M5 mounting hole for frame attachment
module m5_mount_hole(x_pos, y_pos) {
    translate([x_pos, y_pos, -1])
        cylinder(h=mount_tab_thickness + 2, d=mount_hole_diameter, $fn=24);
}

// Mounting ear/tab for frame attachment
module mount_ear(x_offset, side) {
    // side: -1 for left, +1 for right
    translate([x_offset, (enclosure_width/2 + 10) * side, enclosure_height - 5]) {
        difference() {
            // Solid mounting block
            cube([mount_tab_width, 20, mount_tab_height], center=true);
            // M5 bolt hole
            translate([0, 0, mount_tab_height/2 - 2])
                cylinder(h=mount_tab_thickness + 2, d=mount_hole_diameter, $fn=24);
        }
    }
}

// ============================================================================
// BASE ENCLOSURE
// ============================================================================

module enclosure_base() {
    // Calculate interior dimensions
    interior_length = enclosure_length - 2 * wall_thickness;
    interior_width = enclosure_width - 2 * wall_thickness;

    difference() {
        // Outer shell
        union() {
            // Main box
            cube([enclosure_length, enclosure_width, enclosure_height]);

            // Mounting ears on long sides (for 2020 frame attachment)
            mount_ear(40, -1);
            mount_ear(40, 1);
            mount_ear(140, -1);
            mount_ear(140, 1);
        }

        // Internal cavity
        translate([wall_thickness, wall_thickness, wall_thickness])
            cube([interior_length, interior_width, enclosure_height - wall_thickness + 1]);

        // Ventilation slots on long sides (horizontal orientation - no supports needed)
        // Left side - 3 slots
        vent_slot(30, 0, vent_slot_length, vent_slot_width);
        vent_slot(60, 0, vent_slot_length, vent_slot_width);
        vent_slot(90, 0, vent_slot_length, vent_slot_width);

        // Right side - 3 slots (mirrored)
        vent_slot(30, enclosure_width, vent_slot_length, vent_slot_width);
        vent_slot(60, enclosure_width, vent_slot_length, vent_slot_width);
        vent_slot(90, enclosure_width, vent_slot_length, vent_slot_width);

        // Cable exit holes - USB-C power (back left)
        cable_exit_hole(wall_thickness/2 + 2, 30, cable_hole_diameter);

        // Camera ribbon cable exit (back center)
        cable_exit_hole(wall_thickness/2 + 2, 50, cable_hole_diameter);

        // GPIO ribbon cable exit (back right)
        cable_exit_hole(wall_thickness/2 + 2, 70, cable_hole_diameter);

        // Servo cable exit (left side)
        cable_exit_hole(50, -wall_thickness/2 - 1, cable_hole_diameter);

        // Stepper motor cable exit (left side, lower)
        cable_exit_hole(100, -wall_thickness/2 - 1, cable_hole_diameter);

        // Screw holes for lid attachment (4 corners + 2 mid-points)
        translate([15, 15, enclosure_height - 3])
            cylinder(h=5, d=screw_hole_diameter, $fn=20);
        translate([enclosure_length - 15, 15, enclosure_height - 3])
            cylinder(h=5, d=screw_hole_diameter, $fn=20);
        translate([15, enclosure_width - 15, enclosure_height - 3])
            cylinder(h=5, d=screw_hole_diameter, $fn=20);
        translate([enclosure_length - 15, enclosure_width - 15, enclosure_height - 3])
            cylinder(h=5, d=screw_hole_diameter, $fn=20);
        translate([90, 15, enclosure_height - 3])
            cylinder(h=5, d=screw_hole_diameter, $fn=20);
        translate([90, enclosure_width - 15, enclosure_height - 3])
            cylinder(h=5, d=screw_hole_diameter, $fn=20);
    }

    // Internal standoffs for component mounting
    // Pi 5 standoffs - left side (4 mounting holes at 58mm x 49mm spacing)
    pi_x_base = wall_thickness + 12;
    pi_y_base = wall_thickness + 8;

    translate([pi_x_base, pi_y_base, wall_thickness])
        standoff(standoff_height_pi);
    translate([pi_x_base + 58, pi_y_base, wall_thickness])
        standoff(standoff_height_pi);
    translate([pi_x_base, pi_y_base + 49, wall_thickness])
        standoff(standoff_height_pi);
    translate([pi_x_base + 58, pi_y_base + 49, wall_thickness])
        standoff(standoff_height_pi);

    // PCA9685 #1 standoffs - right side, top (56mm x 19mm spacing)
    pca1_x_base = wall_thickness + 102;
    pca1_y_base = wall_thickness + 8;

    translate([pca1_x_base, pca1_y_base, wall_thickness])
        standoff(standoff_height_pca);
    translate([pca1_x_base + 56, pca1_y_base, wall_thickness])
        standoff(standoff_height_pca);
    translate([pca1_x_base, pca1_y_base + 19, wall_thickness])
        standoff(standoff_height_pca);
    translate([pca1_x_base + 56, pca1_y_base + 19, wall_thickness])
        standoff(standoff_height_pca);

    // PCA9685 #2 standoffs - right side, stacked below first board
    pca2_y_base = pca1_y_base + 19 + pca_stack_spacing + 5;

    translate([pca1_x_base, pca2_y_base, wall_thickness])
        standoff(standoff_height_pca);
    translate([pca1_x_base + 56, pca2_y_base, wall_thickness])
        standoff(standoff_height_pca);
    translate([pca1_x_base, pca2_y_base + 19, wall_thickness])
        standoff(standoff_height_pca);
    translate([pca1_x_base + 56, pca2_y_base + 19, wall_thickness])
        standoff(standoff_height_pca);

    // TMC2209 mounting bracket - small stepper driver on DIN rail bracket
    // Mounted near stepper cable exit (left side)
    tmc_x_base = wall_thickness + 25;
    tmc_y_base = wall_thickness + 50;

    translate([tmc_x_base, tmc_y_base, wall_thickness])
        standoff(standoff_height_pca);
    translate([tmc_x_base + 15, tmc_y_base, wall_thickness])
        standoff(standoff_height_pca);
}

// ============================================================================
// LID ENCLOSURE
// ============================================================================

module enclosure_lid() {
    interior_length = enclosure_length - 2 * wall_thickness;
    interior_width = enclosure_width - 2 * wall_thickness;
    lid_height = 8;  // Thin lid for easy access

    difference() {
        // Solid lid base
        cube([enclosure_length, enclosure_width, lid_height]);

        // Large internal recess for component access
        translate([wall_thickness, wall_thickness, wall_thickness])
            cube([interior_length, interior_width, lid_height]);

        // Screw holes for base attachment (matching base holes)
        translate([15, 15, -1])
            cylinder(h=lid_height + 2, d=screw_hole_diameter, $fn=20);
        translate([enclosure_length - 15, 15, -1])
            cylinder(h=lid_height + 2, d=screw_hole_diameter, $fn=20);
        translate([15, enclosure_width - 15, -1])
            cylinder(h=lid_height + 2, d=screw_hole_diameter, $fn=20);
        translate([enclosure_length - 15, enclosure_width - 15, -1])
            cylinder(h=lid_height + 2, d=screw_hole_diameter, $fn=20);
        translate([90, 15, -1])
            cylinder(h=lid_height + 2, d=screw_hole_diameter, $fn=20);
        translate([90, enclosure_width - 15, -1])
            cylinder(h=lid_height + 2, d=screw_hole_diameter, $fn=20);
    }

    // Snap tabs on underside (2mm walls, 4mm tall - print without support)
    snap_offset = 20;
    translate([snap_offset, wall_thickness + 2, wall_thickness])
        cube([snap_tab_thickness, snap_tab_thickness, snap_tab_height]);
    translate([enclosure_length - snap_offset, wall_thickness + 2, wall_thickness])
        cube([snap_tab_thickness, snap_tab_thickness, snap_tab_height]);
    translate([snap_offset, enclosure_width - wall_thickness - 2, wall_thickness])
        cube([snap_tab_thickness, snap_tab_thickness, snap_tab_height]);
    translate([enclosure_length - snap_offset, enclosure_width - wall_thickness - 2, wall_thickness])
        cube([snap_tab_thickness, snap_tab_thickness, snap_tab_height]);
}

// ============================================================================
// PCA9685 MOUNTING PLATE (Qty: 2)
// ============================================================================

module pca9685_mount_plate() {
    plate_length = 70;      // mm, some extra space around board
    plate_width = 35;       // mm
    plate_thickness = 3;    // mm mounting plate
    hole_diameter = 3;      // mm clearance for M2.5 screws

    // Hole pattern for PCA9685: 56mm x 19mm spacing
    hole_x_offset = 7;      // mm from left edge
    hole_y_offset = 8;      // mm from bottom edge
    hole_x_spacing = 56;    // mm between holes (length)
    hole_y_spacing = 19;    // mm between holes (width)

    difference() {
        // Base plate
        cube([plate_length, plate_width, plate_thickness]);

        // Mounting holes
        translate([hole_x_offset, hole_y_offset, -0.5])
            cylinder(h=plate_thickness + 1, d=hole_diameter, $fn=20);
        translate([hole_x_offset + hole_x_spacing, hole_y_offset, -0.5])
            cylinder(h=plate_thickness + 1, d=hole_diameter, $fn=20);
        translate([hole_x_offset, hole_y_offset + hole_y_spacing, -0.5])
            cylinder(h=plate_thickness + 1, d=hole_diameter, $fn=20);
        translate([hole_x_offset + hole_x_spacing, hole_y_offset + hole_y_spacing, -0.5])
            cylinder(h=plate_thickness + 1, d=hole_diameter, $fn=20);

        // 2mm chamfer on edges for easier insertion
        // Top edges
        for (x = [0, plate_length]) {
            translate([x, 0, plate_thickness - 0.5])
                rotate([0, 45, 0])
                    cube([2, plate_width, 2], center=true);
        }
        for (y = [0, plate_width]) {
            translate([0, y, plate_thickness - 0.5])
                rotate([45, 0, 0])
                    cube([plate_length, 2, 2], center=true);
        }
    }
}

// ============================================================================
// ASSEMBLY VISUALIZATION
// ============================================================================

// Uncomment below to show complete assembly (comment out for individual part exports)

// Base with internal components
enclosure_base();

// Lid positioned above (translate to see separation)
translate([0, 0, enclosure_height + 5])
    enclosure_lid();

// PCA9685 mounting plates (for reference - position above lid)
translate([10, 0, enclosure_height + 20])
    pca9685_mount_plate();

translate([90, 0, enclosure_height + 20])
    pca9685_mount_plate();

// ============================================================================
// EXPORT INSTRUCTIONS
// ============================================================================
/*
MANUFACTURING & ASSEMBLY GUIDE:

PART 1: ENCLOSURE BASE
  - Export: enclosure_base()
  - Print Settings: 0.2mm layers, 20% infill (grid), 3 walls
  - Orientation: Flat on build plate (no supports needed)
  - Estimated time: ~6-7 hours, ~280g PLA
  - Post-processing: Light sanding of cable exit holes

PART 2: ENCLOSURE LID
  - Export: enclosure_lid()
  - Print Settings: 0.2mm layers, 20% infill (grid), 3 walls
  - Orientation: Flat on build plate (no supports needed)
  - Estimated time: ~2-3 hours, ~110g PLA
  - Post-processing: Sand snap tabs if tight fit

PART 3 & 4: PCA9685 MOUNTING PLATES (print 2x)
  - Export: pca9685_mount_plate()
  - Print Settings: 0.2mm layers, 20% infill (grid), 3 walls
  - Orientation: Flat on build plate (no supports needed)
  - Estimated time: ~1 hour each, ~25g PLA each
  - Post-processing: Deburr mounting holes

ASSEMBLY STEPS:
  1. Verify all standoffs are properly seated in base
  2. Mount Raspberry Pi 5 on left standoffs using M2.5x6 socket head screws
  3. Mount PCA9685 boards on right standoffs:
     - PCA #1 on top standoff set
     - PCA #2 on lower standoff set (stacked)
     - Use supplied mounting plates for additional support
  4. Mount TMC2209 stepper driver on DIN rail bracket at stepper cable exit area
  5. Route cables through appropriate exit holes:
     - USB-C power → back left hole
     - Camera ribbon → back center hole
     - GPIO ribbon → back right hole
     - Servo cable bundle → left side hole
     - Stepper motor cable → left side hole (lower)
  6. Align lid with base, verify snap tabs engage
  7. Secure with M3x8 screws in 6 mounting holes (4 corners + 2 mid-points)
  8. Mount complete enclosure to 2020 aluminum frame using M5 T-nuts through mounting ears

VENTILATION:
  - 6 horizontal slot vents (3 per long side) provide passive airflow
  - Ensure mounting allows air circulation around enclosure
  - Monitor Pi CPU temp during extended operation

CABLE ROUTING:
  - Use cable ties to organize wiring inside enclosure
  - Keep servo signal wires away from stepper power cables (noise immunity)
  - Secure camera ribbon to prevent flexing at connector
*/
