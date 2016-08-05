#!/usr/bin/env ruby
require 'open3'

#Any signal below this power will be automatically ignored
$POWER_MIN_THRESHOLD = 120000

#Any signal which changes power by at least this much between scans
#counts as a "new" signal
$POWER_CHANGE_THRESHOLD = 250000

#Path to kal command used for scanning
$KAL_PATH = "./kalibrate-rtl/src/kal"

#Frequency bands to scan
$FREQUENCY_BANDS = ["GSM850"]

def scanConfirmedChannels(lines)
  lines
    .select do |x|
      #The confirmed channels have 'chan' followed by a :
      x.match(/^\tchan:/) != nil
    end
    .map do |x|
      fields = x.split(/\s+/)
      { :channel => fields[2].to_i,
        :power => fields[7].to_f
      }
    end
    .uniq do |x|
      #Ensure we dont have channels in there twice.
      #This could happen if the script is configured to scan overlapping bands.
      x[:channel]
    end
end

def runScan
  #Run a scan for each frequency band, combining the results
  $FREQUENCY_BANDS
    .map do |band|
      input, _ = Open3.capture2e(
        $KAL_PATH,
        "-g", "50",
        "-s", band,
        "-t", "1",
        "-p", $POWER_MIN_THRESHOLD.to_s,
        "-vvv")
      input
    end
    .join "\n"
end

#Find channels in the current set which either did not exist in the
#previous set of channels, or has changed in power by an amount
#greater than $POWER_CHANGE_THRESHOLD
def diff(oldChannels, currentChannels)
  currentChannels
    .select do |nc|
      oc = oldChannels.find do |x|
        x[:channel] == nc[:channel]
      end
      oc == nil || (oc[:power] - nc[:power]).abs >= $POWER_CHANGE_THRESHOLD
    end
end

def displayChannels(channels)
  puts "== Current Scan =="
  channels.each do |c|
    puts "chan: #{c[:channel]}\tpower: #{c[:power]}"
  end
end

oldChannels = scanConfirmedChannels(runScan.lines)
displayChannels(oldChannels)
puts
puts

while true
  currentChannels = scanConfirmedChannels(runScan.lines)
  addedChannels = diff(oldChannels, currentChannels)
  removedChannels = diff(currentChannels, oldChannels)

  if addedChannels.length > 0 || removedChannels.length > 0
    puts "----------------------"
    puts "!! Removed Channels !!"
    removedChannels.each do |c|
      puts "    chan: #{c[:channel]}\tpower: #{c[:power]}"
    end
    puts
    puts
    puts "!! Added Channels !!"
    addedChannels.each do |c|
      puts "    chan: #{c[:channel]}\tpower: #{c[:power]}"
    end
    puts
    puts
    displayChannels(currentChannels)
    puts "----------------------"
    puts
    puts
  else
    puts "Scan done. No changes."
  end

  oldChannels = currentChannels
end
