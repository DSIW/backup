# encoding: utf-8

require "date"
require "time"

module BackupLib
  HOME = ENV['HOME']
  SOURCE = "home"
  CCOLLECT_CONF = "/etc/ccollect"
  BACKUP_DIR = File.read("#{CCOLLECT_CONF}/sources/#{SOURCE}/destination").chomp
  DEFAULT_INTERVALS = %w[daily weekly monthly yearly]
  CONFIG_FILE_PATH = "#{HOME}/.lastbackups"

  SETTINGS_BY_INTERVAL = {
    yearly: {
      format: '%Y',
      factor: 60*60*24*365, # from seconds
      units: ['year', 'years']
    },
    monthly: {
      format: '%Y%m',
      human_format: '%m',
      factor: 60*60*24*31, # from seconds
      units: ['month', 'months']
    },
    weekly: {
      format: '%Y%V',
      parse_format: '%Y%m%d',
      human_format: '%V',
      factor: 60*60*24*7, # from seconds
      units: ['week', 'weeks']
    },
    daily: {
      format: '%Y%m%d',
      human_format: '%d',
      factor: 60*60*24, # from seconds
      units: ['day', 'days']
    },
    hourly: {
      format: '%Y%m%d%H%z',
      human_format: '%H',
      factor: 60*60, # from seconds
      units: ['hour', 'hours']
    }
  }

  class Interval
    YEAR_OLD = 1990
    DATE_OLD = DateTime.new(YEAR_OLD, 1, 1)

    module SOURCES
      BACKUP_DIR = "backup_dir"
      CONFIG_FILE = "config_file"
    end

    def self.source=(source)
      @source = source
    end

    def self.source
      @source || SOURCES::BACKUP_DIR
    end

    attr_reader :name

    def self.all
      from_names(SETTINGS_BY_INTERVAL.keys)
    end

    def self.used
      from_names(OPTIONS[:intervals])
    end

    def self.from_names(names)
      names.map { |name| new(name.to_s) }
    end

    def self.olds
      used.select { |interval| interval.old? }
    end

    def self.names
      all.map(&:name)
    end

    def self.last_dates_by_interval
      send("from_#{source}")
    end

    def self.from_config_file
      ConfigFile.new.read
    end

    def self.from_backup_dir
      groups = {}
      all.map(&:name).each { |interval| groups[interval] = [] }

      # group dir names by interval
      Dir.glob("#{BACKUP_DIR}/*/").each do |dir_name|
        found_interval = dir_name.scan(Regexp.union(Interval.names)).first
        groups[found_interval] << dir_name
      end

      # convert last dir name to date
      all.map(&:name).each do |interval|
        last_dir = groups[interval].sort.last
        if last_dir
          raw_date = File.basename(last_dir).scan(/\d{8}-\d{4}/).first
          date = DateTime.strptime(raw_date, "%Y%m%d-%H%M")
        else
          date = DATE_OLD
        end
        groups[interval] = date
      end

      groups
    end

    def initialize(name)
      @name = name.to_s
    end

    def setting
      SETTINGS_BY_INTERVAL[name.to_sym]
    end

    def active?
      OPTIONS[:intervals].include? name
    end

    def format
      setting[:format]
    end

    def units
      setting[:units]
    end

    def human_date_format
      setting[:human_format]
    end

    def last_date
      self.class.last_dates_by_interval[name]
    end

    def last_date_without_useless_information
      date_format = setting[:parse_format] || format
      DateTime.strptime(last_date.strftime(date_format), date_format) # remove useless information (e.g. hours for daily backup)
    end

    def duration
      duration = (now_without_timezone - last_date_without_useless_information.to_time).to_i # seconds
      duration / setting[:factor]
    end

    def old?
      duration > 0
    end

    def never_executed?
      last_date.year == YEAR_OLD
    end

    private

    # Convert current time to UTC because `last_date` is set to UTC
    def now_without_timezone
      Time.parse(Time.now.strftime('%Y-%m-%d %H:%M:%S UTC'))
    end
  end

  class ConfigFile
    def initialize
      @file_path = File.expand_path(CONFIG_FILE_PATH)
    end

    def write(intervals)
      File.open(@file_path, 'w') do |file|
        intervals.each do |interval|
          file.puts [interval.name, interval.last_date.strftime('%FT%H:%M:%S')].join(';')
        end
      end
    end

    def read
      groups = Interval.all.reduce({}) do |hash, key|
        hash.merge(key => Interval::DATE_OLD)
      end

      File.open(@file_path, "r") do |file|
        file.each_line do |line|
          interval_name, last_date = line.chomp.split(';')
          groups[interval_name] = Time.parse(last_date)
        end
      end

      groups
    end
  end
end
