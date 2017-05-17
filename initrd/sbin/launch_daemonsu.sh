#!/system/bin/sh

MODE=$1

log_print() {
  echo "($MODE) $1"
  echo "($MODE) $1" >> /dev/.launch_daemonsu.log
  log -p i -t launch_daemonsu "($MODE) $1"
}

log_print "start"

if [ -d "/su/bin" ]; then
  if [ `ps | grep -v "launch_daemonsu.sh" | grep "daemonsu" >/dev/null 2>&1; echo $?` -eq 0 ]; then
    # nothing to do here
    log_print "abort: daemonsu already running"
    exit
  fi
fi

setprop sukernel.daemonsu.launch $MODE

REBOOT=false

# do we have an APK to install ?
if [ -f "/cache/SuperSU.apk" ]; then
  cp /cache/SuperSU.apk /data/SuperSU.apk
  rm /cache/SuperSU.apk
fi
if [ -f "/data/SuperSU.apk" ]; then
  log_print "installing SuperSU APK in /data"

  APKPATH=eu.chainfire.supersu-1
  for i in `ls /data/app | grep eu.chainfire.supersu- | grep -v eu.chainfire.supersu.pro`; do
    if [ `cat /data/system/packages.xml | grep $i >/dev/null 2>&1; echo $?` -eq 0 ]; then
      APKPATH=$i
      break;
    fi
  done
  rm -rf /data/app/eu.chainfire.supersu-*

  log_print "target path: /data/app/$APKPATH"

  mkdir /data/app/$APKPATH
  chown 1000.1000 /data/app/$APKPATH
  chmod 0755 /data/app/$APKPATH
  chcon u:object_r:apk_data_file:s0 /data/app/$APKPATH

  cp /data/SuperSU.apk /data/app/$APKPATH/base.apk
  chown 1000.1000 /data/app/$APKPATH/base.apk
  chmod 0644 /data/app/$APKPATH/base.apk
  chcon u:object_r:apk_data_file:s0 /data/app/$APKPATH/base.apk

  rm /data/SuperSU.apk

  sync

  # just in case
  REBOOT=false
fi

# sometimes we need to reboot, make it so
if ($REBOOT); then
  log_print "rebooting"
  if [ "$MODE" = "post-fs-data" ]; then
    # avoid device freeze (reason unknown)
    sh -c "sleep 5; reboot" &
  else
    reboot
  fi
  exit
fi

# if other su binaries exist, route them to ours
mount -o bind /su/bin/su /sbin/su 2>/dev/null
mount -o bind /su/bin/su /system/bin/su 2>/dev/null
mount -o bind /su/bin/su /system/xbin/su 2>/dev/null

# poor man's overlay on /system/xbin
if [ -d "/su/xbin_bind" ]; then
  busybox cp -f -a /system/xbin/. /su/xbin_bind
  rm -rf /su/xbin_bind/su
  ln -s /su/bin/su /su/xbin_bind/su
  mount -o bind /su/xbin_bind /system/xbin
fi

# start daemon
if [ "$MODE" != "post-fs-data" ]; then
  # if launched by service, replace this process (exec)
  log_print "exec daemonsu"
  exec /su/bin/daemonsu --auto-daemon
else
  # if launched by exec, fork (non-exec) and wait for su.d to complete executing
  log_print "fork daemonsu"
  /su/bin/daemonsu --auto-daemon

  # wait for a while for su.d to complete
  if [ -d "/su/su.d" ]; then
    log_print "waiting for su.d"
    for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16; do
      # su.d finished ?
      if [ -f "/dev/.su.d.complete" ]; then
        break
      fi

      for j in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16; do
        # su.d finished ?
        if [ -f "/dev/.su.d.complete" ]; then
          break
        fi

        # sleep 240ms if usleep supported, warm up the CPU if not
        # 16*16*240ms=60s maximum if usleep supported, else much shorter
      done
    done
  fi
  log_print "end"
fi
