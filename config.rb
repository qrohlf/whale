# the location to install payloads to
INSTALL_LOCATION = '/Users/student/Desktop'

MACHINES = Hash.new { |hash, key| hash[key] = {:host => "maclabcs#{key.to_s}", :user => "student", :pass => "maclabcs#{key.to_s}"}}

# the machine that is used as the central server and file repository
SOURCE = MACHINES[22]