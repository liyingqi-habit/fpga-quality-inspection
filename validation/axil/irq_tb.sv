`timescale 1ns/1ps
module irq_tb;
 reg clk=0,rstn=0,key=1;always #18.5185 clk=~clk;
 wire tx;wire [7:0] led;
 axil_soc dut(.clk(clk),.rstn(rstn),.key(key),.uart_rx(1'b1),.uart_tx(tx),.led(led));
 integer fd,boot,delay_cycles,wait_key=0,count=0;
 reg [7:0] last_led=0;reg key_target=1;
 always @(posedge clk)if(!dut.bus_reset && dut.commit_write)begin
  if(dut.address>=32'h80004800 && dut.address<32'h80008000)begin
   if((^dut.data)===1'bx)$fatal(1,"Unknown IRQ record");
   $fdisplay(fd,"%0d,%0d,%0d",boot,dut.address,dut.data);count=count+1;
  end
  if(dut.address==32'h10000010 && dut.data==32'hee)$fatal(1,"Unexpected trap cause");
 end
 always @(negedge clk)begin
  if(!rstn)begin key=1;key_target=1;last_led=0;wait_key=0;end
  else begin
   if(led!=last_led)begin
    last_led=led;
    if(led==8'he1||led==8'he2)begin key_target=(led==8'he2);wait_key=delay_cycles+1;end
   end
   if(wait_key>0)begin wait_key=wait_key-1;if(wait_key==0)key=key_target;end
  end
 end
 initial begin
  if(!$value$plusargs("KEY_DELAY=%d",delay_cycles))$fatal(1,"KEY_DELAY required");
  fd=$fopen("irq.csv","w");$fdisplay(fd,"boot,addr,data");
  for(boot=1;boot<=2;boot=boot+1)begin
   rstn=0;repeat(20)@(negedge clk);count=0;rstn=1;
   wait(led==8'h6b);repeat(50)@(negedge clk);
   $display("IRQ_TRACE_COMPLETE boot=%0d delay=%0d words=%0d",boot,delay_cycles,count);
  end
  $fclose(fd);$finish;
 end
 initial begin repeat(200000)@(posedge clk);$fatal(1,"IRQ timeout pc=%h cause=%h",dut.cpu.writeBack_PC,dut.cpu.CsrPlugin_mcause_exceptionCode);end
endmodule
