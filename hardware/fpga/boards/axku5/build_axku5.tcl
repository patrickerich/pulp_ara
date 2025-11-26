# Vivado project-mode build script for Ara on AXKU5
#
# Usage (from repo root):
#   make -C hardware synth_flist_fpga_wrap config=2_lanes_128
#   vivado -mode batch -source hardware/fpga/boards/axku5/build_axku5.tcl -tclargs 2_lanes_128
#
# Or in GUI mode (Tcl console):
#   set argv {2_lanes_128}
#   set argc [llength $argv]
#   source hardware/fpga/boards/axku5/build_axku5.tcl
#
# This script:
#   - Creates a Vivado project under hardware/build/build_axku5_<config>/
#   - Adds sources from the synthesis filelist (synth_flist_fpga_wrap)
#   - Applies include directories
#   - Adds the AXKU5 board constraints
#   - Runs synthesis and implementation
#   - Writes a bitstream ara_axku5_<config>.bit in the same project directory

# -----------------------
# Parse command line args
# -----------------------

if { $argc < 1 } {
  puts "ERROR: Expected at least 1 argument: <config> (e.g. 2_lanes_128)"
  return -code error
}

set config [lindex $argv 0]
puts "INFO: Using Ara configuration: $config"

# -------------------
# Derive key paths
# -------------------

# This script lives in hardware/fpga/boards/axku5
set script_dir [file dirname [file normalize [info script]]]

# repo_dir is the project root: pulp_ara/
#   script_dir            = hardware/fpga/boards/axku5
#   ../../../../ from there = .
set repo_dir  [file normalize [file join $script_dir ../../../../]]

# hw_dir is pulp_ara/hardware
set hw_dir    [file normalize [file join $repo_dir hardware]]

# hardware/build where the Makefile writes the FPGA flists
set hw_build_dir [file normalize [file join $hw_dir build]]

# Vivado project directory under hardware/build
set proj_dir  [file normalize [file join $hw_build_dir build_axku5_${config}]]
set proj_name "ara_axku5_${config}"

# Flist and incdir files produced by 'make -C hardware synth_flist_fpga_wrap'
set flist_file   [file join $hw_build_dir synth_fpga_wrap_${config}.f]
set incdirs_file [file join $hw_build_dir synth_fpga_wrap_incdirs_${config}.txt]
set xdc_file     [file normalize [file join $script_dir axku5.xdc]]

if {![file exists $flist_file]} {
  puts "ERROR: Filelist $flist_file does not exist. Run 'make -C hardware synth_flist_fpga_wrap config=$config' first."
  return -code error
}

if {![file exists $incdirs_file]} {
  puts "WARNING: Include-dir file $incdirs_file does not exist. Continuing without extra include dirs."
}

if {![file exists $xdc_file]} {
  puts "ERROR: XDC constraints file $xdc_file does not exist."
  return -code error
}

puts "INFO: Project dir : $proj_dir"
puts "INFO: Project name: $proj_name"
puts "INFO: Flist       : $flist_file"
puts "INFO: XDC         : $xdc_file"

# -------------------
# Project setup
# -------------------

# Device part for AXKU5 (adjust if needed)
set part_name "xcku5p-ffvb676-2-e"
set top_name  "ara_fpga_wrap"

# Create / recreate project
file mkdir $proj_dir
create_project -force $proj_name $proj_dir -part $part_name

# Make sure sources_1 is the active fileset
set src_fs [get_filesets sources_1]
set constr_fs [get_filesets constrs_1]

# -------------------
# Add RTL sources
# -------------------
#
# The flist is a plain text list of SV/SystemVerilog files, one per line.
# We must parse it and add the referenced files, *not* the flist itself.

set sv_files {}
set fh [open $flist_file r]
while {[gets $fh line] >= 0} {
  set line [string trim $line]
  # Skip empty lines and comments
  if {$line eq ""} {
    continue
  }
  if {[string match "#*" $line]} {
    continue
  }

  # Basic handling: assume each line is a file path (absolute or relative)
  if {[file pathtype $line] eq "absolute"} {
    set full $line
  } else {
    # Treat relative paths as relative to repo root
    set full [file normalize [file join $repo_dir $line]]
  }

  # Only add if it looks like a source file
  if {[file extension $full] in {".v" ".sv" ".vhd" ".vhdl"}} {
    add_files -fileset $src_fs -norecurse $full
    lappend sv_files $full
  }
}
close $fh

# Mark all added files as SystemVerilog where appropriate
if {[llength $sv_files] > 0} {
  set_property file_type {SystemVerilog} [get_files -of_objects $src_fs]
}

# Apply include directories if present
if {[file exists $incdirs_file]} {
  set incdir_line [string trim [read [open $incdirs_file r]]]
  if {$incdir_line ne ""} {
    puts "INFO: Applying include dirs: $incdir_line"
    set tokens  [split $incdir_line " "]
    set incdirs {}
    set expecting_path 0
    foreach tok $tokens {
      if {$tok eq "-incdir"} {
        set expecting_path 1
      } elseif {$expecting_path} {
        # Normalize relative path against hardware/build (where flists live)
        set full [file normalize [file join $hw_build_dir $tok]]
        lappend incdirs $full
        set expecting_path 0
      }
    }
    if {[llength $incdirs] > 0} {
      set_property include_dirs $incdirs $src_fs
    }
  }
}

# -------------------
# Constraints
# -------------------

add_files -fileset $constr_fs $xdc_file

# -------------------
# Top and compile order
# -------------------

set_property top $top_name $src_fs
update_compile_order -fileset $src_fs

puts "INFO: Part      : $part_name"
puts "INFO: Top-Level : $top_name"

# -------------------
# Runs: synthesis & implementation
# -------------------

# Launch synthesis
launch_runs synth_1 -jobs 4
wait_on_run synth_1

# Launch implementation up to bitstream
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

# -------------------
# Bitstream
# -------------------

# Open implemented design and write a named bitstream in the project dir
open_run impl_1
set bit_file [file normalize [file join $proj_dir "ara_axku5_${config}.bit"]]
set mmi_file [file normalize [file join $proj_dir "ara_axku5_${config}.mmi"]]
write_bitstream -force $bit_file
puts "INFO: Bitstream written to $bit_file"
write_mem_info -force ara_axku5_2_lanes_256.mmi
puts "INFO: Memory map info written to $mmi_file"


# Use updatemem to merge ELF contents into the bitstream:
# set cwd [pwd]
#
# updatemem \
#   -meminfo $cwd/hardware/build/build_axku5_2_lanes_256/ara_axku5_2_lanes_256.mmi \
#   -data    $cwd/apps/bin/hello_world_uart \
#   -bit     $cwd/hardware/build/build_axku5_2_lanes_256/ara_axku5_2_lanes_256.bit \
#   -out     $cwd/hardware/build/build_axku5_2_lanes_256/ara_axku5_2_lanes_256_with_app.bit