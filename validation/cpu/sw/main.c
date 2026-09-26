#include <stdint.h>
#define REG(o) (*(volatile uint32_t *)(0x10000000u+(o)))
static void putc_uart(char c) { while(REG(4)&1u) {} REG(0)=(uint8_t)c; }
static void puts_uart(const char *s) { while(*s) putc_uart(*s++); }
static volatile uint32_t initialized=0x12345678;
static volatile uint32_t scratch[8];
extern int hazard_test(void);
static void fail(void) { REG(0x10)=0xee; puts_uart("SELFTEST FAIL\r\n"); for(;;) {} }
static void selftest(void) {
  if(hazard_test()!=0) fail();
  if(initialized!=0x12345678 || scratch[0]!=0) fail();
  scratch[0]=0x11223344;
  volatile uint8_t *b=(volatile uint8_t *)scratch;
  b[1]=0x80; b[3]=0xfe;
  if(scratch[0]!=0xfe228044) fail();
  if(*(volatile int8_t *)(b+1)!=-128) fail();
  volatile uint16_t *h=(volatile uint16_t *)scratch;
  h[1]=0x8001;
  if(scratch[0]!=0x80018044 || *(volatile int16_t *)(h+1)!=-32767) fail();
  volatile int32_t a=-123, c=7;
  if(a*c!=-861 || a/c!=-17 || a%c!=-4) fail();
  uint32_t t=REG(0x20);
  while((uint32_t)(REG(0x20)-t)<100) {}
  REG(0x10)=0xa5;
  if(REG(0x10)!=0xa5 || REG(0x28)!=0) fail();
}
int main(void) {
  puts_uart("VEX MINI RV32IM\r\n");
  selftest();
  puts_uart("SELFTEST PASS\r\n");
  uint32_t prev=2, next=REG(0x20), period=REG(0x24)/10;
  uint8_t pattern=1;
  for(;;) {
    uint32_t key=REG(0x14)&1;
    if(key!=prev) { puts_uart(key ? "KEY=1\r\n" : "KEY=0\r\n"); prev=key; }
    if(REG(4)&2) putc_uart((char)REG(0));
    if((int32_t)(REG(0x20)-next)>=0) {
      REG(0x10)=pattern; pattern=(uint8_t)((pattern<<1)|(pattern>>7)); next+=period;
    }
  }
}
