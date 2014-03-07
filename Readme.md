# Sup Miles
You can run this on one of the maclab machines or on your laptop. Just make sure you've got a ruby version that's >= 1.9.3

## Instructions

Setup: 

```bash
git clone git@github.com:qrohlf/whale.git
cd whale
git checkout miles-stuff
gem install commander colorize timeout
```

### 1. prep files
put all the stuff you want to deploy into a file called install.zip on the desktop of `student@SOURCE`.

### 2. check your connection
```
./whale.rb up
```

### 3. deploy to load-balancing servers
```
../whale.rb install --sources
```

### 4. deploy to lab
```
../whale.rb install
```

everything in install.zip will be SCP'd to the maclabs in parallel and unzipped to the desktop of the Student user.

(you can edit where the files are copied to in `config.rb:2` and add ssh commands to execute after the files are unzipped in `whale.rb:125`)

:boom: BOOM :boom:
