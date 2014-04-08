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

JOB = 'lab2.1' #the make target to build and bin file to run (bin/$filename must match make target)

# target notes:
# simpson22 causes zlib compression errors, suspect broken zlib
# scp upload fails on 29
# 25 is down today
targets = (2..29).to_a - [25, 9, 3, 29] #exclude non-working machines
startframe = 0
endframe = 72

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
  c.summary = 'check which machines are up'
  c.option '--targets', 'only check the specified targets'
  c.action do |args, options|
    puts "Checking who's up"
    threads = Array.new
    targets = (1..29) unless options.targets
    targets.each_with_index do |i, index| #todo: THREEEEAAAAAADS
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

  c.action do |args, options|
    options.default \
      mkdir: true,
      upload: true,
      compile: true

    # package installer
    puts "packaging installer"
    `cd install && make clean`
    `rm -f ./install.zip`
    `zip -r ./install.zip ./install/Makefile ./install/labs ./install/lib`

    threads = Array.new
    targets.each_with_index do |i, index| #todo: THREEEEAAAAAADS
      threads << Thread.new(i, index) do |i, index|
        target = MACHINES[i];
        
        #upload
        begin
          Net::SSH.start(target[:host], target[:user], password: target[:pass], timeout: 3) do |ssh| #if options.mkdir
            ssh.exec!("mkdir #{INSTALL_LOCATION}")
          end

          Net::SCP.upload!(target[:host], target[:user], "./install.zip", "#{INSTALL_LOCATION}/install.zip", :ssh => { password: target[:pass], compression: true}) #if options.upload
          
          print "SCP upload completed on #{target[:host]}\n".cyan
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
          ssh.exec!("cd #{INSTALL_LOCATION} && unzip -o install.zip")
          ssh.exec!("mkdir #{INSTALL_LOCATION}/install/bin")
          ssh.exec!("cd #{INSTALL_LOCATION}/install/ && make #{JOB}")
          ssh.exec!("cd #{INSTALL_LOCATION} && rm -rf install.zip")
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
    # split frames into chunks 
    framechunks = (startframe..endframe).each_slice( ((startframe..endframe).count / targets.count).floor ).to_a
    jobs = framechunks.each_with_index.map{|f, i| {frames: f, target: targets[i%targets.count]}}

    jobs.each_with_index do |job, index| #todo: THREEEEAAAAAADS
      threads << Thread.new(job, index) do |job, index|
        print "starting thread #{index}\n"
        target = MACHINES[job[:target]];
        render(job[:frames], target)
        transfer(job[:frames], target) if options.transfer
        
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
    ssh.exec!("Xvfb :30 -ac -screen 0 1024x768x24")
    print "started framebuffer on #{target[:host]}\n".green
    frames.each do |framenum|
      ssh.exec("cd #{INSTALL_LOCATION}/install && DISPLAY=':30' bin/#{JOB} lab21-mov #{framenum}")
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

