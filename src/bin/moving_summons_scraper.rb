#!/usr/bin/env ruby
# encoding: utf-8

# Usage:
# This tool requires you to tell it what month/year the most recent documents on the NYPD site pertain to.
# specify the month, then the year, separated by spaces
# e.g. `./bin/moving_summons_scraper.rb 12 2014`
# for Dec 2014


require_relative '../lib/moving_summons_parser.rb'

if __FILE__ == $0
  config = YAML::load_file(File.join(File.dirname(File.expand_path(__FILE__)), '..', 'config.yml')) || {}
  moving_summons_parser = MovingSummonsParser.new(config)

  month = ARGV[0].to_i
  year = ARGV[1].to_i
  raise ArgumentError, "you must specify the month, then year of these reports as the arguments to parse_local_moving_summons_reports.rb" unless month > 0 && month <= 12 && year > 2000 && year < 3000 # lol who are we kidding no one is going to use this script in 2020, let alone 2999

  # scrape the page to download each precinct's report
  scraper = Upton::Scraper.new("http://www.nyc.gov/html/nypd/html/traffic_reports/traffic_summons_reports.shtml", '.bodytext table td a')
  scraper.sleep_time_between_requests = 3
  scraper.scrape do |pdf, url| 
    next unless url.include?(".pdf")

    # process the PDFS
    moving_summons_parser.process(pdf, url, month, year) 
  end
end
