#!/usr/bin/env ruby

require 'rubygems'
require 'xml'
require 'time'
require 'optparse'

# Parse command line arguments
options = {}
optparse = OptionParser.new do |opts|
  opts.banner = "Usage: convert.rb [options]"
  
  options[:input_dir] = File.expand_path('~/Documents/Colloquy Transcripts')
  opts.on('-i', '--input INPUT_DIR', 'The directory containing the Colloquy transcripts') do |input|
    options[:input_dir] = File.expand_path(input)
  end
  
  options[:output_dir] = File.expand_path('~/Library/Application Support/Adium 2.0/Users/Default/Logs')
  opts.on('-o', '--output OUTPUT_DIR', 'The directory to output Adium chatlogs') do |output|
    options[:output_dir] = File.expand_path(output)
  end
  
  options[:nickname] = nil
  opts.on('-n', '--nickname NICKNAME', 'The account name to use (IRC nickname)') do |account|
    options[:nickname] = account
  end
  
  opts.on_tail('-h', '--help', 'Display this screen') do
    puts opts
    exit
  end
end
optparse.parse!

puts "Reading Colloquy logs from #{options[:input_dir]}"
puts "Outputting Adium logs to #{options[:output_dir]}"
puts ""

# Open Colloquy transcripts
Dir.glob("#{options[:input_dir]}/**/*.colloquyTranscript").each do |filename|
  parser = XML::Parser.file(filename)
  doc = parser.parse
  
  # See if we can find the nickname
  if nick = doc.find_first('/log/envelope/sender[@self]')
    nickname = nick.content
  else
    nickname = options[:nickname]
  end
  
  # Create our new Adium chatlog
  newdoc = XML::Document.new();
  newdoc.root = XML::Node.new('chat')
  newdoc.root['xmlns'] = 'http://purl.org/net/ulf/ns/0.4-02'
  newdoc.root['account'] = nickname
  newdoc.root['service'] = 'IRC'
  adium = newdoc.root
  
  # Start
  adium << elem = XML::Node.new('event')
  elem['type'] = 'windowOpenened'
  elem['sender'] = nickname
  elem['time'] = Time.parse(doc.root['began']).iso8601
  
  # Loop through each element
  doc.root.children.each do |element|
    case element.name
    when 'event'
  
      # Left the room
      if element['name'] == 'parted'
        adium << event = XML::Node.new('event')
        event['type'] = 'windowClosed'
        event['sender'] = nickname
        event['time'] = Time.parse(element['occurred']).iso8601
        next
      end
  
      who = element.find('who')[0]
  
      adium << status = XML::Node.new('status')
      status['time'] = Time.parse(element['occurred']).iso8601
      status << div = XML::Node.new('div')
  
      # What kind of event?
      case element['name']
      when 'memberJoined'
        status['type'] = 'purple'
        div << "#{who.content} ["
        div << italic = XML::Node.new('span', who['hostmask'])
        italic['style'] = 'font-style: italic;'
        div << "] entered the room."
      when 'memberParted'
        status['type'] = 'purple'
        reason = element.find('reason')[0]
        if reason.nil?
          div << "#{who.content} left the room."
        else
          div << "#{who.content} left the room (#{reason.content})."
        end
      when 'disconnected'
        status['type'] = 'disconnected'
        status['sender'] = nickname
        div << 'You have disconnected'
      when 'rejoined'
        status['type'] = 'connected'
        div << 'You have connected'
      end
  
    when 'envelope'
      # envelopes contain multiple messages from the same sender
      sender = element.find('sender')[0].content
      element.find('message').each do |message|
        adium << msg = XML::Node.new('message')
        msg['sender'] = sender
        msg['time'] = Time.parse(message['received']).iso8601
        msg << div = XML::Node.new('div')
        div << XML::Node.new_text(message.content)
      end
    end
  end

  # Construct filename
  prefix = filename.split('/').last.split(' ')[0]
  begin_time = Time.parse(doc.root['began']).iso8601.reverse.gsub(':', '.').sub('.', '').reverse
  output_file = "#{prefix} (#{begin_time}).chatlog"
  output_path = "#{options[:output_dir]}/IRC.#{nickname}/#{prefix}"
  
  # Make directories if necessary
  Dir.mkdir(options[:output_dir]) if !File.directory?(options[:output_dir])
  Dir.mkdir("#{options[:output_dir]}/IRC.#{nickname}") if !File.directory?("#{options[:output_dir]}/IRC.#{nickname}")
  Dir.mkdir(output_path) if !File.directory?(output_path)
  
  # Output the new logfile
  newdoc.save("#{output_path}/#{output_file}",  :indent => false)
  puts "Processed #{output_file}"
  
end

puts ""
puts "Completed!"