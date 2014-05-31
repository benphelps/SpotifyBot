require 'uri'
require 'text'
require 'mustache'

module Mumbletune

  class Message

    # class methods

    class << self
      attr_accessor :template
    end
    self.template = Hash.new

    def self.parse(client, data)
      message = Message.new(client, data)

      message.text = message.text.gsub("<p>", "").gsub("</p>", "")
      puts "[Debug] #{message.sender.name} issued bot command: '#{message.text}'"

      begin
        case message.text

          when /^play/i
            if message.argument.length > 0 # user wants to play something
              if message.words.last =~ /now/i
                play_now = true
                message.argument = message.words[1...message.words.length-1].join(" ")
              else
                play_now = false
              end

              no_song = nil

              Thread.new {
                sleep 5
                if no_song == nil # Check if setting the collection timed out...
                  puts "Lost connection to Spotify/Mumble! Stopping!"
                  `kill -9 #{Process.pid}` # force kill process
                end
              }

              collection = Mumbletune.resolve(message.argument) # This can time out and freeze...
              no_song = "I couldn't find what you wanted me to play. :'("

              # handle unknown argument
              return message.respond no_song unless collection

              # associate the collection with a user
              collection.user = message.sender.name

              # add these tracks to the queue
              Mumbletune.player.add_collection(collection, play_now)

              if play_now
                message.respond_all "#{message.sender.name} is playing #{collection.description} RIGHT NOW."
              else
                message.respond_all "#{message.sender.name} added #{collection.description} to the queue."
              end

            else # user wants to unpause
              if Mumbletune.player.paused?
                Mumbletune.player.play
                message.respond "Unpaused."
              else
                message.respond "Not paused."
              end
            end

          when /^queue/i
            if message.argument.length > 0 # user has something to play

              return message.respond "No other songs in queue! Use 'play <Song>'!" unless Mumbletune.player.empty?

              collection = Mumbletune.resolve(message.argument) # This can time out and freeze...

              # handle unknown argument
              return message.respond "I couldn't find what you wanted me to play. :'(" unless collection

              # associate the collection with a user
              collection.user = message.sender.name

              # add these tracks to the queue
              Mumbletune.player.add_collection(collection, false, true)

              message.respond_all "#{message.sender.name} added #{collection.description} to the queue."
            end

          when /^pause$/i
            paused = Mumbletune.player.pause
            response = (paused) ? "Paused." : "Unpaused."
            message.respond response

          when /^unpause$/i
            if Mumbletune.player.paused?
              Mumbletune.player.play
              message.respond "Unpaused."
            else
              message.respond "Not paused."
            end


          when /^next$/i
            if Mumbletune.player.any?
              Mumbletune.player.next
              current = Mumbletune.player.current_track
              message.respond_all "#{message.sender.name} skipped to #{current.artist.name} - #{current.name}" if current
            else
              message.respond "We're at the end of the queue. Try adding something to play!"
            end

          when /^clear$/i
            Mumbletune.player.clear_queue
            message.respond_all "#{message.sender.name} cleared the queue."

          when /^undo$/i
            removed = Mumbletune.player.undo
            if message.sender.name == removed.user
              message.respond_all "#{message.sender.name} removed #{removed.description}."
            else
              message.respond_all "#{message.sender.name} removed #{removed.description} at #{removed.user} added."
            end

          when /^(what)$/i
            message.respond Mumbletune.player.get_rendered_queue

          when /^volume\?$/i
            message.respond "The volume is #{Mumbletune.mumble.volume}."

          when /^volume/i
            if message.argument.length == 0
              message.respond "The volume is #{Mumbletune.mumble.volume}."
            else
              if Integer(message.argument) > 100
                message.argument = "100"
              end
              Mumbletune.mumble.volume = message.argument
              message.respond "Now the volume is #{Mumbletune.mumble.volume}."
            end

          when /^help$/i
            rendered = Mustache.render Message.template[:commands]
            message.respond rendered

          when /^itsfucked$/i
            puts "Force killed by #{message.sender.name}"
            `kill -9 #{Process.pid}`

          else # Unknown command was given.
            rendered = Mustache.render Message.template[:commands],
                                       :unknown => {:command => message.text}
            message.respond rendered
        end

      rescue => err # Catch any command that errored.
        message.respond "Woah, an error occurred: #{err.message}"
        unless Mumbletune.verbose
          puts "#{err.class}: #{err.message}"
          puts err.backtrace
        end
      end
    end


    # instance methods

    attr_accessor :client, :sender, :text, :command, :argument, :words

    def initialize(client, data)
      @client = client
      @sender = client.users[data[:actor]] # users are stored by their session ID
      @me = client.me
      @text = data[:message]

      @words = @text.split
      @command = words[0]
      @argument = words[1...words.length].join(" ")
    end

    def respond(message)
      @client.text_user(@sender.session, message)
    end

    def respond_all(message) # send to entire channel
      @client.text_channel(@me.channel_id, message)
    end
  end

  # load templates
  Dir.glob(File.dirname(__FILE__) + "/template/*.mustache").each do |f_path|
    f = File.open(f_path)
    Message.template[File.basename(f_path, ".mustache").to_sym] = f.read
  end
end