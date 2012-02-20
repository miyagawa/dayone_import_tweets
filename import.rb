#!/usr/bin/env ruby

require 'json'
require 'open-uri'
require 'open3'
require 'date'

class Importer
  attr_reader :screen_name

  def initialize(name, page=1)
    @screen_name = name
    @new_last_id = 0
    @begin_page = page.to_i
    restore_last_id
  end

  def last_id_path
    "#{ENV['HOME']}/Dropbox/Journal.dayone/tweets_last_id.txt"
  end

  def restore_last_id
    begin
      @last_id = File.read(last_id_path).to_i
    rescue Errno::ENOENT => e
      @last_id = 0
    end
  end

  def save_last_id
    if @new_last_id > 0
      File.open(last_id_path, 'w') do |file|
        file.write @new_last_id
      end
    end
  end

  def import
    begin
      (@begin_page..@begin_page+199).each do |page|
        puts "Importing page #{page}"
        import_chunk page
      end
    rescue Done
    rescue OpenURI::HTTPError => e
      puts "You are running out of the #{e.io.meta['x-ratelimit-limit']} requests rate limit."
      puts "Try again in #{e.io.meta['x-ratelimit-reset'].to_i - Time.now.to_i} seconds."
    end
    save_last_id
  end

  def import_chunk(page)
    uri = URI.parse "https://api.twitter.com/1/statuses/user_timeline.json?screen_name=#{screen_name}&include_entities=t&page=#{page}"
    tweets = JSON.parse(uri.read).collect { |i| Tweet.new(i) }
    if tweets.empty?
      raise Done
    end
    tweets.each do |t|
      handle_tweet t
    end
  end

  def handle_tweet(tweet)
    @new_last_id = [ @new_last_id, tweet.id ].max
    if @begin_page == 1 and tweet.id <= @last_id
      raise Done
    end
    unless tweet.reply?
      import_tweet(tweet)
    end
  end

  def import_tweet(tweet)
    Open3.popen3('dayone', "-d=#{tweet.localtime}", 'new') do |stdin, stdout, stderr|
      stdin.write(tweet.text + " via " + tweet.url)
      stdin.close_write
      puts stdout.read
    end
  end
end

class Done < Exception; end

class Tweet
  def initialize(data)
    @data = data
  end

  def id
    @data['id']
  end

  def id_str
    @data['id_str']
  end

  def reply?
    /^@/.match @data['text']
  end

  def url
    "https://twitter.com/#!/#{@data['user']['screen_name']}/status/#{id_str}"
  end

  def text
    text = @data['text']
    if @data.key?('entities') and @data['entities'].key?('urls')
      @data['entities']['urls'].each do |entity|
        text.gsub! /#{entity['url']}/, entity['expanded_url']
      end
    end
    text
  end

  def localtime
    DateTime.parse(@data['created_at']).to_time.to_s
  end
end

Importer.new(*ARGV).import
