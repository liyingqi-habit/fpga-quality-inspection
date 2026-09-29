// Test-only independent target. CPU-local reset is intentionally NOT an input.
module cancel_target(
 input wire clk,reset,allow_aw,allow_w,allow_ar,never_old,
 input wire [7:0] delay_cycles,input wire [1:0] old_code,
 input wire av,output wire ar,input wire [31:0] aa,
 input wire wv,output wire wr,input wire [31:0] wd,input wire [3:0] ws,
 output reg bv=0,input wire br,output reg [1:0] bc=0,
 input wire qv,output wire qr,input wire [31:0] qa,
 output reg pv=0,input wire pr,output reg [31:0] pd=0,output reg [1:0] pc=0,
 output reg [31:0] old_memory=32'h11223344,
 output reg commit=0,output reg [31:0] commit_addr=0,commit_data=0
);
 reg have_a=0,have_w=0,have_q=0,applied=0;
 reg [31:0] addr=0,data=0,raddr=0;reg[3:0] mask=0;
 integer age=0,lane;
 assign ar=allow_aw&&!have_a&&!bv;
 assign wr=allow_w&&!have_w&&!bv;
 assign qr=allow_ar&&!have_q&&!pv;
 always @(posedge clk)begin
  commit<=0;
  if(reset)begin
   have_a<=0;have_w<=0;have_q<=0;applied<=0;bv<=0;pv<=0;age<=0;old_memory<=32'h11223344;
  end else begin
   if(av&&ar)begin have_a<=1;addr<=aa;end
   if(wv&&wr)begin have_w<=1;data<=wd;mask<=ws;end
   if(qv&&qr)begin have_q<=1;raddr<=qa;end
   if(have_a&&have_w&&!bv)begin
    if(!applied)begin
     applied<=1;
     // Selected policy: errors have no memory effect; cancellation does not roll back success.
     if(addr!=32'h10000000 || old_code==0)begin
      commit<=1;commit_addr<=addr;commit_data<=data;
      if(addr==32'h10000000)for(lane=0;lane<4;lane=lane+1)
       if(mask[lane])old_memory[lane*8+:8]<=data[lane*8+:8];
     end
    end
    age<=age+1;
    if(age>=delay_cycles && !(never_old&&addr==32'h10000000))begin bv<=1;bc<=addr==32'h10000000 ? old_code : 0;end
   end
   if(have_q&&!pv)begin
    age<=age+1;
    if(age>=delay_cycles && !(never_old&&raddr==32'h10000000))begin
     pv<=1;pc<=raddr==32'h10000000 ? old_code : 0;
     pd<=raddr==32'h10000000 ? 32'hdeadbeef : 32'hcafebabe;
    end
   end
   if(bv&&br)begin bv<=0;have_a<=0;have_w<=0;applied<=0;age<=0;end
   if(pv&&pr)begin pv<=0;have_q<=0;age<=0;end
  end
 end
endmodule
