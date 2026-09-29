// Offline AXI4-Lite integration target, NOT a DDR/CLINT/PLIC implementation.
module axil_soc(input wire clk,rstn,key,uart_rx,output wire uart_tx,output reg [7:0] led=0);
  reg [7:0] reset_pipe=0;
  always @(posedge clk or negedge rstn)
    if(!rstn)reset_pipe<=0;else reset_pipe<={reset_pipe[6:0],1'b1};
  wire bus_reset=!reset_pipe[7];wire cpu_reset;
  reg key_meta=1,key_sync=1;
  always @(posedge clk)begin key_meta<=key;key_sync<=key_meta;end
  wire cv,ready,writing,rv,re,busy,cancelled;
  wire [31:0] ca,cd,rd;wire [3:0] mask;
  wire av,ar,wv,wr,bv,br,qv,qr,pv,pr;
  wire [31:0] aa,wd,qa;wire [3:0] ws;wire [2:0] ap,qp;
  reg [1:0] bc=0,pc=0;reg [31:0] pd=0;
  wire iv;wire [31:0] ip;reg ir=0,ifault=0;reg [31:0] instruction=0;
  reg [31:0] rom[0:4095],ram[0:4095];
  initial $readmemh("firmware.hex",rom);
  reg soft_irq=0;reg [31:0] ticks=0,compare_value=32'hffffffff;
  wire timer_irq=ticks>=compare_value;
  VexAxilCpu cpu(.clk(clk),.reset(cpu_reset),
    .iBus_cmd_valid(iv),.iBus_cmd_ready(!bus_reset),.iBus_cmd_payload_pc(ip),
    .iBus_rsp_valid(ir),.iBus_rsp_payload_error(ifault),.iBus_rsp_payload_inst(instruction),
    .dBus_cmd_valid(cv),.dBus_cmd_ready(ready),.dBus_cmd_payload_wr(writing),
    .dBus_cmd_payload_address(ca),.dBus_cmd_payload_data(cd),.dBus_cmd_payload_size(),.dBus_cmd_payload_mask(mask),
    .dBus_rsp_ready(rv),.dBus_rsp_error(re),.dBus_rsp_data(rd),
    .timerInterrupt(timer_irq),.softwareInterrupt(soft_irq),.externalInterrupt(!key_sync),
    .obs_cmd_pc(),.obs_store_retire(),.obs_retire_pc(),.obs_retire_valid());
  cpu_axil_bridge bridge(clk,bus_reset,1'b0,1'b1,1'b1,cv,writing,ca,cd,mask,ready,rv,re,rd,
    cpu_reset,busy,cancelled,av,ar,aa,ap,wv,wr,wd,ws,bv,br,bc,qv,qr,qa,qp,pv,pr,pd,pc);
  reg have_aw=0,have_w=0,bvalid=0,rvalid=0;
  reg [31:0] address=0,data=0;reg [3:0] strobes=0;
  assign ar=!bus_reset && !have_aw && !bvalid;
  assign wr=!bus_reset && !have_w && !bvalid;
  assign qr=!bus_reset && !rvalid;
  assign bv=bvalid;assign pv=rvalid;
  wire tx_busy,rx_valid,rx_overrun,rx_framing;wire [7:0] rx_data;
  wire commit_write=have_aw && have_w && !bvalid && !(address==32'h10000000 && tx_busy);
  mini_uart #(.CLK_HZ(27000000)) uart(.clk(clk),.reset(bus_reset),.rx(uart_rx),.tx(uart_tx),
    .tx_start(commit_write && address==32'h10000000 && strobes[0]),.tx_data(data[7:0]),.tx_busy(tx_busy),
    .rx_pop(qv&&qr&&qa==32'h10000000),.clear_errors(commit_write&&address==32'h10000004),
    .rx_data(rx_data),.rx_valid(rx_valid),.overrun(rx_overrun),.framing_error(rx_framing));
  integer lane;
  always @(posedge clk)begin
    if(bus_reset)begin
      have_aw<=0;have_w<=0;bvalid<=0;rvalid<=0;bc<=0;pc<=0;pd<=0;
      ir<=0;ifault<=0;instruction<=0;led<=0;soft_irq<=0;ticks<=0;compare_value<=32'hffffffff;
    end else begin
      ticks<=ticks+1;
      ir<=iv;if(iv)begin instruction<=rom[ip[13:2]];ifault<=ip[31:14]!=18'h20000;end
      if(av&&ar)begin have_aw<=1;address<=aa;end
      if(wv&&wr)begin have_w<=1;data<=wd;strobes<=ws;end
      if(bvalid&&br)begin bvalid<=0;have_aw<=0;have_w<=0;end
      if(rvalid&&pr)rvalid<=0;
      if(commit_write)begin
        bvalid<=1;bc<=0;
        if(address[31:14]==18'h20001)begin
          for(lane=0;lane<4;lane=lane+1)if(strobes[lane])ram[address[13:2]][lane*8+:8]<=data[lane*8+:8];
        end else case(address)
          32'h10000000,32'h10000004:begin end
          32'h10000010:if(strobes[0])led<=data[7:0];
          32'h10000030:if(strobes[0])soft_irq<=data[0];
          32'h10000034:for(lane=0;lane<4;lane=lane+1)if(strobes[lane])compare_value[lane*8+:8]<=data[lane*8+:8];
          default:bc<=2'b11;
        endcase
      end
      if(qv&&qr)begin
        rvalid<=1;pc<=0;
        if(qa[31:14]==18'h20001)pd<=ram[qa[13:2]];
        else if(qa[31:14]==18'h20000)pd<=rom[qa[13:2]];
        else case(qa)
          32'h10000000:pd<={24'b0,rx_data};
          32'h10000004:pd<={28'b0,rx_framing,rx_overrun,rx_valid,tx_busy};
          32'h10000010:pd<={24'b0,led};
          32'h10000020:pd<=ticks;
          32'h10000030:pd<={31'b0,soft_irq};
          32'h10000034:pd<=compare_value;
          default:begin pd<=0;pc<=2'b11;end
        endcase
      end
    end
  end
endmodule
