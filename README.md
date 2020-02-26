# shell_helpers

* [Homepage](https://github.com/DamienRobert/shell_helpers#readme)
* [Issues](https://github.com/DamienRobert/shell_helpers/issues)
* [Documentation](http://rubydoc.info/gems/shell_helpers)
* [Email](mailto:Damien.Olivier.Robert+gems@gmail.com)

[![Gem Version](https://img.shields.io/gem/v/shell_helpers.svg)](https://rubygems.org/gems/shell_helpers)
[![Ruby test result](https://github.com/DamienRobert/shell_helpers/workflows/Ruby/badge.svg)](https://github.com/DamienRobert/shell_helpers/actions?query=workflow%3ARuby)
[![Build Status](https://travis-ci.org/DamienRobert/shell_helpers.svg?branch=master)](https://travis-ci.org/DamienRobert/shell_helpers)

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

## Features

  One of the main feature is an extension of the class `Pathname` with a
  lots of methods to help in shell related task.

## Examples

    ~~~ ruby
    require 'shell_helpers'
    SH::Pathname.new("foo").cp("bar") #calls FileUtils.cp("foo","bar")
    SH::Pathname.new("foo/").on_cp("bar","baz") #copy 'bar' and 'baz' to 'foo/'
    SH::Pathname.new("foo").on_rm(mode: :dangling_symlink) #remove 'foo' only if it is a dangling symlink
    SH::Pathname.new("foo").squel("bar/baz", action: :on_ln_s) #create a symlink foo/bar/baz -> ../../bar/baz

    #Symlink all files in a directory into another, while preserving the structure
    SH::Pathname.new("foo").squel_dir("bar',action: :on_ln_s)
    #Remove these symlinks
    SH::Pathname.new("foo").squel_dir("bar") {|o,t| o.on_rm(mode: :symlink)} 
    ~~~

## Warning

  For now the API is experimental and some parts are not ready to use!

## Install

    $ gem install shell_helpers

## Copyright

Copyright © 2015–2018 Damien Robert

MIT License. See [`LICENSE.txt`](LICENSE.txt) for details.

See above for the copyright: for the files `logger.rb` and `sh.rb` the
copyright applies only to the diff from the original import from methadone.
