require 'swirl'
require 'json'
require 'stem/cli'

module Stem
  extend self

  def swirl
    @swirl ||= Swirl::EC2.new(
      :aws_access_key_id => ENV['AWS_ACCESS_KEY_ID'],
      :aws_secret_access_key => ENV['AWS_SECRET_ACCESS_KEY']
    )
  end

  def launch config, userdata = nil
    avail_zone = config["availability_zone"] || "us-east-1c"

    ami = nil
    if config["ami"]
      ami = config["ami"]
    elsif config["ami-name"]
      i = swirl.call "DescribeImages", "Owner" => "self"
      ami = i["imagesSet"].select {|m| m["name"] == config["ami-name"] }.map { |m| m["imageId"] }.first
    end
    throw "No AMI specified." unless ami

    opt = {
      "Placement.AvailabilityZone" => avail_zone,
      "MinCount" => "1",
      "MaxCount" => "1",
      "KeyName" => "default",
      "ImageId" => ami
    }

    opt["KeyName"] = config["key-pair"] || "default"
    opt["SecurityGroup.0"] = config["security-group"] || "default"
    opt["InstanceType"] = config["type"] if config["type"]

    if config["volumes"]
      devices = []
      sizes = []
      config["volumes"].each do |v|
        puts "Adding a volume of #{v["size"]} to be mounted at #{v["device"]}."
        devices << v["device"]
        sizes << v["size"].to_s
      end

      opt.merge! "BlockDeviceMapping.#.Ebs.VolumeSize" => sizes,
                 "BlockDeviceMapping.#.DeviceName" => devices
    end

    if userdata
      puts "Userdata provided, encoded and sent to the instance."
      opt.merge!({ "UserData" => Base64.encode64(userdata)})
    end

    response = swirl.call "RunInstances", opt

    puts "Success!"
    response["instancesSet"].each do |i|
      return i["instanceId"]
    end
  end

  def capture name, instance
    description = {} # more to come here...
    swirl.call "CreateImage", "InstanceId" => instance, "Name" => name, "Description" => "%%" + description.to_json
  end

  def allocate_ip
    swirl.call("AllocateAddress")["publicIp"]
  end

  def associate_ip ip, instance
    result = swirl.call("AssociateAddress", "InstanceId" => instance, "PublicIp" => ip)["return"]
    result == true
  end

  def list
    instances = swirl.call("DescribeInstances")

    lookup = {}
    instances["reservationSet"].each {|r| r["instancesSet"].each { |i| lookup[i["imageId"]] = nil } }
    amis = swirl.call("DescribeImages", "ImageId" => lookup.keys)["imagesSet"]

    amis.each do |ami|
      name = ami["name"]
      if !ami["description"] || ami["description"][0..1] != "%%"
        # only truncate ugly names from other people (never truncate ours)
        name.gsub!(/^(.{8}).+(.{8})/) { $1 + "..." + $2 }
        name = "(foreign) " + name
      end
      lookup[ami["imageId"]] = name
    end

    instances["reservationSet"].each do |r|
      r["instancesSet"].each do |i|
        name = lookup[i["imageId"]]
        puts "%-15s %-15s %-15s %s" % [ i["instanceId"], i["ipAddress"] || "no ip", i["instanceState"]["name"], name ? name : i["imageId"]]
      end
    end
  end

  def restart instance_id
    swirl.call "RebootInstances", "InstanceId" => instance_id
  end

end
