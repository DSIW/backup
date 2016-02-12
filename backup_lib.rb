# encoding: utf-8

require "date"
require "time"
require "yaml"

module BackupLib
  HOME = "/home/dsiw"
  CACHE_FILE_PATH = "#{HOME}/.lastbackups"
  CONFIG = YAML.load_file(File.join('/etc', 'borg', 'config.yml'))
  BACKUPS  = CONFIG['backups']

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

  class SSHConfig
    attr_reader :path

    def initialize(path = nil)
      path = File.join(ENV['HOME'], '.ssh', 'config') if path.to_s.length == 0
      @path = path
    end

    def hosts
      @hosts ||= parse
    end

    private

    def parse
      raw_datasets = []
      current_dataset = []
      File.readlines(@path).each do |line|
        line = line.chomp.sub(/^\s+/, '').sub(/\s*#.*$/, '')
        next if line.start_with? '#'

        if line =~ /Host .*/
          raw_datasets << current_dataset unless current_dataset.empty?
          current_dataset = []
        end

        current_dataset << line unless line.empty?
      end

      # last entry
      raw_datasets << current_dataset unless current_dataset.empty?

      datasets = raw_datasets.reduce({}) do |hash, raw_dataset|
        key = raw_dataset[0].split(/\s+/)[1..-1].join(' ')
        options = Hash[raw_dataset[1..-1].map { |option| option.split(/\s+/) }]
        hash.merge!(key => options)
      end
    end
  end

  class Interval
    YEAR_OLD = 1990
    DATE_OLD = DateTime.new(YEAR_OLD, 1, 1)

    attr_reader :name
    attr_reader :name

    def self.all
      names.map { |name| new(name.to_s) }
    end

    def self.olds
      all.select { |interval| interval.old? }
    end

    def self.names
      BACKUPS.keys
    end

    def self.dirnames
      BACKUPS.keys.map do |key|
        BACKUPS[key]['dirname']
      end
    end

    def self.from_config_file
      @from_config_file ||= CacheFile.new.read
    end

    def self.from_backup_dir
      @from_backup_dir ||= begin
        groups = {}
        names.each do |name|
          begin
            interval = Interval.new(name)
            raise "Not mounted" unless interval.mounted?
            output = `#{BACKUPS[name]['sudo'] ? 'sudo' : ''} borg list #{interval.destination}/#{BACKUPS[name]['dirname']} | tail -1`.chomp
            raw_date = output.match(/^(?<name>.*?)\s+/)[:name]
            if raw_date.to_s == ""
              date = DATE_OLD
            else
              date = DateTime.strptime(raw_date, BACKUPS[name]['naming'])
            end
            groups[name] = date
          rescue Exception => e
            groups[name] = from_config_file[name]
          end
        end
        groups
      end
    end

    def initialize(name)
      @name = name.to_s
    end

    def setting
      SETTINGS_BY_INTERVAL[interval.to_sym]
    end

    def interval
      backup_config['min_interval']
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

    def mounted?
      if remote? && active_vpn?
        `ping -W 1 -c 1 #{host} >/dev/null`
        $? == 0 # connected
      else
        File.exist?(destination) && !Dir.glob("#{destination}/*/").empty?
      end
    end

    def active_vpn?
      `ifconfig | grep -q tun0`
      $? == 0
    end

    def remote?
      destination.include? ':'
    end

    def destination
      destination_config['path']
    end

    def destination_host
      destination_config['path'].split(':')[0]
    end

    def vpn_config
      destination_config['vpn_conf']
    end

    def dirname
      backup_config['dirname']
    end

    def destination_key
      backup_config['destination_key']
    end

    def host
      (destination_config['host'] || ssh_hostname).to_s
    end

    def notify(message)
      notification_port = destination_config['notification_port'].to_s
      if !host.nil? && !notification_port.nil? && message.to_s.length > 0
        system('message_ping', host, notification_port, "'#{message.gsub("'", '"')}'")
      end
    end

    def last_date
      last_dates = self.class.from_config_file
      last_dates[name] || DATE_OLD
    end

    def live_last_date
      last_dates = self.class.from_backup_dir
      last_dates[name] || DATE_OLD
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

    def ssh_hostname
      ssh_config = SSHConfig.new
      ssh_hosts = ssh_config.hosts
      ssh_host = destination.split(':').first
      unless ssh_hosts.has_key? ssh_host
        raise "Host #{ssh_host} not found in #{ssh_config.path}!"
      end
      ssh_hosts[ssh_host]['HostName']
    end

    def destination_config
      CONFIG['destinations'][destination_key]
    end

    def backup_config
      BACKUPS[name] || {}
    end

    # Convert current time to UTC because `last_date` is set to UTC
    def now_without_timezone
      Time.parse(Time.now.strftime('%Y-%m-%d %H:%M:%S UTC'))
    end
  end

  class IntervalPresenter
    attr_reader :object

    def initialize(object, options = {})
      @object = object
      @options = options
    end

    def message
      [dirname, old.ljust(26), ago].join(' ')
    end

    def dirname
      object.dirname.ljust(Interval.dirnames.map(&:length).max + 1)
    end

    def old
      old? ? Utils.colorize('needs backup', :red) : Utils.colorize('UP TO DATE', :green)
    end

    def ago
      if never_executed?
        "(never executed)"
      else
        "(#{Utils.pluralize(duration, *units)} ago at #{@object.last_date.strftime('%F %H:%M')})"
      end
    end

    private

    def old?
      @options[:force_old] ? true : object.old?
    end

    def method_missing(meth, *args, &blk)
      if object.respond_to? meth
        object.send(meth, *args, &blk)
      else
        super
      end
    end
  end

  class CacheFile
    def initialize
      @file_path = File.expand_path(CACHE_FILE_PATH)
    end

    def write(intervals)
      File.open(@file_path, 'w') do |file|
        intervals.each do |interval|
          file.puts [interval.name, interval.live_last_date.strftime('%FT%H:%M:%S')].join(';')
        end
      end
    end

    def read
      groups = Interval.all.reduce({}) do |hash, key|
        hash.merge(key => Interval::DATE_OLD)
      end

      File.open(@file_path, "r") do |file|
        file.each_line do |line|
          name, last_date = line.chomp.split(';')
          groups[name] = Time.parse(last_date)
        end
      end

      groups
    end
  end
end
