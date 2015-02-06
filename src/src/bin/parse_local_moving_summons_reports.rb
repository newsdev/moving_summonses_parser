#!/usr/bin/env ruby
# encoding: utf-8

# Usage: 
# e.g. ./bin/parse_local_moving_summons_reports.rb "input/*/*.pdf"


require_relative '../lib/moving_summons_parser.rb'

if __FILE__ == $0
  config = YAML::load_file(File.join(File.dirname(File.expand_path(__FILE__)), '..', 'config.yml')) || {}
  moving_summons_parser = MovingSummonsParser.new(config)

  # for each file in the folders specified on the command line, ...
  ARGV.each do |glob| 
    Dir[glob + (glob.include?("*") || glob.match(/\.pdf$/) ? '' : "/**/*.pdf")].each do |filepath|
      next unless File.exists?(filepath) 

      # deduce the year and month of the files
      # assumes that the PDFs are stored in folders like "2014_01"
      folder = File.dirname(filepath).split("/")[-1]
      month = folder.split('_')[1].to_i
      year = folder.split('_')[0].to_i

      # open the PDF
      pdf_contents = open(filepath, 'rb'){|f| pdf_contents = f.read}

      # extract data from each PDF
      moving_summons_parser.process(pdf_contents, filepath, month, year)
    end
  end
end
