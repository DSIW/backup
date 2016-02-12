# Backup

Backup your files using `borg` with different intervals and destinations.

## Example output

```
DESTINATION: wd
home    UP TO DATE   (0 days ago at 2016-02-12 18:00)
system  UP TO DATE   (0 weeks ago at 2016-02-10 15:28)
media   UP TO DATE   (0 weeks ago at 2016-02-10 15:29)

DESTINATION: jokke (remote)
home    needs backup (never executed)
system  needs backup (never executed)

'home' (jokke) backup started
VPN connection already established
Connected to jokke-backup
[Borg output]

'system' (jokke) backup started
VPN connection already established
Connected to jokke-backup
[Borg output]

Don't forget to unmount!
```

## Requirements

* Ruby
* Gem [colorize](https://rubygems.org/gems/colorize) (optional)
* `borg`
* `pass`
* `openvpn`

## Installation

1. Install `borg`
1. Install `pass`
1. Install `openvpn`
1. Install gem: `gem install colorize`
1. Move `backup`, `borg-backup` and `backup_lib.rb` to a directory which is added to `$PATH`
1. Change `BackupLib::HOME` in `backup_lib.rb` to your home path. Don't $HOME, because of running with sudo
1. Copy `config.yaml` to `/etc/borg/config.yaml` and make changes
1. Add pass file `encryption/backup` via `pass generate encryption/pass`

I recommend using `ssh-agent` and `gpg-agent`.

## First backup

1. `borg init ...`
1. Start `backup -n`

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
