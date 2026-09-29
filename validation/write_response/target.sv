`timescale 1ns/1ps
// Verification-only, single-slot, single-beat AXI-like WRITE target.
// No CPU reset input: accepted requests survive a CPU-only reset.
module write_target(
  input wire clk, bus_reset, allow_aw, allow_w,
  input wire awvalid, input wire [31:0] awaddr, output wire awready,
  input wire wvalid, input wire [31:0] wdata, input wire [3:0] wstrb,
  output wire wready, output reg bvalid=0, input wire bready,
  output reg [1:0] bresp=0,
  input wire [7:0] response_delay, input wire [1:0] response_code,
  input wire never_respond
);
  reg have_aw=0, have_w=0;
  reg [31:0] address, data;
  reg [3:0] mask;
  integer remaining=0, i;
  reg [31:0] memory [0:15];
  assign awready=!bus_reset && allow_aw && !have_aw && !bvalid;
  assign wready=!bus_reset && allow_w && !have_w && !bvalid;
  always @(posedge clk) begin
    if(bus_reset) begin
      have_aw<=0; have_w<=0; bvalid<=0; bresp<=0; remaining<=0;
      for(i=0;i<16;i=i+1) memory[i]<=32'h11223344;
    end else begin
      if(awvalid && awready) begin have_aw<=1; address<=awaddr; end
      if(wvalid && wready) begin
        have_w<=1; data<=wdata; mask<=wstrb; remaining<=response_delay;
      end
      if(have_aw && have_w && !bvalid && !never_respond) begin
        if(remaining!=0) remaining<=remaining-1;
        else begin
          bvalid<=1; bresp<=response_code;
          // Explicit model policy: error writes do not modify memory.
          // Real targets may partially write before reporting an error.
          if(response_code==0) for(i=0;i<4;i=i+1)
            if(mask[i]) memory[address[5:2]][8*i+:8]<=data[8*i+:8];
        end
      end
      if(bvalid && bready) begin bvalid<=0; have_aw<=0; have_w<=0; end
    end
  end
endmodule
