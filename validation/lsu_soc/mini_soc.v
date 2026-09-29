// CPU-WR-04: migrated first-party mini SoC, isolated from original board files.
// rstn is a whole local-system reset; there are no external outstanding transactions.
`timescale 1ns/1ps
module mini_soc #(
  parameter integer CLK_HZ=27000000,
  parameter integer DEBOUNCE_CYCLES=270000,
  parameter integer RESPONSE_DELAY=0,
  parameter ROM_FILE="firmware.hex"
)(input wire clk, rstn, key, uart_rx, output wire uart_tx, output reg [7:0] led);
  // Power-on reset plus synchronous release after the active-low reset button.
  reg [7:0] reset_pipe=0;
  always @(posedge clk or negedge rstn)
    if(!rstn) reset_pipe<=0; else reset_pipe<={reset_pipe[6:0],1'b1};
  wire reset=!reset_pipe[7];
  reg key_meta, key_sync, key_stable;
  reg [31:0] debounce_count;
  always @(posedge clk) begin
    if(reset) begin key_meta<=1; key_sync<=1; key_stable<=1; debounce_count<=0; end
    else begin
      key_meta<=key; key_sync<=key_meta;
      if(key_sync==key_stable) debounce_count<=0;
      else if(debounce_count==DEBOUNCE_CYCLES-1) begin
        key_stable<=key_sync; debounce_count<=0;
      end else debounce_count<=debounce_count+1'b1;
    end
  end
  wire i_valid, i_ready;
  wire [31:0] i_pc;
  reg i_rsp_valid, i_rsp_error;
  reg [31:0] i_rsp_data;
  wire d_valid, d_ready, d_write;
  wire [31:0] d_addr,d_data;
  wire [1:0] d_size;
  wire [3:0] d_mask;
  reg d_rsp_ready,d_rsp_error;
  reg [31:0] d_rsp_data;
  wire [31:0] obs_cmd_pc,obs_retire_pc;
  wire obs_store_retire,obs_retire_valid;
  reg pending=0;
  integer response_count=0;
  VexWriteResponse cpu(
    .clk(clk),.reset(reset),
    .iBus_cmd_valid(i_valid),.iBus_cmd_ready(i_ready),.iBus_cmd_payload_pc(i_pc),
    .iBus_rsp_valid(i_rsp_valid),.iBus_rsp_payload_error(i_rsp_error),.iBus_rsp_payload_inst(i_rsp_data),
    .dBus_cmd_valid(d_valid),.dBus_cmd_ready(d_ready),.dBus_cmd_payload_wr(d_write),
    .dBus_cmd_payload_address(d_addr),.dBus_cmd_payload_data(d_data),
    .dBus_cmd_payload_size(d_size),.dBus_cmd_payload_mask(d_mask),
    .dBus_rsp_ready(d_rsp_ready),.dBus_rsp_error(d_rsp_error),.dBus_rsp_data(d_rsp_data),
    .timerInterrupt(1'b0),.externalInterrupt(1'b0),.softwareInterrupt(1'b0),
    .obs_cmd_pc(obs_cmd_pc),.obs_retire_pc(obs_retire_pc),
    .obs_store_retire(obs_store_retire),.obs_retire_valid(obs_retire_valid)
  );
  // Harvard physical ROM copies, same contents; synchronous reads map to FPGA RAM.
  // 16 KiB ROM at 0x80000000; 16 KiB RW RAM at 0x80004000.
  reg [31:0] rom[0:4095];
  reg [31:0] ram[0:4095];
  initial $readmemh(ROM_FILE,rom);
  wire i_rom=i_pc[31:14]==18'h20000;
  wire d_rom=d_addr[31:14]==18'h20000;
  wire d_ram=d_addr[31:14]==18'h20001;
  wire mmio=d_addr[31:8]==24'h100000;
  wire tx_busy,rx_valid,rx_overrun,rx_framing;
  wire [7:0] rx_data;
  wire uart_data_sel=mmio && d_addr[7:0]==8'h00;
  // A write is accepted only when the UART can consume it; other writes commit on handshake.
  assign d_ready=!reset && !pending && !d_rsp_ready && !(d_write && uart_data_sel && tx_busy);
  assign i_ready=!reset;
  wire d_fire=d_valid && d_ready;
  wire uart_start=d_fire && d_write && uart_data_sel && d_mask[0];
  wire rx_pop=d_fire && !d_write && uart_data_sel;
  wire clear_errors=d_fire && d_write && mmio && d_addr[7:0]==8'h04;
  mini_uart #(.CLK_HZ(CLK_HZ)) uart(
    .clk(clk),.reset(reset),.rx(uart_rx),.tx(uart_tx),
    .tx_start(uart_start),.tx_data(d_data[7:0]),.tx_busy(tx_busy),
    .rx_pop(rx_pop),.clear_errors(clear_errors),.rx_data(rx_data),
    .rx_valid(rx_valid),.overrun(rx_overrun),.framing_error(rx_framing)
  );
  reg [31:0] ticks;
  reg [31:0] fault_count;
  wire legal_mmio=mmio && (d_addr[7:0]==0 || d_addr[7:0]==4 ||
    d_addr[7:0]==8'h10 || d_addr[7:0]==8'h14 || d_addr[7:0]==8'h20 ||
    d_addr[7:0]==8'h24 || d_addr[7:0]==8'h28);
  wire legal_write=d_ram || (legal_mmio &&
    (d_addr[7:0]==0 || d_addr[7:0]==4 || d_addr[7:0]==8'h10));
  // Separate synchronous memory ports: no reset loop over RAM.
  always @(posedge clk) begin
    if(i_valid && i_ready) i_rsp_data<=rom[i_pc[13:2]];
    if(d_fire && !d_write) begin
      if(d_rom) d_rsp_data<=rom[d_addr[13:2]];
      else if(d_ram) d_rsp_data<=ram[d_addr[13:2]];
      else case(d_addr)
        32'h10000000: d_rsp_data<={24'b0,rx_data};
        32'h10000004: d_rsp_data<={28'b0,rx_framing,rx_overrun,rx_valid,tx_busy};
        32'h10000010: d_rsp_data<={24'b0,led};
        32'h10000014: d_rsp_data<={31'b0,key_stable};
        32'h10000020: d_rsp_data<=ticks;
        32'h10000024: d_rsp_data<=CLK_HZ;
        32'h10000028: d_rsp_data<=fault_count;
        default: d_rsp_data<=0;
      endcase
    end
    if(d_fire && d_write && d_ram) begin
      if(d_mask[0]) ram[d_addr[13:2]][7:0]<=d_data[7:0];
      if(d_mask[1]) ram[d_addr[13:2]][15:8]<=d_data[15:8];
      if(d_mask[2]) ram[d_addr[13:2]][23:16]<=d_data[23:16];
      if(d_mask[3]) ram[d_addr[13:2]][31:24]<=d_data[31:24];
    end
  end
  always @(posedge clk) begin
    if(reset) begin
      i_rsp_valid<=0; i_rsp_error<=0; d_rsp_ready<=0; d_rsp_error<=0;
      led<=0; ticks<=0; fault_count<=0; pending<=0; response_count<=0;
    end else begin
      ticks<=ticks+1'b1;
      i_rsp_valid<=i_valid && i_ready;
      i_rsp_error<=!i_rom;
      d_rsp_ready<=0;
      if(pending) begin
        if(response_count==1) begin pending<=0; d_rsp_ready<=1; end
        else response_count<=response_count-1;
      end
      if(d_fire) begin
        d_rsp_error<=d_write ? !legal_write : !(d_rom || d_ram || legal_mmio);
        if(RESPONSE_DELAY==0) d_rsp_ready<=1;
        else begin pending<=1; response_count<=RESPONSE_DELAY; end
      end
      if(d_fire && d_write && mmio && d_addr[7:0]==8'h10 && d_mask[0]) led<=d_data[7:0];
      // Diagnostic count is retained, but invalid writes now also return precise errors.
      if(d_fire && d_write && !(d_ram || (legal_mmio &&
        (d_addr[7:0]==0 || d_addr[7:0]==4 || d_addr[7:0]==8'h10)))) fault_count<=fault_count+1'b1;
    end
  end
endmodule
