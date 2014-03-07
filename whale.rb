#!/usr/bin/env ruby
require 'rubygems'
require 'net/ssh'
require 'net/scp'
require 'commander/import'
require './config.rb'
require 'timeout'
require 'colorize'

program :name, 'whale'
program :version, '0.0.1'
program :description, 'network control system'

@always_trace = true
@never_trace = false

# target notes:
# simpson22 causes zlib compression errors, suspect broken zlib
# scp upload fails on 29
# 16 was down last time I checked
sources = (1..4) #[2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 17, 18, 19, 20, 21, 23, 24, 25, 26, 27, 28];
targets = (5..22)
totalframes = 72

chunksize = (totalframes.to_f / targets.count).ceil;


command :run do |c|
  c.syntax = 'whale run "[command --opts]"'
  c.summary = 'run a command on all machines'
  c.action do |args, options|
    cmd = args.first;
    ssh_all(targets) do |ssh, user, host|
      puts "#{user}@#{host}$ #{cmd}"
      puts ssh.exec!(cmd);
    end
  end
end

command :up do |c|
  c.syntax = 'whale up'
  c.summary = 'check which targets are up'
  c.action do |args, options|
    puts "Checking who's up"
    threads = Array.new
    (1..29).each_with_index do |i, index| #todo: THREEEEAAAAAADS
      threads << Thread.new(i, index) do |i, index|
        target = MACHINES[i]
        up = false
        begin 
          Net::SSH.start(target[:host], target[:user], :password => target[:pass], :timeout => 3) do |ssh|
            up = true if ssh.exec!('hostname')
          end
        rescue Exception
          
        end

        if up
          print "#{target[:host]} is #{'up'.green}\n" 
        else
          print "#{target[:host]} is #{'down'.red}\n" 
        end
      end
    end
    # wait for all threads to finish
    threads.each(&:join) #this is hanging on the transfer
    puts "Check Complete".cyan
  end
end

command :clean do |c|
  c.syntax = 'whale clean'
  c.summary = 'clean the results dir'
  c.description = ''
  c.action do |args, options|
    `rm -f results/*`
    puts "deleted stale results"
  end
end

command :install do |c|
  c.syntax = 'whale install --mkdir -n numberofmachines -f framelimit'
  c.summary = 'distributed rendering'
  c.description = ''
  c.option '--[no-]mkdir', 'skip creating the install dir'
  c.option '--[no-]upload', 'skip uploading the installer'
  c.option '--[no-]compile', 'skip unzipping and compiling the installer'
  c.option '--sources', 'deploy from SOURCE to sources for load-balancing'

  c.action do |args, options|
    options.default \
      mkdir: true,
      upload: true,
      compile: true,
      sources: false

    targets = sources if options.sources

    threads = Array.new
    targets.each_with_index do |i, index| #todo: THREEEEAAAAAADS
      next if MACHINES[i] == SOURCE; #don't do it on maclabcs1
      
      if i == 1 # double-check to make sure you're not being an idiot
        puts "wrong wrong wrong"
        next
      end
      threads << Thread.new(i, index) do |i, index|
        target = MACHINES[i];
        #mkdir

        source = MACHINES[sources.to_a.sample] #load balancing I AM A SORCERER
        copy = scp_auto(source[:user], source[:host], source[:pass], "/Users/student/Desktop/install.zip", "/Users/student/#{INSTALL_LOCATION}")
        
        #upload
        begin
          Net::SSH.start(target[:host], target[:user], password: target[:pass], timeout: 3) do |ssh| #if options.mkdir
            ssh.exec!("mkdir #{INSTALL_LOCATION}")
            ssh.exec!("rm -rf /Users/student/Desktop/install.zip") # scp doesn't like to clobber
            print "Starting SCP on #{target[:host]} (source #{source[:host]}) \n".magenta
            ssh.exec!(copy)
            print "SCP transfer completed on #{target[:host]}\n".cyan
          end
        rescue Net::SSH::AuthenticationFailed
          print "SSH Authentication failed on #{target[:host]}\n".red
          Thread.exit
        rescue Net::SCP::Error => e
          print "SCP upload failed on #{target[:host]}\n".red
          Thread.exit
        rescue Timeout::Error
          print "SSH timed out on #{target[:host]}\n".red
          Thread.exit
        end
        
        # install 
        # run whatever installation commands you want to here
        Net::SSH.start(target[:host], target[:user], password: target[:pass], timeout: 3) do |ssh| #if options.compile
          print "Unzipping your junk on #{target[:host]}\n".magenta
          ssh.exec!("cd #{INSTALL_LOCATION} && unzip -o install.zip")
          # ssh.exec!("cd #{INSTALL_LOCATION} && rm -rf install.zip")
          print "Done unzipping your junk on #{target[:host]}\n".cyan
          ssh.exec!("cd #{INSTALL_LOCATION} && mv quinn kaliVM")
        end
        print "Install complete on #{target[:host]}\n".green
      end
    end
    threads.each(&:join) #this is hanging on the transfer
    puts "Install Complete".cyan
  end
end

command :render do |c|
  c.syntax = 'whale render'
  c.summary = 'distributed rendering'
  c.description = ''
  c.option '--transfer', 'download the results'

  c.action do |args, options|
    `rm -f results/*`
    puts "deleted stale results".white

    puts "rendering files".white
    threads = Array.new
    targets.each_with_index do |i, index| #todo: THREEEEAAAAAADS
      threads << Thread.new(i, index) do |i, index|
        print "starting thread #{index}\n"
        target = MACHINES[i];
        startframe = chunksize*index
        endframe = startframe+chunksize-1
        endframe = totalframes if endframe > totalframes
        render(startframe..endframe, target)
        transfer(startframe..endframe, target) if options.transfer
        
        print "exiting thread #{index}\n"
      end
    end
    # wait for all threads to finish
    threads.each(&:join) #this is hanging on the transfer
    puts "Rendering Complete".cyan
    puts "Transfer Complete".cyan if options.transfer
  end
end

command :transfer do |c|
  c.syntax = 'whale transfer'
  c.summary = 'distributed rendering'
  c.description = ''

  c.action do |args, options|
    `rm -f results/*`
    puts "deleted stale results".white

    puts "transferring files".white
    threads = Array.new
    targets.each_with_index do |i, index| #todo: THREEEEAAAAAADS
      threads << Thread.new(i, index) do |i, index|
        print "starting thread #{index}\n"
        target = MACHINES[i];
        startframe = chunksize*index
        endframe = startframe+chunksize-1
        endframe = totalframes if endframe > totalframes
        transfer(startframe..endframe, target)
        
        print "exiting thread #{index}\n"
      end
    end
    # wait for all threads to finish
    threads.each(&:join)
    puts "Transfer Complete"
  end
end

def render(frames, target) 
  Net::SSH.start(target[:host], target[:user], :password => target[:pass], :timeout => 5) do |ssh|
    #clean previous run synchronously
    ssh.exec!("cd #{INSTALL_LOCATION}/install && rm -rf ./*.xwd")
    #start framebuffer synchronously
    print "starting framebuffer on #{target[:host]}\n"
    ssh.exec!("Xvfb :30 -ac -screen 0 1024x768x24")
    frames.each do |framenum|
      ssh.exec("cd #{INSTALL_LOCATION}/install && DISPLAY=':30' bin/lab2.1 lab21-mov #{framenum}")
    end
    ssh.loop #wait for all frames to finish rendering
  end
end

# make sure ./results exists!!!
def transfer(frames, target)
  files = frames.map { |f| "#{INSTALL_LOCATION}/install/lab21-mov#{sprintf("%04d", f)}.xwd" }
  print("transferring frames #{frames.first} to #{frames.last} from #{target[:host]}\n".blue)
  begin
    transfers = Array.new
    Net::SCP.start(target[:host], target[:user], {password: target[:pass], compression: true}) do |scp|
      files.each do |file|
        transfers << scp.download(file, "./results/")
      end
    end
    transfers.each{|t| t.wait}
    print "All transfers completed on #{target[:host]}\n".green
  rescue Exception => e
    puts e
    printf "error caused by machine #{target[:host]}.\n".red
  end
end


def ssh_all(machines, options = {})
  machines.each do |i| 
      target = MACHINES[i];
      puts "############ initiating SSH to #{target[:host]} ############"
      if target[:host] == SOURCE[:host]
        puts "Skipping #{target[:host]} (control server)"
        next
      end

      begin 
        Net::SSH.start(target[:host], target[:user], password: target[:pass], timeout: 3) do |ssh|
          yield ssh, target[:user], target[:host]
        end
      rescue Timeout::Error
        puts "Connection timed out on #{target[:host]}"
      rescue Net::SSH::AuthenticationFailed
        puts "Authentication failed on #{target[:host]}"
      rescue IOError
        puts "SSH session closed by target"
      rescue Errno::ECONNREFUSED
        puts "SSH connection refused by target"
      end
      puts "\n"
    end
  end

def scp_all(machines, file, dest)
  machines.each do |i| 
      target = MACHINES[i];
      puts "############ initiating SCP to #{target[:host]} ############"
      begin
        Net::SCP.upload!(target[:host], target[:user], file, dest, :ssh => { :password => target[:pass] })
        puts "SCP upload to #{target[:host]} successful"
      rescue Net::SCP::Error
        puts "SCP to #{target[:host]} unsuccessful"
      end
    end
  end

def scp_auto(user, host, password, file, dest) 
  "expect -c \"spawn scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null #{user}@#{host}:#{file} #{dest}
    set timeout 5
    expect {
        \"*Password:*\" { send #{password}\\n; interact }
        eof { exit }
        timeout { puts \\n--TIMEOUT!--\\n;exit}
    }
    exit\""
end



