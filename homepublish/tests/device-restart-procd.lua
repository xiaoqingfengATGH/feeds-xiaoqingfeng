-- Actual target rc.common/procd, uniquely named service, private daemon/store/socket.
arg[3]='procd'
dofile(assert(arg[1])..'/device-restart-daemon.lua')
