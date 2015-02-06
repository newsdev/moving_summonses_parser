#!/usr/bin/env jruby
# encoding: utf-8

# you can require this file if you'd like to use it in another script.

require 'upton'
require 'fileutils'
require 's3-publisher'
require 'aws-sdk-v1'
require 'active_record'
require 'activerecord-jdbcmysql-adapter'
require 'yaml'
require 'tabula'
require 'tmpdir'

# A list of headers, as they appear in the PDFs.
RAW_MOVING_SUMMONS_HEADERS = ["Backing Unsafely",
                              "Brake Lights (Defect. or Improper)",
                              "Bus Lane, Driving in",
                              "Cell Phone",
                              "Commercial Veh on Pkwy",
                              "Defective Brakes",
                              "Disobey Sign",
                              "Disobey Steady Red Signal",
                              "Disobey Traffic Control Device",
                              "Equipment (Other)",
                              "Fail to Keep Right",
                              "Fail to Signal",
                              "Fail to Stop on Signal",
                              "Following Too Closely",
                              "Headlights (Defect. or Improper)",
                              "Improper Lights",
                              "Improper Passing",
                              "Improper Turn",
                              "Improper/Missing Plates",
                              "Not Giving R of W to Pedes.",
                              "Not Giving R of W to Veh.",
                              "One Way Street",
                              "Pavement Markings",
                              "Safety Belt",
                              "School Bus, Passing Stopped",
                              "Speeding",
                              "Spillback",
                              "Tinted Windows",
                              "Truck Routes",
                              "U-Turn",
                              "Uninspected",
                              "Uninsured",
                              "Unlicensed Operator",
                              "Unregistered",
                              "Unsafe Lane Change",
                              "Other Movers"]

# A list of headers, in computerese
MOVING_SUMMONS_HEADERS   =   ["backing_unsafely",
                              "brake_lights",
                              "bus_lane",
                              "cell_phone",
                              "commercial_veh_on_pkwy",
                              "defective_brakes",
                              "disobey_sign",
                              "disobey_steady_red_signal",
                              "disobey_traffic_control_device",
                              "equipment",
                              "fail_to_keep_right",
                              "fail_to_signal",
                              "fail_to_stop_on_signal",
                              "following_too_closely",
                              "headlights",
                              "improper_lights",
                              "improper_passing",
                              "improper_turn",
                              "improper_missing_plates",
                              "not_giving_r_of_w_to_pedes",
                              "not_giving_r_of_w_to_veh",
                              "one_way_street",
                              "pavement_markings",
                              "safety_belt",
                              "school_bus_passing_stopped",
                              "speeding",
                              "spillback",
                              "tinted_windows",
                              "truck_routes",
                              "u_turn",
                              "uninspected",
                              "uninsured",
                              "unlicensed_operator",
                              "unregistered",
                              "unsafe_lane_change",
                              "other_movers"]

MOVING_SUMMONS_HEADER_TRANSLATION = Hash[*RAW_MOVING_SUMMONS_HEADERS.zip(MOVING_SUMMONS_HEADERS).flatten]

class MovingSummonsParser
  def initialize(config)
    @config = config
    # setup the places we're going to put our data (MySQL and a CSV for data, S3 for pdfs).
    @csv_output = @config.has_key?("csv") ? @config["csv"] : "moving_summons_stats.csv"
    open(@csv_output , 'wb'){|f| f << "precinct, month, year, " + MOVING_SUMMONS_HEADERS.join(", ") + "\n"} unless !@csv_output || File.exists?(@csv_output)
    AWS.config(access_key_id: @config['aws']['access_key_id'], secret_access_key: @config['aws']['secret_access_key']) if @config['aws']
    ActiveRecord::Base.establish_connection(:adapter => 'jdbcmysql', :host => @config['mysql']['host'], :username => @config['mysql']['username'], :password => @config['mysql']['password'], :port => @config['mysql']['port'], :database => @config['mysql']['database']) unless !@config || !@config['mysql']
    ActiveRecord::Base.connection.execute("CREATE TABLE IF NOT EXISTS moving_violations_by_precinct(precinct varchar(30), month integer, year integer, "+
      MOVING_SUMMONS_HEADERS.join(" integer,")+" integer" +
      ")") if @config["mysql"]
    ActiveRecord::Base.connection.execute("CREATE TABLE IF NOT EXISTS moving_violations_citywide(precinct varchar(30), month integer, year integer, "+
      MOVING_SUMMONS_HEADERS.join(" integer,")+" integer" +
      ")") if @config["mysql"]
  end

  def process(pdf_data, pdf_path, month, year)
    # parse the given PDF
    report = parse_pdf( pdf_data, (pdf_basename = pdf_path.split("/")[-1]), (pct = pdf_basename.split('.pdf')[0].gsub('cs', '').gsub('pct', '').gsub('sum', '') ), month, year )
    return if report.nil?
    
    # if this report is already in the database, don't put it in the DB (and assume it exists in S3, perhaps under another date)
    table_name = (report.precinct == 'city') ? 'moving_violations_citywide' : 'moving_violations_by_precinct'
    return if @config['mysql'] && ActiveRecord::Base.connection.active? && !ActiveRecord::Base.connection.execute("SELECT * FROM #{table_name} WHERE precinct = '#{report.precinct}' AND month = '#{report.month}' AND year = '#{report.year}'").empty?
    
    # add our data to MySQL, if config.yml says to.
    ActiveRecord::Base.connection.execute("INSERT INTO #{table_name}(precinct, month, year, #{MOVING_SUMMONS_HEADERS.join(',')}) VALUES (" + report.to_csv_row(true)+ ")") if @config['mysql']


    # N.B.: If there's no database, you'll get duplicate records in the CSV. 
    open(@csv_output, 'ab'){|f| f << report.to_csv_row + "\n"} if @csv_output

    puts "#{pct}: #{report.month}/#{report.year}"

    # Save the file to disk and/or S3, if specified in config.yml
    if @config['aws'] && @config['aws']['s3']
      if !@s3[config['aws']['s3']['bucket']].objects[key].exists?
        S3Publisher.publish(@config['aws']['s3']['bucket'], {logger: 'faux /dev/null'}) do |p| 
          p.push( File.join('moving_summonses', report.year.to_s, report.month.to_s, pdf_basename), 
                  data: pdf_data, gzip: false) 
        end
      end
    end
    if @config['local_pdfs_path']
      full_path = File.join(@config['local_pdfs_path'], "#{report.year}_#{report.month}_sum", pdf_basename)
      FileUtils.mkdir_p( File.dirname full_path )
      FileUtils.copy(report.path, full_path) unless File.exists?(full_path) # don't overwrite
    end
  end

  # transform a PDF into the data we want to extract
  def parse_pdf(pdf, pdf_basename, pct, month, year)
    tmp_dir = File.join(Dir::tmpdir, "moving_summons_pdfs")
    Dir.mkdir(tmp_dir) unless Dir.exists?(tmp_dir)

    # write the file to disk; we need to write the file to disk for Tabula to use it.  
    open( pdf_path = File.join(tmp_dir, pdf_basename) , 'wb'){|f| f << pdf}
    # open the file in Tabula
    begin
      page = (extractor = Tabula::Extraction::ObjectExtractor.new(pdf_path, [1])).extract.first
    rescue java.io.IOException => e
      puts "Failed to open PDF (#{pdf_basename}) #{e.message}"
      return nil
    end

    # create a report to represent the data from this report (but it's empty right now)
    report = MovingSummonsReport.new(pct, month, year, pdf_path)

    # for each table Tabula detects in the PDF
    page.spreadsheets.each do |spreadsheet|
      # and for each row in that spreadsheet
      spreadsheet.rows.each do |row|

        # get the name of the violation and the amount in this month (for this precinct)
        violation_type = row[0].text
        mtd_amount = row[1].text.gsub(',', '')

        # but skip the header
        next if violation_type.include?("Offense Description") || violation_type.include?("TOTAL Movers")
        raise IOError if mtd_amount.include?("YTD")

        # add this data to the report object
        mtd_amount = mtd_amount.to_i
        report.violations[MOVING_SUMMONS_HEADER_TRANSLATION[violation_type]] = mtd_amount
      end
    end
    extractor.close!

    # zero out any violations that aren't included in this month's report
    MOVING_SUMMONS_HEADERS.each do |violation_type|
      report.violations[violation_type] = 0 unless report.violations.has_key?(violation_type)
    end

    report
  end
end

# a class to represent the data contained in each report.
class MovingSummonsReport
  attr_reader :precinct, :month, :year, :path
  attr_accessor :violations

  def initialize pct, month, year, path
    @precinct = pct
    @month = month
    @year = year
    @path = path
    @violations = {}
  end

  def to_a
    [@precinct, @month, @year] + MOVING_SUMMONS_HEADERS.map{|h| @violations[h]}
  end

  def to_csv_row(enquote=false)
    to_a.map{|s| enquote ? "'#{s}'" : s.to_s}.join(",")
  end

end
