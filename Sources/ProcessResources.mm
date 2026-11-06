#import "VEEngine.h"
#include <libproc.h>
#include <mach/mach_time.h>
#include <sys/resource.h>
#include <unistd.h>
#include <cerrno>
#include <set>
#include <vector>

// Read only this browser's descendants. No process names, URLs or page data.
// proc_listchildpids returns a PID count (the buffer size is still in bytes).
// https://github.com/apple-oss-distributions/xnu/blob/main/libsyscall/wrappers/libproc/libproc.c
static bool VEFamily(std::set<pid_t>& family) {
  family.clear();family.insert(getpid());
  std::vector<pid_t> pending{getpid()};
  for(size_t index=0;index<pending.size();++index) {
    errno=0;int count=proc_listchildpids(pending[index],nullptr,0);
    if(count<0 || (count==0 && errno!=0)) return false;
    size_t capacity=static_cast<size_t>(count)+16;
    for(;;) {
      if(capacity>4096) return false;
      std::vector<pid_t> children(capacity);
      errno=0;count=proc_listchildpids(pending[index],children.data(),static_cast<int>(children.size()*sizeof(pid_t)));
      if(count<0 || (count==0 && errno!=0)) return false;
      if(static_cast<size_t>(count)>=capacity){capacity*=2;continue;}
      for(int i=0;i<count;++i)if(children[i]>0 && family.insert(children[i]).second)pending.push_back(children[i]);
      break;
    }
    if(family.size()>4096) return false;
  }
  return true;
}

NSDictionary<NSString *,id> *VEProcessResources(void) {
  @autoreleasepool {
    mach_timebase_info_data_t timebase{};
    if(mach_timebase_info(&timebase)!=KERN_SUCCESS || !timebase.denom)return @{@"complete":@NO};
    for(int attempt=0;attempt<3;++attempt) {
      std::set<pid_t> before,after;
      if(!VEFamily(before))continue;
      long double ticks=0;uint64_t memory=0,rootStarted=0;bool valid=true;
      for(pid_t pid:before) {
        rusage_info_v2 info{};
        if(proc_pid_rusage(pid,RUSAGE_INFO_V2,reinterpret_cast<rusage_info_t *>(&info))!=0){valid=false;break;}
        // Reaped descendants are rolled into their parent by XNU. Include
        // them so a renderer exit cannot make cumulative family CPU decrease.
        ticks+=static_cast<long double>(info.ri_user_time)+info.ri_system_time+info.ri_child_user_time+info.ri_child_system_time;
        memory+=info.ri_phys_footprint;
        if(pid==getpid())rootStarted=info.ri_proc_start_abstime;
      }
      if(!valid || !VEFamily(after) || before!=after)continue;
      return @{@"complete":@YES,@"cpuNanoseconds":@(static_cast<double>(ticks*timebase.numer/timebase.denom)),
        @"footprintBytes":@(memory),@"processCount":@(before.size()),@"rootStarted":@(rootStarted)};
    }
    // A partial process tree must not masquerade as a smaller successful read.
    return @{@"complete":@NO};
  }
}
