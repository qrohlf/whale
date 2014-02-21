#!/usr/bin/env ruby
require 'rubygems'
require 'net/ssh'
require 'net/scp'
require 'commander/import'
require './config.rb'
require 'timeout'

program :name, 'manatee'
program :version, '0.0.1'
program :description, 'network control system'


targets = [2, 3, 4, 5, 6, 7, 9, 10, 11, 12];
totalframes = 72


command :run do |c|
  c.syntax = 'manatee run "[command --opts]"'
  c.summary = 'run a command on all machines'
  c.description = ''
  c.action do |args, options|
    cmd = args.first;
    ssh_all(targets) do |ssh, user, host|
      puts "#{user}@#{host}$ #{cmd}"
      puts ssh.exec!(cmd);
    end
  end
end

command :clean do |c|
  c.syntax = 'manatee clean'
  c.summary = 'clean the results dir'
  c.description = ''
  c.action do |args, options|
    `rm -f results/*`
    puts "deleted stale results"
  end
end

command :install do |c|
  c.syntax = 'manatee install --mkdir -n numberofmachines -f framelimit'
  c.summary = 'distributed rendering'
  c.description = ''
  c.option '--mkdir', 'create install directory'
  c.option '--upload', 'upload the installer'
  c.option '--compile', 'unzip and compile the installer'
  
  c.action do |args, options|

    puts "packaging installer"
    `./package_installer.sh`
    
    puts "creating install directory"
    ssh_all(targets) do |ssh, user, host|
      ssh.exec!("mkdir #{INSTALL_LOCATION}")
      puts "success!"
    end

    puts "uploading installer"
    scp_all((targets), "./install.zip", "#{INSTALL_LOCATION}/install.zip");
    puts "\n"

    # compile files
    puts "compiling renderer"
    ssh_all(targets) do |ssh, user, host|
      puts "...connection established"
      ssh.exec!("cd #{INSTALL_LOCATION} && unzip -o install.zip")
      puts "...installer unzipped"
      ssh.exec!("mkdir #{INSTALL_LOCATION}/install/bin")
      puts "...bin directory created"
      ssh.exec!("cd #{INSTALL_LOCATION}/install/ && make lab2.1")
      puts "...lab2.1 compiled"
    end
  end
end

command :render do |c|
  c.syntax = 'manatee render'
  c.summary = 'distributed rendering'
  c.description = ''
  c.option '--transfer', 'download the results'

  c.action do |args, options|
    `rm -f results/*`
    puts "deleted stale results"

    puts "rendering files"
    threads = Array.new
    targets.each_with_index do |i, index| #todo: THREEEEAAAAAADS
      threads << Thread.new(i, index) do |i, index|
        print "starting thread #{index}\n"
        target = MACHINES[i];
        startframe = (totalframes/targets.count+1)*index
        endframe = startframe+(totalframes/targets.count+1)-1
        endframe = totalframes if endframe > totalframes
        render(startframe..endframe, target)
        transfer(startframe..endframe, target) if options.transfer
        
        print "exiting thread #{index}\n"
      end
    end
    # wait for all threads to finish
    threads.each(&:join)
    puts "Rendering Complete"
  end
end

command :transfer do |c|
  c.syntax = 'manatee transfer'
  c.summary = 'distributed rendering'
  c.description = ''

  c.action do |args, options|
    `rm -f results/*`
    puts "deleted stale results"

    puts "transferring files"
    threads = Array.new
    targets.each_with_index do |i, index| #todo: THREEEEAAAAAADS
      threads << Thread.new(i, index) do |i, index|
        print "starting thread #{index}\n"
        target = MACHINES[i];
        startframe = (totalframes/targets.count+1)*index
        endframe = startframe+(totalframes/targets.count+1)-1
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
    ssh.exec("cd #{INSTALL_LOCATION}/install && rm -rf ./*.xwd")
    #start framebuffer synchronously
    print "starting framebuffer on #{target[:host]}\n"
    ssh.exec!("Xvfb :30 -ac -screen 0 1024x768x24")
    frames.each do |framenum|
      ssh.exec("cd #{INSTALL_LOCATION}/install && DISPLAY=':30' bin/lab2.1 lab21-mov #{framenum}")
    end
    ssh.loop #wait for all frames to finish rendering
  end
end

def transfer(frames, target)
  files = frames.map { |f| "#{INSTALL_LOCATION}/install/lab21-mov#{sprintf("%04d", f)}.xwd" }
  print("transferring frames #{frames.first} to #{frames.last} from #{target[:host]}\n")
  transfers = Array.new
  Net::SCP.start(target[:host], target[:user], :password => target[:pass]) do |scp|
    files.each do |file|
      transfers << scp.download(file, "./results/")
    end
  end
  transfers.each{|t| t.wait}
  print "All transfers completed on #{target[:host]}\n"
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
        Net::SSH.start(target[:host], target[:user], :password => target[:pass], :timeout => 3) do |ssh|
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
