# the location to install payloads to
INSTALL_LOCATION = '/home/student/.manatee'

MACHINES = Hash.new { |hash, key| hash[key] = {:host => "simpson#{key.to_s}.lclark.edu", :user => "student", :pass => "student"}}

# the machine that is used as the central server and file repository
SOURCE = MACHINES[22]