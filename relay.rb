#!/usr/bin/env ruby

require 'yaml'
require 'thread'
require 'xmpp4r'
require 'xmpp4r/muc'
require 'isaac/bot'

module SophSec
  module XMPP
    module IRC
      class Relay < Isaac::Bot

        include Jabber

        FLOOD_LIMIT = 2.0

        def initialize(options={},&block)
          @xmpp_user= JID.new(options[:xmpp][:user])
          @xmpp_password = options[:xmpp][:password]

          @xmpp_channel = JID.new(options[:xmpp][:channel])
          @xmpp_channel.resource ||= @xmpp_user.resource

          @irc_channel = "##{options[:irc][:channel]}"

          @flood_limit = (options[:irc][:flood_limit] || FLOOD_LIMIT)
          @mesg_queue = Queue.new

          super()

          configure do |c|
            c.nick = options[:irc][:nick]
            c.server = options[:irc][:server]
            c.port = options[:irc][:port] if options[:irc][:port]
          end

          on :connect do
            puts "Joining #{@irc_channel}"
            join @irc_channel

            @xmpp = Client.new(@xmpp_user)

            puts "Connecting to #{@xmpp_user.domain}"
            @xmpp.connect

            puts "Logging in as #{@xmpp_user}"
            @xmpp.auth(@xmpp_password) if @xmpp_password

            @muc = MUC::SimpleMUCClient.new(@xmpp)
            @muc.on_message { |time,nick,text| to_irc(nick,text) }

            puts "Joining #{@xmpp_channel}"
            @muc.join(@xmpp_channel)

            @consumer = Thread.new do
              loop do
                sleep(@flood_limit)
                msg('#sophsec',@mesg_queue.pop)
              end
            end

            puts "Relaying messages between #{@xmpp_channel} and #{@irc_channel} on #{@config.server}:#{@config.port}"
          end

          on :channel do
            to_xmpp(nick,message)
          end
        end

        def self.start(options={})
          self.new(options).start
        end

        def start
          begin
            super()
          rescue Interrupt
          ensure
            @consumer.kill if (@consumer && @consumer.alive?)
            @muc.exit if (@muc && @muc.active?)
            @xmpp.close if @xmpp
          end
        end

        protected

        def to_xmpp(from,text)
          if @muc
            @muc.say("#{from}: #{text}") unless text.strip.empty?
          end
        end

        def to_irc(from,text)
          unless from == @xmpp_channel.resource
            text.each_line do |line|
              @mesg_queue << "#{from}: #{line.chomp}"
            end
          end
        end

      end
    end
  end
end

SophSec::XMPP::IRC::Relay.start(YAML.load_file(ARGV[0])) if ARGV[0]
