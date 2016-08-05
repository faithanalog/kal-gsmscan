#!/usr/bin/env ruby
require 'open3'

#Any signal below this power will be automatically ignored
$POWER_MIN_THRESHOLD = 120000

#Any signal which changes power by at least this much between scans
#counts as a "new" signal
$POWER_CHANGE_THRESHOLD = 250000

def scanTentativeChannels(lines)
  lines
    .select do |x|
      #The tentative channels have 'chan' followed by a space
      x.match(/^\tchan /) != nil
    end
    .map do |x|
      fields = x.split(/\s+/)
      { :channel => fields[2].to_i,
        #:frequency => fields[3][1..-6].to_f,
        :power => fields[5].to_f
      }
    end
end

def scanConfirmedChannels(lines)
  lines
    .select do |x|
      #The confirmed channels have 'chan' followed by a :
      x.match(/^\tchan:/) != nil
    end
    .map do |x|
      fields = x.split(/\s+/)
      { :channel => fields[2].to_i,
        #:frequency => fields[3][1..-4].to_f,
        :power => fields[7].to_f
      }
    end
    .select do |x|
      x[:power] >= $POWER_MIN_THRESHOLD
    end
end

def runScan
  input, _ = Open3.capture2e(
    "./kalibrate-rtl/src/kal",
    "-g", "50",
    "-s", "GSM850",
    "-t", "1",
    "-vvv")
  input
end

def diff(oldChannels, currentChannels)
  currentChannels
    .map do |nc|
      oc = oldChannels.find do |x|
        x[:channel] == nc[:channel]
      end
      if oc == nil || (oc[:power] - nc[:power]).abs >= $POWER_CHANGE_THRESHOLD
        nc
      else
        nil
      end
    end
    .select do |x|
      x != nil
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
