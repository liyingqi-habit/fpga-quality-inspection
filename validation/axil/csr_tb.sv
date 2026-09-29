`timescale 1ns/1ps
module csr_tb;
 reg clk=0,rstn=0;always #18.5185 clk=~clk;
 wire tx;wire [7:0] led;
 axil_soc dut(.clk(clk),.rstn(rstn),.key(1'b1),.uart_rx(1'b1),.uart_tx(tx),.led(led));
 integer fd,boot,count=0;
 always @(posedge clk)if(!dut.bus_reset && dut.commit_write)begin
  if(dut.address>=32'h80004800 && dut.address<32'h80008000)begin
   if((^dut.data)===1'bx)$fatal(1,"Unknown CSR record");
   $fdisplay(fd,"%0d,%0d,%0d",boot,dut.address,dut.data);
   count=count+1;
  end
 end
 initial begin
  fd=$fopen("csr.csv","w");$fdisplay(fd,"boot,addr,data");
  for(boot=1;boot<=2;boot=boot+1)begin
   rstn=0;repeat(20)@(negedge clk);count=0;rstn=1;
   wait(led==8'h6b);repeat(30)@(negedge clk);
   $display("CSR_TRACE_COMPLETE boot=%0d words=%0d",boot,count);
  end
  $fclose(fd);$finish;
 end
 initial begin repeat(300000)@(posedge clk);$fatal(1,"CSR timeout pc=%h",dut.cpu.writeBack_PC);end
endmodule
