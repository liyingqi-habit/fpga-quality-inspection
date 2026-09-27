`timescale 1ns/1ps
module bridge_tb;
 reg clk=0;always #5 clk=~clk;
 reg reset=1,cancel=0,cv=0,cw=0,allow_rsp=0,awready=0,wready=0,arready=0,bvalid=0,rvalid=0;
 reg [31:0] ca=0,cd=0,rdata=0;reg [3:0] mask=0;reg [1:0] response=0;
 wire ready,rv,re,cr,busy,cancelled,av,wv,qv,br,rr;wire [31:0] aa,wd,qa,rd;wire[3:0] ws;wire[2:0] ap,qp;
 cpu_axil_bridge dut(clk,reset,cancel,1'b1,allow_rsp,cv,cw,ca,cd,mask,ready,rv,re,rd,cr,busy,cancelled,
   av,awready,aa,ap,wv,wready,wd,ws,bvalid,br,response,qv,arready,qa,qp,rvalid,rr,rdata,response);
 task step;begin @(posedge clk);#1;end endtask
 task cancel_now;begin cancel=1;step;cancel=0;if(!cancelled||!cr||!busy)$fatal(1,"quarantine missing");end endtask
 integer write_mode,code,delay,phase,m,n,cases=0;
 reg[3:0] testmask;
 initial begin
 for(write_mode=0;write_mode<2;write_mode=write_mode+1)
 for(code=0;code<4;code=code+1)
 for(delay=0;delay<=14;delay=delay+7)
 for(phase=0;phase<6;phase=phase+1)
 for(m=0;m<4;m=m+1)begin
   reset=1;cv=0;cancel=0;awready=0;wready=0;arready=0;bvalid=0;rvalid=0;allow_rsp=0;step;step;reset=0;step;
   testmask=m==0?0:m==1?1:m==2?5:15;
   cv=1;cw=write_mode;ca=32'h8000401c;cd=32'h89abcdef;mask=testmask;
   if(!ready)$fatal(1,"not ready idle");step;cv=0;ca=0;cd=0;mask=0;
   if(phase==1)cancel_now;
   repeat(delay+1)begin step;if(aa!==32'h8000401c||qa!==32'h8000401c||wd!==32'h89abcdef||ws!==testmask||ap!==0||qp!==0)$fatal(1,"payload changed");end
   if(write_mode)begin
     if(phase==3)begin wready=1;step;wready=0;if(wv||!av)$fatal(1,"W order");cancel_now;awready=1;step;awready=0;end
     else begin awready=1;step;awready=0;if(av||!wv)$fatal(1,"AW order");if(phase==2)cancel_now;wready=1;step;wready=0;end
   end else begin
     if(phase==2)cancel_now;
     arready=1;step;arready=0;if(qv||av||wv)$fatal(1,"read channel order");
     if(phase==3)cancel_now;
   end
   if(phase==4)cancel_now;
   repeat(delay+1)begin step;if(rv||!busy)$fatal(1,"early response");end
   response=code;rdata=32'h87654321;bvalid=write_mode;rvalid=!write_mode;
   repeat(3)begin step;if(rv||br||rr)$fatal(1,"response backpressure");end
   if(phase==5)cancel=1;
   allow_rsp=1;step;bvalid=0;rvalid=0;cancel=0;
   if(busy||cancelled)$fatal(1,"not drained");
   if(phase==0)begin if(!rv||re!==(code!=0)||rd!==(write_mode?32'b0:32'h87654321))$fatal(1,"wrong completion");end
   else if(rv)$fatal(1,"stale completion after cancel");
   step;if(rv||!ready||cr)$fatal(1,"not recovered");cases=cases+1;
 end
 // A missing target response must never release a cancelled slot.
 for(write_mode=0;write_mode<2;write_mode=write_mode+1)begin
   cw=write_mode;cv=1;step;cv=0;cancel_now;
   repeat(40)begin step;if(!busy||!cr||!cancelled||ready||rv)$fatal(1,"unsafe timeout release");end
   reset=1;step;reset=0;step;
 end
 $display("PASS: bridge cases=%0d plus 2 no-response quarantines",cases);$finish;
 end
 initial begin repeat(100000)step;$fatal(1,"timeout");end
endmodule
