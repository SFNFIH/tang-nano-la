# Build Tang Nano 9K LA bitstream with Gowin IDE (gw_sh)
cd /home/tony/gw_FPGA/tang-nano-la/tang-nano-la
open_project la.gprj
set_option -top_module top
set_option -looplimit 20000
run all
puts "BUILD_DONE"
exit
