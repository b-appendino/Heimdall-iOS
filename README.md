This was build on macOS and tested on an iPhone 8 running iOS 16.7, jailbroken with **rootless palera1n**

# Setup Environment 
### Setup password-less SSH over USB 
- Install iProxy (macOS)
```
brew install libimobiledevice
```
- Run iProxy, forwards all traffic from port 2222 to port 22 over USB
```
iproxy 2222 22 &
```
- Copy public key to iPhone
```
ssh-copy-id -p 2222 mobile@localhost
```
- Test connection
```
ssh -p 2222 mobile@localhost
```

### Add user `mobile` to sudoers file
- Edit sudoers file
```
sudo visudo 
```
- Add:
```
mobile ALL=(ALL:ALL) NOPASSWD: ALL
```

### Install Heimdall dependencies 
```
sudo apt install lsof grep -y 
```

### Setup the Environment Variables
- In master makefile define the environment variables of the iPhone. Current values are for rootless palera1n 
`SHELL_PATH` : Defines the absolute path to the binary used to execute shell commands, e.g., bash or zsh  
`PATH` : Specifies a set of directories where executable programs are located  
`HEIMDALL_DATABASE_PATH` : The absolute path to the main database  
`APP_DUMP_DATABASE_PATH` : The absolute path to the helper database  
`DAEMON_PLIST_PATH` : The absolute path to the property list file of the daemon  
`DAEMON_LABEL` : The bundle identifier of the daemon
### Setup Theos
- [Install Theos](https://theos.dev/docs/installation)
- If not done during the Theos installation: copy [patched iOS SDK's](https://github.com/theos/sdks)  to ```~/thoes/sdks``` 
- Setup Theos variables (currently also set in master Makefile which is not pretty)
```
export THEOS=~/theos
export THEOS_MAKE_PATH=$THEOS/makesfiles
export THEOS_DEVICE_IP=localhost
export THEOS_DEVICE_PORT=2222
export THEOS_DEVICE_USER=mobile
```
# Build and install
- inside the project directory run:
```
make all
```
- to only build and install the Heimdall app or the PortResolver daemon:
```
make Heimdall
```
```
make portresolver
```
