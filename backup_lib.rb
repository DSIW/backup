# encoding: utf-8

require 'date'
require 'time'
require 'yaml'
require 'open3'
require 'shellwords'
require 'socket'

module BackupLib
  HOME = "/home/dsiw"
  CACHE_FILE_PATH = "#{HOME}/.lastbackups"
  CONFIG_HOME = ENV['XDG_CONFIG_HOME'] || File.join(ENV['HOME'], '.config')
  [CONFIG_HOME, '/etc'].each do |dir|
    config_file = File.join(dir, 'borg', 'config.yml')
    if File.exist?(config_file)
      CONFIG = YAML.load_file(config_file)
      break
    end
  end
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
          interval = Interval.new(name)
          if interval.mounted?
            output = interval.execute_command({}, "borg list '#{interval.repo}' | tail -1")
            output = nil if output == ""
            raw_date = output && output.match(/^(?<name>.*?)\s+/)[:name]
            if raw_date.to_s == ""
              date = DATE_OLD
            else
              date = DateTime.strptime(raw_date, BACKUPS[name]['naming'])
            end
            groups[name] = date
          else
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
        connected?
      else
        File.exist?(destination) && !Dir.glob("#{destination}/*/").empty?
      end
    end

    def active_vpn?
      `ifconfig | grep -q tun0`
      $? == 0
    end

    def connected?(options = {})
      options ||= {}
      max_times = options[:try] || 1
      max_times.times do |i|
        yield(max_times - i) if block_given?
        `ping -W 1 -c 1 #{host} >/dev/null`
        return true if $? == 0
      end

      false
    end

    def remote?
      destination.include? ':'
    end

    def execute_command(env, args, options = {})
      env ||= {}
      args = [args] if args.is_a? String

      # add passphrase
      if destination_config['encrypted']
        passphrase = `pass show encryption/backup | head -1`.chomp
        env['BORG_PASSPHRASE'] = passphrase
      end

      # add sudo
      args.unshift 'sudo' if backup_config['sudo']

      command = args.join(' ')

      # execute command
      exit_status = nil
      output = nil
      if options[:continous_output]
        system(env, command)
        exit_status = $?
      else
        Open3.popen3(env, command) do |stdin, stdout, stderr, wait_thread|
          stdin.close
          exit_status = wait_thread.value
          output = exit_status.success? ? stdout.read : stderr.read
        end
      end

      # throw execption
      unless exit_status.success?
        env_string = env.map {|k, v| [k,v].join('=')}.join(' ')
        abort("#{output}\nCommand failed.\nDo you have connection to borg repository #{repo}?\nTry it manually:\n#{env_string} #{command}")
      end

      output
    end

    def repo
      File.join(destination, dirname)
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
        socket = TCPSocket.new(host, notification_port)
        socket.puts message
        socket.close
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

    def execute_backup!
      Executor.new(self).start
    end

    def backup_config
      BACKUPS[name] || {}
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

      File.open(@file_path, 'r') do |file|
        file.each_line do |line|
          name, last_date = line.chomp.split(';')
          groups[name] = Time.parse(last_date)
        end
      end

      groups
    end
  end

  class Executor
    def initialize(interval)
      @interval = interval
    end

    def start
      execute_all(backup_config['run_before'])
      execute_with_continous_output(create_command)
      execute_with_continous_output(prune_command) if backup_config['prune']
      execute_all(backup_config['run_after'])
    end

    private

    def create_command
      name = Time.now.strftime(backup_config['naming'])

      additional_args = []
      %w(exclude exclude-if-present).each do |option|
        next unless backup_config[option]
        additional_args << backup_config[option].reduce([]) { |args, pattern| [*args, "--#{option}", "'#{pattern}'"] }
      end

      additional_flags = convert_to_flags(backup_config['flags'])
      additional_flags.flatten!

      ['borg', 'create', '-C', backup_config['compression'], *additional_args, *additional_flags, "#{@interval.repo}::#{name}", *backup_config['sources']]
    end

    def prune_command
      keepings = backup_config['prune'].reduce([]) { |args, (k, v)| [*args, "--keep-#{k}", v.to_s] }
      ['borg', 'prune', *keepings, @interval.repo]
    end

    def convert_to_flags(flags)
      (backup_config['flags'] || []).map { |flag| "--#{flag}" }
    end

    def execute_all(commands)
      (commands || []).all? { |cmd| @interval.execute_command({}, cmd) }
    end

    def execute_with_continous_output(cmd)
      @interval.execute_command({}, cmd, continous_output: true)
    end

    def backup_config
      @interval.backup_config
    end
  end
end
