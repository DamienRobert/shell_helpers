# shell_helpers

* [Homepage](https://github.com/DamienRobert/shell_helpers#readme)
* [Gems]("https://rubygems.org/gems/shell_helpers)
* [Issues](https://github.com/DamienRobert/shell_helpers/issues)
* [Documentation](http://rubydoc.info/gems/shell_helpers/frames)
* [Email](mailto:Damien.Olivier.Robert+gems at gmail.com)

## Description

  This gem contains a collection of libraries to ease working with the
  shell with ruby.

  A lot of the ideas here are inspired by the utilities in
  [methadone](https://github.com/davetron5000/methadone). In particular
  `logger.rb` and `sh.rb` which were based on `cli_logger.rb`,
  `cli_logging.rb`, `error.rb`, `exit_now.rb`, `process_status.rb`,
  `run.rb` from methadone.

  The reason to incorporate them in this gem is that I wanted to be able to
  add some functionalities (such as `log_and_do` for `logger.rb`, and on
  succes and on error callbacks for `sh.rb`), and also to be able to use
  this functionality from other command parsers than methadone
  (like [gli](https://github.com/davetron5000/gli)).

## Warning

  For now the API is experimental and some parts are not ready to use!

## Install

    $ gem install shell_helpers

## Copyright

Copyright (c) 2015 Damien Robert

MIT License. See {file:LICENSE.txt} for details.

See above for the copyright: for the files `logger.rb` and `sh.rb` the
copyright applies only to the diff from the original import from methadone.
