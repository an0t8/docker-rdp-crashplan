#!/bin/bash

#########################################
##        ENVIRONMENTAL CONFIG         ##
#########################################

# Configure user nobody to match unRAID's settings
export DEBIAN_FRONTEND="noninteractive"
mkdir -p /nobody
usermod -u 99 nobody
usermod -g 100 nobody
usermod -m -d /nobody nobody
usermod -s /bin/bash nobody
usermod -a -G adm,sudo nobody

# Disable SSH
rm -rf /etc/service/sshd /etc/service/cron /etc/my_init.d/00_regen_ssh_host_keys.sh

#########################################
##    REPOSITORIES AND DEPENDENCIES    ##
#########################################

# Repositories
cat <<'EOT' > /etc/apt/sources.list
deb http://us.archive.ubuntu.com/ubuntu/ xenial main restricted universe multiverse
deb http://us.archive.ubuntu.com/ubuntu/ xenial-security main restricted universe multiverse
deb http://us.archive.ubuntu.com/ubuntu/ xenial-updates main restricted universe multiverse
deb http://us.archive.ubuntu.com/ubuntu/ xenial-proposed main restricted universe multiverse
deb http://us.archive.ubuntu.com/ubuntu/ xenial-backports main restricted universe multiverse
EOT

# Install Dependencies
apt-get update -qq

# Install CrashPlan dependencies
apt-get install -qy --force-yes --no-install-recommends \
                grep \
                sed \
                cpio \
                gzip \
                wget \
                gtk2-engines \
                ttf-ubuntu-font-family \
                net-tools \
                paxctl

#########################################
##             INSTALLATION            ##
#########################################

sync

# Install Crashplan
TARGETDIR=/usr/local/crashplan
BINSDIR="/usr/local/bin"
CACHEDIR=/config/cache
MANIFESTDIR=/backup
INITDIR=/etc/init.d
RUNLVLDIR=/etc/rc2.d

# Downloading Crashplan
mkdir /tmp/crashplan
curl -L https://web-eam-msp.crashplanpro.com/client/installers/CrashPlanPRO_${CP_PRO_VERSION}_Linux.tgz | tar -xz --strip=1 -C /tmp/crashplan

cd /tmp/crashplan

# Adding some defaults
echo "TARGETDIR=${TARGETDIR}"     >> /tmp/crashplan/install.vars
echo "BINSDIR=${BINSDIR}"         >> /tmp/crashplan/install.vars
echo "MANIFESTDIR=${MANIFESTDIR}" >> /tmp/crashplan/install.vars
echo "INITDIR=${INITDIR}"         >> /tmp/crashplan/install.vars
echo "RUNLVLDIR=${RUNLVLDIR}"     >> /tmp/crashplan/install.vars
# echo "JRE_X64_DOWNLOAD_URL=http://192.168.0.100:88/jre-linux-x64-1.8.0_72.tgz" >> install.vars

# Creating directories
mkdir -p /usr/local/crashplan/bin /backup /etc/rc.d

# Skipping inverview
sed -i -e '/INTERVIEW=0/a source \"/tmp/install.vars\"' \
       -e 's/INTERVIEW=0/INTERVIEW=1/g' /tmp/crashplan/install.sh

# Install
yes "" | /tmp/crashplan/install.sh


# Add service to init
cat <<'EOT' > ${INITDIR}/crashplan
#!/bin/bash
BACKUP_PORT=${TCP_PORT_4242:-4242}
SERVICE_PORT=${TCP_PORT_4243:-4243}
APP_NAME="CrashPlan ${CP_VERSION}"

case "$1" in
  start)
    /usr/bin/sv start crashplan
    /usr/bin/sv start openbox
    ;;
  stop)
    /usr/bin/sv stop crashplan
    /usr/bin/sv stop openbox
    ;;
  restart)
    /usr/bin/sv restart crashplan
    /usr/bin/sv restart openbox
    ;;
  status)
    eval 'exec 6<>/dev/tcp/127.0.0.1/${SERVICE_PORT} && echo "running" || echo "stopped"' 2>/dev/null
    exec 6>&- # close output connection
    exec 6<&- # close input connection
    ;;
esac
EOT
chmod +x /etc/init.d/crashplan

# GUI Start script
cat <<'EOT' > /startapp.sh
#!/bin/bash
umask 0000

TARGETDIR=/usr/local/crashplan
export SWT_GTK3=0

. ${TARGETDIR}/install.vars
. ${TARGETDIR}/bin/run.conf

cd ${TARGETDIR}

i=0
until [ "$(/etc/init.d/crashplan status)" == "running" ]; do
  sleep 1
  let i+=1
  if [ $i -gt 10 ]; then
    break
  fi
done

${JAVACOMMON} ${GUI_JAVA_OPTS} -classpath "./lib/com.backup42.desktop.jar:./lang:./skin" com.backup42.desktop.CPDesktop \
              > /config/log/desktop_output.log 2> /config/log/desktop_error.log
EOT
chmod +x /startapp.sh

# Service Start Script
mkdir /etc/service/crashplan
cat << 'EOT' > /etc/service/crashplan/run
#!/bin/bash
umask 000

TARGETDIR=/usr/local/crashplan
if [[ -f $TARGETDIR/install.vars ]]; then
  . $TARGETDIR/install.vars
else
  echo "Did not find $TARGETDIR/install.vars file."
  exit 1
fi
if [[ -e $TARGETDIR/bin/run.conf ]]; then
  . $TARGETDIR/bin/run.conf
else
  echo "Did not find $TARGETDIR/bin/run.conf file."
  exit 1
fi
cd $TARGETDIR
FULL_CP="$TARGETDIR/lib/com.backup42.desktop.jar:$TARGETDIR/lang"
$JAVACOMMON $SRV_JAVA_OPTS -classpath "$TARGETDIR/lib/com.backup42.desktop.jar:$TARGETDIR/lang" com.backup42.service.CPService \
            > /config/log/engine_output.log 2> /config/log/engine_error.log
exit 0
EOT
chmod +x /etc/service/crashplan/run

# Crashplan init script
cat << 'EOT' > /etc/my_init.d/03_crashplan.sh
#!/bin/bash

BACKUP_PORT=${TCP_PORT_4242:-4242}
SERVICE_PORT=${TCP_PORT_4243:-4243}
APP_NAME="CrashPlan ${CP_VERSION}"

# create default dirs
mkdir -p /config/id /config/log /config/conf /config/bin /config/cache

chown -R nobody:users /config

# move identity out of container, this prevent having to adopt account every time you rebuild the Docker
if [ ! -L "/var/lib/crashplan" ]; then
  rm -rf /var/lib/crashplan
  ln -sf /config/id /var/lib/crashplan
fi

# move log directory out of container
if [ ! -L "/usr/local/crashplan/log" ]; then
  rm -rf /usr/local/crashplan/log
  ln -sf /config/log /usr/local/crashplan/log
fi

# move conf directory out of container
if [[ ! -L "/usr/local/crashplan/conf" ]]; then
  if [ ! -f "/config/conf/default.service.xml" ]; then
    cp -rf /usr/local/crashplan/conf/* /config/conf/
  fi
  rm -rf /usr/local/crashplan/conf
  ln -sf /config/conf /usr/local/crashplan/conf
fi

# move run.conf out of container
# adjust RAM as described here: http://support.code42.com/CrashPlan/Latest/Troubleshooting/CrashPlan_Runs_Out_Of_Memory_And_Crashes
if [[ ! -L "/usr/local/crashplan/bin" ]]; then
  if [ ! -f "/config/bin/run.conf" ]; then
    cp -rf /usr/local/crashplan/bin/run.conf /config/bin/run.conf
  fi
  rm -rf /usr/local/crashplan/bin
  ln -sf /config/bin /usr/local/crashplan/bin
fi

# CrashPlan
if [ -f "/config/conf/my.service.xml" ]; then
  sed -i -e "s#<location>\([^:]*\):[^<]*</location>#<location>\1:${BACKUP_PORT}</location>#g" \
         -e "s#<servicePort>[^<]*</servicePort>#<servicePort>${SERVICE_PORT}</servicePort>#g" \
         -e "s#<upgradePath>[^<]*</upgradePath>#<upgradePath>upgrade</upgradePath>#g" /config/conf/my.service.xml

  if grep "<cachePath>.*</cachePath>" /config/conf/my.service.xml > /dev/null; then
    sed -i "s|<cachePath>.*</cachePath>|<cachePath>/config/cache</cachePath>|g" /config/conf/my.service.xml
  else
    sed -i "s|<backupConfig>|<backupConfig>\n\t\t\t<cachePath>/config/cache</cachePath>|g" /config/conf/my.service.xml
  fi
fi

# Allow CrashPlan to restart
echo -e '#!/bin/sh\n/etc/init.d/crashplan restart' > /usr/local/crashplan/bin/restartLinux.sh
chmod +x /usr/local/crashplan/bin/restartLinux.sh

# Move old logs to /config/log/
find /config -maxdepth 1 -type f -iname "*.log" -exec mv '{}' /config/log/ \;

# Disable MPROTECT for grsec on java executable (for hardened kernels)
if [ -n "${HARDENED}" -a ! -f "/tmp/.hardened" ]; then
  echo "Disable MPROTECT for grsec on JAVA executable."
  source /usr/local/crashplan/install.vars
  paxctl -c "${JAVACOMMON}"
  paxctl -m "${JAVACOMMON}"
  touch /tmp/.hardened
fi
EOT
chmod +x /etc/my_init.d/03_crashplan.sh

# Clean up
cd / && rm -rf /tmp/crashplan
apt-get autoremove -y
apt-get clean -y
rm -rf /var/lib/apt/lists/* /var/cache/* /var/tmp/*
