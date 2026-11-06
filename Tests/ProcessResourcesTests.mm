#import "VEEngine.h"
#include <sys/resource.h>
#include <sys/wait.h>
#include <unistd.h>
#include <cmath>
#include <cstdio>

static double CPU(){rusage r{};getrusage(RUSAGE_SELF,&r);return r.ru_utime.tv_sec+r.ru_utime.tv_usec/1e6+r.ru_stime.tv_sec+r.ru_stime.tv_usec/1e6;}
int main(){@autoreleasepool{
  NSDictionary *before=VEProcessResources();
  if(![before[@"complete"] boolValue] || [before[@"footprintBytes"] unsignedLongLongValue]==0)return 1;
  rusage old{};getrusage(RUSAGE_CHILDREN,&old);
  pid_t child=fork();if(child<0)return 2;
  if(child==0){double start=CPU();while(CPU()-start<0.30){};_exit(0);}
  usleep(100000);NSDictionary *live=VEProcessResources();int status=0;waitpid(child,&status,0);
  NSDictionary *after=VEProcessResources();rusage current{};getrusage(RUSAGE_CHILDREN,&current);
  if(![live[@"complete"] boolValue] || ![after[@"complete"] boolValue])return 3;
  double measured=([after[@"cpuNanoseconds"] doubleValue]-[before[@"cpuNanoseconds"] doubleValue])/1e9;
  double reference=current.ru_utime.tv_sec+current.ru_utime.tv_usec/1e6+current.ru_stime.tv_sec+current.ru_stime.tv_usec/1e6-old.ru_utime.tv_sec-old.ru_utime.tv_usec/1e6-old.ru_stime.tv_sec-old.ru_stime.tv_usec/1e6;
  bool pass=std::abs(measured-reference)<0.06 && reference>=0.28 && measured>=0.28 && measured<0.70
    && [after[@"cpuNanoseconds"] doubleValue]>=[live[@"cpuNanoseconds"] doubleValue]
    && [live[@"processCount"] intValue]>[before[@"processCount"] intValue];
  NSDictionary *result=@{@"passed":@(pass),@"familyCPUSeconds":@(measured),@"getrusageChildCPUSeconds":@(reference),
    @"liveProcessCount":live[@"processCount"],@"afterReapProcessCount":after[@"processCount"],@"memoryCounterAvailable":@YES};
  NSData *data=[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:nil];fwrite(data.bytes,1,data.length,stdout);fputc('\n',stdout);return pass?0:4;
}}
