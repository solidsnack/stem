require 'json'
require 'swirl'
require 'pp'

c = Swirl::EC2.new

CONFIG = ARGV[0]
USERDATA = ARGV[1]

config = JSON.parse File.read ARGV[0]
throw "No config" unless config

avail_zone = config["availability_zone"] || "us-east-1c"

ebs = config["volumes"].select {|v| v["media"] == "ebs"}

# XXX: check that the ebs group is ok before starting to create volumes

snapshots = []
devices = []
sizes = []
ebs.each do |v|
  puts "Adding a volume of #{v["size"]} to be mounted at #{v["device"]}."
#  volumeId = c.call("CreateVolume", "Size" => v["size"].to_s,  "AvailabilityZone" => avail_zone)["volumeId"]
#  snapshotId = c.call("CreateSnapshot", "VolumeId" => volumeId)["snapshotId"]
#  snapshots << snapshotId
  snapshots << "snap-87fcd7ef" # an empty snapshot
  devices << v["device"]
  sizes << v["size"].to_s
end

opt = {
  "Placement.AvailabilityZone" => avail_zone,
  "MinCount" => "1",
  "MaxCount" => "1",
  "KeyName" => "default",
  "ImageId" => config["ami32"],
  "BlockDeviceMapping.#.Ebs.SnapshotId" => snapshots,
  "BlockDeviceMapping.#.Ebs.VolumeSize" => sizes,
  "BlockDeviceMapping.#.DeviceName" => devices
}

if USERDATA && data = File.read(USERDATA)
  puts "Including userdata."
  opt.merge!({ "UserData" => Base64.encode64(data)})
end

pp opt

pp c.call "RunInstances", opt

