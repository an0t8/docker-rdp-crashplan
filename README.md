
This container starts an instance of Crashplan, with a GUI application.  
This project was copied from https://hub.docker.com/r/gfjardim/crashplan/ and modified to use my version of dockergui that exposes a RDP connection for GUI apps on a headless server.  Pairing this with a guacamole and guacd container you can access the GUI.

The original project by gfjardim contained a VNC & noVNC connection, but since I already had an ecosystem including guacamole and dockergui, I decided to port it.

# CrashPlan Container with CrashPlan Desktop App

To run this container, please use this command:


    docker run -d --name="CrashPlan" \
           --net="bridge" \
           -p 4242:4242 \
           -p 4243:4243 \
           -p 3389:3389 \
           -v "/path/to/your/crashplan/config":"/config":rw \
           -v "/path/to/your/data/dir":"/data":rw \
               an0t8/docker-rdp-crashplan

###Some supported variables:

####Variable TZ: 

This will set the correct timezone. Set yours to avoid time related issues.

```
-e TZ="America/Sao_Paulo"
```

####Variable HARDENED:

This will disable MPROTECT for grsec on Java executable (for hardened kernels).

```
-e HARDENED="Yes"
```

###Ports:

This container ports can be changed, in bridge network mode, changing the "-p" switch from the run command.

####Port 4242:

This port is used by CrashPlan for computer-to-computer backups.

####Port 4243:

This port is used by CrashPlan app to connect to CrashPlan service.

####Port 3389:

This port exposes a RDP instance with the CrashPlan Desktop App. 


You will need to use a RDP service such as quacamole to connect to the GUI.
