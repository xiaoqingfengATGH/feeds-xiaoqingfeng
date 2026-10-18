#define _GNU_SOURCE
#include <arpa/inet.h>
#include <errno.h>
#include <linux/filter.h>
#include <linux/if_packet.h>
#include <net/ethernet.h>
#include <net/if.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>
int main(int argc,char **argv){
 if(argc!=4)return 2;
 struct in_addr a;if(!inet_aton(argv[2],&a))return 2;
 int seconds=atoi(argv[3]);if(seconds<1||seconds>120)return 2;
 unsigned ip=ntohl(a.s_addr);
 struct sock_filter f[]={
 BPF_STMT(BPF_LD|BPF_B|BPF_ABS,0),BPF_STMT(BPF_ALU|BPF_AND|BPF_K,0xf0),BPF_JUMP(BPF_JMP|BPF_JEQ|BPF_K,0x40,0,16),
 BPF_STMT(BPF_LD|BPF_B|BPF_ABS,9),BPF_JUMP(BPF_JMP|BPF_JEQ|BPF_K,6,0,14),
 BPF_STMT(BPF_LD|BPF_W|BPF_ABS,12),BPF_JUMP(BPF_JMP|BPF_JEQ|BPF_K,ip,2,0),
 BPF_STMT(BPF_LD|BPF_W|BPF_ABS,16),BPF_JUMP(BPF_JMP|BPF_JEQ|BPF_K,ip,0,10),
 BPF_STMT(BPF_LDX|BPF_B|BPF_MSH,0),
 BPF_STMT(BPF_LD|BPF_H|BPF_IND,0),BPF_JUMP(BPF_JMP|BPF_JEQ|BPF_K,18444,3,0),
 BPF_STMT(BPF_LD|BPF_H|BPF_IND,2),BPF_JUMP(BPF_JMP|BPF_JEQ|BPF_K,18444,1,0),
 BPF_STMT(BPF_RET|BPF_K,0),BPF_STMT(BPF_MISC|BPF_TXA,0),
 BPF_STMT(BPF_ALU|BPF_ADD|BPF_K,20),BPF_STMT(BPF_RET|BPF_A,0),
 BPF_STMT(BPF_RET|BPF_K,0),BPF_STMT(BPF_RET|BPF_K,0)};
 struct sock_fprog prog={sizeof(f)/sizeof(f[0]),f};
 int s=socket(AF_PACKET,SOCK_DGRAM,htons(ETH_P_ALL));if(s<0){perror("socket");return 3;}
 struct sockaddr_ll bindaddr={.sll_family=AF_PACKET,.sll_protocol=htons(ETH_P_ALL),.sll_ifindex=if_nametoindex(argv[1])};
 if(!bindaddr.sll_ifindex||setsockopt(s,SOL_SOCKET,SO_ATTACH_FILTER,&prog,sizeof(prog))||bind(s,(void*)&bindaddr,sizeof(bindaddr))){perror("filter/bind");close(s);return 4;}
 setvbuf(stdout,NULL,_IOLBF,0);printf("READY interface=%s peer=%s tcp_port=18444 seconds=%d headers_only no_promisc\n",argv[1],argv[2],seconds);
 time_t end=time(NULL)+seconds;unsigned count=0;
 while(time(NULL)<end){struct pollfd p={s,POLLIN,0};if(poll(&p,1,500)<=0)continue;
 unsigned char b[80];struct sockaddr_ll from;socklen_t len=sizeof(from);ssize_t n=recvfrom(s,b,sizeof(b),0,(void*)&from,&len);
 if(n<40)continue;
 unsigned h=(b[0]&15)*4;if(h<20||n<(ssize_t)h+20)continue;
 char src[INET_ADDRSTRLEN],dst[INET_ADDRSTRLEN];inet_ntop(AF_INET,b+12,src,sizeof(src));inet_ntop(AF_INET,b+16,dst,sizeof(dst));
 unsigned sp=((unsigned)b[h]<<8)|b[h+1],dp=((unsigned)b[h+2]<<8)|b[h+3];
 printf("epoch=%ld if=%s direction=%s src=%s:%u dst=%s:%u flags=0x%02x iplen=%u captured=%ld\n",(long)time(NULL),argv[1],from.sll_pkttype==PACKET_OUTGOING?"out":"in",src,sp,dst,dp,b[h+13],((unsigned)b[2]<<8)|b[3],(long)n);count++;
 }
 printf("END packets=%u\n",count);close(s);return 0;
}
