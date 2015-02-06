#!/usr/bin/env ruby

# Usage:
# Argument 1 (optional): location to put zips
# e.g. `./bin/scrape_old_moving_summons_reports.rb input_zips`

# Downloads and parses ZIP files of per-precinct moving summons reports, e.g.:
# http://www.nyc.gov/html/nypd/downloads/zip/traffic_data/2011_08_acc.zip

require 'net/http'
require 'fileutils'

DATA_START = {month: 8, year: 2011}

Time.new.month

failed = []
config = YAML::load_file(File.join(File.dirname(File.expand_path(__FILE__)), '..', 'config.yml')) || {}
data_folder =  config.has_key?("local_pdfs_path") ? config["local_pdfs_path"] : "input"

zip_folder = File.absolute_path "#{ARGV[0]||input_zips}/zips/"
FileUtils.mkdir_p(zip_folder)

while year <= Time.new.year do
  for month_i in 1..12.to_a.each do
    next if year == DATA_START[:year] && month < DATA_START[:month]
    next if year == Time.new.year     && month >= Time.new.month
    begin
      month = month_i.to_s.rjust(2, "0")

      zip_url = "http://www.nyc.gov/html/nypd/downloads/zip/traffic_data/#{year}_#{month}_sum.zip"
      zip_filename = zip_url.split("/")[-1]
      zip_path = File.join(zip_folder, zip_filename)
      unless File.exists?(zip_path)
        open(zip_path, 'wb') do |f|
          puts zip_url
          f << Net::HTTP.get(URI(zip_url))
        end
      end

      unzip_dest = "input/#{zip_filename.split('.')[0]}"
      unless Dir.exists?(unzip_dest)
        unzip_cmd = "unzip #{zip_path} -d #{unzip_dest}"
        puts unzip_cmd
        `#{unzip_cmd}`
      else
        # puts "#{unzip_dest}"
      end
    rescue Exception => e
      puts e
      puts e.inspect
      failed << zip_url 
    end
  end
  year += 1
end

puts "failed: #{failed.inspect}" unless failed.empty?
