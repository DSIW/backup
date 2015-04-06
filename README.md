# Backup

Backup your files using `ccollect` with different intervals. I suggest to use weekly interval as minimum, so you have a
backup which is only one week old in the worst case. You can try to use daily or hourly backups on your local partition
to protect you against fatal system reactions by your commands. Alternatively you can use a version control system like
`git` for your important files.

## Example output

```
[✓] YEARLY  UP TO DATE   (0 years ago)
[✓] MONTHLY UP TO DATE   (0 months ago)
[✓] WEEKLY  UP TO DATE   (0 weeks ago)
[ ] DAILY   needs backup (never executed)
[ ] HOURLY  needs backup (never executed)

Yeah, nothing to backup!

Please don't forget to unmount via `umountwd`.
```

The hook in the first column shows you the active state of this interval.

## Requirements

* Ruby
* [ccollect](http://www.nico.schottelius.org/software/ccollect/)
* `rsync`
* Gem [colorize](https://rubygems.org/gems/colorize)
* [Subtle](https://wiki.archlinux.org/index.php/Subtle) plugin [sublet-lastbackups](http://www.github.com/DSIW/sublet-lastbackups) (optional)

## Installation

1. Install `ccollect`
1. Install gem: `gem install colorize`
1. Move ccollect directory to `/etc`
1. Look into `*.TODO` files and follow the instructions
1. Move `backup` and `backup_lib.rb` to a directory which is added to `$PATH`

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
