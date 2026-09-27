// Single-clock, single-slot experiment. CPU reset never resets accepted bus work.
module write_bridge(
  input wire clk, bus_reset, reset_request, admit, allow_b,
  input wire cmd_valid, cmd_write, input wire [31:0] cmd_addr,cmd_data,
  input wire [3:0] cmd_mask,
  output wire cmd_ready, output reg rsp_valid=0,rsp_error=0,
  output wire cpu_reset, output reg busy=0, output reg cancelled=0,
  output wire awvalid, input wire awready, output reg [31:0] awaddr,
  output wire wvalid, input wire wready, output reg [31:0] wdata,
  output reg [3:0] wstrb,
  input wire bvalid, output wire bready, input wire [1:0] bresp
);
  reg aw_sent=0,w_sent=0;
  // Quarantine is sticky until the old response is drained. No timeout release.
  assign cpu_reset=bus_reset || reset_request || cancelled;
  assign cmd_ready=admit && !cpu_reset && !busy && !rsp_valid;
  assign awvalid=busy && !aw_sent;
  assign wvalid=busy && !w_sent;
  assign bready=busy && aw_sent && w_sent && allow_b;
  always @(posedge clk) begin
    if(bus_reset) begin
      busy<=0; cancelled<=0; aw_sent<=0; w_sent<=0; rsp_valid<=0; rsp_error<=0;
      awaddr<=0; wdata<=0; wstrb<=0;
    end else begin
      rsp_valid<=0;
      if(reset_request && busy) cancelled<=1;
      if(cmd_valid && cmd_ready) begin
        if(cmd_write) begin
          busy<=1; aw_sent<=0; w_sent<=0;
          awaddr<=cmd_addr; wdata<=cmd_data; wstrb<=cmd_mask;
        end else begin
          // This isolated fixture has no data-memory read target. Reject loads.
          rsp_valid<=1; rsp_error<=1;
        end
      end
      if(awvalid && awready) aw_sent<=1;
      if(wvalid && wready) w_sent<=1;
      if(bvalid && bready) begin
        busy<=0; cancelled<=0;
        if(!cancelled && !reset_request) begin rsp_valid<=1; rsp_error<=bresp!=0; end
      end
    end
  end
endmodule
