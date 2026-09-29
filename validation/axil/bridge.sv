// Single outstanding AXI4-Lite data transaction. CPU-local reset drains, never retracts.
module cpu_axil_bridge(
  input wire clk,bus_reset,reset_request,admit,allow_response,
  input wire cmd_valid,cmd_write,input wire [31:0] cmd_addr,cmd_data,input wire [3:0] cmd_mask,
  output wire cmd_ready,output reg rsp_valid=0,rsp_error=0,output reg [31:0] rsp_data=0,
  output wire cpu_reset,output reg busy=0,cancelled=0,
  output wire awvalid,input wire awready,output reg [31:0] awaddr=0,output wire [2:0] awprot,
  output wire wvalid,input wire wready,output reg [31:0] wdata=0,output reg [3:0] wstrb=0,
  input wire bvalid,output wire bready,input wire [1:0] bresp,
  output wire arvalid,input wire arready,output reg [31:0] araddr=0,output wire [2:0] arprot,
  input wire rvalid,output wire rready,input wire [31:0] rdata,input wire [1:0] rresp
);
  reg writing=0,aw_sent=0,w_sent=0,ar_sent=0;
  assign cpu_reset=bus_reset || reset_request || cancelled;
  assign cmd_ready=admit && !cpu_reset && !busy && !rsp_valid;
  assign awvalid=busy && writing && !aw_sent;
  assign wvalid=busy && writing && !w_sent;
  assign arvalid=busy && !writing && !ar_sent;
  assign bready=busy && writing && aw_sent && w_sent && allow_response;
  assign rready=busy && !writing && ar_sent && allow_response;
  assign awprot=3'b000;
  assign arprot=3'b000;
  always @(posedge clk) begin
    if(bus_reset) begin
      busy<=0;cancelled<=0;rsp_valid<=0;rsp_error<=0;rsp_data<=0;
      writing<=0;aw_sent<=0;w_sent<=0;ar_sent<=0;awaddr<=0;araddr<=0;wdata<=0;wstrb<=0;
    end else begin
      rsp_valid<=0;
      if(reset_request && busy) cancelled<=1;
      if(cmd_valid && cmd_ready) begin
        busy<=1;writing<=cmd_write;aw_sent<=0;w_sent<=0;ar_sent<=0;
        awaddr<=cmd_addr;araddr<=cmd_addr;wdata<=cmd_data;wstrb<=cmd_mask;
      end
      if(awvalid && awready) aw_sent<=1;
      if(wvalid && wready) w_sent<=1;
      if(arvalid && arready) ar_sent<=1;
      if((bvalid && bready) || (rvalid && rready)) begin
        busy<=0;cancelled<=0;
        if(!cancelled && !reset_request) begin
          rsp_valid<=1;rsp_error<=writing ? bresp!=0 : rresp!=0;
          rsp_data<=writing ? 0 : rdata;
        end
      end
    end
  end
endmodule
